-- ============================================================================
-- GTQC / SAC-GEO — MIGRACIÓN 0006
-- El autor de una fila de auditoría no se puede falsificar (hallazgo H-06)
-- ============================================================================
--
-- ⚠ MIGRACIÓN PREPARADA. NO EJECUTADA. Lea esta cabecera entera antes.
--
-- Una sola función y un solo trigger. Nada de datos, ningún privilegio nuevo,
-- ninguna tabla. Se revierte con un DROP TRIGGER.
--
-- ----------------------------------------------------------------------------
-- POR QUÉ ESTA MIGRACIÓN VA SOLA, Y POR QUÉ ES LA 0006
-- ----------------------------------------------------------------------------
--
-- La auditoría de la fase PRE-API propuso que 0006 fuera el RBAC. Se cambia, y
-- el motivo es de gestión del riesgo, no de gusto:
--
--   · H-06 es DOS objetos y cero filas modificadas. Su vuelta atrás es
--     `DROP TRIGGER b_auditoria_autor ON auditoria` y se acabó.
--   · El RBAC son tres tablas, un rol nuevo, semillas y un trigger de validación
--     de scope. Su vuelta atrás es un restore.
--   · No hay dependencia en ninguna de las dos direcciones: H-06 no necesita
--     permisos y el RBAC no necesita esta guarda.
--
-- Juntarlas obligaría a revertir la protección de la auditoría por un fallo en
-- el catálogo de permisos. Separarlas cuesta una migración más y permite
-- certificar cada una por su cuenta.
--
-- La numeración del plan PRE-API queda desplazada:
--     0006 autor de auditoría (esta)   0007 RBAC        0008 sesiones
--     0009 eventos de seguridad        0010 flujo de aprobación
--
-- ============================================================================
-- EL PROBLEMA, REPRODUCIDO
-- ============================================================================
--
-- Conectado como `sacgeo_app`, con el contexto del tenant 1 y del usuario 1:
--
--     INSERT INTO auditoria (tenant_id, tabla, registro_id, accion, usuario_id,
--                            datos_anteriores, datos_nuevos)
--     VALUES (1, 'cotizaciones', 1, 'UPDATE', 2, '{"a":1}', '{"a":2}');
--     -- INSERT 0 1   ← la fila queda a nombre del usuario 2
--
-- `b_auditoria_sello` (0005) comprueba la coherencia del TENANT. No dice nada
-- del autor. `trg_append_only` impide reescribir y borrar, pero no impide
-- AÑADIR una fila falsa.
--
-- MODELO_AMENAZAS.md §1 identifica `auditoria` como el activo crítico del
-- producto: "si es alterable, todo lo demás pierde valor probatorio". Una fila
-- inventada a nombre de otra persona es repudiación en las dos direcciones —
-- sirve para encubrirse y para incriminar— y, siendo append-only, no se puede
-- retirar después.
--
-- ============================================================================
-- LA REGLA
-- ============================================================================
--
--     NEW.usuario_id = fn_app_usuario()
--
-- El autor de una fila de auditoría es quien opera la sesión. No es un dato que
-- el que inserta pueda elegir.
--
-- `fn_auditar()` ya escribe exactamente `fn_app_usuario()`, así que ninguna
-- auditoría legítima cambia de comportamiento: la regla formaliza lo que la
-- función ya hacía, y se lo impone a todo lo demás.
--
-- ----------------------------------------------------------------------------
-- QUÉ PASA EN CADA CASO LÍMITE (analizado uno a uno)
-- ----------------------------------------------------------------------------
--
-- `app.usuario_id` SIN DEFINIR
--     fn_app_usuario() devuelve 1 (`sistema`) por su COALESCE. La fila queda a
--     nombre de `sistema` y la guarda la acepta. Es el comportamiento vigente y
--     deliberado: a diferencia de fn_app_tenant(), que lanza, aquí el proyecto
--     decidió que un cambio sin autor identificado es un defecto molesto y no
--     una fuga. El control I2 de 99_verificacion.sql cuenta esas filas —hoy 342
--     de 343, todas de la siembra— y debe tender a cero.
--     ► Residuo consciente: quien controle el backend puede seguir LAVANDO la
--       autoría (borrar el contexto y firmar como `sistema`). Lo que ya no
--       puede es INCRIMINAR a una persona concreta, que es el daño grave.
--       Cerrarlo del todo exige quitarle el fallback a fn_app_usuario(), lo que
--       rompería la siembra y las migraciones. No se hace aquí.
--
-- `app.usuario_id` APUNTA A UN USUARIO INEXISTENTE
--     Ya estaba cubierto: `auditoria_usuario_id_fkey` es una FK a usuarios(id).
--     Es DEFERRABLE, así que salta al COMMIT, no en el INSERT. La guarda no
--     cambia nada aquí.
--
-- `app.usuario_id` ES DE OTRO TENANT
--     La igualdad se cumple, así que la guarda la acepta. NO se comprueba la
--     pertenencia, y es a propósito: `usuarios` lleva la política estricta de
--     0004, de modo que desde el tenant 1 el usuario del tenant 2 es invisible
--     — y el usuario `sistema`, con tenant NULL, TAMBIÉN lo es. Un trigger que
--     leyera `usuarios` confundiría "no lo veo" con "no existe" y volvería a
--     caer en la trampa que 0005 corrigió en fn_validar_plantilla_tenant.
--     ► Residuo consciente: quien pueda fijar `app.usuario_id` arbitrariamente
--       ya controla el backend. Pero ahora ese cambio afecta a TODAS las filas
--       de auditoría de la transacción y también a `actualizado_por`, así que
--       deja de ser quirúrgico y se vuelve evidente.
--
-- USUARIO DESACTIVADO
--     No se comprueba. Un usuario desactivado no obtiene sesión
--     (fn_sesion_resolver_usuario devuelve `activo` y el backend rechaza), así
--     que el caso no se alcanza por la vía normal. Comprobarlo aquí exigiría
--     leer `usuarios`, con el mismo problema del caso anterior.
--
-- TENANT NULL / OPERACIÓN GLOBAL
--     Ortogonal. De eso se ocupa `b_auditoria_sello`, que no se toca. Una
--     operación sobre `roles` sigue produciendo tenant NULL y la guarda solo
--     mira el autor.
--
-- USUARIO `sistema`
--     Sigue funcionando en los dos sentidos: como autor real de las siembras
--     (por el fallback) y como autor explícito cuando el contexto lo fija en 1.
--
-- INSERT DIRECTO SOBRE auditoria
--     Es el caso que esta migración cierra.
--
-- UPDATE / DELETE DIRECTOS
--     Ya bloqueados por `trg_append_only` desde 02_triggers.sql. No se tocan.
--
-- ----------------------------------------------------------------------------
-- UN EFECTO QUE HAY QUE CONOCER: fn_purgar_auditoria(p_hasta, p_usuario)
-- ----------------------------------------------------------------------------
--
-- Esa función escribe su propia fila de auditoría con:
--
--     v_usuario := COALESCE(p_usuario, fn_app_usuario())
--
-- A partir de esta migración, pasar un `p_usuario` DISTINTO del usuario de la
-- sesión hará fallar la purga. Es una consecuencia buscada, no un daño
-- colateral: atribuir una purga de auditoría a alguien que no la ejecutó es
-- exactamente la falsificación que se está cerrando. Sigue valiendo pasar NULL
-- (lo normal) o el propio usuario de la sesión.
--
-- Comprobado que no rompe nada: `98_pruebas.sql` solo ejercita el camino de
-- rechazo (`23001`, menos de 365 días) y nunca llega al INSERT; `97` y `99` no
-- la usan; y `sacgeo_app` no puede ejecutarla (0004 le revocó el EXECUTE).
--
-- ============================================================================
-- POR QUÉ UN TRIGGER NUEVO Y NO AMPLIAR fn_auditoria_sello_coherente()
-- ============================================================================
--
-- Son dos invariantes distintos —de quién es el rastro, y a qué laboratorio
-- pertenece— y separarlos tiene un beneficio concreto: revertir 0006 es
-- `DROP TRIGGER b_auditoria_autor`, sin volver a tocar un objeto que creó 0005
-- y que ya está certificado. Si se hubieran fundido, deshacer esto obligaría a
-- reescribir la función de la migración anterior.
--
-- El orden de disparo entre triggers BEFORE del mismo evento es alfabético:
-- `b_auditoria_autor` corre antes que `b_auditoria_sello`. Da igual cuál falle
-- primero —las dos condiciones deben cumplirse— pero conviene que esté escrito.
--
-- ============================================================================
-- LA BASE ES LA ÚLTIMA BARRERA, NO LA ÚNICA
-- ============================================================================
--
-- Esta guarda no sustituye a que el backend jamás acepte `usuario_id` del
-- cliente. Es la red que queda cuando esa regla se incumple por descuido.
--
-- ============================================================================

\set ON_ERROR_STOP on
\echo '*** 0006 es una migración PREPARADA. Lea la cabecera antes de aplicarla. ***'

BEGIN;


-- ============================================================================
-- SECCIÓN 0 · PRECONDICIONES
-- ============================================================================

DO $precondiciones$
DECLARE
    v_n INTEGER;
BEGIN
    -- 0.1 · 0005 aplicada. Esta migración convive con b_auditoria_sello y da
    --       por hecho el estado que aquélla dejó.
    IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0005') THEN
        RAISE EXCEPTION '0005 no está aplicada. 0006 la presupone.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 0.2 · 0006 no aplicada.
    IF EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0006') THEN
        RAISE EXCEPTION '0006 ya está aplicada. No se ejecuta dos veces.'
            USING ERRCODE = 'duplicate_object';
    END IF;

    -- 0.3 · fn_app_usuario() debe seguir siendo la fuente del autor. Si alguien
    --       la cambió, el análisis de casos límite de la cabecera ya no vale.
    IF NOT EXISTS (SELECT 1 FROM pg_proc
                    WHERE proname = 'fn_app_usuario'
                      AND prosrc ILIKE '%current_setting(''app.usuario_id''%') THEN
        RAISE EXCEPTION 'fn_app_usuario() no lee app.usuario_id como se espera.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 0.4 · fn_auditar() debe seguir escribiendo fn_app_usuario() como autor.
    --       Si escribiera otra cosa, esta guarda haría fallar TODA operación.
    IF NOT EXISTS (SELECT 1 FROM pg_proc
                    WHERE proname = 'fn_auditar' AND prosrc ILIKE '%fn_app_usuario()%') THEN
        RAISE EXCEPTION 'fn_auditar() no atribuye el autor con fn_app_usuario(). '
                        'Aplicar 0006 bloquearía toda escritura auditada.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 0.5 · El append-only sigue activo. 0006 cubre el INSERT; el UPDATE y el
    --       DELETE los cubre aquél, y sin él esta migración protegería la mitad.
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid = 'auditoria'::regclass
                      AND tgname = 'trg_append_only' AND tgenabled = 'O') THEN
        RAISE EXCEPTION 'trg_append_only no está activo sobre auditoria.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 0.6 · b_auditoria_sello sigue en pie. No se toca, pero se comprueba:
    --       0006 se diseñó para convivir con él, no para sustituirlo.
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid = 'auditoria'::regclass
                      AND tgname = 'b_auditoria_sello' AND tgenabled = 'O') THEN
        RAISE EXCEPTION 'b_auditoria_sello no está activo. Revise 0005.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 0.7 · Informe previo: cuántas filas existentes NO cumplirían la regla.
    --       0006 solo mira los INSERT futuros y no reescribe historial, pero
    --       este número dice si el pasado es coherente. No aborta: la auditoría
    --       es append-only y un dato histórico no se corrige a posteriori.
    SELECT count(*) INTO v_n FROM auditoria WHERE usuario_id IS NULL;
    RAISE NOTICE '0006: filas de auditoría sin autor (histórico): %', v_n;
    SELECT count(*) INTO v_n FROM auditoria;
    RAISE NOTICE '0006: filas de auditoría totales, que NO se tocan: %', v_n;
END
$precondiciones$;


-- ============================================================================
-- SECCIÓN 1 · LA GUARDA
-- ============================================================================
-- SECURITY INVOKER, como todos los triggers del proyecto. No hace falta leer
-- nada que el invocante no pueda leer: compara dos enteros.

CREATE OR REPLACE FUNCTION fn_auditoria_autor_coherente() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.usuario_id IS DISTINCT FROM fn_app_usuario() THEN
        RAISE EXCEPTION
            'La auditoría no puede atribuirse a un usuario distinto del que opera '
            'la sesión (se intentó %, la sesión es %)',
            NEW.usuario_id, fn_app_usuario()
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_auditoria_autor_coherente() IS
  'El autor de una fila de auditoría es quien opera la sesión, no quien inserta '
  'la fila. Cierra H-06: sacgeo_app tiene INSERT directo sobre auditoria y podía '
  'atribuir un rastro a otra persona. Ver 0006.';

-- El mensaje incluye los dos identificadores a propósito: este error nunca
-- llega al cliente —errors.py convierte 42501 en un 500 con una referencia de
-- correlación— y va al log, donde un id concreto es la diferencia entre
-- diagnosticar en un minuto o en una tarde.

DROP TRIGGER IF EXISTS b_auditoria_autor ON auditoria;
CREATE TRIGGER b_auditoria_autor BEFORE INSERT ON auditoria
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_autor_coherente();


-- ============================================================================
-- SECCIÓN 2 · VALIDACIONES INTERNAS
-- ============================================================================
-- No comprueban que el SQL se haya ejecutado. Comprueban el resultado de
-- seguridad, provocando de verdad los intentos que deben fallar.

DO $validar$
DECLARE
    v_ok      BOOLEAN;
    v_estado  TEXT;
    v_usr     INTEGER;
BEGIN
    -- 2.1 · La función existe, es plpgsql y NO es SECURITY DEFINER.
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
                    WHERE p.proname = 'fn_auditoria_autor_coherente'
                      AND l.lanname = 'plpgsql' AND NOT p.prosecdef) THEN
        RAISE EXCEPTION '2.1 fn_auditoria_autor_coherente ausente o con SECURITY DEFINER.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 2.2 · Sin SQL dinámico.
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_auditoria_autor_coherente'
                 AND prosrc ~* '(^|[^_[:alnum:]])(execute|format|quote_)') THEN
        RAISE EXCEPTION '2.2 La guarda contiene SQL dinámico.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 2.3 · El trigger está activo y es BEFORE INSERT.
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid = 'auditoria'::regclass
                      AND tgname = 'b_auditoria_autor' AND tgenabled = 'O') THEN
        RAISE EXCEPTION '2.3 b_auditoria_autor no quedó activo.'
            USING ERRCODE = 'undefined_object';
    END IF;

    -- 2.4 · Los triggers anteriores siguen en pie. 0006 AÑADE, no sustituye.
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='auditoria'::regclass
                     AND tgname='b_auditoria_sello' AND tgenabled='O')
    OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='auditoria'::regclass
                     AND tgname='trg_append_only' AND tgenabled='O') THEN
        RAISE EXCEPTION '2.4 0006 dejó fuera de servicio un trigger anterior.'
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- ---- Las pruebas de seguridad, de verdad ------------------------------
    -- Se ejecutan dentro de esta transacción, en SAVEPOINT, para no dejar rastro.

    PERFORM set_config('app.usuario_id', '1', TRUE);
    PERFORM set_config('app.tenant_id',  '1', TRUE);

    -- 2.5 · LEGÍTIMA: el autor coincide con la sesión. Debe pasar.
    BEGIN
        INSERT INTO auditoria (tenant_id, tabla, registro_id, accion, usuario_id,
                               datos_anteriores, datos_nuevos)
        VALUES (1, 'cotizaciones', 0, 'UPDATE', 1, '{"v":1}'::jsonb, '{"v":2}'::jsonb);
        v_ok := TRUE;
    EXCEPTION WHEN OTHERS THEN
        v_ok := FALSE; v_estado := SQLSTATE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION '2.5 Una auditoría legítima quedó bloqueada [%]. '
                        'La guarda es demasiado estricta.', v_estado
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 2.6 · FALSIFICACIÓN: atribuirla a otro usuario. Debe fallar con 42501.
    BEGIN
        INSERT INTO auditoria (tenant_id, tabla, registro_id, accion, usuario_id,
                               datos_anteriores, datos_nuevos)
        VALUES (1, 'cotizaciones', 0, 'UPDATE', 2, '{"v":1}'::jsonb, '{"v":2}'::jsonb);
        v_ok := TRUE;
    EXCEPTION WHEN insufficient_privilege THEN
        v_ok := FALSE;
    WHEN OTHERS THEN
        v_ok := FALSE; v_estado := SQLSTATE;
        RAISE EXCEPTION '2.6 La falsificación se bloqueó, pero con el estado % '
                        'en lugar de 42501.', v_estado
            USING ERRCODE = 'invalid_object_definition';
    END;
    IF v_ok THEN
        RAISE EXCEPTION '2.6 SE PUDO FALSIFICAR EL AUTOR DE LA AUDITORÍA. '
                        'H-06 sigue abierto.'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 2.7 · Sin contexto de usuario, el autor debe ser `sistema` y nada más.
    PERFORM set_config('app.usuario_id', '', TRUE);
    SELECT fn_app_usuario() INTO v_usr;
    IF v_usr <> 1 THEN
        RAISE EXCEPTION '2.7 Sin contexto, fn_app_usuario() devolvió % y no 1.', v_usr
            USING ERRCODE = 'invalid_object_definition';
    END IF;
    BEGIN
        INSERT INTO auditoria (tenant_id, tabla, registro_id, accion, usuario_id,
                               datos_anteriores, datos_nuevos)
        VALUES (1, 'cotizaciones', 0, 'UPDATE', 2, '{"v":1}'::jsonb, '{"v":2}'::jsonb);
        v_ok := TRUE;
    EXCEPTION WHEN insufficient_privilege THEN
        v_ok := FALSE;
    END;
    IF v_ok THEN
        RAISE EXCEPTION '2.7 Sin contexto se pudo atribuir la auditoría al usuario 2.'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    PERFORM set_config('app.usuario_id', '1', TRUE);

    -- 2.8 · La auditoría GLOBAL (tenant NULL) sigue funcionando: 0006 no toca
    --       el sello de tenant.
    BEGIN
        INSERT INTO auditoria (tenant_id, tabla, registro_id, accion, usuario_id,
                               datos_anteriores, datos_nuevos)
        VALUES (NULL, 'roles', 0, 'UPDATE', 1, '{"v":1}'::jsonb, '{"v":2}'::jsonb);
        v_ok := TRUE;
    EXCEPTION WHEN OTHERS THEN
        v_ok := FALSE; v_estado := SQLSTATE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION '2.8 La auditoría de una entidad global quedó bloqueada [%].',
                        v_estado
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    -- 2.9 · La vía real: una operación de negocio sigue generando su auditoría.
    --       Es la prueba que de verdad importa, porque es la que se rompería si
    --       la guarda estuviera mal puesta.
    BEGIN
        UPDATE roles SET descripcion = descripcion WHERE codigo = 'admin';
        v_ok := TRUE;
    EXCEPTION WHEN OTHERS THEN
        v_ok := FALSE; v_estado := SQLSTATE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION '2.9 Una operación normal dejó de funcionar [%].', v_estado
            USING ERRCODE = 'invalid_object_definition';
    END IF;

    RAISE NOTICE '0006: 9 validaciones internas superadas (incluidas 5 de seguridad).';
END
$validar$;

-- Las filas de prueba de la sección 2 se deshacen aquí: se insertaron dentro de
-- esta transacción y este ROLLBACK a un punto de guardado no existe, así que se
-- eliminan de la única forma posible en una tabla append-only — no llegando a
-- confirmarse. Se apaga el append-only para retirarlas y se reenciende en la
-- MISMA transacción, igual que hicieron 0003 y 0005.
ALTER TABLE auditoria DISABLE TRIGGER USER;
DELETE FROM auditoria WHERE tabla IN ('cotizaciones','roles') AND registro_id = 0;
ALTER TABLE auditoria ENABLE TRIGGER USER;

DO $limpieza$
DECLARE v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM auditoria WHERE registro_id = 0;
    IF v_n > 0 THEN
        RAISE EXCEPTION 'Quedaron % filas de prueba en auditoria.', v_n
            USING ERRCODE = 'check_violation';
    END IF;
    -- Y los tres triggers encendidos tras el apagado temporal.
    SELECT count(*) INTO v_n FROM pg_trigger
     WHERE tgrelid = 'auditoria'::regclass AND NOT tgisinternal AND tgenabled = 'O';
    IF v_n <> 3 THEN
        RAISE EXCEPTION 'Se esperaban 3 triggers activos sobre auditoria, hay %.', v_n
            USING ERRCODE = 'invalid_object_definition';
    END IF;
    RAISE NOTICE '0006: filas de prueba retiradas, 3 triggers activos.';
END
$limpieza$;


-- ============================================================================
-- SECCIÓN 3 · REGISTRO
-- ============================================================================

INSERT INTO schema_migrations (version, nombre, nota)
VALUES ('0006',
        'El autor de una fila de auditoría no se puede falsificar (H-06)',
        'Trigger b_auditoria_autor: NEW.usuario_id debe ser fn_app_usuario(). '
        'Reversible con DROP TRIGGER. No modifica datos ni privilegios.');

COMMIT;

\echo '*** 0006 aplicada. Ejecute 97 (con sacgeo_app), 98 y 99 antes de darla por buena. ***'
