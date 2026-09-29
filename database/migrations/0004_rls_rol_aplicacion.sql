-- ============================================================================
--  ⚠  MIGRACIÓN 0004 — RLS + ROL DE APLICACIÓN  ·  ESCRITA, **NO APLICADA**  ⚠
-- ============================================================================
-- Convierte el aislamiento entre laboratorios de una convención que el backend
-- debe recordar en una regla que PostgreSQL impone.
--
-- 0003 puso la estructura: tenant_id, FK compuestas, unicidad por tenant. Esta
-- migración pone la última línea de defensa: aunque una consulta olvide su
-- WHERE, el motor no devuelve filas de otro laboratorio.
--
-- ----------------------------------------------------------------------------
-- PRECONDICIONES, TODAS
-- ----------------------------------------------------------------------------
--   1. 0003 aplicada y 99_verificacion.sql limpio.
--   2. Backend que resuelve el tenant desde la sesión autenticada  ← fase 5C-A ✓
--   3. Ese backend abre cada transacción con set_config('app.tenant_id',…,true)
--                                                        ← fase 5B ✓
--   4. Pruebas de aislamiento escritas          ← 97_aislamiento.sql ✓
--   5. Respaldo verificado y ventana de mantenimiento.
--
-- ----------------------------------------------------------------------------
-- LA FRONTERA LOGIN ↔ RLS  (auditada en 4A-TER, aprobada como D-12)
-- ----------------------------------------------------------------------------
-- Hay una circularidad que RLS introduce y que hay que resolver a propósito:
--
--     el backend necesita:  email → usuarios → tenant_id → set_config
--     la política exige:    set_config → fn_app_tenant() → leer usuarios
--
-- Con la política de tenant activa, la consulta de login falla con 42501 antes
-- de poder averiguar a qué laboratorio pertenece quien intenta entrar. Está
-- reproducido en 4A-TER, no es una hipótesis.
--
-- Se resuelve con UNA excepción acotada, y se descartaron las alternativas:
--
--   · un rol aparte que lea `usuarios` — traslada la fuga, no la cierra: ese
--     rol necesitaría leer los usuarios de todos los laboratorios;
--   · dejar `usuarios` fuera de RLS — cualquier tenant vería a todos;
--   · una política que tolere la ausencia de contexto — convierte "falla
--     ruidosamente" en "devuelve algo", que es como se pierde una fuga de
--     vista.
--
-- La excepción es fn_login_buscar() (sección 6): SECURITY DEFINER, una consulta
-- fija, cinco columnas, una fila. Y NO necesita BYPASSRLS: su propietario es un
-- rol NOLOGIN con una política propia, así que la única forma de usar sus
-- privilegios es llamar a esa función.
--
-- ----------------------------------------------------------------------------
-- EL USUARIO `sistema` NO ES VISIBLE PARA NINGÚN TENANT
-- ----------------------------------------------------------------------------
-- La primera versión de esta migración daba a `usuarios` la política híbrida
--     USING (tenant_id IS NULL OR tenant_id = fn_app_tenant())
-- para que vw_auditoria_legible pudiera unir con el autor de cada cambio.
--
-- 4A-TER lo probó y encontró lo que eso significa en realidad: CUALQUIER tenant
-- leía la fila completa del usuario `sistema` — email, rol_id = 1 (admin),
-- estado y **password_hash entero**. Una cuenta administrativa global expuesta
-- a todos los clientes de la instalación.
--
-- Por eso `usuarios` lleva aquí la política ESTRICTA, sin el NULL. Y como esa
-- política dejaba vw_auditoria_legible en cero filas —340 de 341 entradas de
-- auditoría son de `sistema`—, la vista se recrea con LEFT JOIN (sección 7).
-- La vista deja de necesitar VER al autor para poder nombrarlo.
--
-- ----------------------------------------------------------------------------
-- LO QUE ESTA MIGRACIÓN NO TRAE
-- ----------------------------------------------------------------------------
--   · sesiones / sesion_tokens / refresh tokens → 0005
--   · RBAC, multi-rol, permisos                 → posterior
--   · eventos_seguridad                         → posterior
--   · contraseña de sacgeo_app                  → fuera del repositorio (§2)
-- ============================================================================

\echo '*** 0004 es una migración PREPARADA. Lea la cabecera antes de aplicarla. ***'
\set ON_ERROR_STOP on
BEGIN;


-- ----------------------------------------------------------------------------
-- 0. PRECONDICIONES — abortar antes de tocar nada
-- ----------------------------------------------------------------------------
DO $precondiciones$
DECLARE
    v_falta TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0003') THEN
        RAISE EXCEPTION '0003 no está aplicada. 0004 depende de tenant_id y fn_app_tenant().'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF to_regprocedure('public.fn_app_tenant()') IS NULL THEN
        RAISE EXCEPTION 'fn_app_tenant() no existe. La crea 0003.'
            USING ERRCODE = 'undefined_function';
    END IF;

    -- Las 17 tablas que recibirán RLS deben existir. Si falta una, la
    -- migración dejaría un aislamiento a medias, que es peor que ninguno.
    SELECT string_agg(t, ', ') INTO v_falta
      FROM unnest(ARRAY[
        'empresas','contactos','personas','categorias_ensayo','subcategorias_ensayo',
        'ensayos_catalogo','ensayo_acreditacion_historial','paquete_componentes',
        'correlativos','cotizaciones','cotizacion_items','cotizacion_historial_estados',
        'integraciones','documentos_externos',
        'usuarios','plantillas_cotizacion','auditoria']) AS t
     WHERE to_regclass('public.' || t) IS NULL;
    IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'Faltan tablas esperadas: %', v_falta
            USING ERRCODE = 'undefined_table';
    END IF;

    -- Toda tabla que vaya a llevar RLS necesita la columna sobre la que filtrar.
    SELECT string_agg(t, ', ') INTO v_falta
      FROM unnest(ARRAY[
        'empresas','contactos','personas','categorias_ensayo','subcategorias_ensayo',
        'ensayos_catalogo','ensayo_acreditacion_historial','paquete_componentes',
        'correlativos','cotizaciones','cotizacion_items','cotizacion_historial_estados',
        'integraciones','documentos_externos',
        'usuarios','plantillas_cotizacion','auditoria']) AS t
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema='public' AND table_name=t AND column_name='tenant_id');
    IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'Tablas sin columna tenant_id: %', v_falta
            USING ERRCODE = 'undefined_column';
    END IF;

    -- sacgeo_auth no debe preexistir con atributos inseguros, por el mismo
    -- motivo que sacgeo_app: sería señal de que alguien hizo algo a mano.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='sacgeo_auth'
                AND (rolcanlogin OR rolsuper OR rolbypassrls OR rolcreatedb
                     OR rolcreaterole OR rolreplication)) THEN
        RAISE EXCEPTION 'El rol sacgeo_auth ya existe CON ATRIBUTOS INSEGUROS.'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='sacgeo_auth') THEN
        RAISE EXCEPTION 'El rol sacgeo_auth ya existe. Revise su origen antes de continuar.'
            USING ERRCODE = 'duplicate_object';
    END IF;

    -- Ninguna política previa debe existir: si la hay, alguien aplicó algo a
    -- mano y no se sobrescribe en silencio.
    IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
                WHERE c.relnamespace = 'public'::regnamespace) THEN
        RAISE EXCEPTION 'Ya existen políticas RLS en public. Revise el estado antes de continuar.'
            USING ERRCODE = 'duplicate_object';
    END IF;
END
$precondiciones$;


-- ----------------------------------------------------------------------------
-- 1. EL ROL DE APLICACIÓN
-- ----------------------------------------------------------------------------
-- Los cinco atributos negados no son ceremonia. Cada uno anula RLS por su
-- cuenta:
--   SUPERUSER   — ignora todas las políticas, siempre.
--   BYPASSRLS   — el atributo cuyo nombre lo dice.
--   CREATEROLE  — podría concederse a sí mismo los dos anteriores.
--   CREATEDB    — no lo necesita.
--   REPLICATION — permite leer el WAL, que contiene todas las filas de todos
--                 los tenants sin pasar por ninguna política.
--
-- Y hay un sexto requisito que no es un atributo: NO DEBE SER PROPIETARIO de
-- las tablas. Un propietario ignora sus propias políticas salvo FORCE. Aquí se
-- usan las dos defensas —no ser propietario Y FORCE— porque cada una cubre el
-- fallo de la otra.
--
-- CONTRASEÑA: no se fija aquí. Una contraseña en un archivo versionado es una
-- contraseña comprometida. Tras aplicar la migración, el operador ejecuta de
-- forma interactiva:
--
--     psql -U <admin> -d sacgeo_dev -c '\password sacgeo_app'
--
-- `\password` pide la contraseña por terminal y envía un ALTER ROLE ya cifrado:
-- no aparece en el historial de psql ni en los logs del servidor. El valor va
-- después al vault y a la variable DATABASE_URL del backend.
DO $rol$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sacgeo_app') THEN
        -- Existe. Se verifica que sea seguro; NO se "corrige" en silencio,
        -- porque un rol preexistente con privilegios de más significa que
        -- alguien hizo algo que hay que revisar antes de seguir.
        IF EXISTS (SELECT 1 FROM pg_roles
                    WHERE rolname = 'sacgeo_app'
                      AND (rolsuper OR rolbypassrls OR rolcreatedb
                           OR rolcreaterole OR rolreplication)) THEN
            RAISE EXCEPTION
                'El rol sacgeo_app ya existe CON ATRIBUTOS INSEGUROS. Revise por qué antes de continuar.'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
        RAISE NOTICE 'sacgeo_app ya existe con atributos correctos; no se recrea.';
    ELSE
        EXECUTE 'CREATE ROLE sacgeo_app LOGIN
                   NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS';
        RAISE NOTICE 'Rol sacgeo_app creado SIN CONTRASEÑA. Fíjela con \\password (ver cabecera).';
    END IF;
END
$rol$;


-- ----------------------------------------------------------------------------
-- 2. PRIVILEGIOS MÍNIMOS
-- ----------------------------------------------------------------------------
-- Primero se retira lo que PostgreSQL concede por omisión, y después se otorga
-- lo justo. El orden importa: conceder sobre un esquema abierto a PUBLIC deja
-- la puerta de atrás abierta.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT  USAGE ON SCHEMA public TO sacgeo_app;

-- 2.1 · Las 14 tenant-scoped: CRUD completo. RLS acota el alcance a su tenant,
--       y los triggers del dominio siguen imponiendo qué es posible (una
--       cotización emitida no se edita, un ensayo cotizado no se borra…).
--       La autorización decide quién puede intentar; la integridad decide qué
--       llega a ocurrir.
GRANT SELECT, INSERT, UPDATE, DELETE ON
    empresas, contactos, personas,
    categorias_ensayo, subcategorias_ensayo, ensayos_catalogo,
    ensayo_acreditacion_historial, paquete_componentes,
    correlativos, cotizaciones, cotizacion_items,
    cotizacion_historial_estados, integraciones, documentos_externos
TO sacgeo_app;

-- 2.2 · Híbridas.
GRANT SELECT, INSERT, UPDATE, DELETE ON plantillas_cotizacion TO sacgeo_app;

-- usuarios: sin DELETE. El trigger a_no_delete ya lo impide, pero negarlo
-- también a nivel de privilegio es más barato que un trigger y más explícito.
GRANT SELECT, INSERT, UPDATE ON usuarios TO sacgeo_app;

-- auditoria: SOLO lectura e inserción. Nunca UPDATE ni DELETE.
-- Es append-only por trigger; negarlo además por privilegio significa que la
-- aplicación no podría reescribir el rastro ni aunque un trigger se
-- desactivara por error en una migración futura.
GRANT SELECT, INSERT ON auditoria TO sacgeo_app;

-- 2.3 · Globales: solo lectura. La aplicación las consulta, no las administra.
--       Dar de alta un laboratorio, tocar los roles del producto o cambiar qué
--       campos son sensibles son actos de plataforma, no de la aplicación.
GRANT SELECT ON tenants, roles, campos_sensibles TO sacgeo_app;

-- schema_migrations: ni SELECT. La versión del esquema no le incumbe a la
-- aplicación, y saber qué migraciones existen es información de operación.

-- 2.4 · Las 8 vistas.
GRANT SELECT ON
    vw_catalogo_disponible, vw_paquete_detalle, vw_paquetes_resumen,
    vw_acreditacion_vigente, vw_resumen_por_categoria, vw_ensayos_mas_cotizados,
    vw_auditoria_legible, vw_cotizacion_pdf
TO sacgeo_app;

-- 2.5 · Secuencias: hacen falta para las columnas IDENTITY.
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO sacgeo_app;

-- 2.6 · Funciones.
-- Se retira el EXECUTE que PostgreSQL concede a PUBLIC por omisión y se
-- concede en bloque a sacgeo_app, con UNA excepción explícita.
--
-- Conceder EXECUTE sobre todas y revocar la peligrosa, en lugar de enumerar 45,
-- es deliberado: la lista se quedaría obsoleta en la primera migración que
-- añada una función, y una función nueva sin permiso rompe la aplicación de
-- forma difícil de diagnosticar. Las funciones de este esquema son todas
-- SECURITY INVOKER —verificado: cero SECURITY DEFINER—, así que ninguna puede
-- saltarse RLS: ejecutarlas no concede nada que el rol no tuviera ya.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT  EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO sacgeo_app;

-- La excepción: fn_purgar_auditoria() BORRA filas de auditoría. Es una tarea
-- de operador con su propia ventana y su propia justificación, no algo que la
-- aplicación deba poder invocar.
REVOKE EXECUTE ON FUNCTION fn_purgar_auditoria(DATE, INTEGER) FROM sacgeo_app;


-- ----------------------------------------------------------------------------
-- 3. RLS — ACTIVAR Y FORZAR
-- ----------------------------------------------------------------------------
-- ENABLE sin FORCE es una trampa silenciosa: las políticas existen, se ven en
-- el catálogo, y el propietario de la tabla las ignora por completo. Como las
-- migraciones se aplican con el rol administrativo —que es el propietario—,
-- sin FORCE una verificación hecha con ese rol daría "todo bien" mientras el
-- aislamiento no existe.
ALTER TABLE empresas                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE empresas                      FORCE  ROW LEVEL SECURITY;
ALTER TABLE contactos                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE contactos                     FORCE  ROW LEVEL SECURITY;
ALTER TABLE personas                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE personas                      FORCE  ROW LEVEL SECURITY;
ALTER TABLE categorias_ensayo             ENABLE ROW LEVEL SECURITY;
ALTER TABLE categorias_ensayo             FORCE  ROW LEVEL SECURITY;
ALTER TABLE subcategorias_ensayo          ENABLE ROW LEVEL SECURITY;
ALTER TABLE subcategorias_ensayo          FORCE  ROW LEVEL SECURITY;
ALTER TABLE ensayos_catalogo              ENABLE ROW LEVEL SECURITY;
ALTER TABLE ensayos_catalogo              FORCE  ROW LEVEL SECURITY;
ALTER TABLE ensayo_acreditacion_historial ENABLE ROW LEVEL SECURITY;
ALTER TABLE ensayo_acreditacion_historial FORCE  ROW LEVEL SECURITY;
ALTER TABLE paquete_componentes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE paquete_componentes           FORCE  ROW LEVEL SECURITY;
ALTER TABLE correlativos                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE correlativos                  FORCE  ROW LEVEL SECURITY;
ALTER TABLE cotizaciones                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE cotizaciones                  FORCE  ROW LEVEL SECURITY;
ALTER TABLE cotizacion_items              ENABLE ROW LEVEL SECURITY;
ALTER TABLE cotizacion_items              FORCE  ROW LEVEL SECURITY;
ALTER TABLE cotizacion_historial_estados  ENABLE ROW LEVEL SECURITY;
ALTER TABLE cotizacion_historial_estados  FORCE  ROW LEVEL SECURITY;
ALTER TABLE integraciones                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE integraciones                 FORCE  ROW LEVEL SECURITY;
ALTER TABLE documentos_externos           ENABLE ROW LEVEL SECURITY;
ALTER TABLE documentos_externos           FORCE  ROW LEVEL SECURITY;

-- Híbridas: mismo ENABLE/FORCE, distinta política (sección 5).
ALTER TABLE usuarios                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios                      FORCE  ROW LEVEL SECURITY;
ALTER TABLE plantillas_cotizacion         ENABLE ROW LEVEL SECURITY;
ALTER TABLE plantillas_cotizacion         FORCE  ROW LEVEL SECURITY;
ALTER TABLE auditoria                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditoria                     FORCE  ROW LEVEL SECURITY;

-- Sin RLS, a propósito:
--   tenants, roles, campos_sensibles → globales del producto, y sacgeo_app
--       solo tiene SELECT. Ponerles políticas rompería fn_hoy_lima() (lee
--       tenants) y fn_campos_sensibles() (lee campos_sensibles).
--   schema_migrations → sacgeo_app no tiene ningún privilegio sobre ella.


-- ----------------------------------------------------------------------------
-- 4. POLÍTICAS — LAS 14 TENANT-SCOPED
-- ----------------------------------------------------------------------------
-- USING y WITH CHECK no son redundantes y omitir el segundo es el error
-- clásico:
--   USING       filtra lo que se LEE, y qué filas alcanzan UPDATE y DELETE.
--   WITH CHECK  impide DEJAR una fila en otro tenant: sin él, un INSERT con
--               tenant_id ajeno pasa sin ruido, y un UPDATE puede MOVER una
--               fila del tenant 1 al tenant 2.
--
-- Las políticas se otorgan a sacgeo_app explícitamente y no a PUBLIC: una
-- política sobre PUBLIC se aplicaría también a roles futuros que quizá deban
-- tener otro tratamiento.
CREATE POLICY p_tenant ON empresas FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON contactos FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON personas FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON categorias_ensayo FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON subcategorias_ensayo FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON ensayos_catalogo FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON ensayo_acreditacion_historial FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON paquete_componentes FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON correlativos FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON cotizaciones FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON cotizacion_items FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON cotizacion_historial_estados FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON integraciones FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());
CREATE POLICY p_tenant ON documentos_externos FOR ALL TO sacgeo_app
    USING (tenant_id = fn_app_tenant()) WITH CHECK (tenant_id = fn_app_tenant());


-- ----------------------------------------------------------------------------
-- 5. POLÍTICAS — LAS 3 HÍBRIDAS
-- ----------------------------------------------------------------------------
-- Una regla que atraviesa esta sección entera:
--
--     tenant_id IS NULL significa "no pertenece a ningún laboratorio".
--     NUNCA significa "acceso a todos los laboratorios".
--
-- Admitir NULL en un USING deja ver las filas del producto —las 3 plantillas
-- base, el usuario `sistema`, los cambios globales del rastro—, que son las
-- mismas para todos. No abre ni una fila de otro tenant.

-- 5.1 · plantillas_cotizacion
-- La asimetría es el diseño: se LEEN las base y las propias; solo se ESCRIBEN
-- las propias. Y con esto queda cerrado un hueco que 3E dejó abierto: hoy
-- ningún trigger impide modificar una plantilla base, y este WITH CHECK es el
-- único mecanismo que lo hará.
CREATE POLICY p_hibrida ON plantillas_cotizacion FOR ALL TO sacgeo_app
    USING      (tenant_id IS NULL OR tenant_id = fn_app_tenant())
    WITH CHECK (tenant_id = fn_app_tenant());

-- 5.2 · usuarios — POLÍTICA ESTRICTA, sin el NULL
--
-- A diferencia de plantillas_cotizacion, aquí el USING NO admite tenant_id
-- NULL. La razón está medida, no supuesta: con el NULL, 4A-TER comprobó que
-- cualquier tenant leía la fila entera del usuario `sistema`, incluido su
-- password_hash. Una identidad global no es una fila compartida: es una fila
-- que no le corresponde a nadie.
--
--     tenant_id IS NULL significa "no pertenece a ningún laboratorio".
--     NUNCA significa "lo pueden ver todos".
--
-- Consecuencia asumida y resuelta: vw_auditoria_legible ya no puede unir con
-- `sistema`, autor de casi toda la auditoría. Se recrea en la sección 7 con
-- LEFT JOIN para que siga mostrando el historial completo.
--
-- El login, que necesita encontrar al usuario antes de conocer su tenant, se
-- resuelve con fn_login_buscar() en la sección 6.
CREATE POLICY p_tenant ON usuarios FOR ALL TO sacgeo_app
    USING      (tenant_id = fn_app_tenant())
    WITH CHECK (tenant_id = fn_app_tenant());

-- 5.3 · auditoria  — DECISIÓN D-6, cerrada
--
--   USING      (tenant_id IS NULL OR tenant_id = fn_app_tenant())
--   WITH CHECK (tenant_id IS NULL OR tenant_id = fn_app_tenant())
--
-- Lectura: el tenant 1 ve su rastro y el de los cambios del producto que le
-- afectan (un rol modificado, una plantilla base, el usuario sistema). No ve
-- NADA del tenant 2.
--
-- Escritura: el WITH CHECK admite NULL, a diferencia de las dos anteriores, y
-- el motivo es concreto. Quien escribe aquí es SIEMPRE el trigger fn_auditar(),
-- nunca una sentencia de la aplicación: la tabla es append-only y no acepta
-- INSERT directo. Ese trigger deriva el tenant_id de la fila auditada, así que
-- al modificar una fila global —un rol, una entrada de campos_sensibles—
-- produce una fila de auditoría con tenant_id NULL.
--
-- Con un WITH CHECK que no admitiera NULL, tocar un rol fallaría por culpa de
-- su propia auditoría: no sería una fuga, sería la aplicación rota.
--
-- La alternativa era declarar fn_auditar() como SECURITY DEFINER. Se descarta:
-- añadiría superficie de ataque (dueño, search_path, permisos) para resolver
-- algo que el append-only ya protege.
--
-- Esto NO convierte el NULL en acceso global: un tenant sigue sin poder leer
-- ni escribir una sola fila del tenant 2.
CREATE POLICY p_hibrida ON auditoria FOR ALL TO sacgeo_app
    USING      (tenant_id IS NULL OR tenant_id = fn_app_tenant())
    WITH CHECK (tenant_id IS NULL OR tenant_id = fn_app_tenant());


-- ----------------------------------------------------------------------------
-- 6. LA EXCEPCIÓN DEL LOGIN  (D-12, auditada en 4A-TER)
-- ----------------------------------------------------------------------------
-- Un rol que existe solo para ser PROPIETARIO de una función.
--
-- NOLOGIN es la pieza clave: sus privilegios no son alcanzables conectándose,
-- porque no se puede conectar. La única vía de usarlos es invocar la función
-- SECURITY DEFINER de abajo, que ejecuta una consulta fija.
--
-- Y NO lleva BYPASSRLS. En su lugar recibe una política propia sobre
-- `usuarios`, que es un permiso mucho más acotado: BYPASSRLS se saltaría las
-- políticas de las 17 tablas; esta política solo le da lectura sobre una.
CREATE ROLE sacgeo_auth
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE  ON SCHEMA public TO sacgeo_auth;
GRANT SELECT ON usuarios      TO sacgeo_auth;

COMMENT ON ROLE sacgeo_auth IS
    'Propietario de fn_login_buscar(). NOLOGIN: sus privilegios solo se alcanzan a traves de esa funcion.';

-- Política que solo alcanza a sacgeo_auth. Un rol que no puede conectarse.
CREATE POLICY p_login ON usuarios FOR SELECT TO sacgeo_auth
    USING (true);

-- La función. Todo en ella está acotado a propósito:
--
--   · SECURITY DEFINER  — se ejecuta como sacgeo_auth, que sí puede leer
--                         `usuarios` gracias a p_login.
--   · SET search_path   — obligatorio. Sin fijarlo, un esquema intruso en el
--                         search_path del invocador podría secuestrar la
--                         resolución de `usuarios` y devolver otra tabla.
--   · LANGUAGE sql      — sin SQL dinámico, nada que inyectar.
--   · STABLE            — no escribe.
--   · Cinco columnas    — las que el login necesita y ni una más. NO devuelve
--                         email, ni nombres, ni rol_id: quien la llame no puede
--                         usarla para enumerar el directorio de usuarios.
--   · tenant_id NOT NULL — las identidades globales (el usuario `sistema`) NO
--                         inician sesión. La regla vive en el motor, no solo
--                         en el backend.
--   · password_hash NOT NULL — sin credencial asignada no hay login.
--   · LIMIT 1           — una fila. uq_usuarios_email ya lo garantiza; el
--                         LIMIT lo deja explícito.
CREATE FUNCTION fn_login_buscar(p_email TEXT)
RETURNS TABLE (
    id            INTEGER,
    public_id     UUID,
    tenant_id     INTEGER,
    activo        BOOLEAN,
    password_hash VARCHAR
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $login$
    SELECT u.id, u.public_id, u.tenant_id, u.activo, u.password_hash
      FROM usuarios u
     WHERE lower(u.email) = lower(p_email)
       AND u.tenant_id     IS NOT NULL
       AND u.password_hash IS NOT NULL
     LIMIT 1;
$login$;

ALTER FUNCTION fn_login_buscar(TEXT) OWNER TO sacgeo_auth;

COMMENT ON FUNCTION fn_login_buscar(TEXT) IS
    'Unica via para resolver el login antes de conocer el tenant. Cinco columnas, una fila, sin email ni rol.';

-- EXECUTE solo para la aplicación. PUBLIC no, y ningún otro rol tampoco.
REVOKE EXECUTE ON FUNCTION fn_login_buscar(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION fn_login_buscar(TEXT) TO sacgeo_app;


-- 6.2 · La segunda excepción: resolver la sesión de una petición ya autenticada
--
-- fn_login_buscar() resuelve el ARRANQUE de la sesión. Esta resuelve CADA
-- petición posterior, y tiene el mismo problema de fondo: get_current_user()
-- recibe un token cuyo `sub` es el public_id del usuario, y necesita saber a
-- qué laboratorio pertenece antes de poder fijar el contexto.
--
-- Reordenar el backend no lo resuelve, y conviene decir por qué: no es un
-- problema de secuencia sino de dependencia de datos. El tenant SE DERIVA de
-- la misma consulta que la política bloquea. Meterlo en el JWT está descartado
-- (D-4): un claim firmado no se revoca hasta que expira.
--
-- Comparada con fn_login_buscar(), esta función expone MENOS:
--
--   · tres columnas en vez de cinco;
--   · NO devuelve password_hash — el token ya viene firmado y validado, aquí
--     no hay ninguna contraseña que comprobar;
--   · NO devuelve email, ni rol_id, ni nombres: quien la llame no puede usarla
--     para recorrer el directorio;
--   · el parámetro es UUID, no TEXT. Un valor mal formado ni siquiera llega a
--     ejecutarse, y el espacio de un UUID v4 (122 bits) no se recorre.
--
-- Reutiliza sacgeo_auth y su política p_login. Un segundo rol tendría los
-- mismos atributos y necesitaría la misma política: sería un objeto más que
-- auditar a cambio de ninguna separación real.
--
-- El email SÍ se sigue necesitando (UsuarioAutenticado.email), pero NO se pide
-- aquí: el backend lo lee después, ya dentro de la transacción y protegido por
-- RLS. Una función SECURITY DEFINER para el email sería superficie regalada.
CREATE FUNCTION fn_sesion_resolver_usuario(p_public_id UUID)
RETURNS TABLE (
    id        INTEGER,
    tenant_id INTEGER,
    activo    BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $sesion$
    SELECT u.id, u.tenant_id, u.activo
      FROM usuarios u
     WHERE u.public_id  = p_public_id
       AND u.tenant_id IS NOT NULL      -- las identidades globales no tienen sesión
     LIMIT 1;
$sesion$;

ALTER FUNCTION fn_sesion_resolver_usuario(UUID) OWNER TO sacgeo_auth;

COMMENT ON FUNCTION fn_sesion_resolver_usuario(UUID) IS
    'Resuelve la sesion de una peticion autenticada antes de conocer el tenant. Tres columnas, sin password_hash ni email.';

REVOKE EXECUTE ON FUNCTION fn_sesion_resolver_usuario(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION fn_sesion_resolver_usuario(UUID) TO sacgeo_app;


-- ----------------------------------------------------------------------------
-- 7. vw_auditoria_legible — DEJA DE DEPENDER DE VER AL AUTOR
-- ----------------------------------------------------------------------------
-- Con la política estricta de la sección 5.2, `sistema` es invisible para los
-- tenants. Y como escribió 340 de las 341 filas de auditoría, el INNER JOIN de
-- la vista original la dejaba en CERO filas — medido en 4A-TER: 308 → 0.
--
-- La corrección es no exigir que el autor sea visible: LEFT JOIN y un nombre
-- por defecto. La auditoría conserva su contenido íntegro y el actor aparece
-- como "(identidad del producto)" cuando la política no permite verlo.
--
-- Esto NO reexpone al usuario sistema: la vista no devuelve su email, su rol
-- ni su hash. Solo deja de perder las filas que él escribió.
--
-- El resto de columnas y la semántica no cambian respecto de 0003.
DROP VIEW vw_auditoria_legible;
CREATE VIEW vw_auditoria_legible WITH (security_invoker = true) AS
SELECT a.tenant_id,
       a.id, a.registrado_en, a.tabla, a.registro_id, a.accion,
       COALESCE(u.nombres || ' ' || u.apellidos,
                '(identidad del producto)')     AS usuario,
       COALESCE(r.codigo, '-')::VARCHAR(20)     AS rol,
       a.ip_origen,
       array_to_string(a.campos_cambiados, ', ') AS campos,
       a.datos_anteriores, a.datos_nuevos
  FROM auditoria a
  LEFT JOIN usuarios u ON u.id = a.usuario_id
  LEFT JOIN roles    r ON r.id = u.rol_id;

COMMENT ON VIEW vw_auditoria_legible IS
    'ATENCION: la columna `rol` muestra el rol ACTUAL del usuario, no el que tenia cuando ocurrio el hecho. Si sus roles cambian, esta vista reescribe el pasado. Se corrige en 0006 con un snapshot de roles; hasta entonces, no construir encima de esa columna.';

GRANT SELECT ON vw_auditoria_legible TO sacgeo_app;


-- ----------------------------------------------------------------------------
-- 8. VALIDACIÓN INTERNA — abortar si algo no quedó como debía
-- ----------------------------------------------------------------------------
DO $validacion$
DECLARE
    v_n INT;
    v_det TEXT;
BEGIN
    -- 6.1 · El rol no puede saltarse RLS.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='sacgeo_app'
                AND (rolsuper OR rolbypassrls OR rolcreatedb
                     OR rolcreaterole OR rolreplication)) THEN
        RAISE EXCEPTION 'sacgeo_app quedó con atributos inseguros.'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 6.2 · Y no debe ser propietario de ninguna tabla.
    SELECT count(*) INTO v_n FROM pg_class
     WHERE relkind='r' AND relnamespace='public'::regnamespace
       AND pg_get_userbyid(relowner) = 'sacgeo_app';
    IF v_n > 0 THEN
        RAISE EXCEPTION 'sacgeo_app es propietario de % tablas; ignoraría sus políticas.', v_n
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 6.3 · Las 17 tablas con RLS habilitada Y forzada.
    SELECT count(*) INTO v_n FROM pg_class
     WHERE relnamespace='public'::regnamespace AND relrowsecurity AND relforcerowsecurity;
    IF v_n <> 17 THEN
        RAISE EXCEPTION 'Se esperaban 17 tablas con RLS forzada, hay %.', v_n
            USING ERRCODE = 'check_violation';
    END IF;

    -- 6.4 · Ninguna tabla con ENABLE pero sin FORCE: sería el fallo silencioso.
    SELECT string_agg(relname, ', ') INTO v_det FROM pg_class
     WHERE relnamespace='public'::regnamespace AND relrowsecurity AND NOT relforcerowsecurity;
    IF v_det IS NOT NULL THEN
        RAISE EXCEPTION 'Tablas con RLS habilitada pero SIN FORCE: %', v_det
            USING ERRCODE = 'check_violation';
    END IF;

    -- 6.5 · Toda política debe tener USING y WITH CHECK. Una política sin
    --       WITH CHECK deja pasar escrituras a otro tenant sin hacer ruido.
    -- p_login se excluye: es FOR SELECT, y una política de solo lectura no
    -- tiene WITH CHECK porque no hay nada que escribir que comprobar.
    SELECT string_agg(c.relname || '.' || p.polname, ', ') INTO v_det
      FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
     WHERE c.relnamespace='public'::regnamespace
       AND p.polname <> 'p_login'
       AND (p.polqual IS NULL OR p.polwithcheck IS NULL);
    IF v_det IS NOT NULL THEN
        RAISE EXCEPTION 'Políticas sin USING o sin WITH CHECK: %', v_det
            USING ERRCODE = 'check_violation';
    END IF;

    -- 6.6 · 18 políticas: una por cada una de las 17 tablas protegidas, más
    --       p_login sobre usuarios para el rol propietario de la función.
    SELECT count(*) INTO v_n FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
     WHERE c.relnamespace='public'::regnamespace;
    IF v_n <> 18 THEN
        RAISE EXCEPTION 'Se esperaban 18 políticas, hay %.', v_n
            USING ERRCODE = 'check_violation';
    END IF;

    -- 6.7 · Las 8 vistas deben conservar security_invoker. Sin él, una vista se
    --       ejecuta con los privilegios de su DUEÑO y se convierte en un túnel
    --       que atraviesa todo el aislamiento.
    SELECT count(*) INTO v_n FROM pg_class c
     WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
       AND COALESCE((SELECT option_value::bool FROM pg_options_to_table(c.reloptions)
                      WHERE option_name='security_invoker'), false);
    IF v_n <> 8 THEN
        RAISE EXCEPTION 'Se esperaban 8 vistas con security_invoker, hay %.', v_n
            USING ERRCODE = 'check_violation';
    END IF;

    -- 6.8 · sacgeo_app no debe poder purgar la auditoría.
    IF has_function_privilege('sacgeo_app', 'fn_purgar_auditoria(date,integer)', 'EXECUTE') THEN
        RAISE EXCEPTION 'sacgeo_app conserva EXECUTE sobre fn_purgar_auditoria.'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 6.9 · Ni modificar la auditoría.
    IF has_table_privilege('sacgeo_app', 'auditoria', 'UPDATE')
       OR has_table_privilege('sacgeo_app', 'auditoria', 'DELETE') THEN
        RAISE EXCEPTION 'sacgeo_app puede modificar o borrar auditoria.'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 6.10 · Ni escribir en las tablas globales.
    IF has_table_privilege('sacgeo_app', 'tenants', 'INSERT')
       OR has_table_privilege('sacgeo_app', 'roles', 'UPDATE')
       OR has_table_privilege('sacgeo_app', 'campos_sensibles', 'INSERT') THEN
        RAISE EXCEPTION 'sacgeo_app tiene escritura sobre tablas globales.'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 6.11 · sacgeo_auth existe y es inofensivo por sí solo.
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='sacgeo_auth') THEN
        RAISE EXCEPTION 'sacgeo_auth no se creó.' USING ERRCODE='undefined_object';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='sacgeo_auth'
                AND (rolcanlogin OR rolsuper OR rolbypassrls OR rolcreatedb
                     OR rolcreaterole OR rolreplication)) THEN
        RAISE EXCEPTION 'sacgeo_auth quedó con atributos inseguros. Debe ser NOLOGIN y sin privilegios.'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 6.12 · Y no debe ser propietario de ninguna tabla: solo de la función.
    SELECT count(*) INTO v_n FROM pg_class
     WHERE relkind='r' AND relnamespace='public'::regnamespace
       AND pg_get_userbyid(relowner) = 'sacgeo_auth';
    IF v_n > 0 THEN
        RAISE EXCEPTION 'sacgeo_auth es propietario de % tablas.', v_n
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 6.13 · La función existe, es SECURITY DEFINER, tiene search_path fijado
    --        y pertenece a sacgeo_auth. Las cuatro cosas o ninguna: si es
    --        SECURITY DEFINER sin search_path, es un vector de secuestro; y si
    --        pertenece a un superusuario, se ejecuta como superusuario.
    IF to_regprocedure('public.fn_login_buscar(text)') IS NULL THEN
        RAISE EXCEPTION 'fn_login_buscar(text) no se creó.' USING ERRCODE='undefined_function';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.fn_login_buscar(text)'::regprocedure
                    AND prosecdef) THEN
        RAISE EXCEPTION 'fn_login_buscar no es SECURITY DEFINER.' USING ERRCODE='check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.fn_login_buscar(text)'::regprocedure
                    AND proconfig @> ARRAY['search_path=public, pg_temp']) THEN
        RAISE EXCEPTION 'fn_login_buscar no tiene search_path fijado.' USING ERRCODE='check_violation';
    END IF;
    IF (SELECT pg_get_userbyid(proowner) FROM pg_proc
         WHERE oid='public.fn_login_buscar(text)'::regprocedure) <> 'sacgeo_auth' THEN
        RAISE EXCEPTION 'fn_login_buscar no pertenece a sacgeo_auth.' USING ERRCODE='insufficient_privilege';
    END IF;

    -- 6.14 · EXECUTE: para sacgeo_app sí, para PUBLIC no.
    IF has_function_privilege('public', 'public.fn_login_buscar(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'fn_login_buscar es ejecutable por PUBLIC.' USING ERRCODE='insufficient_privilege';
    END IF;
    IF NOT has_function_privilege('sacgeo_app', 'public.fn_login_buscar(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'sacgeo_app no puede ejecutar fn_login_buscar.' USING ERRCODE='insufficient_privilege';
    END IF;

    -- 6.15 · La política de usuarios debe ser ESTRICTA. Si alguien reintrodujo
    --        el "tenant_id IS NULL OR", el usuario sistema vuelve a quedar
    --        expuesto a todos los tenants.
    SELECT pg_get_expr(p.polqual, p.polrelid) INTO v_det
      FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
     WHERE c.relname='usuarios' AND p.polname='p_tenant';
    IF v_det IS NULL OR v_det ILIKE '%IS NULL%' THEN
        RAISE EXCEPTION 'La política de usuarios NO es estricta: %', COALESCE(v_det,'(ausente)')
            USING ERRCODE = 'check_violation';
    END IF;

    -- 6.16 · auditoria conserva D-6: ambas cláusulas admiten NULL.
    SELECT pg_get_expr(p.polwithcheck, p.polrelid) INTO v_det
      FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
     WHERE c.relname='auditoria' AND p.polname='p_hibrida';
    IF v_det IS NULL OR v_det NOT ILIKE '%IS NULL%' THEN
        RAISE EXCEPTION 'auditoria perdió el WITH CHECK de D-6: %', COALESCE(v_det,'(ausente)')
            USING ERRCODE = 'check_violation';
    END IF;

    -- 6.17 · fn_sesion_resolver_usuario: existe, es SECURITY DEFINER, tiene
    --        search_path fijado y pertenece a sacgeo_auth. Las cuatro juntas:
    --        SECURITY DEFINER sin search_path es un vector de secuestro, y
    --        propiedad de un superusuario la convertiría en una puerta abierta.
    IF to_regprocedure('public.fn_sesion_resolver_usuario(uuid)') IS NULL THEN
        RAISE EXCEPTION 'fn_sesion_resolver_usuario(uuid) no se creó.'
            USING ERRCODE='undefined_function';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc
                    WHERE oid='public.fn_sesion_resolver_usuario(uuid)'::regprocedure
                      AND prosecdef) THEN
        RAISE EXCEPTION 'fn_sesion_resolver_usuario no es SECURITY DEFINER.'
            USING ERRCODE='check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc
                    WHERE oid='public.fn_sesion_resolver_usuario(uuid)'::regprocedure
                      AND proconfig @> ARRAY['search_path=public, pg_temp']) THEN
        RAISE EXCEPTION 'fn_sesion_resolver_usuario no tiene search_path fijado.'
            USING ERRCODE='check_violation';
    END IF;
    IF (SELECT pg_get_userbyid(proowner) FROM pg_proc
         WHERE oid='public.fn_sesion_resolver_usuario(uuid)'::regprocedure) <> 'sacgeo_auth' THEN
        RAISE EXCEPTION 'fn_sesion_resolver_usuario no pertenece a sacgeo_auth.'
            USING ERRCODE='insufficient_privilege';
    END IF;

    -- 6.18 · Retorno EXACTO: id, tenant_id, activo. Ni una columna más.
    --        Es la validación que impide que alguien "solo añada el email" en
    --        una migración futura y reabra la superficie sin darse cuenta.
    SELECT string_agg(nombre, ', ' ORDER BY orden) INTO v_det
      FROM (SELECT unnest(p.proargnames) AS nombre,
                   generate_subscripts(p.proargnames, 1) AS orden,
                   unnest(p.proargmodes) AS modo
              FROM pg_proc p
             WHERE p.oid='public.fn_sesion_resolver_usuario(uuid)'::regprocedure) x
     WHERE modo = 't';
    IF v_det IS DISTINCT FROM 'id, tenant_id, activo' THEN
        RAISE EXCEPTION 'fn_sesion_resolver_usuario devuelve columnas inesperadas: %',
            COALESCE(v_det, '(ninguna)') USING ERRCODE='check_violation';
    END IF;

    -- 6.19 · Ni password_hash, ni email, ni rol_id: ni en el retorno ni en el
    --        cuerpo. Se comprueba el texto de la función porque una columna
    --        puede filtrarse por un alias.
    SELECT prosrc INTO v_det FROM pg_proc
     WHERE oid='public.fn_sesion_resolver_usuario(uuid)'::regprocedure;
    IF v_det ILIKE '%password_hash%' OR v_det ILIKE '%email%' OR v_det ILIKE '%rol_id%' THEN
        RAISE EXCEPTION 'fn_sesion_resolver_usuario menciona columnas sensibles en su cuerpo.'
            USING ERRCODE='check_violation';
    END IF;

    -- 6.20 · Excluye las identidades globales. Sin este filtro, el usuario
    --        `sistema` tendría sesión.
    IF v_det NOT ILIKE '%tenant_id is not null%' THEN
        RAISE EXCEPTION 'fn_sesion_resolver_usuario no filtra tenant_id IS NOT NULL.'
            USING ERRCODE='check_violation';
    END IF;

    -- 6.21 · EXECUTE: sacgeo_app sí, PUBLIC no.
    IF has_function_privilege('public', 'public.fn_sesion_resolver_usuario(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'fn_sesion_resolver_usuario es ejecutable por PUBLIC.'
            USING ERRCODE='insufficient_privilege';
    END IF;
    IF NOT has_function_privilege('sacgeo_app', 'public.fn_sesion_resolver_usuario(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'sacgeo_app no puede ejecutar fn_sesion_resolver_usuario.'
            USING ERRCODE='insufficient_privilege';
    END IF;

    RAISE NOTICE '0004: 21 validaciones internas superadas.';
END
$validacion$;


INSERT INTO schema_migrations (version, nombre, nota) VALUES
    ('0004', 'RLS + rol de aplicación sacgeo_app',
     'Aislamiento impuesto por el motor. El login requiere adaptación del backend: ver cabecera.');

COMMIT;


-- ============================================================================
-- DESPUÉS DE APLICAR
-- ============================================================================
--   1. Fijar la contraseña, de forma interactiva y fuera de todo archivo:
--          psql -U <admin> -d sacgeo_dev -c '\password sacgeo_app'
--
--   2. Apuntar DATABASE_URL del backend a sacgeo_app y poner
--      REQUIRE_RLS_SAFE_ROLE=true: a partir de ahí, arrancar con un rol capaz
--      de saltarse RLS debe IMPEDIR el arranque, no solo advertirlo.
--
--   3. Ejecutar 97_aislamiento.sql CON EL ROL sacgeo_app. Con el rol
--      administrativo los 7 grupos de RLS seguirán saliendo SKIP, y la propia
--      suite lo dirá: es superusuario y propietario, así que probar RLS con él
--      no demuestra nada.
--
--   4. Resolver la limitación del login (cabecera) antes de dar por buena la
--      fase 4B.
-- ============================================================================
