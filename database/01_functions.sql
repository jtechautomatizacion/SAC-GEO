-- ============================================================================
-- GTQC — FUNCIONES  ·  v3.0        (archivo 2 de 6; cargar tras 00_schema.sql)
-- ============================================================================
-- Contiene, en este orden:
--   1. Contexto de aplicación (quién está operando)
--   2. Correlativos atómicos            ← FASE 6 de la auditoría
--   3. Catálogo: casos de uso
--   4. Acreditación: cambio e historia reconstruible
--   5. Cotizaciones: máquina de estados, totales y alta atómica
--   6. Dashboard por periodo
--   7. Mantenimiento de auditoría
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. CONTEXTO DE APLICACIÓN
-- ----------------------------------------------------------------------------
-- El backend debe abrir cada transacción con:
--     SET LOCAL app.usuario_id = '7';
--     SET LOCAL app.ip_origen  = '190.12.x.x';
-- Con eso la auditoría sabe quién hizo el cambio sin que la aplicación tenga
-- que acordarse de escribir actualizado_por en cada UPDATE (que es exactamente
-- lo que fallaba en v2: el cambio se atribuía al creador del registro).
--
-- Si no se fijó, cae en el usuario 1 ('sistema'), que es el autor de los seeds.
-- Eso NO es una puerta trasera: es un valor identificable. Una fila de
-- auditoría con usuario_id = 1 y una acción de negocio significa "el backend
-- no fijó el contexto", y eso es un bug que hay que corregir, no ignorar.
CREATE OR REPLACE FUNCTION fn_app_usuario() RETURNS INTEGER AS $$
    SELECT COALESCE(NULLIF(current_setting('app.usuario_id', TRUE), '')::INTEGER, 1);
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_app_ip() RETURNS VARCHAR AS $$
    SELECT NULLIF(current_setting('app.ip_origen', TRUE), '')::VARCHAR;
$$ LANGUAGE sql STABLE;

-- Hoy en hora de Lima. Toda fecha de negocio sale de aquí, nunca de
-- CURRENT_DATE directo, para que el servidor en UTC no corra los días.
CREATE OR REPLACE FUNCTION fn_hoy_lima() RETURNS DATE AS $$
    SELECT (now() AT TIME ZONE 'America/Lima')::date;
$$ LANGUAGE sql STABLE;


-- ----------------------------------------------------------------------------
-- 2. CORRELATIVOS ATÓMICOS
-- ----------------------------------------------------------------------------
-- Única puerta de entrada a la tabla `correlativos`.
--
-- Por qué es seguro bajo concurrencia: INSERT ... ON CONFLICT DO UPDATE toma
-- el lock de la fila del contador. Si dos transacciones piden el mismo
-- contador a la vez, la segunda espera a que la primera confirme y recibe el
-- siguiente valor. No hay MAX(), no hay ventana de carrera, y el número que
-- se entrega ya está reservado en la misma transacción que lo usa (si esa
-- transacción falla, el contador vuelve atrás y no deja hueco).
--
-- Precio a pagar: las emisiones simultáneas del MISMO contador se serializan.
-- Para un laboratorio que emite decenas de cotizaciones al día es irrelevante,
-- y es el precio correcto: un número de cotización duplicado es un problema
-- legal, una espera de milisegundos no.
CREATE OR REPLACE FUNCTION fn_siguiente_correlativo(
    p_ambito  VARCHAR,
    p_clave   VARCHAR,
    p_periodo VARCHAR
) RETURNS INTEGER AS $$
DECLARE v_valor INTEGER;
BEGIN
    INSERT INTO correlativos (ambito, clave, periodo, ultimo)
    VALUES (p_ambito, p_clave, p_periodo, 1)
    ON CONFLICT (ambito, clave, periodo)
    DO UPDATE SET ultimo = correlativos.ultimo + 1, actualizado_en = now()
    RETURNING ultimo INTO v_valor;
    RETURN v_valor;
END;
$$ LANGUAGE plpgsql;

-- COT-YYYY-NNN. La serie se reinicia cada año (por eso `periodo` = el año).
-- Bajo multi-tenant la PK del contador incluirá tenant_id y entonces
-- Tenant A y Tenant B tendrán ambos su propio COT-2026-001.
CREATE OR REPLACE FUNCTION fn_siguiente_numero_cotizacion(p_anio INTEGER DEFAULT NULL)
RETURNS VARCHAR AS $$
DECLARE
    v_anio INTEGER := COALESCE(p_anio, EXTRACT(YEAR FROM fn_hoy_lima())::INTEGER);
    v_n    INTEGER;
BEGIN
    v_n := fn_siguiente_correlativo('cotizacion', 'GLOBAL', v_anio::TEXT);
    RETURN 'COT-' || v_anio::TEXT || '-' || lpad(v_n::TEXT, 3, '0');
END;
$$ LANGUAGE plpgsql;

-- SU-29, AG-43, … El número NO se reutiliza: aunque se elimine el último
-- ensayo de la categoría, el siguiente código sigue avanzando. En v2 se
-- calculaba con MAX(split_part(codigo,'-',2))+1, así que borrar SU-28 hacía
-- que el siguiente ensayo volviera a llamarse SU-28 — dos servicios
-- distintos con el mismo código en la historia del laboratorio.
CREATE OR REPLACE FUNCTION fn_siguiente_codigo_ensayo(p_categoria_id INTEGER)
RETURNS VARCHAR AS $$
DECLARE v_prefijo VARCHAR(3); v_n INTEGER;
BEGIN
    SELECT prefijo_codigo INTO v_prefijo FROM categorias_ensayo WHERE id = p_categoria_id;
    IF v_prefijo IS NULL THEN
        RAISE EXCEPTION 'La categoría % no existe', p_categoria_id USING ERRCODE = 'no_data_found';
    END IF;
    v_n := fn_siguiente_correlativo('ensayo', v_prefijo, '-');
    RETURN v_prefijo || '-' || lpad(v_n::TEXT, 2, '0');
END;
$$ LANGUAGE plpgsql;

-- Alinea los contadores con los códigos que YA existen. Se ejecuta una vez
-- después de cargar el catálogo histórico (y es idempotente): sin esto, el
-- primer ensayo nuevo intentaría llamarse SU-01 y chocaría con el existente.
CREATE OR REPLACE FUNCTION fn_sincronizar_correlativos_ensayo() RETURNS INTEGER AS $$
DECLARE v_filas INTEGER;
BEGIN
    INSERT INTO correlativos (ambito, clave, periodo, ultimo)
    SELECT 'ensayo', ce.prefijo_codigo, '-',
           MAX(split_part(ec.codigo, '-', 2)::INTEGER)
    FROM ensayos_catalogo ec
    JOIN categorias_ensayo ce ON ce.id = ec.categoria_id
    GROUP BY ce.prefijo_codigo
    ON CONFLICT (ambito, clave, periodo)
    DO UPDATE SET ultimo = GREATEST(correlativos.ultimo, EXCLUDED.ultimo),
                  actualizado_en = now();
    GET DIAGNOSTICS v_filas = ROW_COUNT;
    -- Lo mismo para el año en curso de cotizaciones, si ya hubiera historia.
    INSERT INTO correlativos (ambito, clave, periodo, ultimo)
    SELECT 'cotizacion', 'GLOBAL', split_part(numero, '-', 2),
           MAX(split_part(numero, '-', 3)::INTEGER)
    FROM cotizaciones WHERE numero IS NOT NULL
    GROUP BY split_part(numero, '-', 2)
    ON CONFLICT (ambito, clave, periodo)
    DO UPDATE SET ultimo = GREATEST(correlativos.ultimo, EXCLUDED.ultimo),
                  actualizado_en = now();
    RETURN v_filas;
END;
$$ LANGUAGE plpgsql;


-- ----------------------------------------------------------------------------
-- 3. CATÁLOGO: CASOS DE USO
-- ----------------------------------------------------------------------------

-- Cuántos ensayos (activos o no) cuelgan de una categoría. La usan los
-- triggers de protección R3/R4.
CREATE OR REPLACE FUNCTION fn_ensayos_de_categoria(p_categoria_id INTEGER)
RETURNS BIGINT AS $$
    SELECT COUNT(*) FROM ensayos_catalogo WHERE categoria_id = p_categoria_id;
$$ LANGUAGE sql STABLE;

-- Crear categoría = categoría + subcategoría "General", en una sola
-- operación atómica (R2: ninguna categoría activa queda sin subcategoría).
CREATE OR REPLACE FUNCTION fn_crear_categoria(
    p_nombre VARCHAR, p_prefijo VARCHAR, p_icono VARCHAR DEFAULT NULL,
    p_color VARCHAR DEFAULT NULL, p_usuario INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE v_id INTEGER; v_slug VARCHAR(40); v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    v_slug := left(trim(both '_' from regexp_replace(
                translate(lower(btrim(p_nombre)), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiounAEIOUUN'),
                '[^a-z0-9]+', '_', 'g')), 32);
    IF v_slug = '' OR EXISTS (SELECT 1 FROM categorias_ensayo WHERE slug = v_slug) THEN
        v_slug := left(v_slug, 26) || '_' || lower(p_prefijo);
    END IF;

    INSERT INTO categorias_ensayo (slug, nombre, prefijo_codigo, icono, color_hex, orden, creado_por)
    VALUES (v_slug, btrim(p_nombre), upper(p_prefijo), p_icono, p_color,
            COALESCE((SELECT MAX(orden) FROM categorias_ensayo), 0) + 1, v_usuario)
    RETURNING id INTO v_id;

    INSERT INTO subcategorias_ensayo (categoria_id, nombre, orden, creado_por)
    VALUES (v_id, 'General', 1, v_usuario);

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Crear ensayo individual con código automático y su primera fila de
-- historial de acreditación. Todo o nada.
CREATE OR REPLACE FUNCTION fn_crear_ensayo(
    p_subcategoria_id INTEGER, p_nombre VARCHAR, p_norma VARCHAR,
    p_unidad VARCHAR, p_precio NUMERIC, p_acreditado BOOLEAN DEFAULT FALSE,
    p_usuario INTEGER DEFAULT NULL
) RETURNS VARCHAR AS $$
DECLARE
    v_cat INTEGER; v_codigo VARCHAR(12); v_id INTEGER;
    v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    SELECT categoria_id INTO v_cat FROM subcategorias_ensayo WHERE id = p_subcategoria_id AND activo;
    IF v_cat IS NULL THEN
        RAISE EXCEPTION 'La subcategoría % no existe o está inactiva', p_subcategoria_id
            USING ERRCODE = 'no_data_found';
    END IF;

    v_codigo := fn_siguiente_codigo_ensayo(v_cat);

    INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad,
                                  norma, precio_base, acreditado, creado_por)
    VALUES (v_codigo, v_cat, p_subcategoria_id, p_nombre, COALESCE(p_unidad, 'UND'),
            p_norma, p_precio, COALESCE(p_acreditado, FALSE), v_usuario)
    RETURNING id INTO v_id;

    INSERT INTO ensayo_acreditacion_historial (ensayo_id, acreditado, motivo, vigente_desde, registrado_por)
    VALUES (v_id, COALESCE(p_acreditado, FALSE), 'Alta del ensayo en el catálogo', fn_hoy_lima(), v_usuario);

    RETURN v_codigo;
END;
$$ LANGUAGE plpgsql;

-- Reemplaza TODOS los componentes de un paquete (lo que hace "Guardar paquete").
--   p_componentes = [{"ensayo_id":12,"cantidad":3},{"nombre":"Clasificación SUCS","norma":"ASTM D2487"}]
-- P4 (v3, más estricto que v2): al menos 2 componentes VINCULADOS al catálogo.
-- En v2 bastaban 2 filas cualesquiera, así que un "paquete" podía estar hecho
-- solo de texto libre y no tenía precio individual con el que comparar.
CREATE OR REPLACE FUNCTION fn_definir_componentes(
    p_paquete_id INTEGER, p_componentes JSONB, p_usuario INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_n INTEGER; v_vinculados INTEGER;
    v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    IF jsonb_typeof(COALESCE(p_componentes, 'null'::jsonb)) <> 'array' THEN
        RAISE EXCEPTION 'p_componentes debe ser un arreglo JSON' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    v_n := jsonb_array_length(p_componentes);
    SELECT COUNT(*) INTO v_vinculados
    FROM jsonb_array_elements(p_componentes) e
    WHERE NULLIF(e->>'ensayo_id', '') IS NOT NULL;

    IF v_n < 2 OR v_vinculados < 2 THEN
        RAISE EXCEPTION 'Un paquete debe incluir al menos 2 ensayos del catálogo (recibió % componentes, % vinculados)',
            v_n, v_vinculados USING ERRCODE = 'check_violation';           -- P4
    END IF;

    DELETE FROM paquete_componentes WHERE ensayo_id = p_paquete_id;

    INSERT INTO paquete_componentes (ensayo_id, orden, ensayo_componente_id, cantidad, nombre, norma)
    SELECT p_paquete_id,
           (x.ord - 1)::SMALLINT,
           NULLIF(x.elem->>'ensayo_id', '')::INTEGER,
           COALESCE((x.elem->>'cantidad')::SMALLINT, 1),
           CASE WHEN NULLIF(x.elem->>'ensayo_id', '') IS NOT NULL THEN NULL ELSE x.elem->>'nombre' END,
           CASE WHEN NULLIF(x.elem->>'ensayo_id', '') IS NOT NULL THEN NULL ELSE x.elem->>'norma'  END
    FROM jsonb_array_elements(p_componentes) WITH ORDINALITY AS x(elem, ord);

    UPDATE ensayos_catalogo SET actualizado_por = v_usuario WHERE id = p_paquete_id;
    RETURN v_n;
END;
$$ LANGUAGE plpgsql;

-- Crear paquete = ensayo con es_paquete = TRUE + sus componentes + su
-- historial de acreditación. Si los componentes no pasan P1–P5, NADA queda.
CREATE OR REPLACE FUNCTION fn_crear_paquete(
    p_subcategoria_id INTEGER, p_nombre VARCHAR, p_unidad VARCHAR, p_precio NUMERIC,
    p_acreditado BOOLEAN, p_componentes JSONB, p_usuario INTEGER DEFAULT NULL
) RETURNS VARCHAR AS $$
DECLARE
    v_cat INTEGER; v_codigo VARCHAR(12); v_id INTEGER;
    v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    SELECT categoria_id INTO v_cat FROM subcategorias_ensayo WHERE id = p_subcategoria_id AND activo;
    IF v_cat IS NULL THEN
        RAISE EXCEPTION 'La subcategoría % no existe o está inactiva', p_subcategoria_id
            USING ERRCODE = 'no_data_found';
    END IF;

    v_codigo := fn_siguiente_codigo_ensayo(v_cat);

    INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad,
                                  precio_base, es_paquete, acreditado, creado_por)
    VALUES (v_codigo, v_cat, p_subcategoria_id, p_nombre, COALESCE(p_unidad, 'UND'),
            p_precio, TRUE, COALESCE(p_acreditado, FALSE), v_usuario)
    RETURNING id INTO v_id;

    PERFORM fn_definir_componentes(v_id, p_componentes, v_usuario);

    INSERT INTO ensayo_acreditacion_historial (ensayo_id, acreditado, motivo, vigente_desde, registrado_por)
    VALUES (v_id, COALESCE(p_acreditado, FALSE), 'Alta del paquete en el catálogo', fn_hoy_lima(), v_usuario);

    RETURN v_codigo;
END;
$$ LANGUAGE plpgsql;


-- ----------------------------------------------------------------------------
-- 4. ACREDITACIÓN: CAMBIO E HISTORIA RECONSTRUIBLE
-- ----------------------------------------------------------------------------
-- Única forma correcta de cambiar la acreditación de un ensayo: mueve el
-- estado actual Y deja la fila de historia en la misma transacción.
-- En v2 un UPDATE directo sobre ensayos_catalogo.acreditado no escribía
-- historia, así que el estado y el historial podían contar cosas distintas.
-- Ahora el trigger trg_acreditacion_con_historia bloquea el UPDATE directo.
CREATE OR REPLACE FUNCTION fn_cambiar_acreditacion(
    p_ensayo_id INTEGER, p_acreditado BOOLEAN, p_motivo VARCHAR,
    p_vigente_desde DATE DEFAULT NULL, p_usuario INTEGER DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
    v_actual BOOLEAN;
    v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
    v_desde   DATE    := COALESCE(p_vigente_desde, fn_hoy_lima());
BEGIN
    SELECT acreditado INTO v_actual FROM ensayos_catalogo WHERE id = p_ensayo_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ensayo % no existe', p_ensayo_id USING ERRCODE = 'no_data_found';
    END IF;
    IF v_actual = p_acreditado THEN
        RETURN;   -- nada que registrar
    END IF;

    INSERT INTO ensayo_acreditacion_historial (ensayo_id, acreditado, motivo, vigente_desde, registrado_por)
    VALUES (p_ensayo_id, p_acreditado, p_motivo, v_desde, v_usuario);

    PERFORM set_config('app.acreditacion_con_historia', 'on', TRUE);
    UPDATE ensayos_catalogo
       SET acreditado = p_acreditado, actualizado_por = v_usuario
     WHERE id = p_ensayo_id;
    PERFORM set_config('app.acreditacion_con_historia', 'off', TRUE);
END;
$$ LANGUAGE plpgsql;

-- ¿Estaba este ensayo acreditado en tal fecha? Es la pregunta que hace un
-- auditor ISO 17025 sobre un informe emitido hace dos años.
CREATE OR REPLACE FUNCTION fn_acreditado_en_fecha(p_ensayo_id INTEGER, p_fecha DATE)
RETURNS BOOLEAN AS $$
    SELECT acreditado
    FROM ensayo_acreditacion_historial
    WHERE ensayo_id = p_ensayo_id AND vigente_desde <= p_fecha
    ORDER BY vigente_desde DESC, id DESC
    LIMIT 1;
$$ LANGUAGE sql STABLE;


-- ----------------------------------------------------------------------------
-- 5. COTIZACIONES
-- ----------------------------------------------------------------------------

-- Máquina de estados. Fuera de estas transiciones no hay ninguna válida.
--   borrador → emitida | cancelada
--   emitida  → aceptada | rechazada | cancelada
--   aceptada / rechazada / cancelada → (terminal)
CREATE OR REPLACE FUNCTION fn_transicion_estado_valida(p_de VARCHAR, p_a VARCHAR)
RETURNS BOOLEAN AS $$
    SELECT CASE p_de
        WHEN 'borrador' THEN p_a IN ('emitida','cancelada')
        WHEN 'emitida'  THEN p_a IN ('aceptada','rechazada','cancelada')
        ELSE FALSE
    END;
$$ LANGUAGE sql IMMUTABLE;

-- Recalcula subtotal / IGV / descuento / total desde los ítems reales.
-- Es la única fuente de los totales: la app no los envía, los pide.
CREATE OR REPLACE FUNCTION fn_recalcular_cotizacion(p_cotizacion_id INTEGER)
RETURNS VOID AS $$
DECLARE
    v_sub NUMERIC(12,2); v_igv NUMERIC(12,2); v_dcto NUMERIC(12,2);
    v_tasa NUMERIC(5,4); v_tipo VARCHAR(12); v_valor NUMERIC(10,2);
BEGIN
    SELECT igv_tasa, descuento_tipo, descuento_valor
      INTO v_tasa, v_tipo, v_valor
      FROM cotizaciones WHERE id = p_cotizacion_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cotización % no existe', p_cotizacion_id USING ERRCODE = 'no_data_found';
    END IF;

    SELECT COALESCE(SUM(subtotal), 0) INTO v_sub
      FROM cotizacion_items WHERE cotizacion_id = p_cotizacion_id;

    v_igv := round(v_sub * v_tasa, 2);

    -- NOTA FISCAL (hallazgo M-07 de la auditoría): el descuento se aplica
    -- DESPUÉS del IGV, tal como lo hace hoy el mockup. Se conserva el
    -- comportamiento para no alterar los importes existentes, pero debe
    -- validarse con contabilidad: lo habitual en Perú es descontar sobre la
    -- base imponible y calcular el IGV después.
    v_dcto := CASE v_tipo
                WHEN 'porcentaje' THEN round((v_sub + v_igv) * v_valor / 100, 2)
                WHEN 'monto'      THEN round(v_valor, 2)
                ELSE 0 END;
    v_dcto := LEAST(v_dcto, v_sub + v_igv);

    UPDATE cotizaciones
       SET subtotal = v_sub, igv = v_igv, descuento_monto = v_dcto,
           total = round(v_sub + v_igv - v_dcto, 2),
           actualizado_por = fn_app_usuario()
     WHERE id = p_cotizacion_id;
END;
$$ LANGUAGE plpgsql;

-- Agrega un ítem congelando el snapshot completo del catálogo.
-- Solo funciona mientras la cotización es borrador (lo exige el trigger
-- trg_items_solo_en_borrador).
CREATE OR REPLACE FUNCTION fn_agregar_item(
    p_cotizacion_id INTEGER, p_ensayo_id INTEGER, p_cantidad NUMERIC DEFAULT 1,
    p_acreditado_override BOOLEAN DEFAULT NULL, p_precio_unitario NUMERIC DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
    r RECORD; v_id BIGINT; v_orden SMALLINT; v_precio NUMERIC(10,2);
    v_acred BOOLEAN; v_comp JSONB;
BEGIN
    SELECT ec.id, ec.codigo, ec.nombre, ec.norma, ec.unidad, ec.precio_base,
           ec.es_paquete, ec.acreditado, ec.activo,
           ce.id AS categoria_id, ce.nombre AS categoria, se.nombre AS subcategoria
      INTO r
      FROM ensayos_catalogo ec
      JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
      JOIN categorias_ensayo   ce ON ce.id = ec.categoria_id
     WHERE ec.id = p_ensayo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ensayo % no existe', p_ensayo_id USING ERRCODE = 'no_data_found';
    END IF;
    IF NOT r.activo THEN
        RAISE EXCEPTION 'El ensayo % está desactivado y no se puede cotizar', r.codigo
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT COALESCE(MAX(orden), -1) + 1 INTO v_orden
      FROM cotizacion_items WHERE cotizacion_id = p_cotizacion_id;

    v_precio := COALESCE(p_precio_unitario, r.precio_base);
    v_acred  := COALESCE(p_acreditado_override, r.acreditado);

    IF r.es_paquete THEN
        SELECT jsonb_agg(jsonb_build_object(
                   'codigo',   c.codigo,
                   'nombre',   COALESCE(c.nombre, pc.nombre),
                   'norma',    COALESCE(c.norma,  pc.norma),
                   'cantidad', pc.cantidad
               ) ORDER BY pc.orden)
          INTO v_comp
          FROM paquete_componentes pc
          LEFT JOIN ensayos_catalogo c ON c.id = pc.ensayo_componente_id
         WHERE pc.ensayo_id = r.id;
    END IF;

    INSERT INTO cotizacion_items (
        cotizacion_id, orden, ensayo_id, categoria_id,
        codigo_snapshot, nombre_snapshot, norma_snapshot, unidad_snapshot,
        categoria_snapshot, subcategoria_snapshot, es_paquete_snapshot,
        acreditado_snapshot, acreditado_override,
        cantidad, precio_unitario, subtotal, componentes_snapshot)
    VALUES (
        p_cotizacion_id, v_orden, r.id, r.categoria_id,
        r.codigo, r.nombre, r.norma, r.unidad,
        r.categoria, r.subcategoria, r.es_paquete,
        v_acred, (p_acreditado_override IS NOT NULL AND p_acreditado_override <> r.acreditado),
        p_cantidad, v_precio, round(p_cantidad * v_precio, 2), v_comp)
    RETURNING id INTO v_id;

    PERFORM fn_recalcular_cotizacion(p_cotizacion_id);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Cambia el estado validando la transición. El historial lo escribe el
-- trigger, no esta función: así cualquier otro camino que toque el estado
-- también queda registrado.
CREATE OR REPLACE FUNCTION fn_cambiar_estado_cotizacion(
    p_cotizacion_id INTEGER, p_nuevo VARCHAR, p_nota VARCHAR DEFAULT NULL
) RETURNS VOID AS $$
DECLARE v_actual VARCHAR(12);
BEGIN
    SELECT estado INTO v_actual FROM cotizaciones WHERE id = p_cotizacion_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cotización % no existe', p_cotizacion_id USING ERRCODE = 'no_data_found';
    END IF;
    IF NOT fn_transicion_estado_valida(v_actual, p_nuevo) THEN
        RAISE EXCEPTION 'Transición de estado no permitida: % → %', v_actual, p_nuevo
            USING ERRCODE = 'check_violation';
    END IF;

    PERFORM set_config('app.nota_estado', COALESCE(p_nota, ''), TRUE);
    UPDATE cotizaciones
       SET estado = p_nuevo,
           numero = CASE WHEN p_nuevo = 'emitida' AND numero IS NULL
                         THEN fn_siguiente_numero_cotizacion() ELSE numero END,
           fecha_emision = CASE WHEN p_nuevo = 'emitida' THEN fn_hoy_lima() ELSE fecha_emision END,
           actualizado_por = fn_app_usuario()
     WHERE id = p_cotizacion_id;
END;
$$ LANGUAGE plpgsql;

-- Alta completa de una cotización, atómica: cabecera + ítems + totales +
-- emisión. Es lo que llamará el backend cuando el usuario pulse "Generar".
--   p_items = [{"ensayo_id":12,"cantidad":2},{"ensayo_id":30,"cantidad":1}]
CREATE OR REPLACE FUNCTION fn_crear_cotizacion(
    p_empresa_id INTEGER, p_contacto_id INTEGER, p_persona_id INTEGER,
    p_proyecto VARCHAR, p_plantilla_id INTEGER, p_items JSONB,
    p_validez_dias SMALLINT DEFAULT NULL,
    p_descuento_tipo VARCHAR DEFAULT NULL, p_descuento_valor NUMERIC DEFAULT 0,
    p_descuento_razon VARCHAR DEFAULT NULL, p_notas TEXT DEFAULT NULL,
    p_emitir BOOLEAN DEFAULT TRUE, p_usuario INTEGER DEFAULT NULL
) RETURNS TABLE (cotizacion_id INTEGER, public_id UUID, numero VARCHAR) AS $$
DECLARE
    v_id INTEGER; v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
    v_item JSONB;
BEGIN
    IF jsonb_typeof(COALESCE(p_items, 'null'::jsonb)) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Una cotización necesita al menos un ítem' USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO cotizaciones (empresa_id, contacto_id, persona_id, proyecto_nombre,
                              plantilla_id, validez_dias, descuento_tipo, descuento_valor,
                              descuento_razon, notas, estado, creado_por)
    VALUES (p_empresa_id, p_contacto_id, p_persona_id, p_proyecto,
            p_plantilla_id,
            COALESCE(p_validez_dias,
                     (SELECT validez_dias_sugerida FROM plantillas_cotizacion WHERE id = p_plantilla_id),
                     15),
            NULLIF(p_descuento_tipo, ''), COALESCE(p_descuento_valor, 0),
            p_descuento_razon, p_notas, 'borrador', v_usuario)
    RETURNING id INTO v_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        PERFORM fn_agregar_item(
            v_id,
            (v_item->>'ensayo_id')::INTEGER,
            COALESCE((v_item->>'cantidad')::NUMERIC, 1),
            (v_item->>'acreditado')::BOOLEAN);
    END LOOP;

    PERFORM fn_recalcular_cotizacion(v_id);

    IF p_emitir THEN
        PERFORM fn_cambiar_estado_cotizacion(v_id, 'emitida', 'Emisión inicial');
    END IF;

    RETURN QUERY SELECT c.id, c.public_id, c.numero FROM cotizaciones c WHERE c.id = v_id;
END;
$$ LANGUAGE plpgsql;


-- ----------------------------------------------------------------------------
-- 6. DASHBOARD POR PERIODO (filtro "Desde / Hasta" + botón Aplicar)
-- ----------------------------------------------------------------------------
-- Todas filtran por fecha_emision (DATE, hora de Lima) y excluyen borradores.
-- p_hasta es inclusivo. NULL en cualquiera de los dos extremos = sin límite.
--
-- Cambio respecto de v2: v2 comparaba creado_en (TIMESTAMPTZ) contra un DATE,
-- así que el corte del día dependía del TimeZone de la sesión; y los JOIN al
-- catálogo eran INNER, de modo que un ítem cuyo ensayo desapareciera dejaba de
-- sumar. Ahora se agrupa por la categoría congelada en el ítem.

CREATE OR REPLACE FUNCTION fn_dashboard_kpis(p_desde DATE DEFAULT NULL, p_hasta DATE DEFAULT NULL)
RETURNS TABLE (
    total_cotizaciones BIGINT, emitidas BIGINT, aceptadas BIGINT,
    rechazadas BIGINT, canceladas BIGINT, valor_total NUMERIC, valor_aceptado NUMERIC
) AS $$
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE estado = 'emitida'),
           COUNT(*) FILTER (WHERE estado = 'aceptada'),
           COUNT(*) FILTER (WHERE estado = 'rechazada'),
           COUNT(*) FILTER (WHERE estado = 'cancelada'),
           COALESCE(SUM(total) FILTER (WHERE estado IN ('emitida','aceptada')), 0),
           COALESCE(SUM(total) FILTER (WHERE estado = 'aceptada'), 0)
      FROM cotizaciones
     WHERE estado <> 'borrador'
       AND (p_desde IS NULL OR fecha_emision >= p_desde)
       AND (p_hasta IS NULL OR fecha_emision <= p_hasta);
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_dashboard_evolucion(p_desde DATE DEFAULT NULL, p_hasta DATE DEFAULT NULL)
RETURNS TABLE (periodo DATE, cotizaciones BIGINT, monto NUMERIC) AS $$
    SELECT CASE WHEN p_desde IS NOT NULL AND p_hasta IS NOT NULL AND (p_hasta - p_desde) < 31
                THEN date_trunc('day',   fecha_emision)::date
                ELSE date_trunc('month', fecha_emision)::date END,
           COUNT(*), COALESCE(SUM(total), 0)
      FROM cotizaciones
     WHERE estado <> 'borrador'
       AND (p_desde IS NULL OR fecha_emision >= p_desde)
       AND (p_hasta IS NULL OR fecha_emision <= p_hasta)
     GROUP BY 1 ORDER BY 1;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_dashboard_top_clientes(
    p_desde DATE DEFAULT NULL, p_hasta DATE DEFAULT NULL, p_limite INTEGER DEFAULT 4)
RETURNS TABLE (cliente VARCHAR, cotizaciones BIGINT, monto NUMERIC) AS $$
    SELECT COALESCE(e.razon_social, (p.nombres || ' ' || p.apellidos))::VARCHAR,
           COUNT(*), SUM(c.total)
      FROM cotizaciones c
      LEFT JOIN empresas e ON e.id = c.empresa_id
      LEFT JOIN personas p ON p.id = c.persona_id
     WHERE c.estado <> 'borrador'
       AND (p_desde IS NULL OR c.fecha_emision >= p_desde)
       AND (p_hasta IS NULL OR c.fecha_emision <= p_hasta)
     GROUP BY 1 ORDER BY 3 DESC LIMIT p_limite;
$$ LANGUAGE sql STABLE;

-- Devuelve siempre las categorías activas (en 0 si no vendieron) y además
-- cualquier categoría inactiva que SÍ vendió en el periodo: el dashboard no
-- debe perder historia solo porque el catálogo se reorganizó.
CREATE OR REPLACE FUNCTION fn_dashboard_por_categoria(
    p_desde DATE DEFAULT NULL, p_hasta DATE DEFAULT NULL)
RETURNS TABLE (categoria_id INTEGER, categoria_slug VARCHAR, categoria_nombre VARCHAR,
               color_hex VARCHAR, activo BOOLEAN, items NUMERIC, monto NUMERIC) AS $$
    SELECT ce.id, ce.slug, ce.nombre, ce.color_hex::VARCHAR, ce.activo,
           COALESCE(SUM(x.cantidad), 0), COALESCE(SUM(x.subtotal), 0)
      FROM categorias_ensayo ce
      LEFT JOIN (
            SELECT ci.categoria_id, ci.cantidad, ci.subtotal
              FROM cotizacion_items ci
              JOIN cotizaciones c ON c.id = ci.cotizacion_id
             WHERE c.estado <> 'borrador'
               AND (p_desde IS NULL OR c.fecha_emision >= p_desde)
               AND (p_hasta IS NULL OR c.fecha_emision <= p_hasta)
      ) x ON x.categoria_id = ce.id
     GROUP BY ce.id, ce.slug, ce.nombre, ce.color_hex, ce.activo, ce.orden
    HAVING ce.activo OR COALESCE(SUM(x.subtotal), 0) > 0
     ORDER BY ce.orden;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_dashboard_ensayos_top(
    p_desde DATE DEFAULT NULL, p_hasta DATE DEFAULT NULL, p_limite INTEGER DEFAULT 10)
RETURNS TABLE (codigo VARCHAR, nombre VARCHAR, categoria VARCHAR,
               veces BIGINT, unidades NUMERIC, monto NUMERIC) AS $$
    SELECT ci.codigo_snapshot, ci.nombre_snapshot, ci.categoria_snapshot,
           COUNT(*), SUM(ci.cantidad), SUM(ci.subtotal)
      FROM cotizacion_items ci
      JOIN cotizaciones c ON c.id = ci.cotizacion_id
     WHERE c.estado <> 'borrador'
       AND (p_desde IS NULL OR c.fecha_emision >= p_desde)
       AND (p_hasta IS NULL OR c.fecha_emision <= p_hasta)
     GROUP BY 1, 2, 3 ORDER BY 6 DESC LIMIT p_limite;
$$ LANGUAGE sql STABLE;


-- ----------------------------------------------------------------------------
-- 7. MANTENIMIENTO DE AUDITORÍA
-- ----------------------------------------------------------------------------
-- `auditoria` es append-only. Purgar histórico antiguo es legítimo (la tabla
-- crece sin techo), pero no debe poder hacerse en silencio: esta función es la
-- única puerta, y deja su propia constancia de qué rango se purgó y quién.
CREATE OR REPLACE FUNCTION fn_purgar_auditoria(p_hasta DATE, p_usuario INTEGER DEFAULT NULL)
RETURNS BIGINT AS $$
DECLARE v_n BIGINT; v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    IF p_hasta > fn_hoy_lima() - INTERVAL '365 days' THEN
        RAISE EXCEPTION 'No se purga auditoría de menos de 365 días (pidió hasta %)', p_hasta
            USING ERRCODE = 'restrict_violation';
    END IF;
    PERFORM set_config('app.purga_auditoria', 'on', TRUE);
    DELETE FROM auditoria WHERE registrado_en < p_hasta;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    PERFORM set_config('app.purga_auditoria', 'off', TRUE);

    INSERT INTO auditoria (tabla, registro_id, accion, datos_nuevos, usuario_id, ip_origen)
    VALUES ('auditoria', 0, 'INSERT',
            jsonb_build_object('evento','purga','hasta',p_hasta,'filas_eliminadas',v_n),
            v_usuario, fn_app_ip());
    RETURN v_n;
END;
$$ LANGUAGE plpgsql;
