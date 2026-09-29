-- ============================================================================
-- GTQC / SAC-GEO — MIGRACIÓN 0007
-- RBAC multi-rol · guardas de autoría (H-15) · rol de sistema (H-13)
-- ============================================================================
--
-- ⚠ MIGRACIÓN PREPARADA. NO EJECUTADA. Lea esta cabecera entera antes.
--
-- Decisiones aprobadas en la fase 5C.2. Cada una está implementada aquí y
-- ninguna se tomó por cuenta propia:
--
--   · Cinco roles: admin, comercial, aprobador, laboratorio, lectura.
--     NO se crea un rol "técnico": SAC-GEO no modela muestras, resultados ni
--     informes de ensayo, así que un técnico de ensayo no tendría ninguna
--     operación propia en este sistema. `laboratorio` ES el responsable
--     técnico/calidad dentro del alcance actual.
--   · `admin` NO recibe catalogo.manage, acreditacion.manage ni los ocho
--     permisos de operación de cotizaciones. Se obtienen asignando roles.
--   · `comercial` NO recibe dashboard.read.
--   · `catalogo.price` separado de `catalogo.manage`.
--   · Guardas de p_usuario en 7 funciones, CONSERVANDO las firmas.
--   · H-13: es_sistema no se puede apagar.
--   · `usuario_roles` tenant-scoped con RLS ENABLE + FORCE.
--   · Índice sobre usuario_roles.rol_id (si no, el control I3 de la 99 salta).
--
-- ----------------------------------------------------------------------------
-- POR QUÉ `catalogo.price` EXISTE
-- ----------------------------------------------------------------------------
-- `ensayos_catalogo` guarda `precio_base` en la MISMA tabla que `norma` y
-- `unidad`. Un único permiso `catalogo.manage` juntaría dos autoridades
-- distintas: la técnica (qué ensayos existen, con qué norma) y la comercial
-- (cuánto cuestan).
--
-- Dárselo entero a `laboratorio` dejaría al comercial sin poder cambiar un
-- precio — el espejo exacto del conflicto por el que se le retiró a `admin`.
--
-- Por eso: `catalogo.manage` → laboratorio (estructura), `catalogo.price` →
-- comercial (solo precio_base).
--
-- ⚠ ESTA SEPARACIÓN LA APLICA LA API, NO EL MOTOR. PostgreSQL no sabe qué
-- permiso trae quien escribe; solo ve un UPDATE. Lo que garantiza que
-- `catalogo.price` no toque `norma` es que su endpoint únicamente actualice
-- `precio_base`. Queda escrito aquí para que nadie suponga una defensa que no
-- existe. El motor sí garantiza lo demás: precio no negativo (dom_precio),
-- congelado del snapshot, auditoría del cambio.
--
-- Nota: `fn_crear_ensayo` y `fn_crear_paquete` reciben `p_precio`, así que
-- quien crea un ensayo fija su precio INICIAL. Eso exige `catalogo.manage`,
-- es decir `laboratorio`. `comercial` lo cambia después. Es coherente: el
-- precio de alta lo pone quien define el ensayo; la política comercial la
-- lleva quien vende.
--
-- ----------------------------------------------------------------------------
-- UNA CORRECCIÓN AL DISEÑO PREVIO: EL CHECK DEL CÓDIGO DE PERMISO
-- ----------------------------------------------------------------------------
-- `SEGURIDAD_RBAC.md` §3.1 propone:
--
--     CHECK (codigo ~ '^[a-z_]+\.[a-z_]+$')
--
-- Ese patrón RECHAZA tres de los 31 códigos, porque llevan dos puntos:
-- `tenant.config.read`, `tenant.config.update` y `plataforma.acceso.grant`.
-- Aplicarlo tal cual haría fallar la siembra de esta misma migración.
--
-- Se admite un tercer segmento, y no más: un código con cuatro niveles sería
-- señal de que el catálogo está creciendo hacia una jerarquía que este modelo
-- no contempla.
--
-- ----------------------------------------------------------------------------
-- LO QUE ESTA MIGRACIÓN NO HACE
-- ----------------------------------------------------------------------------
-- No comprueba permisos dentro de ninguna función de negocio, y es deliberado.
-- Una función que consultara `usuario_roles` acoplaría el dominio a la
-- autorización y duplicaría la regla en dos sitios que se desincronizarían.
--
--     La autorización decide quién puede INTENTAR.
--     La integridad decide qué es POSIBLE.
--
-- Lo segundo ya está en el motor y ningún permiso lo levanta: append-only,
-- congelado del documento emitido, máquina de estados, autor de auditoría
-- infalsificable (0006).
--
-- No retira `usuarios.rol_id`. Se conserva como "rol principal" y se usa para
-- poblar `usuario_roles`. Retirarlo exige que nada lo lea, y eso es una
-- migración posterior.
--
-- ----------------------------------------------------------------------------
-- REVERSIBILIDAD
-- ----------------------------------------------------------------------------
-- Las tres tablas son NUEVAS y nada las lee todavía, así que un DROP ordenado
-- las retira sin pérdida. Lo que NO es trivialmente reversible son los
-- CREATE OR REPLACE de las 7 funciones y del trigger de roles: volver atrás
-- exige reaplicar sus definiciones anteriores.
--
-- Por eso la vuelta atrás es el backup COMPLETO —dump + globals— validado por
-- restauración EN OTRO CLÚSTER (CLAUDE.md §4.3 bis). El dump por sí solo no
-- basta: pg_dump no vuelca los roles.
--
-- ============================================================================

\set ON_ERROR_STOP on
\echo '*** 0007 es una migración PREPARADA. Lea la cabecera antes de aplicarla. ***'

BEGIN;


-- ============================================================================
-- SECCIÓN 0 · PRECONDICIONES
-- ============================================================================

DO $precondiciones$
DECLARE
    v_n   INTEGER;
    v_md5 TEXT;
    r     RECORD;
    -- md5 del cuerpo ACTUAL de cada función que se va a reemplazar, tomado de
    -- 01_functions.sql. Si no coincide, alguien las cambió después y este
    -- CREATE OR REPLACE borraría ese cambio sin avisar.
    v_esperado CONSTANT TEXT[][] := ARRAY[
        ['fn_crear_categoria',      '9395a48904cf71c48fa81e5bffc1311c'],
        ['fn_crear_ensayo',         '1195cd7cfdd0828df59325d555d261e7'],
        ['fn_crear_paquete',        '189336602ec53bed82d1217531660c69'],
        ['fn_definir_componentes',  '23bac322f30df8ad9319de09181901f4'],
        ['fn_cambiar_acreditacion', '179d74a361104860341cb0efc6d7ef75'],
        ['fn_crear_cotizacion',     '3eccd77e5ac1466eecc4aa74e2a02196'],
        ['fn_purgar_auditoria',     'c1d4d45bbc5371f3651fe77d4d764cec']
    ];
BEGIN
    -- 0.1 · 0006 aplicada. El rastro de quién asigna un rol tiene que ser
    --       infalsificable ANTES de que existan los roles que asignar.
    IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0006') THEN
        RAISE EXCEPTION '0006 no está aplicada. Sin ella el rastro de usuario_roles sería falsificable.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 0.2 · 0007 no aplicada.
    IF EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0007') THEN
        RAISE EXCEPTION '0007 ya está aplicada. No se ejecuta dos veces.'
            USING ERRCODE = 'duplicate_object';
    END IF;

    -- 0.3 · Ninguna de las tres tablas debe preexistir.
    FOR r IN SELECT unnest(ARRAY['permisos','rol_permisos','usuario_roles']) AS t LOOP
        IF to_regclass('public.' || r.t) IS NOT NULL THEN
            RAISE EXCEPTION 'La tabla % ya existe. Revise su origen antes de continuar.', r.t
                USING ERRCODE = 'duplicate_table';
        END IF;
    END LOOP;

    -- 0.4 · Los cuatro roles esperados, sin más y sin menos.
    SELECT count(*) INTO v_n FROM roles;
    IF v_n <> 4 THEN
        RAISE EXCEPTION 'Se esperaban 4 roles, hay %.', v_n USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM roles WHERE codigo='admin')
    OR NOT EXISTS (SELECT 1 FROM roles WHERE codigo='comercial')
    OR NOT EXISTS (SELECT 1 FROM roles WHERE codigo='laboratorio')
    OR NOT EXISTS (SELECT 1 FROM roles WHERE codigo='lectura') THEN
        RAISE EXCEPTION 'Los códigos de rol no son los esperados.' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM roles WHERE codigo='aprobador') THEN
        RAISE EXCEPTION 'El rol aprobador ya existe.' USING ERRCODE = 'duplicate_object';
    END IF;

    -- 0.5 · Las 7 funciones a reemplazar deben ser EXACTAMENTE las que se
    --       leyeron al preparar esta migración. Un CREATE OR REPLACE sobre una
    --       función que alguien modificó después borraría su cambio en
    --       silencio, y eso es lo que esta comprobación impide.
    FOR v_n IN 1 .. array_length(v_esperado, 1) LOOP
        SELECT md5(prosrc) INTO v_md5 FROM pg_proc
         WHERE proname = v_esperado[v_n][1] AND pronamespace = 'public'::regnamespace;
        IF v_md5 IS NULL THEN
            RAISE EXCEPTION 'La función % no existe.', v_esperado[v_n][1]
                USING ERRCODE = 'undefined_function';
        END IF;
        IF v_md5 <> v_esperado[v_n][2] THEN
            RAISE EXCEPTION 'El cuerpo de % cambió desde que se preparó 0007 '
                            '(esperado %, encontrado %). Regenere la migración.',
                            v_esperado[v_n][1], v_esperado[v_n][2], v_md5
                USING ERRCODE = 'invalid_object_definition';
        END IF;
    END LOOP;

    -- 0.6 · RLS tal como la dejaron 0004 y 0005: 17 tablas, 18 políticas.
    SELECT count(*) INTO v_n FROM pg_class
     WHERE relnamespace='public'::regnamespace AND relkind='r'
       AND relrowsecurity AND relforcerowsecurity;
    IF v_n <> 17 THEN
        RAISE EXCEPTION 'Se esperaban 17 tablas con RLS FORCE, hay %.', v_n
            USING ERRCODE = 'invalid_object_definition';
    END IF;
    SELECT count(*) INTO v_n FROM pg_policies WHERE schemaname='public';
    IF v_n <> 18 THEN
        RAISE EXCEPTION 'Se esperaban 18 políticas, hay %.', v_n
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 0.7 · Los roles del clúster que 0004 creó.
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='sacgeo_app') THEN
        RAISE EXCEPTION 'El rol sacgeo_app no existe. Revise 0004.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 0.8 · Informe previo.
    SELECT count(*) INTO v_n FROM usuarios WHERE tenant_id IS NOT NULL;
    RAISE NOTICE '0007: usuarios de tenant que recibirán fila en usuario_roles: %', v_n;
    SELECT count(*) INTO v_n FROM usuarios WHERE tenant_id IS NULL;
    RAISE NOTICE '0007: identidades globales, que NO reciben rol de tenant: %', v_n;
END
$precondiciones$;


-- ============================================================================
-- SECCIÓN 1 · ROLES: scope, el nuevo `aprobador`, y el nombre de `comercial`
-- ============================================================================

ALTER TABLE roles ADD COLUMN scope VARCHAR(12) NOT NULL DEFAULT 'tenant'
    CONSTRAINT ck_roles_scope CHECK (scope IN ('tenant','plataforma'));

COMMENT ON COLUMN roles.scope IS
  'tenant: rol de un laboratorio. plataforma: rol del producto (Super Admin). '
  'fn_validar_scope_permiso() impide que un rol de tenant reciba un permiso de plataforma.';

-- El producto quiere que `comercial` se llame Cotizador. `a_proteger` bloquea
-- cambiar el CÓDIGO de un rol de sistema, no su nombre — y el código es lo que
-- usan rol_permisos y el backend, así que no se toca.
UPDATE roles SET nombre = 'Cotizador' WHERE codigo = 'comercial';
UPDATE roles SET nombre = 'Laboratorio / Calidad',
                 descripcion = 'Responsable técnico: define el catálogo y gestiona la acreditación ISO 17025'
 WHERE codigo = 'laboratorio';

INSERT INTO roles (codigo, nombre, descripcion, es_sistema, scope)
VALUES ('aprobador', 'Aprobador',
        'Da o niega el visto bueno interno antes de emitir. Nunca sobre sus propias cotizaciones',
        TRUE, 'tenant');


-- ----------------------------------------------------------------------------
-- EL UNIQUE COMPUESTO QUE `usuarios` NO TENÍA
-- ----------------------------------------------------------------------------
-- El primer intento de esta migración (fase 5C.3) falló aquí con 42830:
--
--     there is no unique constraint matching given keys for referenced table "usuarios"
--
-- `0003` añadió UNIQUE (tenant_id, id) a las OCHO tablas estrictamente
-- tenant-scoped y excluyó las dos híbridas, `usuarios` y
-- `plantillas_cotizacion`, porque su tenant_id admite NULL. El diseño de 0007
-- dio por hecho que `usuarios` lo tenía como el resto, y no se comprobó.
--
-- Funciona con tenant_id nullable: `id` ya es único por la PK, así que el par
-- (tenant_id, id) lo es trivialmente. Y como `usuario_roles.tenant_id` es
-- NOT NULL, MATCH SIMPLE evalúa siempre la FK — nunca se salta por NULL.
--
-- Se añade aquí, ANTES de crear usuario_roles, y NO se toca
-- `plantillas_cotizacion`: hoy nada la referencia compositivamente, y ampliar
-- el alcance de una migración por simetría es como se cuelan los cambios que
-- nadie pidió. Anotado en docs/DISENO_RBAC_0007.md §14.
ALTER TABLE usuarios
    ADD CONSTRAINT uq_usuarios_tenant_id UNIQUE (tenant_id, id);

COMMENT ON CONSTRAINT uq_usuarios_tenant_id ON usuarios IS
  'Soporta la FK compuesta de usuario_roles. La pertenencia al tenant se '
  'declara con FK compuestas, no con disciplina (CLAUDE.md 5).';


-- ============================================================================
-- SECCIÓN 2 · CATÁLOGO DE PERMISOS
-- ============================================================================
-- GLOBAL. Lo controla el producto: un laboratorio no inventa acciones.

CREATE TABLE permisos (
    id          INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    codigo      VARCHAR(40)  NOT NULL,
    descripcion VARCHAR(200) NOT NULL,
    scope       VARCHAR(12)  NOT NULL DEFAULT 'tenant',
    CONSTRAINT uq_permisos_codigo UNIQUE (codigo),
    -- Dos o tres segmentos. Ver la cabecera: el patrón de dos que proponía el
    -- diseño previo rechazaba tenant.config.* y plataforma.acceso.grant.
    CONSTRAINT ck_permisos_codigo CHECK (codigo ~ '^[a-z_]+(\.[a-z_]+){1,2}$'),
    CONSTRAINT ck_permisos_scope  CHECK (scope IN ('tenant','plataforma'))
);
COMMENT ON TABLE permisos IS
  'GLOBAL. Catálogo de acciones del producto. Cada permiso corresponde a una '
  'operación que existe: una función de caso de uso o un CRUD con endpoint.';

INSERT INTO permisos (codigo, descripcion, scope) VALUES
 ('catalogo.read',            'Ver categorías, subcategorías, ensayos y paquetes',            'tenant'),
 ('catalogo.manage',          'Crear y editar la ESTRUCTURA del catálogo: categorías, ensayos, normas, unidades, componentes', 'tenant'),
 ('catalogo.price',           'Modificar únicamente el precio base de un ensayo o paquete',   'tenant'),
 ('acreditacion.read',        'Consultar el estado de acreditación a una fecha',              'tenant'),
 ('acreditacion.manage',      'Cambiar el estado de acreditación ISO 17025',                  'tenant'),
 ('clientes.read',            'Ver empresas, contactos y personas naturales',                 'tenant'),
 ('clientes.manage',          'Alta y edición de empresas, contactos y personas',             'tenant'),
 ('cotizaciones.read',        'Ver cotizaciones y su documento',                              'tenant'),
 ('cotizaciones.create',      'Crear una cotización',                                         'tenant'),
 ('cotizaciones.update',      'Editar una cotización en borrador y sus ítems',                'tenant'),
 ('cotizaciones.submit',      'Enviar una cotización a revisión interna',                     'tenant'),
 ('cotizaciones.approve',     'Dar el visto bueno interno a una cotización ajena',            'tenant'),
 ('cotizaciones.reject',      'Devolver una cotización a borrador con motivo',                'tenant'),
 ('cotizaciones.emit',        'Emitir: consume el número de la serie oficial',                'tenant'),
 ('cotizaciones.cancel',      'Cancelar una cotización',                                      'tenant'),
 ('cotizaciones.close',       'Registrar la respuesta del cliente: aceptada o rechazada',     'tenant'),
 ('dashboard.read',           'Ver los indicadores agregados del laboratorio',                'tenant'),
 ('documentos.read',          'Ver los documentos asociados a una cotización',                'tenant'),
 ('documentos.create',        'Registrar un documento local o en nube',                       'tenant'),
 ('integraciones.read',       'Ver las conexiones con Drive o Microsoft 365',                 'tenant'),
 ('integraciones.manage',     'Conectar y revocar integraciones de nube',                     'tenant'),
 ('usuarios.read',            'Ver las personas del laboratorio',                             'tenant'),
 ('usuarios.create',          'Dar de alta una persona',                                      'tenant'),
 ('usuarios.update',          'Editar los datos de una persona',                              'tenant'),
 ('usuarios.disable',         'Desactivar una persona (baja lógica; nunca se elimina)',       'tenant'),
 ('usuarios.assign_role',     'Asignar y retirar roles de tenant',                            'tenant'),
 ('auditoria.read',           'Consultar el rastro de auditoría',                             'tenant'),
 ('auditoria.purge',          'Purgar auditoría de más de 365 días. Sin titular por diseño',  'tenant'),
 ('tenant.config.read',       'Ver los datos del laboratorio',                                'tenant'),
 ('tenant.config.update',     'Editar los datos del laboratorio',                             'tenant'),
 ('plataforma.acceso.grant',  'Conceder acceso de soporte a un laboratorio. Sin titular hoy', 'plataforma');


-- ============================================================================
-- SECCIÓN 3 · QUÉ TRAE CADA ROL
-- ============================================================================
-- GLOBAL. Que un tenant no pueda tocar esta tabla es lo que cierra V-2 del
-- modelo de amenazas: un administrador no puede fabricarse un rol con permisos
-- que no le tocan, porque no puede crear roles ni cambiar qué traen.

CREATE TABLE rol_permisos (
    rol_id     INTEGER NOT NULL REFERENCES roles(id)    ON DELETE CASCADE,
    permiso_id INTEGER NOT NULL REFERENCES permisos(id) ON DELETE RESTRICT,
    PRIMARY KEY (rol_id, permiso_id)
);
COMMENT ON TABLE rol_permisos IS
  'GLOBAL. Qué permisos trae cada rol del producto. El cliente no la modifica.';

-- Un rol de tenant no puede recibir un permiso de plataforma. En el motor, no
-- confiado a FastAPI: responde a "que un cliente no cree un rol que
-- accidentalmente tenga permisos de plataforma".
CREATE OR REPLACE FUNCTION fn_validar_scope_permiso() RETURNS TRIGGER AS $$
DECLARE v_rol VARCHAR(12); v_perm VARCHAR(12); v_cod VARCHAR(40);
BEGIN
    SELECT scope INTO v_rol  FROM roles    WHERE id = NEW.rol_id;
    SELECT scope, codigo INTO v_perm, v_cod FROM permisos WHERE id = NEW.permiso_id;
    IF v_perm = 'plataforma' AND v_rol <> 'plataforma' THEN
        RAISE EXCEPTION 'Un rol de tenant no puede recibir el permiso de plataforma %', v_cod
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER a_validar_scope BEFORE INSERT OR UPDATE ON rol_permisos
    FOR EACH ROW EXECUTE FUNCTION fn_validar_scope_permiso();

-- La PK (rol_id, permiso_id) cubre rol_id como columna líder, pero NO permiso_id.
-- El control I3 de 99_verificacion.sql exige índice en toda FK de navegación, y
-- en la fase 5C.8 lo detectó: `rol_permisos.permiso_id`. Además sirve para la
-- consulta inversa legítima — "qué roles traen este permiso" — al revisar la
-- matriz. Nombre según la convención de 03_indexes_views.sql: idx_<tabla>_<col>.
CREATE INDEX idx_rol_permisos_permiso ON rol_permisos (permiso_id);

-- La matriz. Se escribe por código, no por id: los ids son internos y un
-- cambio de orden en la siembra no debe alterar quién puede qué.
INSERT INTO rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM roles r, permisos p WHERE (r.codigo, p.codigo) IN (
    -- admin — administra el laboratorio, NO lo opera
    ('admin','catalogo.read'),        ('admin','acreditacion.read'),
    ('admin','clientes.read'),        ('admin','cotizaciones.read'),
    ('admin','dashboard.read'),       ('admin','documentos.read'),
    ('admin','integraciones.read'),   ('admin','integraciones.manage'),
    ('admin','usuarios.read'),        ('admin','usuarios.create'),
    ('admin','usuarios.update'),      ('admin','usuarios.disable'),
    ('admin','usuarios.assign_role'), ('admin','auditoria.read'),
    ('admin','tenant.config.read'),   ('admin','tenant.config.update'),
    -- comercial (Cotizador) — vende
    ('comercial','catalogo.read'),          ('comercial','catalogo.price'),
    ('comercial','acreditacion.read'),      ('comercial','clientes.read'),
    ('comercial','clientes.manage'),        ('comercial','cotizaciones.read'),
    ('comercial','cotizaciones.create'),    ('comercial','cotizaciones.update'),
    ('comercial','cotizaciones.submit'),    ('comercial','cotizaciones.emit'),
    ('comercial','cotizaciones.cancel'),    ('comercial','cotizaciones.close'),
    ('comercial','documentos.read'),        ('comercial','documentos.create'),
    -- aprobador — un solo trabajo, con el contexto para hacerlo
    ('aprobador','catalogo.read'),      ('aprobador','acreditacion.read'),
    ('aprobador','clientes.read'),      ('aprobador','cotizaciones.read'),
    ('aprobador','cotizaciones.approve'),('aprobador','cotizaciones.reject'),
    ('aprobador','documentos.read'),
    -- laboratorio — responsable técnico
    ('laboratorio','catalogo.read'),       ('laboratorio','catalogo.manage'),
    ('laboratorio','acreditacion.read'),   ('laboratorio','acreditacion.manage'),
    ('laboratorio','cotizaciones.read'),   ('laboratorio','documentos.read'),
    -- lectura — consulta y agregados
    ('lectura','catalogo.read'),     ('lectura','acreditacion.read'),
    ('lectura','clientes.read'),     ('lectura','cotizaciones.read'),
    ('lectura','dashboard.read'),    ('lectura','documentos.read')
);


-- ============================================================================
-- SECCIÓN 4 · QUÉ ROLES TIENE CADA PERSONA
-- ============================================================================
-- TENANT-SCOPED. La asignación pertenece al laboratorio, no al producto.

CREATE TABLE usuario_roles (
    -- `id` surrogate como PK, y la clave natural en un UNIQUE aparte. No es
    -- una preferencia: es la convención de las DOS tablas puente que ya
    -- existen — paquete_componentes e cotizacion_items usan exactamente este
    -- patrón — y, sobre todo, es un requisito de fn_auditar(), que escribe
    --     (v_ref->>'id')::BIGINT  ->  auditoria.registro_id  NOT NULL
    -- Con PK compuesta y sin columna `id`, la primera fila auditada falla con
    -- 23502. Reproducido en la fase 5C.6.
    --
    -- INTEGER y no BIGINT: el esquema reserva BIGINT para las tablas de alto
    -- volumen (cotizacion_items, auditoria...). Una asignación de rol por
    -- persona no lo es. Y `registro_id` es BIGINT, así que el INTEGER cabe.
    id          INTEGER     GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    tenant_id   INTEGER     NOT NULL,
    usuario_id  INTEGER     NOT NULL,
    rol_id      INTEGER     NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    asignado_por INTEGER    NOT NULL REFERENCES usuarios(id) ON DELETE RESTRICT,
    asignado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- La unicidad de la asignación no la pierde la tabla al mover la PK: la
    -- garantiza este UNIQUE, y `ON CONFLICT (tenant_id, usuario_id, rol_id)`
    -- de fn_asignar_rol resuelve contra él igual que antes contra la PK.
    -- El ORDEN de las columnas importa: con tenant_id al frente, este índice
    -- sigue cubriendo fk_usuario_roles_tenant, cobertura que antes daba la PK.
    CONSTRAINT uq_usuario_roles UNIQUE (tenant_id, usuario_id, rol_id),
    -- FK COMPUESTA: que el usuario sea de ese tenant es imposible de violar,
    -- no una regla que alguien deba recordar. Mismo patrón que contactos.
    CONSTRAINT fk_usuario_roles_usuario FOREIGN KEY (tenant_id, usuario_id)
        REFERENCES usuarios (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_usuario_roles_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenants (id) ON DELETE RESTRICT
);
COMMENT ON TABLE usuario_roles IS
  'TENANT-SCOPED. Un usuario puede tener VARIOS roles: sus permisos son la '
  'unión. Tener aprobador y comercial a la vez es seguro porque no aprobar lo '
  'propio es un CHECK de fila (ck_aprob_no_autoaprueba, 0010), no un permiso.';

-- El control I3 de 99_verificacion.sql exige índice en toda FK de NAVEGACIÓN.
-- (tenant_id, usuario_id) ya va cubierto por la PK, que empieza por tenant_id.
-- rol_id no: sin este índice, I3 se enciende.
CREATE INDEX ix_usuario_roles_rol ON usuario_roles (rol_id);

ALTER TABLE usuario_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuario_roles FORCE  ROW LEVEL SECURITY;

-- La política mira SOLO el tenant. El rol JAMÁS entra en una política RLS:
-- mezclar rol y tenant en la misma política es como se abren los agujeros.
CREATE POLICY p_tenant ON usuario_roles TO sacgeo_app
    USING      (tenant_id = fn_app_tenant())
    WITH CHECK (tenant_id = fn_app_tenant());

CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON usuario_roles
    FOR EACH ROW EXECUTE FUNCTION fn_auditar();

-- ----------------------------------------------------------------------------
-- EL OTORGANTE DE UN ROL ES QUIEN OPERA LA SESIÓN
-- ----------------------------------------------------------------------------
-- Tercera aparición del mismo patrón: H-06 lo cerró para auditoria.usuario_id,
-- H-15 para creado_por, y aquí para asignado_por. Toda columna de atribución
-- que el que escribe puede elegir es falsificable mientras el motor no la ate
-- al contexto de la sesión.
--
-- El riesgo concreto: sacgeo_app tiene INSERT directo sobre usuario_roles, así
-- que sin esto podría registrar a un usuario CUALQUIERA —incluso de otro
-- laboratorio, porque la FK de asignado_por es simple— como quien otorgó un
-- rol. Y la fila diría una cosa mientras su propia auditoría diría otra, ya que
-- fn_auditar() sella con fn_app_usuario() y desde 0006 eso no se puede falsear.
-- Row y rastro discrepando es justo lo que invalida un historial ante un
-- auditor.
--
-- Cubre INSERT **y UPDATE**, a diferencia de b_auditoria_autor (0006), que solo
-- mira INSERT. No es una desviación: allí el UPDATE ya lo bloqueaba
-- trg_append_only. Aquí no existe ese guardián, `usuario_roles` no tiene GRANT
-- de UPDATE para sacgeo_app y no hay ningún escenario legítimo de editar una
-- asignación —se otorga o se retira—, así que cubrir el UPDATE cierra la vía
-- del propietario y la de cualquier GRANT futuro sin coste alguno.
--
-- Nombres según la convención de las tablas de negocio: a_validar_* sobre
-- fn_validar_*, como a_validar_plantilla y a_validar_scope. El prefijo b_ está
-- reservado de hecho a los dos guardianes de `auditoria`.
CREATE OR REPLACE FUNCTION fn_validar_otorgante_rol() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.asignado_por IS DISTINCT FROM fn_app_usuario() THEN
        RAISE EXCEPTION 'El otorgante de un rol es quien opera la sesión '
                        '(se indicó %, la sesión es %)',
                        NEW.asignado_por, fn_app_usuario()
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_validar_otorgante_rol() IS
  'usuario_roles.asignado_por debe ser fn_app_usuario(). Cierra la falsificación '
  'del otorgante por INSERT directo y mantiene la fila alineada con su auditoría.';

CREATE TRIGGER a_validar_otorgante BEFORE INSERT OR UPDATE ON usuario_roles
    FOR EACH ROW EXECUTE FUNCTION fn_validar_otorgante_rol();


-- ----------------------------------------------------------------------------
-- LA SEMILLA VA AQUÍ, Y NO ANTES
-- ----------------------------------------------------------------------------
-- En la primera versión este INSERT estaba justo tras CREATE TABLE, antes de
-- los triggers. Consecuencia, medida en la fase 5C.8: las 5 asignaciones
-- iniciales entraron SIN dejar una sola fila de auditoría. La asignación de rol
-- de todos los usuarios existentes quedaba sin rastro — en un sistema cuyo
-- activo crítico es precisamente la auditoría.
--
-- No era una decisión: era el orden en que se escribieron las sentencias.
--
-- Poblada aquí, cada fila pasa por los dos guardianes:
--   · a_validar_otorgante exige asignado_por = fn_app_usuario(). Durante la
--     migración no hay contexto de usuario, así que fn_app_usuario() devuelve 1
--     por su COALESCE —el usuario `sistema`— y la semilla escribe 1. Coinciden.
--   · trg_auditar deja una fila por asignación, atribuida a `sistema`, que es
--     literalmente cierto: quien asignó estos roles no fue una persona, fue la
--     migración. Es el mismo criterio con el que 0003 selló su relleno.
--
-- Se pobla desde `usuarios.rol_id`, que se conserva como rol principal y se
-- retirará cuando nada lo lea. El usuario `sistema` (tenant_id NULL) NO recibe
-- fila: no es de ningún laboratorio y no inicia sesión.
INSERT INTO usuario_roles (tenant_id, usuario_id, rol_id, asignado_por)
SELECT u.tenant_id, u.id, u.rol_id, 1
  FROM usuarios u WHERE u.tenant_id IS NOT NULL;


-- ============================================================================
-- SECCIÓN 5 · RESOLUCIÓN Y ASIGNACIÓN
-- ============================================================================

-- Los permisos efectivos de una persona: la UNIÓN de sus roles.
-- SECURITY INVOKER: se ejecuta con los privilegios de quien pregunta, así que
-- RLS sigue aplicándose sobre usuario_roles. STABLE para que PostgreSQL la
-- cachee dentro de la sentencia.
CREATE OR REPLACE FUNCTION fn_usuario_permisos(p_usuario INTEGER)
RETURNS TABLE (codigo VARCHAR) AS $$
    SELECT DISTINCT p.codigo
      FROM usuario_roles ur
      JOIN rol_permisos rp ON rp.rol_id = ur.rol_id
      JOIN permisos     p  ON p.id      = rp.permiso_id
     WHERE ur.usuario_id = p_usuario
     ORDER BY 1;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION fn_usuario_permisos(INTEGER) IS
  'Permisos efectivos: la unión de los roles del usuario, sin duplicar. '
  'La lee el backend en CADA petición, dentro de la transacción ya '
  'contextualizada. Nunca se cachea entre peticiones: por eso retirar un rol '
  'surte efecto de inmediato.';

-- Única vía para asignar o retirar un rol. Existe para que la operación tenga
-- un punto con nombre que auditar y autorizar, en vez de un INSERT suelto.
CREATE OR REPLACE FUNCTION fn_asignar_rol(
    p_usuario_id INTEGER, p_rol_codigo VARCHAR, p_otorgar BOOLEAN DEFAULT TRUE
) RETURNS BOOLEAN AS $$
DECLARE v_rol INTEGER; v_scope VARCHAR(12); v_tenant INTEGER; v_ut INTEGER;
BEGIN
    v_tenant := fn_app_tenant();

    SELECT id, scope INTO v_rol, v_scope FROM roles WHERE codigo = p_rol_codigo;
    IF v_rol IS NULL THEN
        RAISE EXCEPTION 'El rol "%" no existe', p_rol_codigo USING ERRCODE = 'undefined_object';
    END IF;

    -- Un rol de plataforma no se asigna por esta vía. El Super Admin llega en
    -- una fase posterior con su propio mecanismo de concesión acotada.
    IF v_scope <> 'tenant' THEN
        RAISE EXCEPTION 'El rol "%" no es un rol de laboratorio', p_rol_codigo
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- El usuario tiene que ser de ESTE tenant. Bajo RLS, uno ajeno es
    -- invisible: se comprueba explícitamente para dar un error claro en vez de
    -- una violación de FK.
    SELECT tenant_id INTO v_ut FROM usuarios WHERE id = p_usuario_id;
    IF v_ut IS DISTINCT FROM v_tenant THEN
        RAISE EXCEPTION 'El usuario no pertenece a este laboratorio'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_otorgar THEN
        INSERT INTO usuario_roles (tenant_id, usuario_id, rol_id, asignado_por)
        VALUES (v_tenant, p_usuario_id, v_rol, fn_app_usuario())
        ON CONFLICT (tenant_id, usuario_id, rol_id) DO NOTHING;
    ELSE
        DELETE FROM usuario_roles
         WHERE tenant_id = v_tenant AND usuario_id = p_usuario_id AND rol_id = v_rol;
        -- Quedarse sin ningún rol es un estado legítimo: una persona
        -- suspendida temporalmente sin desactivar su cuenta.
    END IF;
    RETURN TRUE;
END; $$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_asignar_rol(INTEGER, VARCHAR, BOOLEAN) IS
  'Única vía para otorgar o retirar un rol. El tenant sale del contexto y el '
  'autor de fn_app_usuario(): ninguno de los dos se puede pasar por parámetro. '
  'Requiere el permiso usuarios.assign_role, que lo comprueba la API.';


-- ============================================================================
-- SECCIÓN 6 · GUARDAS DE AUTORÍA — H-15
-- ============================================================================
-- Siete funciones aceptan p_usuario y hacen COALESCE(p_usuario, fn_app_usuario()).
-- Con la sesión del usuario 1 y p_usuario := 2, la fila queda a nombre del 2
-- — reproducido en la fase 5A sobre categorias_ensayo.creado_por.
--
-- 0006 cerró esto para auditoria.usuario_id. Esto lo cierra para creado_por.
-- Las FIRMAS NO CAMBIAN: p_usuario sigue valiendo como NULL o como el propio
-- usuario de la sesión, que es para lo que se escribió.
--
-- Los cuerpos de estas siete funciones NO se transcribieron a mano: se
-- extrajeron de 01_functions.sql —donde están definidas por última vez, ni
-- 0003 ni 0005 las reemplazan— y se les insertó la guarda tras el primer
-- BEGIN. La precondición 0.5 comprueba por md5 que el cuerpo vigente es
-- exactamente ese; si alguien las cambió después, la migración aborta en vez
-- de borrar ese cambio en silencio.

CREATE OR REPLACE FUNCTION fn_crear_categoria(
    p_nombre VARCHAR, p_prefijo VARCHAR, p_icono VARCHAR DEFAULT NULL,
    p_color VARCHAR DEFAULT NULL, p_usuario INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE v_id INTEGER; v_slug VARCHAR(40); v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    -- ►► GUARDA DE AUTORÍA (H-15, migración 0007) ◄◄
    -- p_usuario existe para que un proceso pueda declarar el autor, no para
    -- que pueda elegir OTRO autor. Sin esto, con la sesión del usuario 1 y
    -- p_usuario := 2 la fila queda a nombre del 2 — reproducido en la fase 5A.
    -- 0006 protege auditoria.usuario_id; esto protege creado_por.
    IF p_usuario IS NOT NULL AND p_usuario <> fn_app_usuario() THEN
        RAISE EXCEPTION 'La autoría no se puede atribuir a un usuario distinto '
                        'del que opera la sesión (se pidió %, la sesión es %)',
                        p_usuario, fn_app_usuario()
            USING ERRCODE = 'insufficient_privilege';
    END IF;
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

CREATE OR REPLACE FUNCTION fn_crear_ensayo(
    p_subcategoria_id INTEGER, p_nombre VARCHAR, p_norma VARCHAR,
    p_unidad VARCHAR, p_precio NUMERIC, p_acreditado BOOLEAN DEFAULT FALSE,
    p_usuario INTEGER DEFAULT NULL
) RETURNS VARCHAR AS $$
DECLARE
    v_cat INTEGER; v_codigo VARCHAR(12); v_id INTEGER;
    v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    -- ►► GUARDA DE AUTORÍA (H-15, migración 0007) ◄◄
    -- p_usuario existe para que un proceso pueda declarar el autor, no para
    -- que pueda elegir OTRO autor. Sin esto, con la sesión del usuario 1 y
    -- p_usuario := 2 la fila queda a nombre del 2 — reproducido en la fase 5A.
    -- 0006 protege auditoria.usuario_id; esto protege creado_por.
    IF p_usuario IS NOT NULL AND p_usuario <> fn_app_usuario() THEN
        RAISE EXCEPTION 'La autoría no se puede atribuir a un usuario distinto '
                        'del que opera la sesión (se pidió %, la sesión es %)',
                        p_usuario, fn_app_usuario()
            USING ERRCODE = 'insufficient_privilege';
    END IF;
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

CREATE OR REPLACE FUNCTION fn_crear_paquete(
    p_subcategoria_id INTEGER, p_nombre VARCHAR, p_unidad VARCHAR, p_precio NUMERIC,
    p_acreditado BOOLEAN, p_componentes JSONB, p_usuario INTEGER DEFAULT NULL
) RETURNS VARCHAR AS $$
DECLARE
    v_cat INTEGER; v_codigo VARCHAR(12); v_id INTEGER;
    v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    -- ►► GUARDA DE AUTORÍA (H-15, migración 0007) ◄◄
    -- p_usuario existe para que un proceso pueda declarar el autor, no para
    -- que pueda elegir OTRO autor. Sin esto, con la sesión del usuario 1 y
    -- p_usuario := 2 la fila queda a nombre del 2 — reproducido en la fase 5A.
    -- 0006 protege auditoria.usuario_id; esto protege creado_por.
    IF p_usuario IS NOT NULL AND p_usuario <> fn_app_usuario() THEN
        RAISE EXCEPTION 'La autoría no se puede atribuir a un usuario distinto '
                        'del que opera la sesión (se pidió %, la sesión es %)',
                        p_usuario, fn_app_usuario()
            USING ERRCODE = 'insufficient_privilege';
    END IF;
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

CREATE OR REPLACE FUNCTION fn_definir_componentes(
    p_paquete_id INTEGER, p_componentes JSONB, p_usuario INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_n INTEGER; v_vinculados INTEGER;
    v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    -- ►► GUARDA DE AUTORÍA (H-15, migración 0007) ◄◄
    -- p_usuario existe para que un proceso pueda declarar el autor, no para
    -- que pueda elegir OTRO autor. Sin esto, con la sesión del usuario 1 y
    -- p_usuario := 2 la fila queda a nombre del 2 — reproducido en la fase 5A.
    -- 0006 protege auditoria.usuario_id; esto protege creado_por.
    IF p_usuario IS NOT NULL AND p_usuario <> fn_app_usuario() THEN
        RAISE EXCEPTION 'La autoría no se puede atribuir a un usuario distinto '
                        'del que opera la sesión (se pidió %, la sesión es %)',
                        p_usuario, fn_app_usuario()
            USING ERRCODE = 'insufficient_privilege';
    END IF;
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

CREATE OR REPLACE FUNCTION fn_cambiar_acreditacion(
    p_ensayo_id INTEGER, p_acreditado BOOLEAN, p_motivo VARCHAR,
    p_vigente_desde DATE DEFAULT NULL, p_usuario INTEGER DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
    v_actual BOOLEAN;
    v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
    v_desde   DATE    := COALESCE(p_vigente_desde, fn_hoy_lima());
BEGIN
    -- ►► GUARDA DE AUTORÍA (H-15, migración 0007) ◄◄
    -- p_usuario existe para que un proceso pueda declarar el autor, no para
    -- que pueda elegir OTRO autor. Sin esto, con la sesión del usuario 1 y
    -- p_usuario := 2 la fila queda a nombre del 2 — reproducido en la fase 5A.
    -- 0006 protege auditoria.usuario_id; esto protege creado_por.
    IF p_usuario IS NOT NULL AND p_usuario <> fn_app_usuario() THEN
        RAISE EXCEPTION 'La autoría no se puede atribuir a un usuario distinto '
                        'del que opera la sesión (se pidió %, la sesión es %)',
                        p_usuario, fn_app_usuario()
            USING ERRCODE = 'insufficient_privilege';
    END IF;
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
    -- ►► GUARDA DE AUTORÍA (H-15, migración 0007) ◄◄
    -- p_usuario existe para que un proceso pueda declarar el autor, no para
    -- que pueda elegir OTRO autor. Sin esto, con la sesión del usuario 1 y
    -- p_usuario := 2 la fila queda a nombre del 2 — reproducido en la fase 5A.
    -- 0006 protege auditoria.usuario_id; esto protege creado_por.
    IF p_usuario IS NOT NULL AND p_usuario <> fn_app_usuario() THEN
        RAISE EXCEPTION 'La autoría no se puede atribuir a un usuario distinto '
                        'del que opera la sesión (se pidió %, la sesión es %)',
                        p_usuario, fn_app_usuario()
            USING ERRCODE = 'insufficient_privilege';
    END IF;
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

CREATE OR REPLACE FUNCTION fn_purgar_auditoria(p_hasta DATE, p_usuario INTEGER DEFAULT NULL)
RETURNS BIGINT AS $$
DECLARE v_n BIGINT; v_usuario INTEGER := COALESCE(p_usuario, fn_app_usuario());
BEGIN
    -- ►► GUARDA DE AUTORÍA (H-15, migración 0007) ◄◄
    -- p_usuario existe para que un proceso pueda declarar el autor, no para
    -- que pueda elegir OTRO autor. Sin esto, con la sesión del usuario 1 y
    -- p_usuario := 2 la fila queda a nombre del 2 — reproducido en la fase 5A.
    -- 0006 protege auditoria.usuario_id; esto protege creado_por.
    IF p_usuario IS NOT NULL AND p_usuario <> fn_app_usuario() THEN
        RAISE EXCEPTION 'La autoría no se puede atribuir a un usuario distinto '
                        'del que opera la sesión (se pidió %, la sesión es %)',
                        p_usuario, fn_app_usuario()
            USING ERRCODE = 'insufficient_privilege';
    END IF;
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

-- ============================================================================
-- SECCIÓN 7 · UN ROL DE SISTEMA NO DEJA DE SERLO — H-13
-- ============================================================================
-- El trigger vigente solo mira `OLD.es_sistema AND NEW.codigo <> OLD.codigo`,
-- así que es evadible en dos pasos: primero apagar es_sistema, después cambiar
-- el código. Con rol_permisos en pie, renombrar un código rompería la
-- resolución de permisos de todos los usuarios que tuvieran ese rol.

CREATE OR REPLACE FUNCTION fn_proteger_rol_sistema() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.es_sistema THEN
            RAISE EXCEPTION 'El rol "%" es del sistema y no se elimina', OLD.codigo
                USING ERRCODE = 'restrict_violation';
        END IF;
        RETURN OLD;
    END IF;

    -- ►► H-13 (0007): cerrar la evasión en dos pasos ◄◄
    IF OLD.es_sistema AND NOT NEW.es_sistema THEN
        RAISE EXCEPTION 'El rol "%" es del sistema y no deja de serlo', OLD.codigo
            USING ERRCODE = 'restrict_violation';
    END IF;

    IF OLD.es_sistema AND NEW.codigo <> OLD.codigo THEN
        RAISE EXCEPTION 'El código del rol de sistema "%" no se cambia', OLD.codigo
            USING ERRCODE = 'restrict_violation';
    END IF;

    -- Cambiar `nombre`, `descripcion` y `scope` sigue permitido: es como
    -- `comercial` pasa a llamarse Cotizador sin romper rol_permisos.
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- SECCIÓN 8 · PRIVILEGIOS
-- ============================================================================
-- Las tres tablas globales: solo lectura. Que sacgeo_app no pueda escribirlas
-- es lo que impide que un administrador se fabrique un rol a medida.

GRANT SELECT ON permisos     TO sacgeo_app;
GRANT SELECT ON rol_permisos TO sacgeo_app;

-- usuario_roles sí se escribe: es lo que ejerce el permiso usuarios.assign_role.
-- Sin UPDATE: una asignación se otorga o se retira, no se edita.
GRANT SELECT, INSERT, DELETE ON usuario_roles TO sacgeo_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO sacgeo_app;

-- Las funciones nuevas siguen la regla de 0004: nada ejecutable por PUBLIC.
REVOKE EXECUTE ON FUNCTION fn_usuario_permisos(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_asignar_rol(INTEGER, VARCHAR, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_validar_scope_permiso() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION fn_usuario_permisos(INTEGER) TO sacgeo_app;
GRANT  EXECUTE ON FUNCTION fn_asignar_rol(INTEGER, VARCHAR, BOOLEAN) TO sacgeo_app;


-- ============================================================================
-- SECCIÓN 9 · VALIDACIONES INTERNAS
-- ============================================================================
-- No comprueban que el SQL se ejecutara. Comprueban el resultado, y las de
-- seguridad provocan el intento que debe fallar.

DO $validar$
DECLARE
    v_n INTEGER; v_ok BOOLEAN; v_est TEXT; v_creador INTEGER;
    v_a1 INTEGER; v_ajeno INTEGER; v_otorgante INTEGER; v_aud INTEGER;
BEGIN
    -- ---- Catálogo ---------------------------------------------------------

    -- 9.1 · 31 permisos, 30 de tenant y 1 de plataforma.
    SELECT count(*) INTO v_n FROM permisos;
    IF v_n <> 31 THEN
        RAISE EXCEPTION '9.1 Se esperaban 31 permisos, hay %.', v_n USING ERRCODE='check_violation';
    END IF;
    SELECT count(*) INTO v_n FROM permisos WHERE scope='tenant';
    IF v_n <> 30 THEN
        RAISE EXCEPTION '9.1 Se esperaban 30 permisos de tenant, hay %.', v_n USING ERRCODE='check_violation';
    END IF;
    SELECT count(*) INTO v_n FROM permisos WHERE scope='plataforma';
    IF v_n <> 1 THEN
        RAISE EXCEPTION '9.1 Se esperaba 1 permiso de plataforma, hay %.', v_n USING ERRCODE='check_violation';
    END IF;

    -- 9.2 · Sin duplicados (uq_permisos_codigo ya lo impone; se comprueba por
    --       si alguien lo retirara en el futuro).
    SELECT count(*) INTO v_n FROM (SELECT codigo FROM permisos GROUP BY codigo HAVING count(*)>1) x;
    IF v_n > 0 THEN
        RAISE EXCEPTION '9.2 Hay % códigos de permiso duplicados.', v_n USING ERRCODE='check_violation';
    END IF;

    -- ---- Roles ------------------------------------------------------------

    -- 9.3 · Cinco roles, los cinco de sistema y de scope tenant.
    SELECT count(*) INTO v_n FROM roles;
    IF v_n <> 5 THEN
        RAISE EXCEPTION '9.3 Se esperaban 5 roles, hay %.', v_n USING ERRCODE='check_violation';
    END IF;
    SELECT count(*) INTO v_n FROM roles WHERE scope='tenant' AND es_sistema;
    IF v_n <> 5 THEN
        RAISE EXCEPTION '9.3 Los 5 roles deben ser de sistema y de scope tenant, hay %.', v_n
            USING ERRCODE='check_violation';
    END IF;

    -- 9.4 · La matriz: 49 asignaciones y el reparto por rol.
    SELECT count(*) INTO v_n FROM rol_permisos;
    IF v_n <> 49 THEN
        RAISE EXCEPTION '9.4 Se esperaban 49 filas en rol_permisos, hay %.', v_n
            USING ERRCODE='check_violation';
    END IF;
    FOR v_n IN SELECT 1 WHERE EXISTS (
        SELECT 1 FROM (
            SELECT r.codigo, count(*) AS n FROM rol_permisos rp JOIN roles r ON r.id=rp.rol_id
             GROUP BY r.codigo
        ) x WHERE (x.codigo,x.n) NOT IN
            (('admin',16),('comercial',14),('aprobador',7),('laboratorio',6),('lectura',6))
    ) LOOP
        RAISE EXCEPTION '9.4 El reparto de permisos por rol no es el aprobado.'
            USING ERRCODE='check_violation';
    END LOOP;

    -- 9.5 · admin NO tiene los permisos que la fase 5C.2 le retiró.
    --       Es la decisión más visible de este diseño: se verifica, no se supone.
    SELECT count(*) INTO v_n FROM rol_permisos rp
      JOIN roles r ON r.id=rp.rol_id JOIN permisos p ON p.id=rp.permiso_id
     WHERE r.codigo='admin' AND p.codigo IN
       ('catalogo.manage','catalogo.price','acreditacion.manage',
        'cotizaciones.create','cotizaciones.update','cotizaciones.submit',
        'cotizaciones.approve','cotizaciones.reject','cotizaciones.emit',
        'cotizaciones.cancel','cotizaciones.close');
    IF v_n > 0 THEN
        RAISE EXCEPTION '9.5 admin conserva % permisos que debía perder.', v_n
            USING ERRCODE='check_violation';
    END IF;

    -- 9.6 · comercial NO ve el dashboard; laboratorio es el único que acredita.
    IF EXISTS (SELECT 1 FROM rol_permisos rp JOIN roles r ON r.id=rp.rol_id
                 JOIN permisos p ON p.id=rp.permiso_id
                WHERE r.codigo='comercial' AND p.codigo='dashboard.read') THEN
        RAISE EXCEPTION '9.6 comercial recibió dashboard.read.' USING ERRCODE='check_violation';
    END IF;
    SELECT count(*) INTO v_n FROM rol_permisos rp JOIN roles r ON r.id=rp.rol_id
      JOIN permisos p ON p.id=rp.permiso_id WHERE p.codigo='acreditacion.manage';
    IF v_n <> 1 OR NOT EXISTS (SELECT 1 FROM rol_permisos rp JOIN roles r ON r.id=rp.rol_id
                                 JOIN permisos p ON p.id=rp.permiso_id
                                WHERE p.codigo='acreditacion.manage' AND r.codigo='laboratorio') THEN
        RAISE EXCEPTION '9.6 acreditacion.manage debe tenerlo SOLO laboratorio.'
            USING ERRCODE='check_violation';
    END IF;

    -- 9.7 · Los dos permisos sin titular lo están A PROPÓSITO.
    SELECT count(*) INTO v_n FROM permisos p
     WHERE NOT EXISTS (SELECT 1 FROM rol_permisos rp WHERE rp.permiso_id=p.id);
    IF v_n <> 2 THEN
        RAISE EXCEPTION '9.7 Se esperaban 2 permisos sin rol, hay %.', v_n USING ERRCODE='check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM permisos p
                WHERE NOT EXISTS (SELECT 1 FROM rol_permisos rp WHERE rp.permiso_id=p.id)
                  AND p.codigo NOT IN ('auditoria.purge','plataforma.acceso.grant')) THEN
        RAISE EXCEPTION '9.7 Hay un permiso huérfano que no es de los dos previstos.'
            USING ERRCODE='check_violation';
    END IF;

    -- 9.8 · SEGURIDAD: un rol de tenant no puede recibir el permiso de plataforma.
    BEGIN
        INSERT INTO rol_permisos (rol_id, permiso_id)
        VALUES ((SELECT id FROM roles WHERE codigo='admin'),
                (SELECT id FROM permisos WHERE codigo='plataforma.acceso.grant'));
        v_ok := TRUE;
    EXCEPTION WHEN insufficient_privilege THEN v_ok := FALSE;
    END;
    IF v_ok THEN
        RAISE EXCEPTION '9.8 UN ROL DE TENANT RECIBIÓ UN PERMISO DE PLATAFORMA.'
            USING ERRCODE='insufficient_privilege';
    END IF;

    -- ---- usuario_roles ----------------------------------------------------

    -- 9.9 · Una fila por usuario de tenant, ninguna para las identidades globales.
    SELECT count(*) INTO v_n FROM usuario_roles;
    IF v_n <> (SELECT count(*) FROM usuarios WHERE tenant_id IS NOT NULL) THEN
        RAISE EXCEPTION '9.9 usuario_roles no coincide con los usuarios de tenant.'
            USING ERRCODE='check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM usuario_roles ur JOIN usuarios u ON u.id=ur.usuario_id
                WHERE u.tenant_id IS NULL) THEN
        RAISE EXCEPTION '9.9 Una identidad global recibió un rol de tenant.'
            USING ERRCODE='insufficient_privilege';
    END IF;

    -- 9.9b · LA SEMILLA DEJÓ AUDITORÍA. Una fila por asignación, ni una menos.
    --        No basta con que registro_id no sea NULL: hay que demostrar que
    --        cada asignación inicial tiene SU fila. En la fase 5C.8 la semilla
    --        corría antes de los triggers y producía 5 asignaciones con 0
    --        auditorías, y ningún control lo habría delatado.
    SELECT count(*) INTO v_n FROM auditoria
     WHERE tabla = 'usuario_roles' AND accion = 'INSERT';
    IF v_n <> (SELECT count(*) FROM usuario_roles) THEN
        RAISE EXCEPTION '9.9b % asignaciones de rol pero % auditorías de alta. '
                        'La semilla no quedó auditada.',
                        (SELECT count(*) FROM usuario_roles), v_n
            USING ERRCODE='check_violation';
    END IF;

    -- Y la correspondencia es por fila, no por recuento: cada usuario_roles.id
    -- tiene su auditoria.registro_id.
    SELECT count(*) INTO v_n FROM usuario_roles ur
     WHERE NOT EXISTS (SELECT 1 FROM auditoria a
                        WHERE a.tabla='usuario_roles' AND a.accion='INSERT'
                          AND a.registro_id = ur.id);
    IF v_n > 0 THEN
        RAISE EXCEPTION '9.9b % asignaciones sin su fila de auditoría.', v_n
            USING ERRCODE='check_violation';
    END IF;

    -- El autor de esas auditorías es `sistema` (id 1), y debe coincidir con el
    -- asignado_por de la fila. Durante la migración no hay contexto de usuario:
    -- fn_app_usuario() devuelve 1 por su COALESCE, y eso es lo correcto — quien
    -- asignó estos roles no fue una persona, fue la migración.
    SELECT count(*) INTO v_n FROM usuario_roles ur
      JOIN auditoria a ON a.tabla='usuario_roles' AND a.accion='INSERT' AND a.registro_id=ur.id
     WHERE a.usuario_id IS DISTINCT FROM ur.asignado_por;
    IF v_n > 0 THEN
        RAISE EXCEPTION '9.9b En % filas el autor de la auditoría no coincide con asignado_por.', v_n
            USING ERRCODE='check_violation';
    END IF;

    -- 9.10 · RLS: 18 tablas ENABLE+FORCE, 19 políticas.
    SELECT count(*) INTO v_n FROM pg_class
     WHERE relnamespace='public'::regnamespace AND relkind='r'
       AND relrowsecurity AND relforcerowsecurity;
    IF v_n <> 18 THEN
        RAISE EXCEPTION '9.10 Se esperaban 18 tablas con RLS FORCE, hay %.', v_n
            USING ERRCODE='invalid_object_definition';
    END IF;
    SELECT count(*) INTO v_n FROM pg_policies WHERE schemaname='public';
    IF v_n <> 19 THEN
        RAISE EXCEPTION '9.10 Se esperaban 19 políticas, hay %.', v_n
            USING ERRCODE='invalid_object_definition';
    END IF;

    -- 9.11 · La política de usuario_roles NO menciona roles. Solo el tenant.
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='usuario_roles'
                      AND qual LIKE '%fn_app_tenant()%'
                      AND qual NOT ILIKE '%rol%') THEN
        RAISE EXCEPTION '9.11 La política de usuario_roles no es la esperada.'
            USING ERRCODE='invalid_object_definition';
    END IF;

    -- 9.12b · El guardián del otorgante existe y cubre INSERT y UPDATE.
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname='a_validar_otorgante' AND tgrelid='usuario_roles'::regclass
                      AND tgenabled='O' AND (tgtype::int & 4)=4 AND (tgtype::int & 16)=16) THEN
        RAISE EXCEPTION '9.12b a_validar_otorgante ausente o no cubre INSERT y UPDATE.'
            USING ERRCODE='undefined_object';
    END IF;

    -- 9.12 · Los dos índices que el control I3 de la 99 va a exigir.
    IF NOT EXISTS (SELECT 1 FROM pg_indexes
                    WHERE tablename='usuario_roles' AND indexdef ILIKE '%(rol_id)%') THEN
        RAISE EXCEPTION '9.12 Falta el índice sobre usuario_roles.rol_id.'
            USING ERRCODE='invalid_object_definition';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_indexes
                    WHERE tablename='rol_permisos' AND indexdef ILIKE '%(permiso_id)%') THEN
        RAISE EXCEPTION '9.12 Falta el índice sobre rol_permisos.permiso_id.'
            USING ERRCODE='invalid_object_definition';
    END IF;

    -- ---- Resolución -------------------------------------------------------

    -- 9.13 · fn_usuario_permisos devuelve la UNIÓN sin duplicar.
    --        Se comprueba con un usuario real, no en abstracto.
    -- Se ancla al tenant 1 a propósito: sin el filtro, con más de un laboratorio
    -- poblado el LIMIT 1 podría caer en un usuario de otro tenant y la prueba
    -- dejaría de ser determinista.
    IF EXISTS (SELECT 1 FROM usuarios WHERE tenant_id = 1 AND rol_id=(SELECT id FROM roles WHERE codigo='admin')) THEN
        SELECT count(*) INTO v_n FROM fn_usuario_permisos(
            (SELECT id FROM usuarios WHERE tenant_id = 1
               AND rol_id=(SELECT id FROM roles WHERE codigo='admin') ORDER BY id LIMIT 1));
        IF v_n <> 16 THEN
            RAISE EXCEPTION '9.13 Un admin debería resolver 16 permisos, resolvió %.', v_n
                USING ERRCODE='check_violation';
        END IF;
    END IF;

    -- ---- H-15 -------------------------------------------------------------

    -- 9.14 · SEGURIDAD: las 7 funciones llevan la guarda.
    SELECT count(*) INTO v_n FROM pg_proc
     WHERE pronamespace='public'::regnamespace
       AND proname IN ('fn_crear_categoria','fn_crear_ensayo','fn_crear_paquete',
                       'fn_definir_componentes','fn_cambiar_acreditacion',
                       'fn_crear_cotizacion','fn_purgar_auditoria')
       AND prosrc LIKE '%La autoría no se puede atribuir%';
    IF v_n <> 7 THEN
        RAISE EXCEPTION '9.14 Solo % de 7 funciones llevan la guarda de autoría.', v_n
            USING ERRCODE='invalid_object_definition';
    END IF;

    -- 9.15 · SEGURIDAD REAL: la falsificación falla con 42501.
    PERFORM set_config('app.tenant_id','1',TRUE);
    PERFORM set_config('app.usuario_id','1',TRUE);
    BEGIN
        PERFORM fn_crear_categoria('Prueba 0007','PA','lab','#112233', 2);
        v_ok := TRUE;
    EXCEPTION WHEN insufficient_privilege THEN v_ok := FALSE;
    WHEN OTHERS THEN
        v_est := SQLSTATE; v_ok := FALSE;
        RAISE EXCEPTION '9.15 La falsificación se bloqueó con % y no con 42501.', v_est
            USING ERRCODE='invalid_object_definition';
    END;
    IF v_ok THEN
        RAISE EXCEPTION '9.15 SE PUDO ATRIBUIR LA AUTORÍA A OTRO USUARIO. H-15 sigue abierto.'
            USING ERRCODE='insufficient_privilege';
    END IF;

    -- 9.16 · Y el camino legítimo sigue funcionando: p_usuario NULL.
    BEGIN
        PERFORM fn_crear_categoria('Prueba 0007 legitima','PB','lab','#112233', NULL);
        v_ok := TRUE;
    EXCEPTION WHEN OTHERS THEN v_ok := FALSE; v_est := SQLSTATE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION '9.16 El camino legítimo (p_usuario NULL) se rompió [%].', v_est
            USING ERRCODE='invalid_object_definition';
    END IF;
    -- El filtro de tenant NO es cosmético. Esta validación corre como PROPIETARIO
    -- de las tablas, que no está sujeto a RLS y por tanto ve las categorías de
    -- TODOS los laboratorios. `uq_categorias_prefijo` es UNIQUE (tenant_id,
    -- prefijo_codigo), así que dos tenants pueden tener cada uno su 'PB' y el
    -- SELECT devolvería una fila arbitraria. Con la base poblada con dos
    -- laboratorios, esa ambigüedad es real, no teórica.
    SELECT creado_por INTO v_creador
      FROM categorias_ensayo WHERE prefijo_codigo='PB' AND tenant_id = 1;
    IF v_creador <> 1 THEN
        RAISE EXCEPTION '9.16 creado_por quedó en % y no en el usuario de la sesión.', v_creador
            USING ERRCODE='check_violation';
    END IF;

    -- ---- H-13 -------------------------------------------------------------

    -- 9.17 · SEGURIDAD: es_sistema no se puede apagar.
    BEGIN
        UPDATE roles SET es_sistema = FALSE WHERE codigo='admin';
        v_ok := TRUE;
    EXCEPTION WHEN restrict_violation THEN v_ok := FALSE;
    END;
    IF v_ok THEN
        RAISE EXCEPTION '9.17 SE PUDO APAGAR es_sistema. H-13 sigue abierto.'
            USING ERRCODE='insufficient_privilege';
    END IF;

    -- 9.18 · Y el cambio legítimo de nombre sigue permitido.
    BEGIN
        UPDATE roles SET nombre = nombre WHERE codigo='admin';
        v_ok := TRUE;
    EXCEPTION WHEN OTHERS THEN v_ok := FALSE; v_est := SQLSTATE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION '9.18 H-13 bloqueó un cambio legítimo de nombre [%].', v_est
            USING ERRCODE='invalid_object_definition';
    END IF;

    -- ---- Lo que 0007 NO debía tocar ---------------------------------------

    -- 9.19 · Los triggers de auditoría de 0005 y 0006 siguen activos.
    SELECT count(*) INTO v_n FROM pg_trigger
     WHERE tgrelid='auditoria'::regclass AND NOT tgisinternal AND tgenabled='O';
    IF v_n <> 3 THEN
        RAISE EXCEPTION '9.19 Se esperaban 3 triggers activos en auditoria, hay %.', v_n
            USING ERRCODE='invalid_object_definition';
    END IF;

    -- 9.20 · Ningún rol de clúster nuevo. 0007 no amplía la superficie.
    SELECT count(*) INTO v_n FROM pg_roles WHERE rolname LIKE 'sacgeo%';
    IF v_n <> 3 THEN
        RAISE EXCEPTION '9.20 Se esperaban 3 roles sacgeo_*, hay %.', v_n
            USING ERRCODE='invalid_object_definition';
    END IF;

    -- ---- asignado_por -----------------------------------------------------

    -- 9.21 · SEGURIDAD: no se puede declarar otorgante a otro usuario.
    --        Se usa el rol `aprobador`, que nace en esta migración: ninguna fila
    --        sembrada puede tenerlo, así que la PK no estorba.
    SELECT id INTO v_a1 FROM usuarios WHERE tenant_id = 1 ORDER BY id LIMIT 1;
    SELECT id INTO v_ajeno FROM usuarios WHERE tenant_id IS DISTINCT FROM 1
                                            AND tenant_id IS NOT NULL ORDER BY id LIMIT 1;
    IF v_a1 IS NOT NULL THEN
        PERFORM set_config('app.usuario_id', v_a1::TEXT, TRUE);
        PERFORM set_config('app.tenant_id', '1', TRUE);
        BEGIN
            INSERT INTO usuario_roles (tenant_id, usuario_id, rol_id, asignado_por)
            VALUES (1, v_a1, (SELECT id FROM roles WHERE codigo='aprobador'),
                    COALESCE(v_ajeno, 1));
            v_ok := TRUE;
        EXCEPTION WHEN insufficient_privilege THEN v_ok := FALSE;
        END;
        -- Si no hay usuario de otro tenant, COALESCE cae en 1 (`sistema`), que
        -- tampoco es el de la sesión: la prueba sigue siendo válida.
        IF v_ok AND COALESCE(v_ajeno, 1) <> v_a1 THEN
            RAISE EXCEPTION '9.21 SE PUDO DECLARAR OTORGANTE A OTRO USUARIO.'
                USING ERRCODE='insufficient_privilege';
        END IF;
        SELECT count(*) INTO v_n FROM usuario_roles
         WHERE rol_id = (SELECT id FROM roles WHERE codigo='aprobador');
        IF v_n <> 0 THEN
            RAISE EXCEPTION '9.21 La falsificación dejó % filas residuales.', v_n
                USING ERRCODE='check_violation';
        END IF;

        -- 9.22 · El otorgante correcto SÍ pasa, y la auditoría queda alineada.
        INSERT INTO usuario_roles (tenant_id, usuario_id, rol_id, asignado_por)
        VALUES (1, v_a1, (SELECT id FROM roles WHERE codigo='aprobador'), v_a1);
        SELECT asignado_por INTO v_otorgante FROM usuario_roles
         WHERE tenant_id=1 AND usuario_id=v_a1
           AND rol_id=(SELECT id FROM roles WHERE codigo='aprobador');
        SELECT usuario_id INTO v_aud FROM auditoria
         WHERE tabla='usuario_roles' ORDER BY id DESC LIMIT 1;
        IF v_otorgante <> v_a1 OR v_aud IS DISTINCT FROM v_a1 THEN
            RAISE EXCEPTION '9.22 Fila y auditoría no coinciden: asignado_por=%, auditoria=%, sesión=%',
                            v_otorgante, v_aud, v_a1
                USING ERRCODE='check_violation';
        END IF;
        RAISE NOTICE '0007: fila y auditoría alineadas en el otorgante (usuario %)', v_a1;
        DELETE FROM usuario_roles
         WHERE tenant_id=1 AND usuario_id=v_a1
           AND rol_id=(SELECT id FROM roles WHERE codigo='aprobador');
        PERFORM set_config('app.usuario_id', '1', TRUE);
    ELSE
        RAISE NOTICE '0007: 9.21/9.22 omitidas — no hay usuarios de tenant en esta base.';
    END IF;

    RAISE NOTICE '0007: 23 validaciones internas superadas (8 de seguridad real).';
END
$validar$;

-- Las dos categorías de prueba de las validaciones 9.15/9.16 se retiran. Sus
-- filas de auditoría no: la auditoría es append-only y dejarlas es correcto —
-- esas categorías existieron durante la migración y el rastro lo refleja.
-- TRES pasos, no dos. `fn_crear_categoria` crea siempre una subcategoría
-- "General" (regla R2), y `fn_proteger_subcategoria` impide borrar la única
-- activa de una categoría ACTIVA:
--
--     DELETE subcategoria -> 23001 'Es la única subcategoría activa de su categoría'
--     DELETE categoria    -> 23503 violación de FK, porque la subcategoría sigue ahí
--
-- Reproducido en la fase 5C.5. Desactivar la categoría primero apaga esa guarda
-- —mira `v_cat_activa`— sin tocar ningún trigger ni ninguna restricción.
--
-- El filtro por tenant evita que, con varios laboratorios poblados, la limpieza
-- alcance una categoría 'PA' o 'PB' legítima de otro: `uq_categorias_prefijo`
-- es UNIQUE (tenant_id, prefijo_codigo), no global.
UPDATE categorias_ensayo SET activo = FALSE
 WHERE prefijo_codigo IN ('PA','PB') AND tenant_id = 1;

DELETE FROM subcategorias_ensayo
 WHERE categoria_id IN (SELECT id FROM categorias_ensayo
                         WHERE prefijo_codigo IN ('PA','PB') AND tenant_id = 1);

DELETE FROM categorias_ensayo WHERE prefijo_codigo IN ('PA','PB') AND tenant_id = 1;

DO $limpieza$
DECLARE v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM categorias_ensayo
     WHERE prefijo_codigo IN ('PA','PB') AND tenant_id = 1;
    IF v_n > 0 THEN
        RAISE EXCEPTION 'Quedaron % categorías de prueba.', v_n USING ERRCODE='check_violation';
    END IF;
    RAISE NOTICE '0007: categorías de prueba retiradas.';
END
$limpieza$;


-- ============================================================================
-- SECCIÓN 10 · REGISTRO
-- ============================================================================

INSERT INTO schema_migrations (version, nombre, nota)
VALUES ('0007',
        'RBAC multi-rol: permisos, rol_permisos, usuario_roles + guardas H-15 y H-13',
        '31 permisos (30 tenant + 1 plataforma), 5 roles, 49 asignaciones. '
        'usuario_roles tenant-scoped con RLS FORCE: 18 tablas, 19 políticas. '
        'admin pierde catálogo, acreditación y operación de cotizaciones por diseño.');

COMMIT;

\echo '*** 0007 aplicada. Ejecute 97 (con sacgeo_app), 98 y 99 antes de darla por buena. ***'
