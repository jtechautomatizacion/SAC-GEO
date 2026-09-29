-- ============================================================================
-- GTQC / SAC-GEO — MIGRACIÓN 0005
-- Guarda de plantilla bajo RLS (D-1) y sello de tenant en la auditoría (D-2)
-- ============================================================================
--
-- ⚠ MIGRACIÓN PREPARADA. NO EJECUTADA. Lea esta cabecera entera antes.
--
-- Corrige los dos defectos que la certificación de la fase 4B dejó abiertos.
-- No añade funcionalidad, no cambia el modelo de datos y no toca 0004.
--
-- ----------------------------------------------------------------------------
-- POR QUÉ NO SE LLAMA "0005_corregir_rigidez_r2"
-- ----------------------------------------------------------------------------
-- Ese nombre venía propuesto, pero describe otra cosa: R2 es la regla de
-- "toda categoría activa tiene al menos una subcategoría activa", que no
-- interviene aquí. El nombre de una migración es lo único que un compañero lee
-- dentro de un año cuando busca cuándo cambió un comportamiento; si miente,
-- cuesta más que si no existiera.
--
-- ============================================================================
-- D-1 · LA GUARDA DE PLANTILLA DEJÓ DE GUARDAR
-- ============================================================================
--
-- fn_validar_plantilla_tenant() dice hoy:
--
--     SELECT tenant_id INTO v_tp FROM plantillas_cotizacion WHERE id = NEW.plantilla_id;
--     IF v_tp IS NOT NULL AND v_tp <> NEW.tenant_id THEN RAISE ...
--
-- El `IS NOT NULL` existe para dejar pasar las plantillas base del producto,
-- que tienen tenant_id NULL. Antes de 0004 eso era correcto: el único valor
-- que podía salir NULL era el de una plantilla realmente global.
--
-- Con RLS forzada aparece un segundo camino hacia NULL: si la plantilla
-- pertenece a otro laboratorio, la política no la deja ver y el SELECT no
-- devuelve fila, así que v_tp queda NULL. El trigger no distingue
-- "es global" de "no la puedo ver", y deja pasar la referencia cruzada.
--
-- REPRODUCIDO en la fase 4B: el tenant 1 creó COT-2026-003 apuntando a la
-- plantilla 4, privada del tenant 2. No hay fuga de contenido —la fila sigue
-- siendo invisible— pero sí una referencia entre laboratorios y una cotización
-- cuya plantilla no se puede resolver al generar el PDF.
--
-- Es una REGRESIÓN causada por 0004: el trigger funcionaba antes.
--
-- ----------------------------------------------------------------------------
-- ALTERNATIVAS DESCARTADAS
-- ----------------------------------------------------------------------------
--
-- (a) FK COMPUESTA  (tenant_id, plantilla_id) → plantillas_cotizacion(tenant_id, id)
--
--     Sería la solución preferible: estructural, imposible de saltar, sin
--     código. No sirve aquí, y el motivo es concreto: cotizaciones.tenant_id es
--     NOT NULL y las plantillas base tienen tenant_id NULL, así que el par
--     (1, 1) no encontraría a la plantilla base 1 y la FK rechazaría el caso
--     legítimo. MATCH SIMPLE tampoco ayuda: solo omite la comprobación cuando
--     la columna del que REFERENCIA es NULL, y aquí nunca lo es.
--     Una FK no sabe expresar "global O propia".
--
-- (b) COPIAR LAS 3 PLANTILLAS BASE A CADA TENANT y usar entonces la FK
--     compuesta de (a). Funcionaría, pero cambia el modelo de datos: las
--     plantillas del producto dejarían de ser del producto. Rompe la política
--     híbrida de 0004 y las pruebas 13 y 14 de 97, que exigen que los dos
--     laboratorios vean LAS MISMAS 3 y que ninguno pueda modificarlas.
--     Desproporcionado para una corrección.
--
-- (c) CHECK constraint. No puede consultar otra tabla. Descartada de entrada.
--
-- (d) SECURITY DEFINER para que el trigger vea todas las plantillas.
--     Funciona, y era la opción esperada, pero NO HACE FALTA — ver abajo—, y
--     traía coste: un rol nuevo propietario de la función (el dueño actual,
--     sacgeo_dev, solo la ve todo por tener BYPASSRLS, y depender de eso es
--     volver a lo que 0004 vino a quitar), una política nueva sobre
--     plantillas_cotizacion para ese rol, y una función más que ejecuta con
--     privilegios ajenos en el camino de escritura más transitado.
--     Se descarta por innecesaria: añadir superficie de privilegio que no se
--     necesita es el peor intercambio posible.
--
-- ----------------------------------------------------------------------------
-- SOLUCIÓN ADOPTADA: PREGUNTARLE A RLS EN VEZ DE RODEARLO
-- ----------------------------------------------------------------------------
--
-- La política de plantillas_cotizacion para sacgeo_app dice exactamente:
--
--     USING (tenant_id IS NULL OR tenant_id = fn_app_tenant())
--
-- Es decir: una plantilla que el backend PUEDE VER es, por definición, o base
-- del producto o suya. Entonces la pregunta correcta no es "¿de quién es?"
-- sino "¿la veo?". Esa pregunta RLS ya la contesta, y la contesta bien.
--
-- La función pasa a hacer DOS comprobaciones, y las dos hacen falta:
--
--   1. ¿Existe una fila visible?  No → bloquear.
--      Cubre el caso de RLS: plantilla de otro laboratorio, o inexistente.
--      Es la que faltaba.
--
--   2. Si es visible y tiene dueño, ¿es el mismo tenant?  No → bloquear.
--      Es la comprobación original. Sigue siendo necesaria para los roles que
--      NO están sujetos a RLS —el dueño de las tablas ejecutando una migración
--      o una semilla, que ve todas las plantillas— y para un UPDATE que mueva
--      tenant_id.
--
-- Por separado cada una tiene un hueco; juntas cubren todos los roles. No
-- necesita SECURITY DEFINER, ni un rol nuevo, ni una política nueva, ni un
-- privilegio nuevo: funciona CON la política en vez de alrededor de ella.
--
-- ============================================================================
-- D-2 · EL SELLO DE TENANT EN LA AUDITORÍA
-- ============================================================================
--
-- ⚠ CORRECCIÓN DEL DIAGNÓSTICO DE LA FASE 4B.
--
-- El informe de 4B dijo que fn_auditar() sellaba mal la auditoría de las
-- entidades globales. ES FALSO, y conviene dejarlo escrito porque la
-- corrección que se deducía de aquel diagnóstico habría sido destructiva.
--
-- fn_auditar() sella con el tenant DE LA FILA AUDITADA:
--
--     VALUES ((v_ref->>'tenant_id')::INTEGER, ...)
--
-- Una tabla global no tiene esa columna, así que el valor sale NULL. COMPROBADO
-- sobre una base con 0003+0004: con app.tenant_id fijado a 1 a propósito, tocar
-- `roles`, una plantilla base y `campos_sensibles` produjo tres filas de
-- auditoría con tenant_id NULL. El comportamiento vivo es correcto.
--
-- Lo que está mal son DATOS HISTÓRICOS. La propia 0003 hace, en su relleno:
--
--     UPDATE auditoria SET tenant_id = 1;          -- (0003, línea 193)
--
-- un barrido en bloque que metió en el tenant 1 TODAS las filas anteriores,
-- incluidas las que hablaban de entidades globales. Los 4 registros de `roles`
-- que 4B encontró con tenant_id = 1 son ese residuo, no el trigger.
--
-- Por tanto D-2 no se arregla tocando fn_auditar(): se arregla corrigiendo
-- ocho filas, una sola vez.
--
-- ----------------------------------------------------------------------------
-- POR QUÉ EL CRITERIO "SIN tenant_id EN EL PAYLOAD → NULL" ES UNA TRAMPA
-- ----------------------------------------------------------------------------
--
-- La regla que parece natural es:
--
--     UPDATE auditoria SET tenant_id = NULL
--      WHERE (COALESCE(datos_nuevos, datos_anteriores) ->> 'tenant_id') IS NULL;
--
-- Sobre sacgeo_dev eso alcanza a 341 de 343 filas, entre ellas las de
-- `cotizaciones`, `empresas` y `contactos`. El motivo es que esas filas las
-- escribió la fn_auditar() ANTERIOR a 0003, cuando la columna tenant_id todavía
-- no existía: su `to_jsonb(NEW)` no la contiene. La ausencia del campo no dice
-- "esto es global", dice "esto se auditó antes de que existiera el multi-tenant".
--
-- Aplicarla habría marcado como globales casi todos los movimientos de GTQC:
-- visibles para cualquier laboratorio futuro, e invisibles para el propio GTQC
-- por su política tenant. Habría convertido un defecto cosmético en una fuga.
--
-- El criterio correcto es la CLASIFICACIÓN DE LA TABLA, y para las híbridas la
-- fila realmente auditada:
--
--   GLOBAL   (roles, campos_sensibles)        → tenant_id NULL siempre.
--   HÍBRIDA  (plantillas_cotizacion, usuarios)→ NULL solo si esa fila es global.
--   TENANT   (las otras 11)                   → NO SE TOCAN. El relleno de 0003
--                                               fue correcto para ellas: esta
--                                               instalación tiene un solo
--                                               laboratorio y esos datos son
--                                               suyos.
--
-- Alcance medido sobre sacgeo_dev: 8 filas de 343.
--     4 · roles                  (tabla global)
--     3 · plantillas_cotizacion  (las 3 base del producto)
--     1 · usuarios               (el usuario `sistema`)
--
-- ----------------------------------------------------------------------------
-- Y UNA GUARDA, PARA QUE NULL NO SE VUELVA UN ESCONDITE
-- ----------------------------------------------------------------------------
--
-- Con la política híbrida de auditoría, tenant_id NULL significa "lo ven
-- todos". Una fila de auditoría sobre datos de un laboratorio marcada como
-- global sería, a la vez, una fuga y una forma de sacar un movimiento del
-- historial que su dueño revisa.
--
-- Hoy nadie la escribe —fn_auditar() la deriva de la fila— pero sacgeo_app
-- tiene INSERT directo sobre `auditoria`, así que la posibilidad existe.
-- Se cierra con un trigger que compara el sello contra la clasificación de la
-- tabla auditada, deducida del catálogo y no de una lista escrita a mano: una
-- lista se queda vieja el día que alguien añade una tabla.
--
-- ============================================================================
-- REVERSIBILIDAD
-- ============================================================================
--
-- No hay down migration destructiva, a propósito. El paso D-2 reescribe filas
-- de una tabla append-only: deshacerlo con otro UPDATE sería repetir la misma
-- maniobra por segunda vez sobre un historial que debe ser creíble.
--
-- La vuelta atrás es el backup previo, tal como se hizo en 4B:
--     pg_restore sobre base nueva + validación + conmutación.
-- Antes de ejecutar esta migración debe existir un backup lógico VALIDADO POR
-- RESTAURACIÓN, no solo tomado.
--
-- ============================================================================

\set ON_ERROR_STOP on
\echo '*** 0005 es una migración PREPARADA. Lea la cabecera antes de aplicarla. ***'

BEGIN;


-- ============================================================================
-- SECCIÓN 0 · PRECONDICIONES
-- ============================================================================
-- Todas abortan. Una migración que "se adapta" a un estado que no esperaba es
-- una migración que no se sabe qué dejó.

DO $precondiciones$
DECLARE
    v_n INTEGER;
BEGIN
    -- 0.1 · 0004 debe estar aplicada. 0005 corrige defectos que solo existen
    --       con RLS activa; sobre una base sin 0004 no tendría sentido.
    IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0004') THEN
        RAISE EXCEPTION '0004 no está aplicada. 0005 la presupone.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 0.2 · 0005 no debe estar ya aplicada. Es la idempotencia que importa:
    --       no "volver a aplicar sin efecto", sino negarse en redondo. El paso
    --       D-2 no es idempotente por naturaleza —reescribe historial— y una
    --       segunda pasada sobre un estado ya corregido no se puede distinguir
    --       de una pasada sobre un estado corrompido.
    IF EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0005') THEN
        RAISE EXCEPTION '0005 ya está aplicada. No se ejecuta dos veces.'
            USING ERRCODE = 'duplicate_object';
    END IF;

    -- 0.3 · La función y el trigger que se van a sustituir deben existir y ser
    --       los que esperamos. Si alguien ya los tocó a mano, parar.
    IF NOT EXISTS (SELECT 1 FROM pg_proc
                    WHERE proname = 'fn_validar_plantilla_tenant'
                      AND pronamespace = 'public'::regnamespace) THEN
        RAISE EXCEPTION 'fn_validar_plantilla_tenant no existe.'
            USING ERRCODE = 'undefined_function';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname = 'a_validar_plantilla'
                      AND tgrelid = 'cotizaciones'::regclass) THEN
        RAISE EXCEPTION 'El trigger a_validar_plantilla no existe sobre cotizaciones.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 0.4 · Nadie debe haber convertido esa función en SECURITY DEFINER: si lo
    --       fuera, el diagnóstico de D-1 no sería el que esta migración corrige.
    IF EXISTS (SELECT 1 FROM pg_proc
                WHERE proname = 'fn_validar_plantilla_tenant' AND prosecdef) THEN
        RAISE EXCEPTION 'fn_validar_plantilla_tenant ya es SECURITY DEFINER: estado inesperado.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 0.5 · fn_auditar() debe seguir sellando con el tenant DE LA FILA. Si
    --       alguien le puso un COALESCE(..., fn_app_tenant()), el diagnóstico
    --       de D-2 cambia por completo y esta corrección de datos sería errónea.
    IF NOT EXISTS (SELECT 1 FROM pg_proc
                    WHERE proname = 'fn_auditar'
                      AND prosrc LIKE '%v_ref->>''tenant_id''%') THEN
        RAISE EXCEPTION 'fn_auditar() no sella con el tenant de la fila auditada. '
                        'Revise el diagnóstico D-2 antes de continuar.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc
                WHERE proname = 'fn_auditar' AND prosrc ILIKE '%COALESCE%fn_app_tenant%') THEN
        RAISE EXCEPTION 'fn_auditar() usa fn_app_tenant() como respaldo. '
                        'El diagnóstico D-2 de esta migración no aplica.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 0.6 · Informe previo: cuántas filas de auditoría se van a reescribir.
    --       Se imprime ANTES de tocarlas para que quede en el log de ejecución
    --       junto al número que resulte después. Si no coinciden, se ve.
    SELECT count(*) INTO v_n FROM auditoria a
     WHERE a.tenant_id IS NOT NULL
       AND ( a.tabla IN ('roles','campos_sensibles')
          OR EXISTS (SELECT 1 FROM plantillas_cotizacion p
                      WHERE a.tabla = 'plantillas_cotizacion'
                        AND p.id = a.registro_id AND p.tenant_id IS NULL)
          OR EXISTS (SELECT 1 FROM usuarios u
                      WHERE a.tabla = 'usuarios'
                        AND u.id = a.registro_id AND u.tenant_id IS NULL) );
    RAISE NOTICE '0005: filas de auditoría a resellar como globales: %', v_n;

    -- 0.7 · Y cuántas NO se van a tocar, para que el orden de magnitud sea
    --       visible: si algún día este número baja de golpe, alguien amplió el
    --       criterio sin darse cuenta de lo que arrastraba.
    SELECT count(*) INTO v_n FROM auditoria WHERE tenant_id IS NOT NULL;
    RAISE NOTICE '0005: filas de auditoría con tenant, antes de corregir: %', v_n;
END
$precondiciones$;


-- ============================================================================
-- SECCIÓN 1 · D-1 · LA GUARDA DE PLANTILLA
-- ============================================================================
-- SECURITY INVOKER, igual que antes. Se conserva a propósito: es lo que hace
-- que la comprobación 1 vea exactamente lo que ve quien escribe.

CREATE OR REPLACE FUNCTION fn_validar_plantilla_tenant() RETURNS TRIGGER AS $$
DECLARE
    v_visible BOOLEAN;
    v_tp      INTEGER;
BEGIN
    -- Una sola lectura para las dos preguntas: si hay fila visible, y de quién
    -- es. v_visible se queda NULL cuando el SELECT no devuelve nada, que es
    -- justo el caso que antes se confundía con "plantilla global".
    SELECT TRUE, p.tenant_id INTO v_visible, v_tp
      FROM plantillas_cotizacion p
     WHERE p.id = NEW.plantilla_id;

    -- 1 · No la veo. O no existe, o es de otro laboratorio y la política me la
    --     oculta. Los dos casos son un error del que escribe y se responden
    --     igual: decir cuál de los dos es sería confirmar la existencia de una
    --     plantilla ajena a quien la está tanteando.
    IF NOT COALESCE(v_visible, FALSE) THEN
        RAISE EXCEPTION 'La plantilla % no existe o pertenece a otro tenant', NEW.plantilla_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 2 · La veo y tiene dueño: tiene que ser el mío. Esta es la comprobación
    --     original y NO sobra. Para un rol no sujeto a RLS —el dueño de las
    --     tablas aplicando una migración o una semilla— la comprobación 1
    --     siempre pasa, porque lo ve todo; aquí es donde se le para. También
    --     es la que atrapa un UPDATE que mueva tenant_id dejando la plantilla.
    IF v_tp IS NOT NULL AND v_tp <> NEW.tenant_id THEN
        RAISE EXCEPTION 'La plantilla % pertenece a otro tenant', NEW.plantilla_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_validar_plantilla_tenant() IS
  'Una cotización solo usa una plantilla base del producto o una suya. '
  'Comprueba visibilidad (cubre RLS) y pertenencia (cubre los roles que no '
  'están sujetos a RLS). Ninguna de las dos basta por sí sola. Ver 0005 (D-1).';

-- El trigger no se recrea: sigue siendo el mismo, sobre los mismos eventos.
-- CREATE OR REPLACE FUNCTION basta, y recrearlo solo añadiría una ventana en
-- la que la tabla se queda sin guarda.


-- ============================================================================
-- SECCIÓN 2 · D-2 · RESELLADO DE LA AUDITORÍA HISTÓRICA
-- ============================================================================

-- 2.1 · Clasificación de una tabla auditada, deducida del catálogo.
--
-- Del catálogo y no de una lista escrita a mano: el día que alguien añada una
-- tabla, una lista se queda vieja en silencio y el catálogo no.
--
--   GLOBAL  — no tiene columna tenant_id. Su auditoría es de todos.
--   HIBRIDA — la tiene y admite NULL. Se decide fila a fila.
--   TENANT  — la tiene NOT NULL. Su auditoría nunca es global.
CREATE OR REPLACE FUNCTION fn_clasificacion_tabla(p_tabla TEXT) RETURNS TEXT AS $$
    SELECT CASE
             WHEN a.attname IS NULL  THEN 'GLOBAL'
             WHEN a.attnotnull       THEN 'TENANT'
             ELSE                         'HIBRIDA'
           END
      FROM pg_class c
      LEFT JOIN pg_attribute a
             ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND a.attnum > 0
            AND NOT a.attisdropped
     WHERE c.relname = p_tabla
       AND c.relnamespace = 'public'::regnamespace
       AND c.relkind = 'r';
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION fn_clasificacion_tabla(TEXT) IS
  'GLOBAL / HIBRIDA / TENANT según la columna tenant_id de la tabla. '
  'Se deduce del catálogo para que no envejezca. Ver 0005 (D-2).';


-- 2.2 · La corrección de datos.
--
-- auditoria es append-only por trigger. Se apaga el trigger de usuario durante
-- la corrección y se vuelve a encender en la MISMA transacción: si algo falla,
-- el ROLLBACK devuelve las dos cosas a la vez. Es el mismo procedimiento que
-- 0003 usó para su relleno, y está aquí para que se vea, no escondido.
ALTER TABLE auditoria DISABLE TRIGGER USER;

UPDATE auditoria a
   SET tenant_id = NULL
 WHERE a.tenant_id IS NOT NULL
   AND (
         -- Tabla global: su auditoría nunca pertenece a un laboratorio.
         fn_clasificacion_tabla(a.tabla) = 'GLOBAL'

         -- Tabla híbrida: solo si la fila auditada es ella misma global.
         -- Se mira la fila REAL y no el payload, porque las filas anteriores a
         -- 0003 no llevan tenant_id dentro: que falte no significa "global",
         -- significa "se auditó antes del multi-tenant".
      OR EXISTS (SELECT 1 FROM plantillas_cotizacion p
                  WHERE a.tabla = 'plantillas_cotizacion'
                    AND p.id = a.registro_id
                    AND p.tenant_id IS NULL)
      OR EXISTS (SELECT 1 FROM usuarios u
                  WHERE a.tabla = 'usuarios'
                    AND u.id = a.registro_id
                    AND u.tenant_id IS NULL)
       );

ALTER TABLE auditoria ENABLE TRIGGER USER;


-- 2.3 · La guarda: que NULL no se convierta en un escondite.
--
-- Solo mira INSERT. Los UPDATE y DELETE sobre auditoria ya están prohibidos por
-- el trigger append-only, que se acaba de volver a encender.
CREATE OR REPLACE FUNCTION fn_auditoria_sello_coherente() RETURNS TRIGGER AS $$
DECLARE
    v_clase TEXT := fn_clasificacion_tabla(NEW.tabla);
BEGIN
    -- Tabla desconocida (ya no existe, o se auditó algo de fuera del esquema):
    -- no se opina. Bloquear aquí impediría conservar el rastro de una tabla
    -- retirada, que es justo lo que un auditor querría seguir viendo.
    IF v_clase IS NULL THEN
        RETURN NEW;
    END IF;

    IF v_clase = 'TENANT' AND NEW.tenant_id IS NULL THEN
        RAISE EXCEPTION
            'Auditoría de la tabla % sin tenant: % es tenant-scoped y su rastro '
            'no puede marcarse como global', NEW.tabla, NEW.tabla
            USING ERRCODE = 'check_violation';
    END IF;

    IF v_clase = 'GLOBAL' AND NEW.tenant_id IS NOT NULL THEN
        RAISE EXCEPTION
            'Auditoría de la tabla global % sellada con el tenant %: '
            'un cambio global no pertenece a ningún laboratorio',
            NEW.tabla, NEW.tenant_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- HIBRIDA: los dos valores son legítimos y quien decide es fn_auditar(),
    -- que lo toma de la fila. Aquí no hay nada que comprobar.
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_auditoria_sello_coherente() IS
  'Impide que una fila de auditoría se selle con un tenant incoherente con la '
  'clasificación de la tabla auditada. tenant_id NULL significa "lo ven todos": '
  'usarlo sobre datos de un laboratorio sería a la vez una fuga y una forma de '
  'sacar un movimiento de su historial. Ver 0005 (D-2).';

DROP TRIGGER IF EXISTS b_auditoria_sello ON auditoria;
CREATE TRIGGER b_auditoria_sello BEFORE INSERT ON auditoria
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_sello_coherente();


-- ============================================================================
-- SECCIÓN 3 · VALIDACIONES INTERNAS
-- ============================================================================
-- Se ejecutan dentro de la misma transacción. Si alguna falla, no hay COMMIT y
-- la base queda como estaba.

DO $validar$
DECLARE
    v_n   INTEGER;
    v_src TEXT;
BEGIN
    -- ---- D-1 --------------------------------------------------------------

    -- 3.1 · La función nueva está puesta y comprueba la visibilidad.
    SELECT prosrc INTO v_src FROM pg_proc
     WHERE proname = 'fn_validar_plantilla_tenant' AND pronamespace = 'public'::regnamespace;
    IF v_src NOT LIKE '%v_visible%' THEN
        RAISE EXCEPTION '3.1 fn_validar_plantilla_tenant no comprueba la visibilidad.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 3.2 · Y conserva la comprobación de pertenencia. Las dos, no una.
    IF v_src NOT LIKE '%v_tp IS NOT NULL%' THEN
        RAISE EXCEPTION '3.2 fn_validar_plantilla_tenant perdió la comprobación de pertenencia.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 3.3 · Sigue siendo SECURITY INVOKER. No se ha colado un DEFINER.
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_validar_plantilla_tenant' AND prosecdef) THEN
        RAISE EXCEPTION '3.3 fn_validar_plantilla_tenant quedó como SECURITY DEFINER.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 3.4 · Sin SQL dinámico.
    IF v_src ~* '(^|[^_[:alnum:]])(execute|format|quote_)' THEN
        RAISE EXCEPTION '3.4 fn_validar_plantilla_tenant contiene SQL dinámico.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 3.5 · El trigger sigue en su sitio, sobre los mismos eventos.
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname = 'a_validar_plantilla'
                      AND tgrelid = 'cotizaciones'::regclass
                      AND tgenabled <> 'D') THEN
        RAISE EXCEPTION '3.5 a_validar_plantilla no está activo sobre cotizaciones.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 3.6 · No se creó ningún rol nuevo para esto. Es parte del diseño: la
    --       corrección de D-1 no debía ampliar la superficie de privilegio.
    IF EXISTS (SELECT 1 FROM pg_roles
                WHERE rolname LIKE 'sacgeo%'
                  AND rolname NOT IN ('sacgeo_dev','sacgeo_app','sacgeo_auth')) THEN
        RAISE EXCEPTION '3.6 Apareció un rol sacgeo_* inesperado.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- ---- D-2 --------------------------------------------------------------

    -- 3.7 · No queda ninguna auditoría de tabla global sellada con un tenant.
    SELECT count(*) INTO v_n FROM auditoria
     WHERE tenant_id IS NOT NULL AND fn_clasificacion_tabla(tabla) = 'GLOBAL';
    IF v_n > 0 THEN
        RAISE EXCEPTION '3.7 Quedan % filas de auditoría global con tenant.', v_n
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3.8 · Y NINGUNA auditoría tenant-scoped se volvió global. Es la
    --       validación que habría detenido el criterio equivocado descrito en
    --       la cabecera: con él, este número habría sido de cientos.
    SELECT count(*) INTO v_n FROM auditoria
     WHERE tenant_id IS NULL AND fn_clasificacion_tabla(tabla) = 'TENANT';
    IF v_n > 0 THEN
        RAISE EXCEPTION '3.8 % filas de auditoría tenant-scoped quedaron sin tenant. '
                        'La corrección alcanzó a datos que no debía.', v_n
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3.9 · Las híbridas quedaron coherentes con la fila que describen.
    SELECT count(*) INTO v_n
      FROM auditoria a JOIN plantillas_cotizacion p ON p.id = a.registro_id
     WHERE a.tabla = 'plantillas_cotizacion'
       AND (p.tenant_id IS NULL) <> (a.tenant_id IS NULL);
    IF v_n > 0 THEN
        RAISE EXCEPTION '3.9 % filas de auditoría de plantillas no coinciden con su fila.', v_n
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3.10 · El trigger append-only volvió a quedar encendido. Si esto fallara,
    --        la migración habría dejado la auditoría reescribible.
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid = 'auditoria'::regclass
                      AND NOT tgisinternal
                      AND tgname <> 'b_auditoria_sello'
                      AND tgenabled = 'O') THEN
        RAISE EXCEPTION '3.10 El trigger append-only de auditoria no quedó activo.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 3.11 · La guarda de sello existe y está activa.
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname = 'b_auditoria_sello'
                      AND tgrelid = 'auditoria'::regclass
                      AND tgenabled <> 'D') THEN
        RAISE EXCEPTION '3.11 b_auditoria_sello no quedó activo.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 3.12 · La clasificación reconoce las cuatro tablas globales conocidas y
    --        no ha reclasificado ninguna tenant-scoped por accidente.
    IF fn_clasificacion_tabla('roles')                 <> 'GLOBAL'
    OR fn_clasificacion_tabla('campos_sensibles')      <> 'GLOBAL'
    OR fn_clasificacion_tabla('tenants')               <> 'GLOBAL'
    OR fn_clasificacion_tabla('schema_migrations')     <> 'GLOBAL'
    OR fn_clasificacion_tabla('plantillas_cotizacion') <> 'HIBRIDA'
    OR fn_clasificacion_tabla('usuarios')              <> 'HIBRIDA'
    OR fn_clasificacion_tabla('cotizaciones')          <> 'TENANT'
    OR fn_clasificacion_tabla('empresas')              <> 'TENANT' THEN
        RAISE EXCEPTION '3.12 fn_clasificacion_tabla no clasifica como se espera.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 3.13 · El total de filas de auditoría no cambió: esto RESELLA, no borra.
    --        Un historial que pierde filas deja de servir ante un auditor.
    SELECT count(*) INTO v_n FROM auditoria;
    RAISE NOTICE '0005: filas de auditoría tras la corrección: % (ninguna se elimina)', v_n;

    SELECT count(*) INTO v_n FROM auditoria WHERE tenant_id IS NULL;
    RAISE NOTICE '0005: filas de auditoría marcadas como globales: %', v_n;

    -- 3.14 · password_hash sigue sin aparecer en ninguna parte del historial.
    SELECT count(*) INTO v_n FROM auditoria
     WHERE datos_nuevos::text LIKE '%$argon2%' OR datos_anteriores::text LIKE '%$argon2%'
        OR datos_nuevos::text LIKE '%$2b$%'    OR datos_anteriores::text LIKE '%$2b$%';
    IF v_n > 0 THEN
        RAISE EXCEPTION '3.14 % filas de auditoría contienen un hash de contraseña.', v_n
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3.15 · La política de auditoría de 0004 no se ha tocado. Sigue siendo la
    --        que admite NULL en las dos cláusulas.
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname = 'public' AND tablename = 'auditoria'
                      AND qual LIKE '%tenant_id IS NULL%'
                      AND with_check LIKE '%tenant_id IS NULL%') THEN
        RAISE EXCEPTION '3.15 La política de auditoria cambió. 0005 no debe tocarla.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 3.16 · RLS sigue como la dejó 0004: 17 tablas, ENABLE y FORCE.
    SELECT count(*) INTO v_n FROM pg_class
     WHERE relnamespace = 'public'::regnamespace AND relkind = 'r'
       AND relrowsecurity AND relforcerowsecurity;
    IF v_n <> 17 THEN
        RAISE EXCEPTION '3.16 Se esperaban 17 tablas con RLS FORCE, hay %.', v_n
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    RAISE NOTICE '0005: 16 validaciones internas superadas.';
END
$validar$;


-- ============================================================================
-- SECCIÓN 4 · REGISTRO
-- ============================================================================

INSERT INTO schema_migrations (version, nombre, nota)
VALUES ('0005',
        'Guarda de plantilla bajo RLS (D-1) y resellado de auditoría global (D-2)',
        'Corrige los dos defectos abiertos por la certificación de la fase 4B. '
        'D-1 es una regresión de 0004; D-2 es residuo del relleno de 0003.');

COMMIT;

\echo '*** 0005 aplicada. Ejecute 97 (con sacgeo_app), 98 y 99 antes de darla por buena. ***'
