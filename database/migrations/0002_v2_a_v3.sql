-- ============================================================================
-- MIGRACIÓN 0002 — de la BD v2 a la v3, PRESERVANDO LOS DATOS
-- ============================================================================
-- Qué hace: transforma una base v2 ya cargada (esquema + catálogo + lo que
-- haya de clientes y cotizaciones) en el modelo v3, sin borrar ni recrear
-- ninguna tabla de datos.
--
-- Cómo se usa:
--     psql -d <base_v2> -v ON_ERROR_STOP=1 -f 0002_v2_a_v3.sql
--
-- Todo va en UNA transacción: si cualquier paso falla, la base queda
-- exactamente como estaba. No hay estado intermedio posible.
--
-- Antes de tocar nada, el PASO 0 imprime un informe de los datos que NO
-- pasarían las nuevas restricciones (RUC mal formado, importes que no cuadran,
-- contactos que no son de su empresa…). Si el informe no está vacío, la
-- migración se detiene: primero se corrigen los datos, después se migra.
-- Ese es el orden correcto; lo contrario es esconder el problema.
--
-- Qué NO hace: no agrega tenant_id. Eso es la migración 0003, que está escrita
-- pero deliberadamente NO aplicada.
-- ============================================================================

\set ON_ERROR_STOP on
BEGIN;

-- ----------------------------------------------------------------------------
-- PASO 0 · INFORME PREVIO: ¿los datos actuales aguantan el modelo nuevo?
-- ----------------------------------------------------------------------------
DO $preflight$
DECLARE v_problemas TEXT := ''; v_n BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM empresas WHERE ruc !~ '^(10|15|16|17|20)[0-9]{9}$';
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s empresa(s) con RUC de formato inválido', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM personas WHERE dni !~ '^[0-9]{8}$';
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s persona(s) con DNI de formato inválido', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM contactos WHERE dni IS NOT NULL AND dni !~ '^[0-9]{8}$';
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s contacto(s) con DNI inválido', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM ensayos_catalogo WHERE precio_base < 0;
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s ensayo(s) con precio negativo', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM ensayos_catalogo
     WHERE unidad NOT IN ('UND','PUNT.','DÍA','M2','M3','ML','KG','GLB');
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s ensayo(s) con unidad fuera del dominio', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM cotizaciones
     WHERE estado NOT IN ('borrador','emitida','aceptada','rechazada','cancelada');
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s cotización(es) con estado fuera del dominio', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM cotizacion_items WHERE subtotal <> round(cantidad * precio_unitario, 2);
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s ítem(s) cuyo subtotal no es cantidad x precio', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM cotizaciones WHERE total <> round(subtotal + igv - descuento_monto, 2);
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s cotización(es) cuyo total no cuadra', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM cotizaciones WHERE igv <> round(subtotal * 0.18, 2);
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s cotización(es) cuyo IGV no es el 18%% del subtotal', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM cotizaciones c JOIN contactos ct ON ct.id = c.contacto_id
     WHERE c.empresa_id IS DISTINCT FROM ct.empresa_id;
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s cotización(es) con un contacto que no es de su empresa', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM cotizaciones WHERE persona_id IS NOT NULL AND contacto_id IS NOT NULL;
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s cotización(es) de persona natural con contacto de empresa', v_n); END IF;

    SELECT COUNT(*) INTO v_n FROM ensayos_catalogo ec
      JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
      JOIN categorias_ensayo ce ON ce.id = se.categoria_id
     WHERE ec.codigo !~ ('^' || ce.prefijo_codigo || '-[0-9]{2,4}$');
    IF v_n > 0 THEN v_problemas := v_problemas || format(E'\n  · %s ensayo(s) con código que no respeta el prefijo de su categoría', v_n); END IF;

    IF v_problemas <> '' THEN
        RAISE EXCEPTION E'La migración se detiene: hay datos que no cumplen el modelo v3.%\n\nCorrija estos datos y vuelva a ejecutar. No se ha modificado nada.', v_problemas;
    END IF;
    RAISE NOTICE 'PASO 0 OK — los datos actuales cumplen el modelo v3.';
END
$preflight$;


-- ----------------------------------------------------------------------------
-- PASO 1 · Fuera los triggers y funciones de v2
-- ----------------------------------------------------------------------------
-- Se eliminan ANTES de cambiar las tablas: varios leen columnas que van a
-- moverse, y si quedaran activos abortarían los propios UPDATE de la migración.
DROP TRIGGER IF EXISTS trg_auditar_ensayos_catalogo  ON ensayos_catalogo;
DROP TRIGGER IF EXISTS trg_proteger_ensayo           ON ensayos_catalogo;
DROP TRIGGER IF EXISTS trg_validar_codigo_ensayo     ON ensayos_catalogo;
DROP TRIGGER IF EXISTS trg_auditar_categorias        ON categorias_ensayo;
DROP TRIGGER IF EXISTS trg_proteger_categoria        ON categorias_ensayo;
DROP TRIGGER IF EXISTS trg_categoria_reactivada      ON categorias_ensayo;
DROP TRIGGER IF EXISTS trg_auditar_subcategorias     ON subcategorias_ensayo;
DROP TRIGGER IF EXISTS trg_proteger_subcategoria     ON subcategorias_ensayo;
DROP TRIGGER IF EXISTS trg_validar_componente        ON paquete_componentes;
DROP TRIGGER IF EXISTS trg_auditar_paquete_componentes ON paquete_componentes;
DROP TRIGGER IF EXISTS trg_max_plantillas_activas    ON plantillas_cotizacion;

DROP VIEW IF EXISTS vw_catalogo_disponible, vw_paquete_detalle, vw_paquetes_resumen,
                    vw_resumen_por_categoria, vw_ensayos_mas_cotizados CASCADE;

DROP FUNCTION IF EXISTS fn_auditar_ensayos_catalogo() CASCADE;
DROP FUNCTION IF EXISTS fn_auditar_generico() CASCADE;
DROP FUNCTION IF EXISTS fn_proteger_categoria() CASCADE;
DROP FUNCTION IF EXISTS fn_categoria_reactivada() CASCADE;
DROP FUNCTION IF EXISTS fn_proteger_subcategoria() CASCADE;
DROP FUNCTION IF EXISTS fn_validar_codigo_ensayo() CASCADE;
DROP FUNCTION IF EXISTS fn_proteger_ensayo() CASCADE;
DROP FUNCTION IF EXISTS fn_validar_componente() CASCADE;
DROP FUNCTION IF EXISTS fn_max_plantillas_activas() CASCADE;
DROP FUNCTION IF EXISTS fn_ensayos_de_categoria(INT) CASCADE;
DROP FUNCTION IF EXISTS fn_crear_categoria(VARCHAR,VARCHAR,VARCHAR,VARCHAR,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_siguiente_codigo_ensayo(INT) CASCADE;
DROP FUNCTION IF EXISTS fn_crear_ensayo(INT,VARCHAR,VARCHAR,VARCHAR,NUMERIC,BOOLEAN,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_definir_componentes(INT,JSONB,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_crear_paquete(INT,VARCHAR,VARCHAR,NUMERIC,BOOLEAN,JSONB,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_dashboard_kpis(DATE,DATE) CASCADE;
DROP FUNCTION IF EXISTS fn_dashboard_evolucion(DATE,DATE) CASCADE;
DROP FUNCTION IF EXISTS fn_dashboard_top_clientes(DATE,DATE,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_dashboard_por_categoria(DATE,DATE) CASCADE;

-- Todos los índices idx_* de v2 se eliminan y 03_indexes_views.sql recrea el
-- juego completo revisado (varios de v2 eran redundantes con su propio UNIQUE:
-- idx_empresas_ruc, idx_personas_dni, idx_ensayos_codigo; y idx_ensayos_acreditado
-- indexaba un booleano de dos valores, que el planificador nunca usa).
-- Los índices que respaldan un PRIMARY KEY o un UNIQUE no se tocan: van por
-- constraint, no por nombre idx_*.
DO $indices$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT i.indexrelid::regclass AS nombre
          FROM pg_index i
          JOIN pg_class ci ON ci.oid = i.indexrelid
         WHERE ci.relnamespace = 'public'::regnamespace
           AND ci.relname LIKE 'idx\_%'
           AND NOT i.indisprimary AND NOT i.indisunique
    LOOP
        EXECUTE format('DROP INDEX %s', r.nombre);
    END LOOP;
END
$indices$;


-- ----------------------------------------------------------------------------
-- PASO 2 · Control de versiones del esquema
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    version      VARCHAR(20)  PRIMARY KEY,
    nombre       VARCHAR(140) NOT NULL,
    aplicada_en  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    nota         VARCHAR(300)
);
INSERT INTO schema_migrations (version, nombre, nota)
VALUES ('0001', 'baseline v2 (esquema original)', 'Registrado retroactivamente por 0002')
ON CONFLICT (version) DO NOTHING;


-- ----------------------------------------------------------------------------
-- PASO 3 · Dominios
-- ----------------------------------------------------------------------------
CREATE DOMAIN dom_estado_cotizacion AS VARCHAR(12)
    CHECK (VALUE IN ('borrador','emitida','aceptada','rechazada','cancelada'));
CREATE DOMAIN dom_unidad AS VARCHAR(10)
    CHECK (VALUE IN ('UND','PUNT.','DÍA','M2','M3','ML','KG','GLB'));
CREATE DOMAIN dom_descuento_tipo AS VARCHAR(12)
    CHECK (VALUE IN ('porcentaje','monto'));
CREATE DOMAIN dom_proveedor_nube AS VARCHAR(20)
    CHECK (VALUE IN ('google_drive','office365'));
CREATE DOMAIN dom_estado_integracion AS VARCHAR(12)
    CHECK (VALUE IN ('activa','revocada','expirada'));
CREATE DOMAIN dom_tipo_documento AS VARCHAR(24)
    CHECK (VALUE IN ('cotizacion_pdf','certificado_ensayo','orden_compra','otro'));
CREATE DOMAIN dom_origen_documento AS VARCHAR(10)
    CHECK (VALUE IN ('local','nube'));
CREATE DOMAIN dom_accion_auditoria AS VARCHAR(8)
    CHECK (VALUE IN ('INSERT','UPDATE','DELETE'));
CREATE DOMAIN dom_ruc AS VARCHAR(11) CHECK (VALUE ~ '^(10|15|16|17|20)[0-9]{9}$');
CREATE DOMAIN dom_dni AS VARCHAR(8)  CHECK (VALUE ~ '^[0-9]{8}$');
CREATE DOMAIN dom_email AS VARCHAR(150)
    CHECK (VALUE ~* '^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z]{2,}$');
CREATE DOMAIN dom_telefono AS VARCHAR(25) CHECK (VALUE ~ '^[-0-9+() ]{6,25}$');
CREATE DOMAIN dom_color_hex AS VARCHAR(7) CHECK (VALUE ~ '^#[0-9a-fA-F]{6}$');
CREATE DOMAIN dom_monto  AS NUMERIC(12,2) CHECK (VALUE >= 0);
CREATE DOMAIN dom_precio AS NUMERIC(10,2) CHECK (VALUE >= 0);


-- ----------------------------------------------------------------------------
-- PASO 4 · SERIAL → IDENTITY (los números existentes NO cambian)
-- ----------------------------------------------------------------------------
-- SERIAL es azúcar sintáctico heredado: la secuencia es un objeto aparte que
-- puede quedar desalineada, y GRANT/REVOKE se administran por separado.
-- IDENTITY es el estándar SQL y la secuencia queda atada a la columna.
-- La conversión conserva todos los ids: solo se reposiciona el contador.
DO $identidad$
DECLARE r RECORD; v_next BIGINT; v_seq TEXT;
BEGIN
    -- Se detecta por el DEFAULT nextval(...) de la columna id, no llamando a
    -- pg_get_serial_sequence() en el WHERE: esa función lanza error si la tabla
    -- no tiene esa columna, y el planificador puede evaluarla antes del filtro.
    FOR r IN
        SELECT c.relname AS tabla
          FROM pg_class c
          JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'id' AND NOT a.attisdropped
          JOIN pg_attrdef  d ON d.adrelid  = c.oid AND d.adnum = a.attnum
         WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
           AND a.attidentity = ''
           AND pg_get_expr(d.adbin, d.adrelid) LIKE 'nextval%'
         ORDER BY c.relname
    LOOP
        v_seq := pg_get_serial_sequence(quote_ident(r.tabla), 'id');
        EXECUTE format('SELECT COALESCE(MAX(id),0) + 1 FROM %I', r.tabla) INTO v_next;
        EXECUTE format('ALTER TABLE %I ALTER COLUMN id DROP DEFAULT', r.tabla);
        EXECUTE format('ALTER SEQUENCE %s OWNED BY NONE', v_seq);
        EXECUTE format('DROP SEQUENCE %s', v_seq);
        EXECUTE format('ALTER TABLE %I ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (START WITH %s)',
                       r.tabla, v_next);
        RAISE NOTICE '  identity: %.id (siguiente = %)', r.tabla, v_next;
    END LOOP;
END
$identidad$;

-- Las tablas que crecen sin techo pasan a BIGINT.
ALTER TABLE cotizacion_items            ALTER COLUMN id TYPE BIGINT;
ALTER TABLE cotizacion_historial_estados ALTER COLUMN id TYPE BIGINT;
ALTER TABLE documentos_externos         ALTER COLUMN id TYPE BIGINT;


-- ----------------------------------------------------------------------------
-- PASO 5 · Identificadores públicos (UUID) — antídoto contra IDOR
-- ----------------------------------------------------------------------------
-- El id secuencial se queda como clave interna; lo que viaja en una URL o un
-- QR pasa a ser un UUID opaco. Con /cotizaciones/8, adivinar la 9 es trivial.
ALTER TABLE usuarios              ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE empresas              ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE contactos             ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE personas              ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE categorias_ensayo     ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE subcategorias_ensayo  ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE ensayos_catalogo      ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE plantillas_cotizacion ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE cotizaciones          ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE integraciones         ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE documentos_externos   ADD COLUMN public_id UUID NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE usuarios              ADD CONSTRAINT uq_usuarios_public_id     UNIQUE (public_id);
ALTER TABLE empresas              ADD CONSTRAINT uq_empresas_public_id     UNIQUE (public_id);
ALTER TABLE contactos             ADD CONSTRAINT uq_contactos_public_id    UNIQUE (public_id);
ALTER TABLE personas              ADD CONSTRAINT uq_personas_public_id     UNIQUE (public_id);
ALTER TABLE categorias_ensayo     ADD CONSTRAINT uq_categorias_public_id   UNIQUE (public_id);
ALTER TABLE subcategorias_ensayo  ADD CONSTRAINT uq_subcategorias_public_id UNIQUE (public_id);
ALTER TABLE ensayos_catalogo      ADD CONSTRAINT uq_ensayos_public_id      UNIQUE (public_id);
ALTER TABLE plantillas_cotizacion ADD CONSTRAINT uq_plantillas_public_id   UNIQUE (public_id);
ALTER TABLE cotizaciones          ADD CONSTRAINT uq_cotizaciones_public_id UNIQUE (public_id);
ALTER TABLE integraciones         ADD CONSTRAINT uq_integraciones_public_id UNIQUE (public_id);
ALTER TABLE documentos_externos   ADD CONSTRAINT uq_documentos_public_id   UNIQUE (public_id);


-- ----------------------------------------------------------------------------
-- PASO 6 · Seguridad: roles y usuarios
-- ----------------------------------------------------------------------------
-- En v2, roles.nombre hacía de código técnico ('admin') y de etiqueta a la vez.
-- Se separan: codigo para el sistema, nombre para la interfaz.
ALTER TABLE roles RENAME COLUMN nombre TO codigo;
ALTER TABLE roles ALTER COLUMN codigo TYPE VARCHAR(20);
ALTER TABLE roles ADD COLUMN nombre VARCHAR(60);
ALTER TABLE roles ADD COLUMN es_sistema BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE roles SET nombre = initcap(codigo),
                 es_sistema = codigo IN ('admin','comercial','laboratorio','lectura');
UPDATE roles SET nombre = 'Solo lectura' WHERE codigo = 'lectura';
ALTER TABLE roles ALTER COLUMN nombre SET NOT NULL;
ALTER TABLE roles DROP CONSTRAINT IF EXISTS roles_nombre_key;
ALTER TABLE roles ADD CONSTRAINT uq_roles_codigo UNIQUE (codigo);
ALTER TABLE roles ALTER COLUMN descripcion TYPE VARCHAR(220);

ALTER TABLE usuarios
    ADD COLUMN password_hash    VARCHAR(255),
    ADD COLUMN ultimo_acceso_en TIMESTAMPTZ,
    ADD COLUMN desactivado_en   TIMESTAMPTZ,
    ADD COLUMN desactivado_por  INTEGER REFERENCES usuarios(id) ON DELETE RESTRICT,
    ADD COLUMN creado_por       INTEGER REFERENCES usuarios(id) ON DELETE RESTRICT,
    ADD COLUMN actualizado_por  INTEGER REFERENCES usuarios(id) ON DELETE RESTRICT,
    ADD COLUMN actualizado_en   TIMESTAMPTZ;
ALTER TABLE usuarios ALTER COLUMN email TYPE dom_email;
ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS usuarios_email_key;
CREATE UNIQUE INDEX uq_usuarios_email ON usuarios (lower(email));
UPDATE usuarios SET desactivado_en = creado_en WHERE NOT activo AND desactivado_en IS NULL;
ALTER TABLE usuarios ADD CONSTRAINT ck_usuarios_desactivado
    CHECK (activo OR desactivado_en IS NOT NULL);
ALTER TABLE usuarios ALTER COLUMN rol_id SET NOT NULL;


-- ----------------------------------------------------------------------------
-- PASO 7 · Clientes: una sola convención de baja lógica + pertenencia
-- ----------------------------------------------------------------------------
-- v2 mezclaba dos convenciones: `activo BOOLEAN` en el catálogo y
-- `estado VARCHAR` en empresas; y contactos y personas no tenían ninguna, así
-- que un contacto obsoleto no se podía ocultar sin borrarlo (y borrarlo estaba
-- bloqueado por sus cotizaciones). Se unifica en `activo BOOLEAN`.
ALTER TABLE empresas ADD COLUMN activo BOOLEAN NOT NULL DEFAULT TRUE;
UPDATE empresas SET activo = (estado = 'activo');
ALTER TABLE empresas DROP COLUMN estado;
ALTER TABLE empresas ALTER COLUMN ruc      TYPE dom_ruc;
ALTER TABLE empresas ALTER COLUMN telefono TYPE dom_telefono;
ALTER TABLE empresas ALTER COLUMN email    TYPE dom_email;
ALTER TABLE empresas DROP CONSTRAINT IF EXISTS empresas_ruc_key;
ALTER TABLE empresas ADD CONSTRAINT uq_empresas_ruc UNIQUE (ruc);
ALTER TABLE empresas ADD CONSTRAINT empresas_razon_social_check CHECK (btrim(razon_social) <> '');

ALTER TABLE contactos ADD COLUMN activo BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE contactos ALTER COLUMN dni     TYPE dom_dni;
ALTER TABLE contactos ALTER COLUMN celular TYPE dom_telefono;
ALTER TABLE contactos ALTER COLUMN email   TYPE dom_email;
-- ON DELETE CASCADE → RESTRICT: borrar una empresa no debe llevarse en
-- silencio a sus contactos (y con ellos la trazabilidad de quién pidió qué).
ALTER TABLE contactos DROP CONSTRAINT IF EXISTS contactos_empresa_id_fkey;
ALTER TABLE contactos ADD CONSTRAINT contactos_empresa_id_fkey
    FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT;
-- Clave que permite la FK compuesta de cotizaciones (aislamiento de pertenencia).
ALTER TABLE contactos ADD CONSTRAINT uq_contactos_empresa_id UNIQUE (empresa_id, id);
ALTER TABLE contactos ADD CONSTRAINT uq_contactos_empresa_dni UNIQUE (empresa_id, dni);

ALTER TABLE personas ADD COLUMN activo BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE personas ALTER COLUMN dni     TYPE dom_dni;
ALTER TABLE personas ALTER COLUMN celular TYPE dom_telefono;
ALTER TABLE personas ALTER COLUMN email   TYPE dom_email;
ALTER TABLE personas DROP CONSTRAINT IF EXISTS personas_dni_key;
ALTER TABLE personas ADD CONSTRAINT uq_personas_dni UNIQUE (dni);


-- ----------------------------------------------------------------------------
-- PASO 8 · Catálogo: categoría denormalizada con FK compuesta
-- ----------------------------------------------------------------------------
ALTER TABLE categorias_ensayo ALTER COLUMN color_hex TYPE dom_color_hex;
ALTER TABLE categorias_ensayo DROP CONSTRAINT IF EXISTS categorias_ensayo_color_hex_check;
ALTER TABLE categorias_ensayo DROP CONSTRAINT IF EXISTS categorias_ensayo_slug_key;
ALTER TABLE categorias_ensayo DROP CONSTRAINT IF EXISTS categorias_ensayo_prefijo_codigo_key;
ALTER TABLE categorias_ensayo ADD CONSTRAINT uq_categorias_slug    UNIQUE (slug);
ALTER TABLE categorias_ensayo ADD CONSTRAINT uq_categorias_prefijo UNIQUE (prefijo_codigo);
ALTER TABLE categorias_ensayo ADD CONSTRAINT categorias_slug_check CHECK (slug ~ '^[a-z0-9_]{2,40}$');
ALTER TABLE categorias_ensayo ADD CONSTRAINT categorias_orden_check CHECK (orden >= 0);

ALTER TABLE subcategorias_ensayo ADD CONSTRAINT uq_subcategorias_categoria_id UNIQUE (categoria_id, id);
ALTER TABLE subcategorias_ensayo DROP CONSTRAINT IF EXISTS subcategorias_ensayo_categoria_id_fkey;
ALTER TABLE subcategorias_ensayo ADD CONSTRAINT subcategorias_ensayo_categoria_id_fkey
    FOREIGN KEY (categoria_id) REFERENCES categorias_ensayo(id) ON DELETE RESTRICT;

-- categoria_id en el ensayo: lo consultan el validador del código y el
-- dashboard en cada fila. La FK compuesta garantiza que esa categoría es
-- exactamente la de su subcategoría (no puede desincronizarse).
ALTER TABLE ensayos_catalogo ADD COLUMN categoria_id INTEGER;
UPDATE ensayos_catalogo ec SET categoria_id = se.categoria_id
  FROM subcategorias_ensayo se WHERE se.id = ec.subcategoria_id;
ALTER TABLE ensayos_catalogo ALTER COLUMN categoria_id SET NOT NULL;
ALTER TABLE ensayos_catalogo DROP CONSTRAINT IF EXISTS ensayos_catalogo_subcategoria_id_fkey;
ALTER TABLE ensayos_catalogo ADD CONSTRAINT fk_ensayos_subcategoria
    FOREIGN KEY (categoria_id, subcategoria_id)
    REFERENCES subcategorias_ensayo (categoria_id, id) ON DELETE RESTRICT;

ALTER TABLE ensayos_catalogo ALTER COLUMN codigo TYPE VARCHAR(12);
ALTER TABLE ensayos_catalogo ALTER COLUMN unidad TYPE dom_unidad;
ALTER TABLE ensayos_catalogo ALTER COLUMN precio_base TYPE dom_precio;
ALTER TABLE ensayos_catalogo DROP CONSTRAINT IF EXISTS ensayos_catalogo_codigo_key;
ALTER TABLE ensayos_catalogo ADD CONSTRAINT uq_ensayos_codigo UNIQUE (codigo);
ALTER TABLE ensayos_catalogo ADD CONSTRAINT ensayos_codigo_check
    CHECK (codigo ~ '^[A-Z]{2,3}-[0-9]{2,4}$');
ALTER TABLE ensayos_catalogo
    ADD COLUMN desactivado_en  TIMESTAMPTZ,
    ADD COLUMN desactivado_por INTEGER REFERENCES usuarios(id) ON DELETE RESTRICT;
UPDATE ensayos_catalogo SET desactivado_en = COALESCE(actualizado_en, creado_en)
 WHERE NOT activo AND desactivado_en IS NULL;
ALTER TABLE ensayos_catalogo ADD CONSTRAINT ck_ensayos_desactivado
    CHECK (activo OR desactivado_en IS NOT NULL);

-- Historial de acreditación: una fila por ensayo y día (si hubiera dos el
-- mismo día, la reconstrucción histórica sería ambigua).
DELETE FROM ensayo_acreditacion_historial h
 WHERE EXISTS (SELECT 1 FROM ensayo_acreditacion_historial h2
                WHERE h2.ensayo_id = h.ensayo_id AND h2.vigente_desde = h.vigente_desde
                  AND h2.id > h.id);
ALTER TABLE ensayo_acreditacion_historial
    ADD CONSTRAINT uq_acreditacion_dia UNIQUE (ensayo_id, vigente_desde);
-- Todo ensayo debe tener su línea base, o fn_acreditado_en_fecha() no puede
-- responder por las cotizaciones antiguas.
INSERT INTO ensayo_acreditacion_historial (ensayo_id, acreditado, motivo, vigente_desde, registrado_por)
SELECT ec.id, ec.acreditado, 'Línea base creada por la migración 0002', ec.creado_en::date, 1
  FROM ensayos_catalogo ec
 WHERE NOT EXISTS (SELECT 1 FROM ensayo_acreditacion_historial h WHERE h.ensayo_id = ec.id);

-- Componentes: un componente vinculado no lleva texto propio.
UPDATE paquete_componentes SET nombre = NULL, norma = NULL WHERE ensayo_componente_id IS NOT NULL;
ALTER TABLE paquete_componentes DROP CONSTRAINT IF EXISTS ck_componente_vinculado_o_descrito;
ALTER TABLE paquete_componentes ADD CONSTRAINT ck_componente_vinculado_o_descrito
    CHECK (ensayo_componente_id IS NOT NULL OR btrim(COALESCE(nombre,'')) <> '');
ALTER TABLE paquete_componentes ADD CONSTRAINT ck_componente_sin_texto_duplicado
    CHECK (ensayo_componente_id IS NULL OR (nombre IS NULL AND norma IS NULL));
CREATE UNIQUE INDEX uq_paquete_componente_orden ON paquete_componentes (ensayo_id, orden);


-- ----------------------------------------------------------------------------
-- PASO 9 · Correlativos
-- ----------------------------------------------------------------------------
CREATE TABLE correlativos (
    ambito          VARCHAR(20) NOT NULL CHECK (ambito IN ('cotizacion','ensayo')),
    clave           VARCHAR(40) NOT NULL,
    periodo         VARCHAR(4)  NOT NULL,
    ultimo          INTEGER     NOT NULL DEFAULT 0 CHECK (ultimo >= 0),
    actualizado_en  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (ambito, clave, periodo)
);


-- ----------------------------------------------------------------------------
-- PASO 10 · Cotizaciones
-- ----------------------------------------------------------------------------
-- fecha_emision (DATE en hora de Lima): v2 comparaba creado_en (TIMESTAMPTZ)
-- contra un DATE, así que el corte del día dependía del TimeZone de la sesión
-- y una cotización de las 20:00 en Lima caía al día siguiente en el dashboard.
ALTER TABLE cotizaciones
    ADD COLUMN fecha_emision DATE,
    ADD COLUMN igv_tasa NUMERIC(5,4) NOT NULL DEFAULT 0.1800 CHECK (igv_tasa BETWEEN 0 AND 1),
    ADD COLUMN moneda CHAR(3) NOT NULL DEFAULT 'PEN' CHECK (moneda IN ('PEN','USD'));
UPDATE cotizaciones SET fecha_emision = (creado_en AT TIME ZONE 'America/Lima')::date;
ALTER TABLE cotizaciones ALTER COLUMN fecha_emision SET NOT NULL;
ALTER TABLE cotizaciones ALTER COLUMN fecha_emision
    SET DEFAULT (now() AT TIME ZONE 'America/Lima')::date;

-- numero pasa a ser opcional: el correlativo se consume al EMITIR, no al abrir
-- el wizard, para que un borrador abandonado no deje un hueco en la serie.
ALTER TABLE cotizaciones ALTER COLUMN numero DROP NOT NULL;
ALTER TABLE cotizaciones DROP CONSTRAINT IF EXISTS cotizaciones_numero_key;
ALTER TABLE cotizaciones ADD CONSTRAINT uq_cotizaciones_numero UNIQUE (numero);
ALTER TABLE cotizaciones ADD CONSTRAINT cotizaciones_numero_check
    CHECK (numero ~ '^COT-[0-9]{4}-[0-9]{3,5}$');
ALTER TABLE cotizaciones ALTER COLUMN estado TYPE dom_estado_cotizacion;
ALTER TABLE cotizaciones ALTER COLUMN estado SET DEFAULT 'borrador';
ALTER TABLE cotizaciones ADD CONSTRAINT ck_cotizacion_numero_emitida
    CHECK (estado = 'borrador' OR numero IS NOT NULL);
ALTER TABLE cotizaciones ALTER COLUMN descuento_tipo TYPE dom_descuento_tipo;
ALTER TABLE cotizaciones ALTER COLUMN subtotal        TYPE dom_monto;
ALTER TABLE cotizaciones ALTER COLUMN igv             TYPE dom_monto;
ALTER TABLE cotizaciones ALTER COLUMN descuento_monto TYPE dom_monto;
ALTER TABLE cotizaciones ALTER COLUMN total           TYPE dom_monto;

-- Pertenencia: el contacto tiene que ser de la empresa de la cotización.
ALTER TABLE cotizaciones ADD CONSTRAINT fk_cotizacion_contacto_de_su_empresa
    FOREIGN KEY (empresa_id, contacto_id)
    REFERENCES contactos (empresa_id, id) ON DELETE RESTRICT;
ALTER TABLE cotizaciones DROP CONSTRAINT IF EXISTS chk_cliente_unico;
ALTER TABLE cotizaciones ADD CONSTRAINT ck_cotizacion_cliente_unico CHECK (
    (empresa_id IS NOT NULL AND persona_id IS NULL) OR
    (empresa_id IS NULL AND persona_id IS NOT NULL AND contacto_id IS NULL));

-- Aritmética verificada por la base, no solo por la app.
ALTER TABLE cotizaciones
    ADD CONSTRAINT ck_cotizacion_igv   CHECK (igv = round(subtotal * igv_tasa, 2)),
    ADD CONSTRAINT ck_cotizacion_total CHECK (total = round(subtotal + igv - descuento_monto, 2)),
    ADD CONSTRAINT ck_cotizacion_dcto  CHECK (descuento_monto <= round(subtotal + igv, 2)),
    ADD CONSTRAINT ck_cotizacion_dcto_tipo CHECK (
        (descuento_tipo IS NULL     AND descuento_valor = 0 AND descuento_monto = 0) OR
        (descuento_tipo IS NOT NULL AND descuento_valor > 0)),
    ADD CONSTRAINT ck_cotizacion_dcto_pct CHECK (
        descuento_tipo <> 'porcentaje' OR descuento_valor <= 100),
    ADD CONSTRAINT cotizaciones_validez_check CHECK (validez_dias BETWEEN 1 AND 365),
    ADD CONSTRAINT cotizaciones_descuento_valor_check CHECK (descuento_valor >= 0);

ALTER TABLE cotizaciones DROP CONSTRAINT IF EXISTS cotizaciones_empresa_id_fkey;
ALTER TABLE cotizaciones ADD CONSTRAINT cotizaciones_empresa_id_fkey
    FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT;
ALTER TABLE cotizaciones DROP CONSTRAINT IF EXISTS cotizaciones_persona_id_fkey;
ALTER TABLE cotizaciones ADD CONSTRAINT cotizaciones_persona_id_fkey
    FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE RESTRICT;

-- Ítems: orden explícito y categoría congelada.
ALTER TABLE cotizacion_items
    ADD COLUMN orden                 SMALLINT,
    ADD COLUMN categoria_id          INTEGER REFERENCES categorias_ensayo(id) ON DELETE RESTRICT,
    ADD COLUMN unidad_snapshot       dom_unidad,
    ADD COLUMN categoria_snapshot    VARCHAR(40),
    ADD COLUMN subcategoria_snapshot VARCHAR(40),
    ADD COLUMN es_paquete_snapshot   BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE cotizacion_items ci SET orden = x.rn - 1
  FROM (SELECT id, row_number() OVER (PARTITION BY cotizacion_id ORDER BY id) AS rn
          FROM cotizacion_items) x
 WHERE x.id = ci.id;

-- Reconstrucción del snapshot que v2 no guardaba. Se toma del catálogo actual
-- porque es la única fuente disponible; queda documentado como dato derivado,
-- no como dato histórico verificado. De aquí en adelante se congela al emitir.
UPDATE cotizacion_items ci
   SET categoria_id          = ec.categoria_id,
       categoria_snapshot    = ce.nombre,
       subcategoria_snapshot = se.nombre,
       unidad_snapshot       = ec.unidad,
       es_paquete_snapshot   = ec.es_paquete
  FROM ensayos_catalogo ec
  JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
  JOIN categorias_ensayo   ce ON ce.id = ec.categoria_id
 WHERE ec.id = ci.ensayo_id;

UPDATE cotizacion_items
   SET categoria_snapshot = COALESCE(categoria_snapshot, '(sin categoría)'),
       unidad_snapshot    = COALESCE(unidad_snapshot, 'UND'),
       orden              = COALESCE(orden, 0);

-- Un paquete cotizado en v2 sin componentes_snapshot se reconstruye desde su
-- composición actual. Es lo mejor que se puede hacer con la información que
-- hay, y se marca en el JSON para que nadie lo confunda con un dato original.
UPDATE cotizacion_items ci
   SET componentes_snapshot = (
        SELECT jsonb_agg(jsonb_build_object(
                   'codigo', c.codigo,
                   'nombre', COALESCE(c.nombre, pc.nombre),
                   'norma',  COALESCE(c.norma,  pc.norma),
                   'cantidad', pc.cantidad,
                   'reconstruido', TRUE) ORDER BY pc.orden)
          FROM paquete_componentes pc
          LEFT JOIN ensayos_catalogo c ON c.id = pc.ensayo_componente_id
         WHERE pc.ensayo_id = ci.ensayo_id)
 WHERE ci.es_paquete_snapshot
   AND (ci.componentes_snapshot IS NULL OR jsonb_array_length(ci.componentes_snapshot) = 0);
-- Si algún paquete quedó sin composición (no tiene componentes registrados),
-- se deja de tratar como paquete: mejor un ítem simple honesto que un paquete
-- que dice incluir nada.
UPDATE cotizacion_items SET es_paquete_snapshot = FALSE
 WHERE es_paquete_snapshot AND (componentes_snapshot IS NULL
                                OR jsonb_array_length(componentes_snapshot) = 0);
UPDATE cotizacion_items SET componentes_snapshot = NULL WHERE NOT es_paquete_snapshot;

ALTER TABLE cotizacion_items
    ALTER COLUMN orden              SET NOT NULL,
    ALTER COLUMN orden              SET DEFAULT 0,
    ALTER COLUMN unidad_snapshot    SET NOT NULL,
    ALTER COLUMN unidad_snapshot    SET DEFAULT 'UND',
    ALTER COLUMN categoria_snapshot SET NOT NULL,
    ALTER COLUMN codigo_snapshot    TYPE VARCHAR(12),
    ALTER COLUMN precio_unitario    TYPE dom_precio,
    ALTER COLUMN subtotal           TYPE dom_monto;

ALTER TABLE cotizacion_items
    ADD CONSTRAINT ck_item_subtotal CHECK (subtotal = round(cantidad * precio_unitario, 2)),
    ADD CONSTRAINT cotizacion_items_cantidad_check CHECK (cantidad > 0),
    ADD CONSTRAINT cotizacion_items_orden_check CHECK (orden >= 0),
    ADD CONSTRAINT ck_item_componentes CHECK (
        componentes_snapshot IS NULL OR jsonb_typeof(componentes_snapshot) = 'array'),
    ADD CONSTRAINT ck_item_paquete_con_componentes CHECK (
        (es_paquete_snapshot AND componentes_snapshot IS NOT NULL
             AND jsonb_array_length(componentes_snapshot) > 0)
        OR (NOT es_paquete_snapshot AND componentes_snapshot IS NULL)),
    ADD CONSTRAINT uq_item_orden UNIQUE (cotizacion_id, orden);

ALTER TABLE cotizacion_items DROP CONSTRAINT IF EXISTS cotizacion_items_ensayo_id_fkey;
ALTER TABLE cotizacion_items ADD CONSTRAINT cotizacion_items_ensayo_id_fkey
    FOREIGN KEY (ensayo_id) REFERENCES ensayos_catalogo(id) ON DELETE RESTRICT;

-- Historial de estados: se guarda de dónde venía, no solo a dónde fue.
ALTER TABLE cotizacion_historial_estados
    ADD COLUMN estado_anterior dom_estado_cotizacion;
ALTER TABLE cotizacion_historial_estados ALTER COLUMN estado TYPE dom_estado_cotizacion;
-- Toda cotización necesita al menos su fila inicial para que el timeline
-- coincida con el estado real (control H2/H3 de 99_verificacion.sql).
INSERT INTO cotizacion_historial_estados (cotizacion_id, estado, nota, registrado_por, registrado_en)
SELECT c.id, c.estado, 'Estado registrado retroactivamente por la migración 0002',
       c.creado_por, c.creado_en
  FROM cotizaciones c
 WHERE NOT EXISTS (SELECT 1 FROM cotizacion_historial_estados h WHERE h.cotizacion_id = c.id);


-- Plantillas: se renombra el UNIQUE automático de v2 para que todos los
-- constraints tengan nombre propio. Un constraint con nombre generado no se
-- puede modificar de forma reproducible en una migración futura — y 0003
-- necesita justamente sustituirlo por (tenant_id, slug).
ALTER TABLE plantillas_cotizacion DROP CONSTRAINT IF EXISTS plantillas_cotizacion_slug_key;
ALTER TABLE plantillas_cotizacion ADD  CONSTRAINT uq_plantillas_slug UNIQUE (slug);
ALTER TABLE plantillas_cotizacion ADD  CONSTRAINT plantillas_slug_check
    CHECK (slug ~ '^[a-z0-9_]{2,30}$');
ALTER TABLE plantillas_cotizacion ADD  CONSTRAINT plantillas_validez_check
    CHECK (validez_dias_sugerida BETWEEN 1 AND 365);


-- ----------------------------------------------------------------------------
-- PASO 11 · Integraciones y documentos
-- ----------------------------------------------------------------------------
-- v2 exigía que toda integración fuera de una empresa CLIENTE, así que la nube
-- propia del laboratorio no cabía y una cotización de persona natural no podía
-- tener documento registrado.
ALTER TABLE integraciones ADD COLUMN titular VARCHAR(12) NOT NULL DEFAULT 'cliente';
ALTER TABLE integraciones ALTER COLUMN empresa_id DROP NOT NULL;
ALTER TABLE integraciones ALTER COLUMN proveedor    TYPE dom_proveedor_nube;
ALTER TABLE integraciones ALTER COLUMN estado       TYPE dom_estado_integracion;
ALTER TABLE integraciones ALTER COLUMN cuenta_email TYPE dom_email;
ALTER TABLE integraciones DROP CONSTRAINT IF EXISTS integraciones_proveedor_check;
ALTER TABLE integraciones DROP CONSTRAINT IF EXISTS integraciones_estado_check;
ALTER TABLE integraciones DROP CONSTRAINT IF EXISTS integraciones_empresa_id_proveedor_key;
ALTER TABLE integraciones DROP CONSTRAINT IF EXISTS integraciones_empresa_id_fkey;
ALTER TABLE integraciones ADD CONSTRAINT integraciones_empresa_id_fkey
    FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE RESTRICT;
ALTER TABLE integraciones
    ADD CONSTRAINT integraciones_titular_check CHECK (titular IN ('laboratorio','cliente')),
    ADD CONSTRAINT ck_integracion_titular CHECK (
        (titular = 'cliente' AND empresa_id IS NOT NULL) OR
        (titular = 'laboratorio' AND empresa_id IS NULL)),
    ADD CONSTRAINT ck_integracion_revocada CHECK (estado <> 'revocada' OR revocado_en IS NOT NULL),
    ADD CONSTRAINT uq_integraciones_empresa_proveedor UNIQUE (empresa_id, proveedor);
CREATE UNIQUE INDEX uq_integraciones_laboratorio
    ON integraciones (proveedor) WHERE empresa_id IS NULL;
ALTER TABLE integraciones ALTER COLUMN titular DROP DEFAULT;

ALTER TABLE documentos_externos
    ADD COLUMN origen         dom_origen_documento NOT NULL DEFAULT 'nube',
    ADD COLUMN nombre_archivo VARCHAR(200),
    ADD COLUMN hash_sha256    CHAR(64);
UPDATE documentos_externos
   SET nombre_archivo = COALESCE(NULLIF(regexp_replace(url_externo, '^.*/', ''), ''),
                                 'documento_' || id || '.pdf');
ALTER TABLE documentos_externos ALTER COLUMN nombre_archivo SET NOT NULL;
ALTER TABLE documentos_externos ALTER COLUMN integracion_id DROP NOT NULL;
ALTER TABLE documentos_externos ALTER COLUMN url_externo DROP NOT NULL;
ALTER TABLE documentos_externos ALTER COLUMN tipo_documento TYPE dom_tipo_documento;
ALTER TABLE documentos_externos DROP CONSTRAINT IF EXISTS documentos_externos_tipo_documento_check;
ALTER TABLE documentos_externos DROP CONSTRAINT IF EXISTS documentos_externos_cotizacion_id_fkey;
ALTER TABLE documentos_externos ADD CONSTRAINT documentos_externos_cotizacion_id_fkey
    FOREIGN KEY (cotizacion_id) REFERENCES cotizaciones(id) ON DELETE RESTRICT;
ALTER TABLE documentos_externos
    ADD CONSTRAINT documentos_nombre_check CHECK (btrim(nombre_archivo) <> ''),
    ADD CONSTRAINT documentos_hash_check CHECK (hash_sha256 IS NULL OR hash_sha256 ~ '^[0-9a-f]{64}$'),
    ADD CONSTRAINT ck_documento_origen CHECK (
        (origen = 'nube'  AND integracion_id IS NOT NULL AND url_externo IS NOT NULL) OR
        (origen = 'local' AND integracion_id IS NULL));
ALTER TABLE documentos_externos ALTER COLUMN origen SET DEFAULT 'local';


-- ----------------------------------------------------------------------------
-- PASO 12 · Auditoría
-- ----------------------------------------------------------------------------
ALTER TABLE auditoria
    ALTER COLUMN registro_id TYPE BIGINT,
    ALTER COLUMN accion TYPE dom_accion_auditoria,
    ADD COLUMN registro_public_id UUID,
    ADD COLUMN campos_cambiados TEXT[];
ALTER TABLE auditoria DROP CONSTRAINT IF EXISTS auditoria_usuario_id_fkey;
ALTER TABLE auditoria ADD CONSTRAINT auditoria_usuario_id_fkey
    FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE RESTRICT
    DEFERRABLE INITIALLY IMMEDIATE;
-- NOT VALID: las filas que v2 ya escribió no se tocan (la auditoría es
-- append-only, reescribirla sería justamente lo que se quiere impedir), pero
-- de aquí en adelante toda fila nueva se verifica.
ALTER TABLE auditoria ADD CONSTRAINT ck_auditoria_payload CHECK (
    (accion = 'INSERT' AND datos_anteriores IS NULL     AND datos_nuevos IS NOT NULL) OR
    (accion = 'UPDATE' AND datos_anteriores IS NOT NULL AND datos_nuevos IS NOT NULL) OR
    (accion = 'DELETE' AND datos_anteriores IS NOT NULL AND datos_nuevos IS NULL)
) NOT VALID;


-- ----------------------------------------------------------------------------
-- PASO 13 · Comentarios de catálogo
-- ----------------------------------------------------------------------------
COMMENT ON TABLE roles            IS 'GLOBAL. Roles del producto.';
COMMENT ON TABLE usuarios         IS 'TENANT-SCOPED. Usuario id=1 (sistema) es global.';
COMMENT ON TABLE empresas         IS 'TENANT-SCOPED. Cartera de clientes del laboratorio.';
COMMENT ON TABLE contactos        IS 'TENANT-SCOPED. Personas de contacto de una empresa.';
COMMENT ON TABLE personas         IS 'TENANT-SCOPED. Cliente persona natural (DNI).';
COMMENT ON TABLE categorias_ensayo     IS 'TENANT-SCOPED. Catálogo nivel 1.';
COMMENT ON TABLE subcategorias_ensayo  IS 'TENANT-SCOPED. Catálogo nivel 2.';
COMMENT ON TABLE ensayos_catalogo      IS 'TENANT-SCOPED. Catálogo nivel 3: servicio vendible.';
COMMENT ON TABLE ensayo_acreditacion_historial IS 'TENANT-SCOPED. APPEND-ONLY. Vigencia ISO 17025.';
COMMENT ON TABLE paquete_componentes   IS 'TENANT-SCOPED. Composición de paquetes.';
COMMENT ON TABLE correlativos     IS 'TENANT-SCOPED. Contadores atómicos de códigos y números.';
COMMENT ON TABLE plantillas_cotizacion IS 'HÍBRIDA. 3 plantillas base del producto + las del tenant.';
COMMENT ON TABLE cotizaciones     IS 'TENANT-SCOPED. Documento comercial. No se elimina: se cancela.';
COMMENT ON TABLE cotizacion_items IS 'TENANT-SCOPED. Snapshot inmutable de lo cotizado.';
COMMENT ON TABLE cotizacion_historial_estados IS 'TENANT-SCOPED. APPEND-ONLY. Timeline de estados.';
COMMENT ON TABLE integraciones    IS 'TENANT-SCOPED. Conexión a nube. token_ref, nunca el token.';
COMMENT ON TABLE documentos_externos IS 'TENANT-SCOPED. Rastro de PDFs y certificados emitidos.';
COMMENT ON TABLE auditoria        IS 'TENANT-SCOPED. APPEND-ONLY. Quién cambió qué y cuándo.';

INSERT INTO schema_migrations (version, nombre, nota) VALUES
    ('0002', 'v3: IDs, correlativos, constraints, auditoría, snapshots',
     'Datos preservados. Ejecutar después: 01_functions.sql, 02_triggers.sql, 03_indexes_views.sql y SELECT fn_sincronizar_correlativos_ensayo().');

COMMIT;

-- ============================================================================
-- DESPUÉS DE ESTA MIGRACIÓN, en este orden:
--     psql -d <base> -f ../01_functions.sql
--     psql -d <base> -f ../02_triggers.sql
--     psql -d <base> -f ../03_indexes_views.sql
--     psql -d <base> -c "SELECT fn_sincronizar_correlativos_ensayo();"
--     psql -d <base> -f ../99_verificacion.sql     ← y leer el informe
-- ============================================================================
