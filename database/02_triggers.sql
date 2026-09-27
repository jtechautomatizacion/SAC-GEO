-- ============================================================================
-- GTQC — TRIGGERS  ·  v3.0     (archivo 3 de 6; cargar tras 01_functions.sql)
-- ============================================================================
-- Todo lo que la aplicación valida, la base de datos lo vuelve a exigir. Si
-- mañana entra una API nueva, una importación de Excel o un script de soporte,
-- ninguno de ellos puede dejar la base inconsistente.
--
-- Orden de ejecución dentro de una fila:
--   1) BEFORE  · protección (¿está permitido este cambio?)
--   2) BEFORE  · sellado de autoría y fechas (fn_tocar)
--   3) AFTER   · auditoría (registra el resultado final)
-- PostgreSQL dispara los triggers del mismo tipo en orden alfabético de
-- nombre; por eso los nombres llevan prefijo (a_, b_, trg_) donde el orden
-- importa.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. SELLADO DE AUTORÍA Y FECHAS  (una sola función para todas las tablas)
-- ----------------------------------------------------------------------------
-- Rellena creado_por, actualizado_por, actualizado_en y desactivado_en/_por
-- sin que la aplicación tenga que acordarse. Funciona sobre cualquier tabla
-- que tenga esas columnas y las ignora en las que no existen.
--
-- Implementación por jsonb: es la única forma en PL/pgSQL de escribir campos
-- de NEW sin conocer el tipo de la fila. Cuesta un round-trip jsonb por fila;
-- para este volumen (decenas de escrituras por día) es irrelevante y evita
-- mantener doce funciones casi idénticas.
CREATE OR REPLACE FUNCTION fn_tocar() RETURNS TRIGGER AS $$
DECLARE j JSONB := to_jsonb(NEW); v_usuario INTEGER := fn_app_usuario();
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Si el INSERT no trae autor, se usa el del contexto de aplicación.
        -- Excepción deliberada: `usuarios`, donde creado_por es NULL para el
        -- primer usuario del sistema (no puede referenciarse a sí mismo antes
        -- de existir).
        IF j ? 'creado_por' AND j->>'creado_por' IS NULL AND TG_TABLE_NAME <> 'usuarios' THEN
            j := jsonb_set(j, '{creado_por}', to_jsonb(v_usuario));
        END IF;
    ELSE
        IF j ? 'actualizado_en'  THEN j := jsonb_set(j, '{actualizado_en}',  to_jsonb(now()));     END IF;
        IF j ? 'actualizado_por' THEN j := jsonb_set(j, '{actualizado_por}', to_jsonb(v_usuario)); END IF;
        -- Baja lógica: registra desde cuándo dejó de estar operativo.
        IF j ? 'activo' AND j ? 'desactivado_en'
           AND (to_jsonb(OLD)->>'activo')::BOOLEAN AND NOT (j->>'activo')::BOOLEAN THEN
            j := jsonb_set(j, '{desactivado_en}',  to_jsonb(now()));
            j := jsonb_set(j, '{desactivado_por}', to_jsonb(v_usuario));
        ELSIF j ? 'activo' AND j ? 'desactivado_en' AND (j->>'activo')::BOOLEAN THEN
            j := jsonb_set(j, '{desactivado_en}',  'null'::jsonb);
            j := jsonb_set(j, '{desactivado_por}', 'null'::jsonb);
        END IF;
    END IF;
    RETURN jsonb_populate_record(NEW, j);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER b_tocar BEFORE INSERT OR UPDATE ON usuarios              FOR EACH ROW EXECUTE FUNCTION fn_tocar();
CREATE TRIGGER b_tocar BEFORE INSERT OR UPDATE ON empresas              FOR EACH ROW EXECUTE FUNCTION fn_tocar();
CREATE TRIGGER b_tocar BEFORE INSERT OR UPDATE ON contactos             FOR EACH ROW EXECUTE FUNCTION fn_tocar();
CREATE TRIGGER b_tocar BEFORE INSERT OR UPDATE ON personas              FOR EACH ROW EXECUTE FUNCTION fn_tocar();
CREATE TRIGGER b_tocar BEFORE INSERT OR UPDATE ON categorias_ensayo     FOR EACH ROW EXECUTE FUNCTION fn_tocar();
CREATE TRIGGER b_tocar BEFORE INSERT OR UPDATE ON subcategorias_ensayo  FOR EACH ROW EXECUTE FUNCTION fn_tocar();
CREATE TRIGGER b_tocar BEFORE INSERT OR UPDATE ON ensayos_catalogo      FOR EACH ROW EXECUTE FUNCTION fn_tocar();
CREATE TRIGGER b_tocar BEFORE INSERT OR UPDATE ON plantillas_cotizacion FOR EACH ROW EXECUTE FUNCTION fn_tocar();
CREATE TRIGGER b_tocar BEFORE INSERT OR UPDATE ON cotizaciones          FOR EACH ROW EXECUTE FUNCTION fn_tocar();


-- ----------------------------------------------------------------------------
-- 2. AUDITORÍA GENÉRICA
-- ----------------------------------------------------------------------------
-- Registra INSERT / UPDATE / DELETE con antes, después y qué campos cambiaron.
-- El usuario sale de fn_app_usuario() (contexto de sesión), NO de una columna
-- de la propia fila: en v2 se leía actualizado_por y un UPDATE que no la
-- fijara atribuía el cambio al creador del registro.
CREATE OR REPLACE FUNCTION fn_auditar() RETURNS TRIGGER AS $$
DECLARE
    v_new JSONB := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
    v_old JSONB := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
    v_ref JSONB := COALESCE(v_new, v_old);
    v_campos TEXT[];
BEGIN
    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(k ORDER BY k) INTO v_campos
        FROM jsonb_object_keys(v_new) AS k
        WHERE v_old -> k IS DISTINCT FROM v_new -> k;
        -- Un UPDATE que solo movió actualizado_en/_por no es un cambio de negocio.
        IF v_campos IS NULL
           OR v_campos <@ ARRAY['actualizado_en','actualizado_por'] THEN
            RETURN NULL;
        END IF;
    END IF;

    INSERT INTO auditoria (tabla, registro_id, registro_public_id, accion,
                           campos_cambiados, datos_anteriores, datos_nuevos,
                           usuario_id, ip_origen)
    VALUES (TG_TABLE_NAME,
            (v_ref->>'id')::BIGINT,
            NULLIF(v_ref->>'public_id','')::UUID,
            TG_OP, v_campos, v_old, v_new,
            fn_app_usuario(), fn_app_ip());
    RETURN NULL;   -- AFTER trigger: el valor de retorno se ignora
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON usuarios              FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON empresas              FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON contactos             FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON personas              FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON categorias_ensayo     FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON subcategorias_ensayo  FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON ensayos_catalogo      FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON paquete_componentes   FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON plantillas_cotizacion FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON cotizaciones          FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON cotizacion_items      FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON integraciones         FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON documentos_externos   FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON roles                 FOR EACH ROW EXECUTE FUNCTION fn_auditar();


-- ----------------------------------------------------------------------------
-- 3. TABLAS APPEND-ONLY
-- ----------------------------------------------------------------------------
-- Una historia que se puede reescribir no es una historia.
CREATE OR REPLACE FUNCTION fn_append_only() RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'auditoria' AND TG_OP = 'DELETE'
       AND current_setting('app.purga_auditoria', TRUE) = 'on' THEN
        RETURN OLD;   -- purga controlada; ver fn_purgar_auditoria()
    END IF;
    RAISE EXCEPTION 'La tabla % es de solo inserción: % no está permitido', TG_TABLE_NAME, TG_OP
        USING ERRCODE = 'restrict_violation',
              HINT = 'Registre un hecho nuevo en lugar de modificar el histórico.';
END;
$$ LANGUAGE plpgsql;

-- El historial de acreditación no se corrige: se agrega una fila nueva.
-- El DELETE sí se permite, pero solo llega por CASCADE al eliminar un ensayo
-- que nunca se cotizó ni forma parte de un paquete (lo garantiza
-- trg_proteger_ensayo). Si no hay nada que trazar, no hay historia que perder.
CREATE TRIGGER trg_append_only BEFORE UPDATE ON ensayo_acreditacion_historial
    FOR EACH ROW EXECUTE FUNCTION fn_append_only();

CREATE TRIGGER trg_append_only BEFORE UPDATE ON cotizacion_historial_estados
    FOR EACH ROW EXECUTE FUNCTION fn_append_only();

CREATE TRIGGER trg_append_only BEFORE UPDATE OR DELETE ON auditoria
    FOR EACH ROW EXECUTE FUNCTION fn_append_only();


-- ----------------------------------------------------------------------------
-- 4. CATÁLOGO: REGLAS R2 – R5
-- ----------------------------------------------------------------------------

-- CATEGORÍA: R3 (no borrar con ensayos), R4 (prefijo fijo), última activa.
CREATE OR REPLACE FUNCTION fn_proteger_categoria() RETURNS TRIGGER AS $$
DECLARE v_n BIGINT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_n := fn_ensayos_de_categoria(OLD.id);
        IF v_n > 0 THEN
            RAISE EXCEPTION 'La categoría "%" tiene % ensayo(s): desactívela en lugar de eliminarla', OLD.nombre, v_n
                USING ERRCODE = 'restrict_violation';
        END IF;
        RETURN OLD;
    END IF;

    IF NEW.prefijo_codigo <> OLD.prefijo_codigo AND fn_ensayos_de_categoria(OLD.id) > 0 THEN
        RAISE EXCEPTION 'El prefijo "%" ya se usa en códigos de ensayo; no se puede cambiar', OLD.prefijo_codigo
            USING ERRCODE = 'restrict_violation';                                          -- R4
    END IF;
    IF OLD.activo AND NOT NEW.activo
       AND NOT EXISTS (SELECT 1 FROM categorias_ensayo WHERE activo AND id <> OLD.id) THEN
        RAISE EXCEPTION 'Debe quedar al menos una categoría activa' USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_proteger BEFORE UPDATE OR DELETE ON categorias_ensayo
    FOR EACH ROW EXECUTE FUNCTION fn_proteger_categoria();

-- R2 al reactivar: una categoría activa nunca queda sin subcategoría activa.
CREATE OR REPLACE FUNCTION fn_categoria_reactivada() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.activo AND NOT OLD.activo
       AND NOT EXISTS (SELECT 1 FROM subcategorias_ensayo WHERE categoria_id = NEW.id AND activo) THEN
        UPDATE subcategorias_ensayo SET activo = TRUE
        WHERE id = (SELECT id FROM subcategorias_ensayo
                     WHERE categoria_id = NEW.id ORDER BY orden, id LIMIT 1);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_categoria_reactivada AFTER UPDATE OF activo ON categorias_ensayo
    FOR EACH ROW EXECUTE FUNCTION fn_categoria_reactivada();

-- SUBCATEGORÍA: R3, R2 y "no mudarla de categoría si ya tiene ensayos"
-- (mudarla rompería el prefijo de los códigos ya emitidos).
CREATE OR REPLACE FUNCTION fn_proteger_subcategoria() RETURNS TRIGGER AS $$
DECLARE v_n BIGINT; v_cat_activa BOOLEAN;
BEGIN
    SELECT COUNT(*) INTO v_n FROM ensayos_catalogo WHERE subcategoria_id = OLD.id;
    SELECT activo INTO v_cat_activa FROM categorias_ensayo WHERE id = OLD.categoria_id;

    IF TG_OP = 'DELETE' THEN
        IF v_n > 0 THEN
            RAISE EXCEPTION 'La subcategoría "%" tiene % ensayo(s): desactívela en lugar de eliminarla', OLD.nombre, v_n
                USING ERRCODE = 'restrict_violation';
        END IF;
        IF OLD.activo AND COALESCE(v_cat_activa, FALSE) AND NOT EXISTS (
            SELECT 1 FROM subcategorias_ensayo
             WHERE categoria_id = OLD.categoria_id AND activo AND id <> OLD.id) THEN
            RAISE EXCEPTION 'Es la única subcategoría activa de su categoría' USING ERRCODE = 'restrict_violation';
        END IF;
        RETURN OLD;
    END IF;

    IF NEW.categoria_id <> OLD.categoria_id AND v_n > 0 THEN
        RAISE EXCEPTION 'No se puede mover "%" a otra categoría: sus ensayos ya tienen código', OLD.nombre
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.activo AND NOT NEW.activo AND COALESCE(v_cat_activa, FALSE) AND NOT EXISTS (
        SELECT 1 FROM subcategorias_ensayo
         WHERE categoria_id = OLD.categoria_id AND activo AND id <> OLD.id) THEN
        RAISE EXCEPTION 'Es la única subcategoría activa de su categoría' USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_proteger BEFORE UPDATE OR DELETE ON subcategorias_ensayo
    FOR EACH ROW EXECUTE FUNCTION fn_proteger_subcategoria();

-- ENSAYO: el código debe corresponder al prefijo de SU categoría (R4).
-- Ahora se lee categoria_id directo (la FK compuesta ya garantiza que esa
-- categoría es la de su subcategoría), en vez de rehacer el JOIN.
CREATE OR REPLACE FUNCTION fn_validar_codigo_ensayo() RETURNS TRIGGER AS $$
DECLARE v_prefijo VARCHAR(3);
BEGIN
    SELECT prefijo_codigo INTO v_prefijo FROM categorias_ensayo WHERE id = NEW.categoria_id;
    IF NEW.codigo !~ ('^' || v_prefijo || '-[0-9]{2,4}$') THEN
        RAISE EXCEPTION 'El código "%" no corresponde a la categoría (debe ser %-NN)', NEW.codigo, v_prefijo
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_validar_codigo
    BEFORE INSERT OR UPDATE OF codigo, categoria_id, subcategoria_id ON ensayos_catalogo
    FOR EACH ROW EXECUTE FUNCTION fn_validar_codigo_ensayo();

-- ENSAYO: no se borra si ya se cotizó o si es componente de un paquete (R3);
-- no cambia de naturaleza (individual ↔ paquete) si eso rompe vínculos (P1/P2).
CREATE OR REPLACE FUNCTION fn_proteger_ensayo() RETURNS TRIGGER AS $$
DECLARE v_n BIGINT; v_paquetes TEXT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        SELECT COUNT(*) INTO v_n FROM cotizacion_items WHERE ensayo_id = OLD.id;
        IF v_n > 0 THEN
            RAISE EXCEPTION 'El ensayo % aparece en % cotización(es): desactívelo en lugar de eliminarlo', OLD.codigo, v_n
                USING ERRCODE = 'restrict_violation';
        END IF;
        SELECT string_agg(p.codigo, ', ' ORDER BY p.codigo) INTO v_paquetes
        FROM paquete_componentes pc JOIN ensayos_catalogo p ON p.id = pc.ensayo_id
        WHERE pc.ensayo_componente_id = OLD.id;
        IF v_paquetes IS NOT NULL THEN
            RAISE EXCEPTION 'El ensayo % forma parte de los paquetes %: quítelo de ellos o desactívelo', OLD.codigo, v_paquetes
                USING ERRCODE = 'restrict_violation';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.es_paquete AND NOT NEW.es_paquete
       AND EXISTS (SELECT 1 FROM paquete_componentes WHERE ensayo_id = OLD.id) THEN
        RAISE EXCEPTION 'El paquete % tiene componentes: quítelos antes de convertirlo en ensayo individual', OLD.codigo
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.es_paquete AND NOT OLD.es_paquete
       AND EXISTS (SELECT 1 FROM paquete_componentes WHERE ensayo_componente_id = OLD.id) THEN
        RAISE EXCEPTION 'El ensayo % es componente de otro paquete; no puede convertirse en paquete', OLD.codigo
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_proteger BEFORE UPDATE OR DELETE ON ensayos_catalogo
    FOR EACH ROW EXECUTE FUNCTION fn_proteger_ensayo();

-- ACREDITACIÓN: el estado actual y el historial no pueden divergir.
-- Un UPDATE directo de `acreditado` queda bloqueado; hay que pasar por
-- fn_cambiar_acreditacion(), que escribe ambas cosas en una transacción.
CREATE OR REPLACE FUNCTION fn_acreditacion_con_historia() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.acreditado IS DISTINCT FROM OLD.acreditado
       AND COALESCE(current_setting('app.acreditacion_con_historia', TRUE), 'off') <> 'on' THEN
        RAISE EXCEPTION 'La acreditación de % no se cambia con UPDATE directo', OLD.codigo
            USING ERRCODE = 'restrict_violation',
                  HINT = 'Use SELECT fn_cambiar_acreditacion(ensayo_id, acreditado, motivo): deja el rastro ISO 17025.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_acreditacion_con_historia BEFORE UPDATE OF acreditado ON ensayos_catalogo
    FOR EACH ROW EXECUTE FUNCTION fn_acreditacion_con_historia();

-- COMPONENTE: el dueño debe ser paquete (P1) y el vinculado, individual (P2).
CREATE OR REPLACE FUNCTION fn_validar_componente() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ensayos_catalogo WHERE id = NEW.ensayo_id AND es_paquete) THEN
        RAISE EXCEPTION 'Solo un paquete (es_paquete = TRUE) puede tener componentes'
            USING ERRCODE = 'check_violation';                                             -- P1
    END IF;
    IF NEW.ensayo_componente_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM ensayos_catalogo WHERE id = NEW.ensayo_componente_id AND es_paquete) THEN
        RAISE EXCEPTION 'Un paquete no puede incluir otro paquete'
            USING ERRCODE = 'check_violation';                                             -- P2
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_validar BEFORE INSERT OR UPDATE ON paquete_componentes
    FOR EACH ROW EXECUTE FUNCTION fn_validar_componente();


-- ----------------------------------------------------------------------------
-- 5. COTIZACIONES: MÁQUINA DE ESTADOS, CONGELADO E HISTORIAL
-- ----------------------------------------------------------------------------

-- Toda transición de estado pasa por la máquina, venga de donde venga.
CREATE OR REPLACE FUNCTION fn_validar_estado_cotizacion() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.estado IS DISTINCT FROM OLD.estado
       AND NOT fn_transicion_estado_valida(OLD.estado, NEW.estado) THEN
        RAISE EXCEPTION 'Transición de estado no permitida en % : % → %',
            COALESCE(OLD.numero, '(borrador)'), OLD.estado, NEW.estado
            USING ERRCODE = 'check_violation';
    END IF;
    -- Una vez emitida, el número nunca cambia.
    IF OLD.numero IS NOT NULL AND NEW.numero IS DISTINCT FROM OLD.numero THEN
        RAISE EXCEPTION 'El número % ya fue emitido y no se puede cambiar', OLD.numero
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_validar_estado BEFORE UPDATE ON cotizaciones
    FOR EACH ROW EXECUTE FUNCTION fn_validar_estado_cotizacion();

-- Una cotización emitida es un documento entregado al cliente: sus importes,
-- su cliente y su proyecto quedan congelados. Solo pueden moverse el estado,
-- las notas internas y los campos de auditoría.
CREATE OR REPLACE FUNCTION fn_congelar_cotizacion_emitida() RETURNS TRIGGER AS $$
DECLARE v_campos TEXT[]; v_permitidos TEXT[] := ARRAY[
    'estado','numero','fecha_emision','notas','actualizado_por','actualizado_en'];
BEGIN
    IF OLD.estado = 'borrador' THEN RETURN NEW; END IF;

    SELECT array_agg(k) INTO v_campos
    FROM jsonb_object_keys(to_jsonb(NEW)) AS k
    WHERE to_jsonb(OLD) -> k IS DISTINCT FROM to_jsonb(NEW) -> k;

    IF v_campos IS NOT NULL AND NOT (v_campos <@ v_permitidos) THEN
        RAISE EXCEPTION 'La cotización % ya fue emitida: no se pueden modificar %',
            OLD.numero, array_to_string(array(SELECT unnest(v_campos) EXCEPT SELECT unnest(v_permitidos)), ', ')
            USING ERRCODE = 'restrict_violation',
                  HINT = 'Emita una cotización nueva o cancele esta.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_congelar BEFORE UPDATE ON cotizaciones
    FOR EACH ROW EXECUTE FUNCTION fn_congelar_cotizacion_emitida();

-- Una cotización NUNCA se elimina: se cancela. Si se pudiera borrar, se irían
-- con ella sus ítems, su historial de estados y el rastro de sus documentos.
CREATE OR REPLACE FUNCTION fn_prohibir_delete() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION '% no se elimina. %', TG_TABLE_NAME,
        CASE TG_TABLE_NAME
            WHEN 'cotizaciones' THEN 'Use fn_cambiar_estado_cotizacion(id, ''cancelada'', motivo).'
            WHEN 'usuarios'     THEN 'Desactívelo (activo = FALSE); la auditoría lo referencia.'
            ELSE 'Use la baja lógica (activo = FALSE).' END
        USING ERRCODE = 'restrict_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_no_delete BEFORE DELETE ON cotizaciones FOR EACH ROW EXECUTE FUNCTION fn_prohibir_delete();
CREATE TRIGGER a_no_delete BEFORE DELETE ON usuarios     FOR EACH ROW EXECUTE FUNCTION fn_prohibir_delete();

-- Los ítems solo se tocan mientras la cotización es borrador.
CREATE OR REPLACE FUNCTION fn_items_solo_en_borrador() RETURNS TRIGGER AS $$
DECLARE v_estado VARCHAR(12); v_id INTEGER;
BEGIN
    IF TG_OP = 'DELETE' THEN v_id := OLD.cotizacion_id; ELSE v_id := NEW.cotizacion_id; END IF;

    SELECT estado INTO v_estado FROM cotizaciones WHERE id = v_id;
    IF v_estado IS NOT NULL AND v_estado <> 'borrador' THEN
        RAISE EXCEPTION 'La cotización ya no es borrador (%): sus ítems son un snapshot inmutable', v_estado
            USING ERRCODE = 'restrict_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_solo_borrador BEFORE INSERT OR UPDATE OR DELETE ON cotizacion_items
    FOR EACH ROW EXECUTE FUNCTION fn_items_solo_en_borrador();

-- El historial de estados lo escribe la BD, no la aplicación: así el timeline
-- que ve el usuario nunca puede contradecir el estado real del documento.
CREATE OR REPLACE FUNCTION fn_registrar_estado() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.estado IS DISTINCT FROM OLD.estado THEN
        INSERT INTO cotizacion_historial_estados
            (cotizacion_id, estado_anterior, estado, nota, registrado_por)
        VALUES (NEW.id,
                CASE WHEN TG_OP = 'UPDATE' THEN OLD.estado END,
                NEW.estado,
                NULLIF(current_setting('app.nota_estado', TRUE), ''),
                fn_app_usuario());
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_registrar_estado AFTER INSERT OR UPDATE OF estado ON cotizaciones
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_estado();


-- ----------------------------------------------------------------------------
-- 6. PLANTILLAS Y ROLES
-- ----------------------------------------------------------------------------
-- Máximo 3 plantillas activas (el mismo límite que aplica la app). Se valida
-- con trigger porque un CHECK de fila no puede contar filas hermanas.
CREATE OR REPLACE FUNCTION fn_max_plantillas_activas() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.activo AND (SELECT COUNT(*) FROM plantillas_cotizacion
                        WHERE activo AND id <> COALESCE(NEW.id, -1)) >= 3 THEN
        RAISE EXCEPTION 'Máximo 3 plantillas activas. Desactive una antes de crear otra.'
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_max_activas BEFORE INSERT OR UPDATE ON plantillas_cotizacion
    FOR EACH ROW EXECUTE FUNCTION fn_max_plantillas_activas();

-- Los 4 roles base del producto no se eliminan ni se renombran de código.
CREATE OR REPLACE FUNCTION fn_proteger_rol_sistema() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.es_sistema THEN
            RAISE EXCEPTION 'El rol "%" es del sistema y no se elimina', OLD.codigo
                USING ERRCODE = 'restrict_violation';
        END IF;
        RETURN OLD;
    END IF;
    IF OLD.es_sistema AND NEW.codigo <> OLD.codigo THEN
        RAISE EXCEPTION 'El código del rol de sistema "%" no se cambia', OLD.codigo
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER a_proteger BEFORE UPDATE OR DELETE ON roles
    FOR EACH ROW EXECUTE FUNCTION fn_proteger_rol_sistema();
