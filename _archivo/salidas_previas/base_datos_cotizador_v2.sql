-- ============================================================================
-- GTQC LABORATORIO — BASE DE DATOS DEL SISTEMA DE COTIZACIONES (v2)
-- ============================================================================
-- Motor objetivo: PostgreSQL 14+ (funciona igual en MySQL 8 cambiando
-- SERIAL->AUTO_INCREMENT, BOOLEAN->TINYINT(1) y JSONB->JSON).
--
-- OBJETIVOS DE ESTE DISEÑO
--   1) Separar correctamente EMPRESA (RUC) / CONTACTO (persona que trabaja
--      en la empresa) / PERSONA NATURAL (DNI, cliente directo) — así se
--      evita repetir datos de contacto cuando una empresa cotiza varias
--      veces con personas distintas.
--   2) Catálogo de ensayos organizado como lo maneja el laboratorio en la
--      práctica: CATEGORÍA (Suelos / Concreto / Asfalto / Albañilería) >
--      SUBCATEGORÍA (Estándares, Químicos, Paquetes, Campo, ...) > ENSAYO.
--      Esto es lo que hace que la app "se le facilite entender a alguien
--      de civil": navega igual que su propia lista de precios en Excel.
--      Categorías y subcategorías son editables por el usuario (v2.1),
--      con reglas de integridad R1–R5 (ver sección 2).
--   3) ACREDITACIÓN (ISO/IEC 17025) como dato editable por ensayo, con
--      historial de cambios (una acreditación se gana o se pierde con
--      fecha real — no basta un booleano suelto).
--   4) CAMPOS DE AUTORÍA / AUDITORÍA en toda tabla mutable (creado_por,
--      creado_en, actualizado_por, actualizado_en) + una tabla genérica
--      de auditoría con snapshot antes/después. Esto es lo que un
--      auditor o un ente verificador (ISO 17025, SUNAT, un futuro
--      inversionista técnico) pide primero: "¿quién cambió qué y cuándo?".
--   5) Preparado para IA sin construir de más hoy: quedan columnas y una
--      sección "ROADMAP IA" al final con las tablas que se agregarán
--      cuando haya volumen de datos real (recomendador de ensayos,
--      predicción de aceptación de cotización, etc.), sin migrar nada
--      de lo ya creado.
-- ============================================================================


-- ============================================================================
-- 0. UTILIDADES Y CATÁLOGOS BASE
-- ============================================================================

-- Roles simples; se amplía cuando haya más de un tipo de usuario operativo.
CREATE TABLE roles (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(40) NOT NULL UNIQUE,   -- 'admin', 'comercial', 'laboratorio', 'lectura'
    descripcion     VARCHAR(200)
);

-- Todo campo de autoría (creado_por / actualizado_por) apunta aquí.
-- Aunque hoy la app no tenga login, la columna ya existe: el mockup usa
-- un usuario 'sistema' por defecto y el día que haya login no se migra nada.
CREATE TABLE usuarios (
    id              SERIAL PRIMARY KEY,
    nombres         VARCHAR(100) NOT NULL,
    apellidos       VARCHAR(100) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    rol_id          INTEGER NOT NULL REFERENCES roles(id),
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO roles (nombre, descripcion) VALUES
    ('admin', 'Acceso total: catálogo, usuarios, configuración'),
    ('comercial', 'Crea y gestiona cotizaciones y clientes'),
    ('laboratorio', 'Solo lectura de cotizaciones + gestiona acreditación de ensayos'),
    ('lectura', 'Solo consulta dashboard e historial');

-- Usuario "sistema" para los registros que hoy genera el mockup sin login real.
INSERT INTO usuarios (nombres, apellidos, email, rol_id, activo) VALUES
    ('Sistema', 'GTQC', 'sistema@gtqc.local', 1, TRUE);


-- ============================================================================
-- 1. CLIENTES: EMPRESA (RUC) / CONTACTO / PERSONA NATURAL (DNI)
-- ============================================================================
-- Regla de negocio: una cotización pertenece SIEMPRE a una EMPRESA+CONTACTO
-- o a una PERSONA, nunca a ambas. Se valida con el CHECK en cotizaciones.

CREATE TABLE empresas (
    id                  SERIAL PRIMARY KEY,
    ruc                 VARCHAR(11) NOT NULL UNIQUE,
    razon_social        VARCHAR(200) NOT NULL,
    direccion           VARCHAR(250),
    telefono            VARCHAR(20),
    email               VARCHAR(150),
    estado              VARCHAR(20) NOT NULL DEFAULT 'activo',   -- activo | inactivo
    -- auditoría
    creado_por          INTEGER NOT NULL REFERENCES usuarios(id),
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_por     INTEGER REFERENCES usuarios(id),
    actualizado_en      TIMESTAMPTZ
);
CREATE INDEX idx_empresas_ruc ON empresas(ruc);

-- Una empresa puede tener varios contactos (personas) que cotizan en su nombre.
CREATE TABLE contactos (
    id                  SERIAL PRIMARY KEY,
    empresa_id          INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    dni                 VARCHAR(8),
    nombres             VARCHAR(100) NOT NULL,
    apellidos           VARCHAR(100) NOT NULL,
    cargo               VARCHAR(100),
    celular             VARCHAR(20),
    email               VARCHAR(150),
    -- auditoría
    creado_por          INTEGER NOT NULL REFERENCES usuarios(id),
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_por     INTEGER REFERENCES usuarios(id),
    actualizado_en      TIMESTAMPTZ
);
CREATE INDEX idx_contactos_empresa ON contactos(empresa_id);

-- Cliente individual que cotiza con DNI (sin empresa), o con una empresa
-- asociada solo como referencia informal (no como FK, porque muchas veces
-- el cliente da el nombre de una empresa que no está registrada aún).
CREATE TABLE personas (
    id                  SERIAL PRIMARY KEY,
    dni                 VARCHAR(8) NOT NULL UNIQUE,
    nombres             VARCHAR(100) NOT NULL,
    apellidos           VARCHAR(100) NOT NULL,
    celular             VARCHAR(20),
    email               VARCHAR(150),
    empresa_asociada    VARCHAR(200),   -- texto libre, informal
    -- auditoría
    creado_por          INTEGER NOT NULL REFERENCES usuarios(id),
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_por     INTEGER REFERENCES usuarios(id),
    actualizado_en      TIMESTAMPTZ
);
CREATE INDEX idx_personas_dni ON personas(dni);


-- ============================================================================
-- 2. CATÁLOGO DE ENSAYOS: CATEGORÍA > SUBCATEGORÍA > ENSAYO
-- ============================================================================

-- Categorías y subcategorías son EDITABLES por el usuario (Más → Categorías
-- y subcategorías en la app). Reglas del modelo, protegidas aquí mismo:
--   R1. Jerarquía estricta Categoría (1) → Subcategorías (N) → Ensayos (N).
--       La categoría de un ensayo se deduce de su subcategoría (no se repite).
--   R2. Toda categoría ACTIVA tiene al menos una subcategoría activa
--       (fn_crear_categoria crea sola la subcategoría "General").
--   R3. Lo que tiene ensayos NO se borra: se desactiva (activo = FALSE).
--       Desactivado = no se ofrece en "Nueva Cotización" (vw_catalogo_disponible),
--       pero cotizaciones, PDFs y dashboard conservan su historial.
--   R4. prefijo_codigo (SU, AG…) arma el código de los ensayos (SU-01) y queda
--       fijo en cuanto la categoría tiene ensayos.
--   R5. Nombres únicos: categoría en todo el catálogo; subcategoría dentro de
--       su categoría (sin distinguir mayúsculas).
CREATE TABLE categorias_ensayo (
    id              SERIAL PRIMARY KEY,
    slug            VARCHAR(40) NOT NULL UNIQUE,     -- 'suelos','concreto'… (identificador estable para integraciones)
    nombre          VARCHAR(40) NOT NULL,
    prefijo_codigo  VARCHAR(3)  NOT NULL UNIQUE
                    CHECK (prefijo_codigo ~ '^[A-Z]{2,3}$'),   -- R4
    icono           VARCHAR(10),                     -- emoji para la UI
    color_hex       VARCHAR(7)  CHECK (color_hex ~ '^#[0-9a-fA-F]{6}$'),  -- color de la categoría en pestañas y gráficos
    orden           SMALLINT NOT NULL DEFAULT 0,     -- orden de las pestañas en Nueva Cotización y del dashboard
    activo          BOOLEAN NOT NULL DEFAULT TRUE,   -- R3: desactivar en vez de borrar
    -- auditoría
    creado_por      INTEGER NOT NULL REFERENCES usuarios(id),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_por INTEGER REFERENCES usuarios(id),
    actualizado_en  TIMESTAMPTZ
);
CREATE UNIQUE INDEX uq_categorias_nombre ON categorias_ensayo (lower(nombre));   -- R5

CREATE TABLE subcategorias_ensayo (
    id              SERIAL PRIMARY KEY,
    categoria_id    INTEGER NOT NULL REFERENCES categorias_ensayo(id) ON DELETE CASCADE,
    nombre          VARCHAR(40) NOT NULL,             -- 'Estándares y Especiales','Químicos','Paquetes','Campo'
    orden           SMALLINT NOT NULL DEFAULT 0,
    activo          BOOLEAN NOT NULL DEFAULT TRUE,    -- R3
    -- auditoría
    creado_por      INTEGER NOT NULL REFERENCES usuarios(id),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_por INTEGER REFERENCES usuarios(id),
    actualizado_en  TIMESTAMPTZ
);
CREATE UNIQUE INDEX uq_subcategorias_nombre ON subcategorias_ensayo (categoria_id, lower(nombre));  -- R5
CREATE INDEX idx_subcategorias_categoria ON subcategorias_ensayo(categoria_id);

-- El corazón del sistema: cada fila es un servicio vendible.
-- `es_paquete` = TRUE cuando el ensayo es en realidad un combo de varios
-- (ver paquete_componentes). El precio del paquete es propio (no se sólo
-- suma automáticamente), porque el laboratorio da descuento por combo.
CREATE TABLE ensayos_catalogo (
    id                  SERIAL PRIMARY KEY,
    codigo              VARCHAR(10) NOT NULL UNIQUE,     -- 'SU-01','AG-14','AS-03','AL-06'
    subcategoria_id     INTEGER NOT NULL REFERENCES subcategorias_ensayo(id),
    nombre              VARCHAR(220) NOT NULL,
    descripcion         VARCHAR(500),
    unidad              VARCHAR(20) NOT NULL DEFAULT 'UND',   -- UND | PUNT. | DÍA
    norma               VARCHAR(120),                          -- 'ASTM D2216-19', 'NTP 339.152', etc.
    precio_base         NUMERIC(10,2) NOT NULL,
    es_paquete          BOOLEAN NOT NULL DEFAULT FALSE,
    acreditado          BOOLEAN NOT NULL DEFAULT FALSE,        -- ISO/IEC 17025 vigente para este ensayo
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    -- auditoría
    creado_por          INTEGER NOT NULL REFERENCES usuarios(id),
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_por     INTEGER REFERENCES usuarios(id),
    actualizado_en      TIMESTAMPTZ
);
CREATE INDEX idx_ensayos_subcategoria ON ensayos_catalogo(subcategoria_id);
CREATE INDEX idx_ensayos_codigo ON ensayos_catalogo(codigo);
CREATE INDEX idx_ensayos_acreditado ON ensayos_catalogo(acreditado);

-- Historial de acreditación: cuándo un ensayo ganó o perdió su alcance
-- acreditado. Esto es exactamente lo que un auditor ISO 17025 pide:
-- trazabilidad de la vigencia de la acreditación, no solo el estado actual.
CREATE TABLE ensayo_acreditacion_historial (
    id              SERIAL PRIMARY KEY,
    ensayo_id       INTEGER NOT NULL REFERENCES ensayos_catalogo(id) ON DELETE CASCADE,
    acreditado      BOOLEAN NOT NULL,
    motivo          VARCHAR(300),                     -- 'Renovación INACAL 2026', 'Alcance retirado', ...
    vigente_desde   DATE NOT NULL DEFAULT CURRENT_DATE,
    registrado_por  INTEGER NOT NULL REFERENCES usuarios(id),
    registrado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- PAQUETES: un paquete es un ensayo más del catálogo (es_paquete = TRUE),
-- vive en una subcategoría y tiene su propio código y precio (el laboratorio
-- da descuento por combo). Sus componentes se AMARRAN a ensayos reales del
-- catálogo mediante ensayo_componente_id, así:
--   · nombre y norma del componente salen del ensayo vinculado (una sola
--     fuente de verdad: si se corrige la norma del ensayo, el paquete la ve);
--   · se puede calcular cuánto costarían sus ensayos por separado;
--   · no se puede borrar un ensayo que forma parte de un paquete.
-- Reglas de paquetes:
--   P1. Solo un ensayo con es_paquete = TRUE puede tener componentes.
--   P2. Un componente vinculado es un ensayo INDIVIDUAL (no se anidan paquetes)
--       y nunca el propio paquete.
--   P3. El mismo ensayo no se repite dentro de un paquete (se usa `cantidad`).
--   P4. Un paquete creado o editado desde la app tiene al menos 2 componentes
--       (fn_crear_paquete / fn_definir_componentes).
--   P5. Los componentes pueden venir de otra categoría (ej. el paquete de
--       cantera de Suelos incluye "Abrasión Los Ángeles" de Concreto).
-- Compatibilidad: los componentes históricos que aún no tienen un ensayo
-- equivalente vendible (ej. "Clasificación SUCS") quedan DESCRIPTIVOS
-- (nombre + norma, ensayo_componente_id NULL) y la app los marca como
-- "sin vincular" para que el laboratorio decida.
CREATE TABLE paquete_componentes (
    id                    SERIAL PRIMARY KEY,
    ensayo_id             INTEGER NOT NULL REFERENCES ensayos_catalogo(id) ON DELETE CASCADE,   -- el paquete
    orden                 SMALLINT NOT NULL DEFAULT 0,
    ensayo_componente_id  INTEGER REFERENCES ensayos_catalogo(id) ON DELETE RESTRICT,     -- el ensayo incluido (vínculo)
    cantidad              SMALLINT NOT NULL DEFAULT 1 CHECK (cantidad BETWEEN 1 AND 999),
    nombre                VARCHAR(200),     -- solo para componentes descriptivos (sin vínculo)
    norma                 VARCHAR(120),
    CONSTRAINT ck_componente_vinculado_o_descrito
        CHECK (ensayo_componente_id IS NOT NULL OR nombre IS NOT NULL),
    CONSTRAINT ck_componente_no_es_el_paquete
        CHECK (ensayo_componente_id IS NULL OR ensayo_componente_id <> ensayo_id)          -- P2
);
CREATE INDEX idx_paquete_componentes_ensayo ON paquete_componentes(ensayo_id);
CREATE INDEX idx_paquete_componentes_componente ON paquete_componentes(ensayo_componente_id);
CREATE UNIQUE INDEX uq_paquete_componente ON paquete_componentes(ensayo_id, ensayo_componente_id)
    WHERE ensayo_componente_id IS NOT NULL;                                                      -- P3


-- ============================================================================
-- 3. PLANTILLAS DE COTIZACIÓN
-- ============================================================================
-- Cada plantilla trae sus propios términos y condiciones y validez sugerida;
-- el usuario elige la plantilla en el paso "Vista Previa" del wizard.

CREATE TABLE plantillas_cotizacion (
    id                      SERIAL PRIMARY KEY,
    slug                    VARCHAR(30) NOT NULL UNIQUE,   -- 'estandar','premium','express'
    nombre                  VARCHAR(60) NOT NULL,
    icono                   VARCHAR(10),
    validez_dias_sugerida   SMALLINT NOT NULL DEFAULT 15,
    terminos_condiciones    TEXT NOT NULL,
    activo                  BOOLEAN NOT NULL DEFAULT TRUE,
    creado_por              INTEGER NOT NULL REFERENCES usuarios(id),
    creado_en               TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_por         INTEGER REFERENCES usuarios(id),
    actualizado_en          TIMESTAMPTZ
);

-- Regla de negocio: máximo 3 plantillas activas (coincide con el límite que
-- ya aplica la app en Config > Plantillas). Se valida con un trigger porque
-- un CHECK de fila no puede contar filas hermanas.
CREATE OR REPLACE FUNCTION fn_max_plantillas_activas() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.activo AND (SELECT COUNT(*) FROM plantillas_cotizacion WHERE activo = TRUE AND id <> COALESCE(NEW.id, -1)) >= 3 THEN
        RAISE EXCEPTION 'Máximo 3 plantillas activas. Desactiva o elimina una antes de crear otra.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_max_plantillas_activas
BEFORE INSERT OR UPDATE ON plantillas_cotizacion
FOR EACH ROW EXECUTE FUNCTION fn_max_plantillas_activas();


-- ============================================================================
-- 4. COTIZACIONES
-- ============================================================================

CREATE TABLE cotizaciones (
    id                  SERIAL PRIMARY KEY,
    numero              VARCHAR(20) NOT NULL UNIQUE,      -- 'COT-2026-001'

    -- Cliente: exactamente uno de los dos bloques debe estar lleno.
    empresa_id          INTEGER REFERENCES empresas(id),
    contacto_id         INTEGER REFERENCES contactos(id),
    persona_id          INTEGER REFERENCES personas(id),
    CONSTRAINT chk_cliente_unico CHECK (
        (empresa_id IS NOT NULL AND persona_id IS NULL) OR
        (empresa_id IS NULL AND persona_id IS NOT NULL)
    ),

    proyecto_nombre     VARCHAR(200) NOT NULL,
    validez_dias        SMALLINT NOT NULL DEFAULT 15,
    plantilla_id        INTEGER NOT NULL REFERENCES plantillas_cotizacion(id),

    subtotal            NUMERIC(12,2) NOT NULL DEFAULT 0,
    igv                 NUMERIC(12,2) NOT NULL DEFAULT 0,     -- 18% sobre subtotal
    descuento_tipo      VARCHAR(12),                          -- 'porcentaje' | 'monto' | NULL
    descuento_valor     NUMERIC(10,2) NOT NULL DEFAULT 0,     -- el valor tal cual lo ingresó el usuario
    descuento_monto     NUMERIC(12,2) NOT NULL DEFAULT 0,     -- el monto S/ ya calculado
    descuento_razon     VARCHAR(300),
    total               NUMERIC(12,2) NOT NULL DEFAULT 0,     -- subtotal + igv - descuento_monto

    notas               TEXT,
    estado              VARCHAR(20) NOT NULL DEFAULT 'emitida',  -- emitida|aceptada|rechazada|cancelada

    -- auditoría (clave para "verificación" futura de la app)
    creado_por          INTEGER NOT NULL REFERENCES usuarios(id),
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_por     INTEGER REFERENCES usuarios(id),
    actualizado_en      TIMESTAMPTZ
);
CREATE INDEX idx_cotizaciones_estado ON cotizaciones(estado);
CREATE INDEX idx_cotizaciones_empresa ON cotizaciones(empresa_id);
CREATE INDEX idx_cotizaciones_persona ON cotizaciones(persona_id);
CREATE INDEX idx_cotizaciones_fecha ON cotizaciones(creado_en);

-- Ítems de la cotización. Se guarda un SNAPSHOT del ensayo (nombre, norma,
-- acreditado, precio) en el momento de cotizar: si mañana cambia el precio
-- o el estado de acreditación en el catálogo, las cotizaciones ya emitidas
-- no deben cambiar retroactivamente. Por eso NO se lee el precio en vivo
-- desde ensayos_catalogo al mostrar una cotización histórica.
CREATE TABLE cotizacion_items (
    id                  SERIAL PRIMARY KEY,
    cotizacion_id       INTEGER NOT NULL REFERENCES cotizaciones(id) ON DELETE CASCADE,
    ensayo_id           INTEGER REFERENCES ensayos_catalogo(id),   -- referencia al catálogo; un ensayo ya cotizado no se borra, se desactiva
    codigo_snapshot     VARCHAR(10) NOT NULL,
    nombre_snapshot     VARCHAR(220) NOT NULL,
    norma_snapshot      VARCHAR(120),
    acreditado_snapshot BOOLEAN NOT NULL,   -- valor que viaja al PDF; por defecto copia el del catálogo al agregar el ítem
    acreditado_override BOOLEAN NOT NULL DEFAULT FALSE, -- TRUE si el usuario lo cambió a mano en el paso "Resumen" (paso 3), distinto del catálogo maestro
    cantidad            NUMERIC(8,2) NOT NULL DEFAULT 1,
    precio_unitario     NUMERIC(10,2) NOT NULL,
    subtotal            NUMERIC(12,2) NOT NULL,
    -- Si el ítem es un paquete: "foto" de lo que incluía el día de la
    -- cotización ([{codigo, nombre, norma, cantidad}]), para que el PDF no
    -- cambie si mañana se edita la composición del paquete.
    componentes_snapshot JSONB
);
CREATE INDEX idx_items_cotizacion ON cotizacion_items(cotizacion_id);
CREATE INDEX idx_items_ensayo ON cotizacion_items(ensayo_id);

-- Línea de tiempo de estados (Emitida -> Aceptada / Rechazada / Cancelada).
-- Es lo que alimenta la vista "Historial" del dashboard.
CREATE TABLE cotizacion_historial_estados (
    id              SERIAL PRIMARY KEY,
    cotizacion_id   INTEGER NOT NULL REFERENCES cotizaciones(id) ON DELETE CASCADE,
    estado          VARCHAR(20) NOT NULL,
    nota            VARCHAR(300),
    registrado_por  INTEGER NOT NULL REFERENCES usuarios(id),
    registrado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_historial_cotizacion ON cotizacion_historial_estados(cotizacion_id);


-- ============================================================================
-- 4.1. INTEGRACIONES SAAS (Google Drive / Microsoft 365)
-- ============================================================================
-- Pensado para cuando los clientes del laboratorio quieran que sus PDFs y
-- certificados de ensayo se guarden automáticamente en su propia nube.
-- Una integración es por empresa (no por usuario individual): cualquier
-- persona con acceso a la cuenta de esa empresa puede usarla.
--
-- IMPORTANTE DE SEGURIDAD: access_token/refresh_token NUNCA se guardan en
-- texto plano en esta tabla en un ambiente real. Aquí solo se guarda una
-- referencia (token_ref) a donde vive el secreto real (un vault / secrets
-- manager como AWS Secrets Manager, GCP Secret Manager o Vault de Hashicorp).
CREATE TABLE integraciones (
    id                SERIAL PRIMARY KEY,
    empresa_id        INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    proveedor         VARCHAR(20) NOT NULL CHECK (proveedor IN ('google_drive','office365')),
    cuenta_email      VARCHAR(150),
    token_ref         VARCHAR(200),        -- referencia al secreto en el vault, NUNCA el token real
    estado            VARCHAR(15) NOT NULL DEFAULT 'activa' CHECK (estado IN ('activa','revocada','expirada')),
    conectado_por     INTEGER NOT NULL REFERENCES usuarios(id),
    conectado_en      TIMESTAMPTZ NOT NULL DEFAULT now(),
    revocado_en       TIMESTAMPTZ,
    UNIQUE(empresa_id, proveedor)
);
CREATE INDEX idx_integraciones_empresa ON integraciones(empresa_id);

-- Cada vez que un PDF/certificado se sube a la nube del cliente, queda el
-- rastro aquí (útil también para una futura auditoría de a dónde salió cada
-- documento).
CREATE TABLE documentos_externos (
    id              SERIAL PRIMARY KEY,
    cotizacion_id   INTEGER NOT NULL REFERENCES cotizaciones(id) ON DELETE CASCADE,
    integracion_id  INTEGER NOT NULL REFERENCES integraciones(id),
    tipo_documento  VARCHAR(20) NOT NULL DEFAULT 'cotizacion_pdf' CHECK (tipo_documento IN ('cotizacion_pdf','certificado_ensayo')),
    url_externo     VARCHAR(500) NOT NULL,
    subido_por      INTEGER NOT NULL REFERENCES usuarios(id),
    subido_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_documentos_externos_cotizacion ON documentos_externos(cotizacion_id);


-- ============================================================================
-- 5. AUDITORÍA GENÉRICA (para cualquier tabla, no solo cotizaciones)
-- ============================================================================
-- Complementa los campos creado_por/actualizado_por: aquí queda el detalle
-- fino (qué campo cambió, de qué valor a qué valor) para una auditoría
-- externa (ISO 17025, revisión legal, o debugging de soporte).

CREATE TABLE auditoria (
    id              BIGSERIAL PRIMARY KEY,
    tabla           VARCHAR(60) NOT NULL,       -- 'ensayos_catalogo', 'cotizaciones', ...
    registro_id     INTEGER NOT NULL,
    accion          VARCHAR(10) NOT NULL,       -- INSERT | UPDATE | DELETE
    datos_anteriores JSONB,
    datos_nuevos     JSONB,
    usuario_id      INTEGER NOT NULL REFERENCES usuarios(id),
    ip_origen       VARCHAR(45),
    registrado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_auditoria_tabla_registro ON auditoria(tabla, registro_id);
CREATE INDEX idx_auditoria_fecha ON auditoria(registrado_en);

-- Trigger de ejemplo (Postgres) para auditar cambios de precio/acreditación
-- en el catálogo automáticamente. Se replica el mismo patrón en las demás
-- tablas sensibles (cotizaciones, empresas) cuando el proyecto lo requiera.
CREATE OR REPLACE FUNCTION fn_auditar_ensayos_catalogo() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        INSERT INTO auditoria(tabla, registro_id, accion, datos_anteriores, datos_nuevos, usuario_id)
        VALUES ('ensayos_catalogo', OLD.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW),
                COALESCE(NEW.actualizado_por, OLD.creado_por));
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO auditoria(tabla, registro_id, accion, datos_nuevos, usuario_id)
        VALUES ('ensayos_catalogo', NEW.id, 'INSERT', to_jsonb(NEW), NEW.creado_por);
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO auditoria(tabla, registro_id, accion, datos_anteriores, usuario_id)
        VALUES ('ensayos_catalogo', OLD.id, 'DELETE', to_jsonb(OLD), OLD.creado_por);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditar_ensayos_catalogo
AFTER INSERT OR UPDATE OR DELETE ON ensayos_catalogo
FOR EACH ROW EXECUTE FUNCTION fn_auditar_ensayos_catalogo();


-- ============================================================================
-- 5.1 REGLAS DEL CATÁLOGO EDITABLE (categorías / subcategorías / ensayos)
-- ============================================================================
-- La app valida estas reglas antes de guardar (mejor experiencia), pero la
-- base de datos las vuelve a exigir: así ningún otro canal (API, importación,
-- un script) puede dejar el catálogo inconsistente.

-- Auditoría genérica: sirve para cualquier tabla con creado_por/actualizado_por
CREATE OR REPLACE FUNCTION fn_auditar_generico() RETURNS TRIGGER AS $$
DECLARE
    v_new JSONB := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
    v_old JSONB := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
    v_usuario INTEGER := COALESCE((v_new->>'actualizado_por')::INT, (v_new->>'creado_por')::INT,
                                  (v_old->>'actualizado_por')::INT, (v_old->>'creado_por')::INT, 1);
BEGIN
    INSERT INTO auditoria(tabla, registro_id, accion, datos_anteriores, datos_nuevos, usuario_id)
    VALUES (TG_TABLE_NAME, COALESCE((v_new->>'id')::INT, (v_old->>'id')::INT), TG_OP, v_old, v_new, v_usuario);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditar_categorias
AFTER INSERT OR UPDATE OR DELETE ON categorias_ensayo
FOR EACH ROW EXECUTE FUNCTION fn_auditar_generico();

CREATE TRIGGER trg_auditar_subcategorias
AFTER INSERT OR UPDATE OR DELETE ON subcategorias_ensayo
FOR EACH ROW EXECUTE FUNCTION fn_auditar_generico();

-- Cantidad de ensayos (activos o no) que cuelgan de una categoría
CREATE OR REPLACE FUNCTION fn_ensayos_de_categoria(p_categoria_id INT) RETURNS BIGINT AS $$
    SELECT COUNT(*) FROM ensayos_catalogo ec
    JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
    WHERE se.categoria_id = p_categoria_id;
$$ LANGUAGE sql STABLE;

-- CATEGORÍA: R3 (no borrar con ensayos), R4 (prefijo fijo), última activa
CREATE OR REPLACE FUNCTION fn_proteger_categoria() RETURNS TRIGGER AS $$
DECLARE v_n BIGINT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_n := fn_ensayos_de_categoria(OLD.id);
        IF v_n > 0 THEN
            RAISE EXCEPTION 'La categoría "%" tiene % ensayo(s): desactívela (activo = FALSE) en lugar de eliminarla', OLD.nombre, v_n
                USING ERRCODE = 'restrict_violation';
        END IF;
        RETURN OLD;
    END IF;

    IF NEW.prefijo_codigo <> OLD.prefijo_codigo AND fn_ensayos_de_categoria(OLD.id) > 0 THEN
        RAISE EXCEPTION 'El prefijo "%" ya se usa en códigos de ensayo; no se puede cambiar', OLD.prefijo_codigo
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.activo AND NOT NEW.activo
       AND NOT EXISTS (SELECT 1 FROM categorias_ensayo WHERE activo AND id <> OLD.id) THEN
        RAISE EXCEPTION 'Debe quedar al menos una categoría activa' USING ERRCODE = 'restrict_violation';
    END IF;
    NEW.actualizado_en := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_proteger_categoria
BEFORE UPDATE OR DELETE ON categorias_ensayo
FOR EACH ROW EXECUTE FUNCTION fn_proteger_categoria();

-- R2 al reactivar: si la categoría vuelve a estar activa sin subcategorías
-- activas, se reactiva la primera (mismo comportamiento que la app).
CREATE OR REPLACE FUNCTION fn_categoria_reactivada() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.activo AND NOT OLD.activo
       AND NOT EXISTS (SELECT 1 FROM subcategorias_ensayo WHERE categoria_id = NEW.id AND activo) THEN
        UPDATE subcategorias_ensayo SET activo = TRUE, actualizado_por = NEW.actualizado_por
        WHERE id = (SELECT id FROM subcategorias_ensayo WHERE categoria_id = NEW.id ORDER BY orden, id LIMIT 1);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_categoria_reactivada
AFTER UPDATE OF activo ON categorias_ensayo
FOR EACH ROW EXECUTE FUNCTION fn_categoria_reactivada();

-- SUBCATEGORÍA: R3 (no borrar con ensayos), R2 (no quitar la última activa),
-- y no mudarla de categoría si ya tiene ensayos (romperías sus códigos).
CREATE OR REPLACE FUNCTION fn_proteger_subcategoria() RETURNS TRIGGER AS $$
DECLARE v_n BIGINT; v_cat_activa BOOLEAN;
BEGIN
    SELECT COUNT(*) INTO v_n FROM ensayos_catalogo WHERE subcategoria_id = OLD.id;
    -- Si la categoría ya no existe (se está borrando en cascada) no aplica R2
    SELECT activo INTO v_cat_activa FROM categorias_ensayo WHERE id = OLD.categoria_id;

    IF TG_OP = 'DELETE' THEN
        IF v_n > 0 THEN
            RAISE EXCEPTION 'La subcategoría "%" tiene % ensayo(s): desactívela en lugar de eliminarla', OLD.nombre, v_n
                USING ERRCODE = 'restrict_violation';
        END IF;
        IF OLD.activo AND v_cat_activa AND NOT EXISTS (
            SELECT 1 FROM subcategorias_ensayo WHERE categoria_id = OLD.categoria_id AND activo AND id <> OLD.id) THEN
            RAISE EXCEPTION 'Es la única subcategoría activa de su categoría' USING ERRCODE = 'restrict_violation';
        END IF;
        RETURN OLD;
    END IF;

    IF NEW.categoria_id <> OLD.categoria_id AND v_n > 0 THEN
        RAISE EXCEPTION 'No se puede mover "%" a otra categoría: sus ensayos ya tienen código', OLD.nombre
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.activo AND NOT NEW.activo AND v_cat_activa AND NOT EXISTS (
        SELECT 1 FROM subcategorias_ensayo WHERE categoria_id = OLD.categoria_id AND activo AND id <> OLD.id) THEN
        RAISE EXCEPTION 'Es la única subcategoría activa de su categoría' USING ERRCODE = 'restrict_violation';
    END IF;
    NEW.actualizado_en := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_proteger_subcategoria
BEFORE UPDATE OR DELETE ON subcategorias_ensayo
FOR EACH ROW EXECUTE FUNCTION fn_proteger_subcategoria();

-- ENSAYO: su código debe empezar con el prefijo de su categoría (R4)
CREATE OR REPLACE FUNCTION fn_validar_codigo_ensayo() RETURNS TRIGGER AS $$
DECLARE v_prefijo VARCHAR(3);
BEGIN
    SELECT ce.prefijo_codigo INTO v_prefijo
    FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
    WHERE se.id = NEW.subcategoria_id;
    IF NEW.codigo !~ ('^' || v_prefijo || '-[0-9]{2,3}$') THEN
        RAISE EXCEPTION 'El código "%" no corresponde a la categoría (debe ser %-NN)', NEW.codigo, v_prefijo
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_codigo_ensayo
BEFORE INSERT OR UPDATE OF codigo, subcategoria_id ON ensayos_catalogo
FOR EACH ROW EXECUTE FUNCTION fn_validar_codigo_ensayo();

-- ---------------------------------------------------------------------------
-- Casos de uso (lo que llama el backend desde las pantallas de la app)
-- ---------------------------------------------------------------------------

-- Crear categoría = categoría + subcategoría "General" en una sola operación (R2)
CREATE OR REPLACE FUNCTION fn_crear_categoria(
    p_nombre VARCHAR, p_prefijo VARCHAR, p_icono VARCHAR, p_color VARCHAR, p_usuario INT
) RETURNS INT AS $$
DECLARE v_id INT; v_slug VARCHAR(40);
BEGIN
    v_slug := left(trim(both '_' from regexp_replace(translate(lower(p_nombre), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', '_', 'g')), 32);
    IF v_slug = '' OR EXISTS (SELECT 1 FROM categorias_ensayo WHERE slug = v_slug) THEN
        v_slug := left(v_slug, 26) || '_' || lower(p_prefijo);
    END IF;
    INSERT INTO categorias_ensayo (slug, nombre, prefijo_codigo, icono, color_hex, orden, creado_por)
    VALUES (v_slug, trim(p_nombre), upper(p_prefijo), p_icono, p_color,
            COALESCE((SELECT MAX(orden) FROM categorias_ensayo), 0) + 1, p_usuario)
    RETURNING id INTO v_id;
    INSERT INTO subcategorias_ensayo (categoria_id, nombre, orden, creado_por)
    VALUES (v_id, 'General', 1, p_usuario);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Próximo código libre de una categoría: SU-28 → SU-29
CREATE OR REPLACE FUNCTION fn_siguiente_codigo_ensayo(p_categoria_id INT) RETURNS VARCHAR AS $$
    SELECT ce.prefijo_codigo || '-' || lpad((COALESCE(MAX(split_part(ec.codigo, '-', 2)::INT), 0) + 1)::TEXT, 2, '0')
    FROM categorias_ensayo ce
    LEFT JOIN ensayos_catalogo ec ON ec.codigo LIKE ce.prefijo_codigo || '-%'
    WHERE ce.id = p_categoria_id
    GROUP BY ce.prefijo_codigo;
$$ LANGUAGE sql STABLE;

-- Crear ensayo con código automático. Bloquea la fila de la categoría para
-- que dos usuarios a la vez no obtengan el mismo código.
CREATE OR REPLACE FUNCTION fn_crear_ensayo(
    p_subcategoria_id INT, p_nombre VARCHAR, p_norma VARCHAR, p_unidad VARCHAR,
    p_precio NUMERIC, p_acreditado BOOLEAN, p_usuario INT
) RETURNS VARCHAR AS $$
DECLARE v_cat INT; v_codigo VARCHAR(10); v_id INT;
BEGIN
    SELECT categoria_id INTO v_cat FROM subcategorias_ensayo WHERE id = p_subcategoria_id AND activo;
    IF v_cat IS NULL THEN
        RAISE EXCEPTION 'La subcategoría no existe o está inactiva';
    END IF;
    PERFORM 1 FROM categorias_ensayo WHERE id = v_cat FOR UPDATE;
    v_codigo := fn_siguiente_codigo_ensayo(v_cat);
    INSERT INTO ensayos_catalogo (codigo, subcategoria_id, nombre, unidad, norma, precio_base, acreditado, creado_por)
    VALUES (v_codigo, p_subcategoria_id, p_nombre, COALESCE(p_unidad, 'UND'), p_norma, p_precio, COALESCE(p_acreditado, FALSE), p_usuario)
    RETURNING id INTO v_id;
    INSERT INTO ensayo_acreditacion_historial (ensayo_id, acreditado, motivo, registrado_por)
    VALUES (v_id, COALESCE(p_acreditado, FALSE), 'Alta del ensayo en el catálogo', p_usuario);
    RETURN v_codigo;
END;
$$ LANGUAGE plpgsql;

-- Lo que se ofrece en "Nueva Cotización": solo lo activo en los 3 niveles,
-- en el orden que el usuario definió para categorías y subcategorías.
CREATE VIEW vw_catalogo_disponible AS
SELECT
    ce.id AS categoria_id, ce.nombre AS categoria, ce.icono, ce.color_hex, ce.orden AS orden_categoria,
    se.id AS subcategoria_id, se.nombre AS subcategoria, se.orden AS orden_subcategoria,
    ec.id AS ensayo_id, ec.codigo, ec.nombre, ec.norma, ec.unidad, ec.precio_base, ec.es_paquete, ec.acreditado
FROM ensayos_catalogo ec
JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
JOIN categorias_ensayo ce    ON ce.id = se.categoria_id
WHERE ec.activo AND se.activo AND ce.activo
ORDER BY ce.orden, se.orden, ec.codigo;


-- ---------------------------------------------------------------------------
-- 5.2 ENSAYOS Y PAQUETES: reglas y casos de uso
-- ---------------------------------------------------------------------------

-- ENSAYO: no se borra si ya se cotizó o si forma parte de un paquete (R3);
-- no se convierte en paquete (o deja de serlo) si eso rompe sus vínculos (P1/P2).
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
        RAISE EXCEPTION 'El ensayo % es componente de otro paquete; no puede convertirse en paquete (no se anidan paquetes)', OLD.codigo
            USING ERRCODE = 'restrict_violation';
    END IF;
    NEW.actualizado_en := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_proteger_ensayo
BEFORE UPDATE OR DELETE ON ensayos_catalogo
FOR EACH ROW EXECUTE FUNCTION fn_proteger_ensayo();

-- COMPONENTE: el dueño debe ser paquete (P1) y el vinculado un ensayo individual (P2)
CREATE OR REPLACE FUNCTION fn_validar_componente() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ensayos_catalogo WHERE id = NEW.ensayo_id AND es_paquete) THEN
        RAISE EXCEPTION 'Solo un paquete (es_paquete = TRUE) puede tener componentes' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.ensayo_componente_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM ensayos_catalogo WHERE id = NEW.ensayo_componente_id AND es_paquete) THEN
        RAISE EXCEPTION 'Un paquete no puede incluir otro paquete' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_componente
BEFORE INSERT OR UPDATE ON paquete_componentes
FOR EACH ROW EXECUTE FUNCTION fn_validar_componente();

CREATE TRIGGER trg_auditar_paquete_componentes
AFTER INSERT OR UPDATE OR DELETE ON paquete_componentes
FOR EACH ROW EXECUTE FUNCTION fn_auditar_generico();

-- Reemplaza TODOS los componentes de un paquete (lo que hace el botón
-- "Guardar paquete"). p_componentes es un arreglo JSON, en orden:
--   [{"ensayo_id": 12, "cantidad": 1}, {"nombre": "Clasificación SUCS", "norma": "ASTM D2487"}]
CREATE OR REPLACE FUNCTION fn_definir_componentes(p_paquete_id INT, p_componentes JSONB, p_usuario INT)
RETURNS INT AS $$
DECLARE v_n INT;
BEGIN
    v_n := jsonb_array_length(COALESCE(p_componentes, '[]'::jsonb));
    IF v_n < 2 THEN
        RAISE EXCEPTION 'Un paquete debe incluir al menos 2 ensayos (recibió %)', v_n USING ERRCODE = 'check_violation';   -- P4
    END IF;
    DELETE FROM paquete_componentes WHERE ensayo_id = p_paquete_id;
    INSERT INTO paquete_componentes (ensayo_id, orden, ensayo_componente_id, cantidad, nombre, norma)
    SELECT p_paquete_id, (x.ord - 1)::SMALLINT,
           NULLIF(x.elem->>'ensayo_id', '')::INT,
           COALESCE((x.elem->>'cantidad')::SMALLINT, 1),
           CASE WHEN x.elem ? 'ensayo_id' THEN NULL ELSE x.elem->>'nombre' END,
           CASE WHEN x.elem ? 'ensayo_id' THEN NULL ELSE x.elem->>'norma' END
    FROM jsonb_array_elements(p_componentes) WITH ORDINALITY AS x(elem, ord);
    UPDATE ensayos_catalogo SET actualizado_por = p_usuario WHERE id = p_paquete_id;
    RETURN v_n;
END;
$$ LANGUAGE plpgsql;

-- Crear paquete = ensayo con es_paquete = TRUE + sus componentes, todo o nada
CREATE OR REPLACE FUNCTION fn_crear_paquete(
    p_subcategoria_id INT, p_nombre VARCHAR, p_unidad VARCHAR, p_precio NUMERIC,
    p_acreditado BOOLEAN, p_componentes JSONB, p_usuario INT
) RETURNS VARCHAR AS $$
DECLARE v_cat INT; v_codigo VARCHAR(10); v_id INT;
BEGIN
    SELECT categoria_id INTO v_cat FROM subcategorias_ensayo WHERE id = p_subcategoria_id AND activo;
    IF v_cat IS NULL THEN RAISE EXCEPTION 'La subcategoría no existe o está inactiva'; END IF;
    PERFORM 1 FROM categorias_ensayo WHERE id = v_cat FOR UPDATE;
    v_codigo := fn_siguiente_codigo_ensayo(v_cat);
    INSERT INTO ensayos_catalogo (codigo, subcategoria_id, nombre, unidad, precio_base, es_paquete, acreditado, creado_por)
    VALUES (v_codigo, p_subcategoria_id, p_nombre, COALESCE(p_unidad, 'UND'), p_precio, TRUE, COALESCE(p_acreditado, FALSE), p_usuario)
    RETURNING id INTO v_id;
    PERFORM fn_definir_componentes(v_id, p_componentes, p_usuario);
    INSERT INTO ensayo_acreditacion_historial (ensayo_id, acreditado, motivo, registrado_por)
    VALUES (v_id, COALESCE(p_acreditado, FALSE), 'Alta del paquete en el catálogo', p_usuario);
    RETURN v_codigo;
END;
$$ LANGUAGE plpgsql;

-- Detalle de cada paquete: nombre y norma salen del ensayo vinculado
CREATE VIEW vw_paquete_detalle AS
SELECT
    p.codigo                        AS paquete_codigo,
    p.nombre                        AS paquete,
    pc.orden,
    c.codigo                        AS componente_codigo,
    COALESCE(c.nombre, pc.nombre)   AS componente,
    COALESCE(c.norma,  pc.norma)    AS norma,
    pc.cantidad,
    c.precio_base                   AS precio_individual,
    (pc.ensayo_componente_id IS NOT NULL) AS vinculado
FROM paquete_componentes pc
JOIN ensayos_catalogo p      ON p.id = pc.ensayo_id
LEFT JOIN ensayos_catalogo c ON c.id = pc.ensayo_componente_id
ORDER BY p.codigo, pc.orden;

-- Precio del paquete vs. lo que costarían sus ensayos por separado
CREATE VIEW vw_paquetes_resumen AS
SELECT
    p.codigo, p.nombre, p.precio_base AS precio_paquete,
    COUNT(pc.id)                                           AS componentes,
    COUNT(pc.ensayo_componente_id)                         AS vinculados,
    SUM(c.precio_base * pc.cantidad)                       AS valor_individual_vinculados,
    CASE WHEN COUNT(pc.id) = COUNT(pc.ensayo_componente_id) AND SUM(c.precio_base * pc.cantidad) > 0
         THEN ROUND(100 * (1 - p.precio_base / SUM(c.precio_base * pc.cantidad)), 1) END AS ahorro_pct
FROM ensayos_catalogo p
LEFT JOIN paquete_componentes pc ON pc.ensayo_id = p.id
LEFT JOIN ensayos_catalogo c     ON c.id = pc.ensayo_componente_id
WHERE p.es_paquete
GROUP BY p.id, p.codigo, p.nombre, p.precio_base
ORDER BY p.codigo;


-- ============================================================================
-- 6. VISTAS DE APOYO PARA EL DASHBOARD
-- ============================================================================

-- Resumen por categoría (lo que alimenta el gráfico "Resumen por Ensayos"
-- del dashboard: cuánto se cotizó y cuánto se vendió por Suelos/Concreto/
-- Asfalto/Albañilería).
CREATE VIEW vw_resumen_por_categoria AS
SELECT
    ce.slug                         AS categoria_slug,
    ce.nombre                       AS categoria_nombre,
    ce.color_hex,
    COUNT(DISTINCT c.id)            AS cotizaciones,
    SUM(ci.cantidad)                AS items_vendidos,
    SUM(ci.subtotal)                AS monto_total,
    SUM(ci.subtotal) FILTER (WHERE c.estado = 'aceptada') AS monto_aceptado
FROM cotizacion_items ci
JOIN cotizaciones c        ON c.id = ci.cotizacion_id
JOIN ensayos_catalogo ec   ON ec.id = ci.ensayo_id
JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
JOIN categorias_ensayo ce  ON ce.id = se.categoria_id
GROUP BY ce.slug, ce.nombre, ce.color_hex;

-- Ensayos más cotizados (útil para negociar precios de proveedores/insumos
-- de laboratorio, y como primer insumo de un futuro recomendador de IA).
CREATE VIEW vw_ensayos_mas_cotizados AS
SELECT
    ec.codigo, ec.nombre, ce.nombre AS categoria,
    COUNT(*)            AS veces_cotizado,
    SUM(ci.cantidad)    AS unidades_totales,
    SUM(ci.subtotal)    AS monto_total
FROM cotizacion_items ci
JOIN ensayos_catalogo ec     ON ec.id = ci.ensayo_id
JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
JOIN categorias_ensayo ce    ON ce.id = se.categoria_id
GROUP BY ec.codigo, ec.nombre, ce.nombre
ORDER BY monto_total DESC;

-- ----------------------------------------------------------------------------
-- 6.1 DASHBOARD POR PERIODO (filtro "Desde / Hasta" + botón Aplicar)
-- ----------------------------------------------------------------------------
-- El dashboard permite elegir un rango de fechas; TODO el panel (indicadores,
-- gráficos, resumen por ensayos y lista de cotizaciones) se recalcula con
-- las cotizaciones creadas dentro de ese rango. Estas funciones devuelven
-- exactamente esos números. Si p_desde / p_hasta llegan NULL, ese extremo
-- queda abierto (NULL, NULL = todo el historial). p_hasta es inclusivo:
-- cubre el día completo. Usan el índice idx_cotizaciones_fecha (creado_en).

-- Indicadores de las 4 tarjetas + el gráfico de estados
CREATE OR REPLACE FUNCTION fn_dashboard_kpis(p_desde DATE, p_hasta DATE)
RETURNS TABLE (
    total_cotizaciones  BIGINT,
    aceptadas           BIGINT,
    pendientes          BIGINT,
    rechazadas          BIGINT,
    canceladas          BIGINT,
    valor_total         NUMERIC
) AS $$
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE estado = 'aceptada'),
        COUNT(*) FILTER (WHERE estado = 'emitida'),
        COUNT(*) FILTER (WHERE estado = 'rechazada'),
        COUNT(*) FILTER (WHERE estado = 'cancelada'),
        COALESCE(SUM(total) FILTER (WHERE estado NOT IN ('rechazada','cancelada')), 0)
    FROM cotizaciones
    WHERE (p_desde IS NULL OR creado_en >= p_desde)
      AND (p_hasta IS NULL OR creado_en <  p_hasta + 1);
$$ LANGUAGE sql STABLE;

-- Gráfico "Evolución": cotizaciones por día (rango <= 31 días) o por mes
CREATE OR REPLACE FUNCTION fn_dashboard_evolucion(p_desde DATE, p_hasta DATE)
RETURNS TABLE (periodo DATE, cotizaciones BIGINT) AS $$
    SELECT
        CASE WHEN p_desde IS NOT NULL AND p_hasta IS NOT NULL AND (p_hasta - p_desde) < 31
             THEN date_trunc('day',   creado_en)::date
             ELSE date_trunc('month', creado_en)::date END AS periodo,
        COUNT(*)
    FROM cotizaciones
    WHERE (p_desde IS NULL OR creado_en >= p_desde)
      AND (p_hasta IS NULL OR creado_en <  p_hasta + 1)
    GROUP BY 1
    ORDER BY 1;
$$ LANGUAGE sql STABLE;

-- Gráfico "Top Clientes por Monto" (empresa o persona natural)
CREATE OR REPLACE FUNCTION fn_dashboard_top_clientes(p_desde DATE, p_hasta DATE, p_limite INT DEFAULT 4)
RETURNS TABLE (cliente VARCHAR, monto NUMERIC) AS $$
    SELECT
        COALESCE(e.razon_social, (p.nombres || ' ' || p.apellidos))::VARCHAR AS cliente,
        SUM(c.total) AS monto
    FROM cotizaciones c
    LEFT JOIN empresas e ON e.id = c.empresa_id
    LEFT JOIN personas p ON p.id = c.persona_id
    WHERE (p_desde IS NULL OR c.creado_en >= p_desde)
      AND (p_hasta IS NULL OR c.creado_en <  p_hasta + 1)
    GROUP BY 1
    ORDER BY monto DESC
    LIMIT p_limite;
$$ LANGUAGE sql STABLE;

-- "Resumen por Ensayos (Categoría)": monto y cantidad por Suelos/Concreto/...
-- Devuelve las 4 categorías siempre (en 0 si no hubo ventas en el periodo).
CREATE OR REPLACE FUNCTION fn_dashboard_por_categoria(p_desde DATE, p_hasta DATE)
RETURNS TABLE (categoria_slug VARCHAR, categoria_nombre VARCHAR, color_hex VARCHAR, activo BOOLEAN,
               items_vendidos NUMERIC, monto_total NUMERIC) AS $$
    -- Activas siempre (aunque estén en 0); inactivas solo si vendieron en el periodo
    SELECT
        ce.slug, ce.nombre, ce.color_hex, ce.activo,
        COALESCE(SUM(x.cantidad), 0),
        COALESCE(SUM(x.subtotal), 0)
    FROM categorias_ensayo ce
    LEFT JOIN (
        SELECT se.categoria_id, ci.cantidad, ci.subtotal
        FROM cotizacion_items ci
        JOIN cotizaciones c          ON c.id = ci.cotizacion_id
        JOIN ensayos_catalogo ec     ON ec.id = ci.ensayo_id
        JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
        WHERE (p_desde IS NULL OR c.creado_en >= p_desde)
          AND (p_hasta IS NULL OR c.creado_en <  p_hasta + 1)
    ) x ON x.categoria_id = ce.id
    GROUP BY ce.id, ce.slug, ce.nombre, ce.color_hex, ce.activo, ce.orden
    HAVING ce.activo OR COALESCE(SUM(x.subtotal), 0) > 0
    ORDER BY ce.orden;
$$ LANGUAGE sql STABLE;

-- Ejemplo de uso (lo que ejecuta el backend al pulsar "Aplicar"):
--   SELECT * FROM fn_dashboard_kpis('2026-09-18', '2026-09-24');
--   SELECT * FROM fn_dashboard_evolucion('2026-09-18', '2026-09-24');
--   SELECT * FROM fn_dashboard_top_clientes('2026-09-18', '2026-09-24');
--   SELECT * FROM fn_dashboard_por_categoria('2026-09-18', '2026-09-24');


-- ============================================================================
-- 7. DATOS BASE (seed) — categorías y subcategorías
-- ============================================================================

-- Nota: el prefijo de Concreto es 'AG' porque su catálogo histórico se
-- codifica desde Agregados (AG-01 … AG-42).
INSERT INTO categorias_ensayo (slug, nombre, prefijo_codigo, icono, color_hex, orden, creado_por) VALUES
    ('suelos',      'Suelos',       'SU', '🟤', '#92400e', 1, 1),
    ('concreto',    'Concreto',     'AG', '⬜', '#64748b', 2, 1),
    ('asfalto',     'Asfalto',      'AS', '⬛', '#1e293b', 3, 1),
    ('albanileria', 'Albañilería',  'AL', '🧱', '#b91c1c', 4, 1);

INSERT INTO subcategorias_ensayo (categoria_id, nombre, orden, creado_por)
SELECT id, sub, ord, 1 FROM categorias_ensayo, LATERAL (VALUES
    ('Estándares y Especiales', 1), ('Químicos', 2), ('Paquetes', 3), ('Campo', 4)
) AS s(sub, ord) WHERE slug = 'suelos';

INSERT INTO subcategorias_ensayo (categoria_id, nombre, orden, creado_por)
SELECT id, sub, ord, 1 FROM categorias_ensayo, LATERAL (VALUES
    ('Agregado', 1), ('Químicos Agregado', 2), ('Químicos Agua', 3),
    ('Fresco y Endurecido', 4), ('Paquetes', 5), ('In-Situ (Campo)', 6)
) AS s(sub, ord) WHERE slug = 'concreto';

INSERT INTO subcategorias_ensayo (categoria_id, nombre, orden, creado_por)
SELECT id, sub, ord, 1 FROM categorias_ensayo, LATERAL (VALUES
    ('Mezclas Asfálticas', 1), ('Paquetes', 2), ('Campo', 3)
) AS s(sub, ord) WHERE slug = 'asfalto';

INSERT INTO subcategorias_ensayo (categoria_id, nombre, orden, creado_por)
SELECT id, 'Ladrillos', 1, 1 FROM categorias_ensayo WHERE slug = 'albanileria';

INSERT INTO plantillas_cotizacion (slug, nombre, icono, validez_dias_sugerida, terminos_condiciones, creado_por) VALUES
    ('estandar', 'Estándar', '🧪', 15,
     'Validez de la cotización: 15 días calendario. Forma de pago: 50% adelanto, 50% contra entrega de informe.', 1),
    ('premium', 'Premium', '⭐', 30,
     'Validez de la cotización: 30 días calendario. Pago flexible según acuerdo. Incluye informe ejecutivo y soporte técnico por 30 días.', 1),
    ('express', 'Express', '⚡', 7,
     'Validez de la cotización: 7 días calendario. Pago 100% adelantado. Entrega de resultados en 48 horas.', 1);

-- Nota: la carga completa de los ~87 ensayos del catálogo (Suelos, Concreto,
-- Asfalto, Albañilería, con código, norma, precio, unidad y acreditación)
-- vive como INSERTs generados en `seed_ensayos_catalogo.sql` (mismo criterio
-- que usa el mockup en gtqc_sistema_unificado.html) para no duplicar aquí
-- 500+ líneas de datos que cambian con frecuencia de precios.


-- ============================================================================
-- ROADMAP IA (a implementar cuando haya volumen real de datos — NO crear
-- estas tablas todavía, quedan documentadas para no re-diseñar después)
-- ============================================================================
-- 1) ensayos_catalogo.embedding VECTOR(384)  — con pgvector, para búsqueda
--    semántica ("necesito algo para ver si el suelo aguanta una losa" debe
--    encontrar CBR y Proctor aunque el usuario no sepa el nombre técnico).
--
-- 2) TABLE ia_recomendaciones_ensayo (
--      cotizacion_id, ensayo_sugerido_id, score, motivo, modelo_version
--    ) — "otros proyectos con este tipo de suelo también pidieron CBR".
--
-- 3) TABLE ia_prediccion_aceptacion (
--      cotizacion_id, probabilidad_aceptacion, features_usadas JSONB,
--      modelo_version, calculado_en
--    ) — para priorizar seguimiento comercial a las cotizaciones "emitidas"
--    con mayor probabilidad de cerrarse.
--
-- 4) TABLE ia_deteccion_anomalias_auditoria (
--      auditoria_id, tipo_anomalia, severidad, revisado
--    ) — cruza la tabla `auditoria` para marcar cambios de precio o de
--    acreditación fuera de patrón (ej. alguien baja un precio 80% a las
--    2am un domingo).
--
-- Estas 4 piezas se apoyan TODAS en que hoy ya existan: snapshots por
-- ítem de cotización, auditoría genérica con antes/después, e historial
-- de acreditación con fecha — que es justamente lo que este esquema ya
-- garantiza desde el día uno.
-- ============================================================================
