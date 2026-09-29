-- ============================================================================
-- GTQC / SAC-GEO — PRUEBAS DE AISLAMIENTO ENTRE TENANTS
-- ============================================================================
-- Verifica que dos laboratorios que comparten la misma base no se vean entre
-- ellos. Es el complemento de 98_pruebas.sql: aquélla comprueba que las reglas
-- del negocio se cumplen, ésta comprueba que se cumplen POR SEPARADO.
--
-- Uso:   psql -d <base_desechable> -f 97_aislamiento.sql
--
-- ATENCIÓN: este archivo ESCRIBE. Crea un segundo tenant con su propio
-- catálogo y sus cotizaciones. Ejecutarlo solo sobre una base desechable,
-- nunca sobre una con datos que importen.
--
-- ----------------------------------------------------------------------------
-- PRECONDICIONES
-- ----------------------------------------------------------------------------
--
--   1. La migración 0003 debe estar aplicada.
--      Sin ella no existen `tenants` ni `fn_app_tenant()`. En ese caso el
--      archivo se detiene solo, avisando, sin marcar fallos falsos.
--
--   2. Para el grupo que depende de RLS, además debe estar aplicada 0004 y la
--      sesión debe conectarse con el rol de aplicación. Ver la advertencia.
--
-- ----------------------------------------------------------------------------
-- ADVERTENCIA: EL ROL CON EL QUE SE CONECTA DECIDE SI ESTAS PRUEBAS VALEN
-- ----------------------------------------------------------------------------
--
-- Hay dos formas muy distintas de que un tenant no vea los datos de otro:
--
--   ESTRUCTURAL — lo impiden las FK compuestas, los UNIQUE por tenant y las
--     funciones de caso de uso. Es imposible de saltar, da igual quién
--     consulte. Se puede verificar en cuanto 0003 está aplicada.
--
--   POR RLS — lo impiden las políticas de fila. Solo actúan sobre un rol que
--     NO sea dueño de las tablas y NO tenga BYPASSRLS.
--
-- `sacgeo_dev` es DUEÑO de las tablas. Ejecutar las pruebas de RLS con ese rol
-- NO demuestra nada: sin FORCE ROW LEVEL SECURITY el dueño ignora sus propias
-- políticas, y aunque pasaran, habrían pasado por el camino estructural y no
-- por RLS. Una suite verde ejecutada como sacgeo_dev NO es evidencia de que
-- RLS funcione.
--
-- Por eso las pruebas de RLS se reportan como SKIP —no como PASS— mientras no
-- exista el rol de aplicación de la fase 0004. Un SKIP es trabajo pendiente
-- declarado; un PASS falso es una fuga que nadie va a volver a mirar.
--
-- ============================================================================

\set QUIET on
SET client_min_messages = NOTICE;

CREATE OR REPLACE FUNCTION t_ok(p_cond BOOLEAN, p_msg TEXT) RETURNS VOID AS $$
BEGIN
    IF p_cond THEN RAISE NOTICE 'PASS  %', p_msg;
    ELSE           RAISE WARNING 'FAIL  %', p_msg; END IF;
END; $$ LANGUAGE plpgsql;

-- Prueba que todavía no puede ejecutarse. No es un fallo: es deuda declarada.
CREATE OR REPLACE FUNCTION t_skip(p_msg TEXT, p_razon TEXT) RETURNS VOID AS $$
BEGIN
    RAISE NOTICE 'SKIP  % — %', p_msg, p_razon;
END; $$ LANGUAGE plpgsql;

-- Misma función endurecida que usa 98_pruebas.sql: exige que el bloqueo se
-- produzca por la razón esperada, no por cualquier error.
CREATE OR REPLACE FUNCTION t_bloquea(p_sql TEXT, p_msg TEXT, p_estado TEXT DEFAULT NULL)
RETURNS VOID AS $$
DECLARE
    v_estado TEXT;
    v_err    TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE WARNING 'FAIL  % — la BD lo permitió', p_msg;
        RETURN;
    EXCEPTION WHEN OTHERS THEN
        v_estado := SQLSTATE;
        v_err    := left(replace(SQLERRM, E'\n', ' '), 70);
    END;

    IF v_estado IN ('42883','42P01','42703','42601','42P02','42804','42P18') THEN
        RAISE WARNING 'FAIL  % — PRUEBA ROTA (%): %', p_msg, v_estado, v_err;
        RETURN;
    END IF;

    IF v_estado = '42501' AND (p_estado IS NULL OR p_estado NOT LIKE '%42501%') THEN
        RAISE WARNING 'FAIL  % — sin contexto de tenant; la regla no se ejerció: %',
                      p_msg, v_err;
        RETURN;
    END IF;

    IF p_estado IS NOT NULL
       AND v_estado <> ALL (string_to_array(replace(p_estado, ' ', ''), ',')) THEN
        RAISE WARNING 'FAIL  % — bloqueado por otra razón (esperado %, obtenido %): %',
                      p_msg, p_estado, v_estado, v_err;
        RETURN;
    END IF;

    RAISE NOTICE 'PASS  % — bloqueado [%]: %', p_msg, v_estado, v_err;
END; $$ LANGUAGE plpgsql;


-- ----------------------------------------------------------------------------
-- GUARDA: ¿hay algo que probar?
-- ----------------------------------------------------------------------------
DO $guarda$
BEGIN
    IF to_regclass('public.tenants') IS NULL THEN
        RAISE NOTICE '';
        RAISE NOTICE '============================================================';
        RAISE NOTICE ' 0003 NO esta aplicada en esta base.';
        RAISE NOTICE ' No existe `tenants`, asi que no hay aislamiento que probar.';
        RAISE NOTICE ' Las 18 pruebas quedan SIN EJECUTAR. No son fallos.';
        RAISE NOTICE '============================================================';
        RAISE NOTICE '';
    END IF;
END
$guarda$;


DO $aislamiento$
DECLARE
    -- Capacidades detectadas del entorno
    v_rls_on    BOOLEAN := FALSE;   -- ENABLE ROW LEVEL SECURITY en las tablas
    v_forzada   BOOLEAN := FALSE;   -- FORCE ROW LEVEL SECURITY
    v_bypass    BOOLEAN;            -- el rol actual se salta RLS
    v_dueno     BOOLEAN;            -- el rol actual es dueño de las tablas
    v_rls_vale  BOOLEAN := FALSE;   -- probar RLS con este rol demuestra algo
    v_motivo    TEXT;

    -- Datos de trabajo
    v_t2        INT;
    v_cat2      INT; v_sub2 INT;
    v_emp1      INT; v_emp2 INT;
    v_ens1      INT; v_ens2 INT;
    v_cod2      VARCHAR;
    v_plant_base INT; v_plant_t2 INT;
    v_num1      VARCHAR; v_num2 VARCHAR;
    v_n         INT;
    v_fecha1    DATE; v_fecha2 DATE;
    v_ruc_comun VARCHAR := '20456789012';
    v_email_t1  VARCHAR;             -- email capturado con el contexto del tenant 1
BEGIN
    IF to_regclass('public.tenants') IS NULL THEN RETURN; END IF;

    -- ------------------------------------------------------------------
    -- Detección de capacidades. Esto es lo que decide PASS contra SKIP.
    -- ------------------------------------------------------------------
    SELECT relrowsecurity, relforcerowsecurity, pg_get_userbyid(relowner) = current_user
      INTO v_rls_on, v_forzada, v_dueno
      FROM pg_class WHERE oid = 'public.empresas'::regclass;

    SELECT rolbypassrls OR rolsuper INTO v_bypass
      FROM pg_roles WHERE rolname = current_user;

    v_rls_vale := v_rls_on AND NOT v_bypass AND (NOT v_dueno OR v_forzada);

    v_motivo := CASE
        WHEN NOT v_rls_on THEN 'RLS no esta habilitada; llega con 0004'
        WHEN v_bypass     THEN 'el rol ' || current_user ||
                               ' tiene BYPASSRLS/SUPERUSER: probar RLS con el no demuestra nada'
        WHEN v_dueno AND NOT v_forzada
                          THEN 'el rol ' || current_user ||
                               ' es DUENO de las tablas y falta FORCE ROW LEVEL SECURITY:' ||
                               ' el dueno ignora sus propias politicas'
        ELSE 'no evaluable'
    END;

    RAISE NOTICE '';
    RAISE NOTICE '=== Entorno detectado ====================================';
    RAISE NOTICE '  rol actual ........ %', current_user;
    RAISE NOTICE '  es dueno .......... %', v_dueno;
    RAISE NOTICE '  BYPASSRLS/super ... %', v_bypass;
    RAISE NOTICE '  RLS habilitada .... %   (FORCE: %)', v_rls_on, v_forzada;
    RAISE NOTICE '  pruebas de RLS .... %',
                 CASE WHEN v_rls_vale THEN 'VALIDAS' ELSE 'NO VALIDAS -> SKIP' END;
    IF NOT v_rls_vale THEN
        RAISE NOTICE '  motivo ............ %', v_motivo;
    END IF;
    RAISE NOTICE '';

    -- ==================================================================
    -- PREPARACIÓN: un segundo laboratorio, con su propio catálogo
    -- ==================================================================
    RAISE NOTICE '--- 0. Preparacion del tenant 2 ----------------------------';

    INSERT INTO tenants (slug, razon_social, ruc, zona_horaria)
    VALUES ('lab-andino', 'Laboratorio Andino S.A.C.', '20777888999', 'America/Bogota')
    RETURNING id INTO v_t2;

    PERFORM set_config('app.usuario_id', '1', FALSE);

    -- Tenant 1: un cliente con un RUC que el tenant 2 también usará.
    PERFORM set_config('app.tenant_id', '1', FALSE);
    INSERT INTO empresas (ruc, razon_social, creado_por)
    VALUES (v_ruc_comun, 'Cliente Compartido S.A.C.', 1) RETURNING id INTO v_emp1;
    SELECT id INTO v_plant_base FROM plantillas_cotizacion
     WHERE tenant_id IS NULL AND slug = 'estandar';
    SELECT id INTO v_ens1 FROM ensayos_catalogo
     WHERE codigo = 'SU-02' AND tenant_id = 1;

    -- Tenant 2: su propio catálogo, desde cero.
    PERFORM set_config('app.tenant_id', v_t2::TEXT, FALSE);
    INSERT INTO empresas (ruc, razon_social, creado_por)
    VALUES (v_ruc_comun, 'Mismo RUC, otro laboratorio S.A.C.', 1) RETURNING id INTO v_emp2;

    v_cat2 := fn_crear_categoria('Suelos', 'SU', 'lab', '#b45309', 1);
    SELECT id INTO v_sub2 FROM subcategorias_ensayo
     WHERE categoria_id = v_cat2 AND nombre = 'General';
    v_cod2 := fn_crear_ensayo(v_sub2, 'Contenido de humedad', 'ASTM D2216', 'UND', 15, TRUE, 1);
    SELECT id INTO v_ens2 FROM ensayos_catalogo WHERE codigo = v_cod2 AND tenant_id = v_t2;

    -- ==================================================================
    -- GRUPO A — LECTURA
    -- ==================================================================
    RAISE NOTICE '--- A. Lectura ---------------------------------------------';

    PERFORM set_config('app.tenant_id', '1', FALSE);

    -- 1. El tenant 1 no puede leer filas del tenant 2.
    IF v_rls_vale THEN
        SELECT COUNT(*) INTO v_n FROM empresas WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '1. un SELECT sin WHERE no devuelve empresas de otro tenant');
        SELECT COUNT(*) INTO v_n FROM ensayos_catalogo WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '1. tampoco ensayos de otro tenant');
        SELECT COUNT(*) INTO v_n FROM cotizaciones WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '1. tampoco cotizaciones de otro tenant');
        SELECT COUNT(*) INTO v_n FROM cotizacion_items WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '1. tampoco items, que son tabla hija');
    ELSE
        PERFORM t_skip('1. lectura cruzada de filas ajenas', v_motivo);
    END IF;

    -- 2. Sin app.tenant_id, las operaciones tenant-scoped fallan.
    --    Esto NO depende de RLS: lo impone fn_app_tenant() vía DEFAULT.
    PERFORM set_config('app.tenant_id', '', FALSE);
    PERFORM t_bloquea(
        'INSERT INTO empresas (ruc, razon_social, creado_por)' ||
        ' VALUES (''20111222333'', ''Sin contexto S.A.'', 1)',
        '2. escribir sin app.tenant_id en la sesion', '42501');
    PERFORM t_bloquea('SELECT fn_hoy_lima()',
        '2. fn_hoy_lima() sin app.tenant_id', '42501');
    PERFORM set_config('app.tenant_id', '1', FALSE);

    -- 3. Las 8 vistas no muestran filas de otro tenant.
    IF v_rls_vale THEN
        SELECT COUNT(*) INTO v_n FROM vw_catalogo_disponible   WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '3. vw_catalogo_disponible aislada');
        SELECT COUNT(*) INTO v_n FROM vw_paquete_detalle       WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '3. vw_paquete_detalle aislada');
        SELECT COUNT(*) INTO v_n FROM vw_paquetes_resumen      WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '3. vw_paquetes_resumen aislada');
        SELECT COUNT(*) INTO v_n FROM vw_acreditacion_vigente  WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '3. vw_acreditacion_vigente aislada');
        SELECT COUNT(*) INTO v_n FROM vw_resumen_por_categoria WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '3. vw_resumen_por_categoria aislada');
        SELECT COUNT(*) INTO v_n FROM vw_ensayos_mas_cotizados WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '3. vw_ensayos_mas_cotizados aislada');
        SELECT COUNT(*) INTO v_n FROM vw_auditoria_legible
         WHERE tenant_id IS NOT NULL AND tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '3. vw_auditoria_legible aislada (lo global sigue visible)');
        SELECT COUNT(*) INTO v_n FROM vw_cotizacion_pdf        WHERE tenant_id <> 1;
        PERFORM t_ok(v_n = 0, '3. vw_cotizacion_pdf aislada');
    ELSE
        PERFORM t_skip('3. las 8 vistas no muestran filas ajenas', v_motivo);
    END IF;

    -- ==================================================================
    -- GRUPO B — ESCRITURA (lo impide el WITH CHECK de la política RLS)
    -- ==================================================================
    RAISE NOTICE '--- B. Escritura -------------------------------------------';

    -- 4. INSERT declarando el tenant del vecino.
    IF v_rls_vale THEN
        PERFORM t_bloquea(format(
            'INSERT INTO empresas (tenant_id, ruc, razon_social, creado_por)' ||
            ' VALUES (%s, ''20999000111'', ''Intrusa S.A.'', 1)', v_t2),
            '4. INSERT declarando el tenant del vecino', '42501');
    ELSE
        PERFORM t_skip('4. INSERT con tenant_id ajeno', v_motivo);
    END IF;

    -- 5. UPDATE de una fila ajena. No debe fallar: debe no encontrar nada.
    IF v_rls_vale THEN
        EXECUTE format('UPDATE empresas SET razon_social = ''Secuestrada'' WHERE id = %s', v_emp2);
        GET DIAGNOSTICS v_n = ROW_COUNT;
        PERFORM t_ok(v_n = 0, '5. UPDATE sobre fila del vecino no afecta ninguna fila');
    ELSE
        PERFORM t_skip('5. UPDATE de fila ajena', v_motivo);
    END IF;

    -- ==================================================================
    -- GRUPO C — INTEGRIDAD ESTRUCTURAL (no depende de RLS)
    -- ==================================================================
    -- Éstas valen aunque RLS no exista: las impiden las FK compuestas que
    -- introduce 0003. Son la última línea de defensa, la que sigue en pie
    -- cuando todas las demás fallan.
    RAISE NOTICE '--- C. Integridad estructural ------------------------------';

    PERFORM set_config('app.tenant_id', v_t2::TEXT, FALSE);

    -- 6. Cotización del tenant 2 apuntando a una empresa del tenant 1.
    PERFORM t_bloquea(format(
        'SELECT fn_crear_cotizacion(%s, NULL, NULL, ''Cruzada'', %s,' ||
        ' ''[{"ensayo_id":%s,"cantidad":1}]''::jsonb)',
        v_emp1, v_plant_base, v_ens2),
        '6. cotizacion del tenant 2 con empresa del tenant 1', '23503');

    -- 7. Contacto del tenant 2 colgado de una empresa del tenant 1.
    PERFORM t_bloquea(format(
        'INSERT INTO contactos (empresa_id, nombres, apellidos, creado_por)' ||
        ' VALUES (%s, ''Intruso'', ''Ajeno'', 1)', v_emp1),
        '7. contacto del tenant 2 sobre empresa del tenant 1', '23503');

    -- 8. Paquete de un tenant con componente del otro.
    PERFORM t_bloquea(format(
        'SELECT fn_crear_paquete(%s, ''Paquete cruzado'', ''UND'', 100, FALSE,' ||
        ' ''[{"ensayo_id":%s,"cantidad":1},{"ensayo_id":%s,"cantidad":1}]''::jsonb, 1)',
        v_sub2, v_ens2, v_ens1),
        '8. paquete del tenant 2 con componente del tenant 1', '23503');

    -- ==================================================================
    -- GRUPO D — CORRELATIVOS Y CÓDIGOS (estructural)
    -- ==================================================================
    RAISE NOTICE '--- D. Correlativos y codigos ------------------------------';

    -- 9. Cada tenant numera su propia serie.
    PERFORM set_config('app.tenant_id', '1', FALSE);
    SELECT c.numero INTO v_num1
      FROM fn_crear_cotizacion(v_emp1, NULL, NULL, 'Obra del tenant 1', v_plant_base,
             jsonb_build_array(jsonb_build_object('ensayo_id', v_ens1, 'cantidad', 1))) c;

    PERFORM set_config('app.tenant_id', v_t2::TEXT, FALSE);
    SELECT c.numero INTO v_num2
      FROM fn_crear_cotizacion(v_emp2, NULL, NULL, 'Obra del tenant 2', v_plant_base,
             jsonb_build_array(jsonb_build_object('ensayo_id', v_ens2, 'cantidad', 1))) c;

    PERFORM t_ok(v_num2 LIKE '%-001',
        '9. el tenant 2 arranca su serie en 001 (' || v_num2 || '), no continua la del otro');
    -- "Cada tenant tiene su propio contador" no se puede afirmar contandolos
    -- los dos a la vez: bajo RLS nadie ve los dos, y esa incapacidad es
    -- justamente la propiedad que el resto de la suite comprueba. Se parte en
    -- dos preguntas, y cada una se le hace a quien puede responderla:
    --
    --   · EXISTENCIA — que cada laboratorio tenga el suyo. Se filtra por
    --     tenant_id de forma explicita, asi la cuenta sale igual la mire el rol
    --     de aplicacion o el dueño de las tablas.
    --   · NO VISIBILIDAD — que ninguno vea el del vecino. Solo significa algo
    --     con un rol sujeto a RLS, asi que va dentro de IF v_rls_vale.
    --
    -- El filtro por periodo sigue haciendo falta: un mismo tenant ya tiene una
    -- fila por periodo (98_pruebas crea la serie de 2031 ademas de la del año
    -- corriente).
    PERFORM set_config('app.tenant_id', '1', FALSE);
    SELECT COUNT(*) INTO v_n FROM correlativos
     WHERE ambito = 'cotizacion'
       AND periodo = EXTRACT(YEAR FROM now())::TEXT
       AND tenant_id = 1;
    PERFORM t_ok(v_n = 1, '9. el tenant 1 tiene su propio contador del periodo');

    PERFORM set_config('app.tenant_id', v_t2::TEXT, FALSE);
    SELECT COUNT(*) INTO v_n FROM correlativos
     WHERE ambito = 'cotizacion'
       AND periodo = EXTRACT(YEAR FROM now())::TEXT
       AND tenant_id = v_t2;
    PERFORM t_ok(v_n = 1, '9. el tenant 2 tiene el suyo, no continua el del otro');

    IF v_rls_vale THEN
        -- Contexto del tenant 2: el contador del tenant 1 no existe para el.
        SELECT COUNT(*) INTO v_n FROM correlativos WHERE tenant_id = 1;
        PERFORM t_ok(v_n = 0, '9. el tenant 2 no ve ningun contador del tenant 1');
    ELSE
        PERFORM t_skip('9. el contador del vecino invisible', v_motivo);
    END IF;

    -- 10. Los dos pueden tener SU-01.
    PERFORM t_ok(v_cod2 = 'SU-01',
        '10. el tenant 2 tambien emite SU-01 teniendo el tenant 1 el suyo');
    -- Mismo reparto que en 9: existencia por tenant con filtro explicito,
    -- aislamiento solo donde RLS se aplica.
    PERFORM set_config('app.tenant_id', '1', FALSE);
    SELECT COUNT(*) INTO v_n FROM ensayos_catalogo
     WHERE codigo = 'SU-01' AND tenant_id = 1;
    PERFORM t_ok(v_n = 1, '10. el tenant 1 tiene exactamente un SU-01');

    PERFORM set_config('app.tenant_id', v_t2::TEXT, FALSE);
    SELECT COUNT(*) INTO v_n FROM ensayos_catalogo
     WHERE codigo = 'SU-01' AND tenant_id = v_t2;
    PERFORM t_ok(v_n = 1, '10. el tenant 2 tiene el suyo: conviven dos SU-01');

    IF v_rls_vale THEN
        SELECT COUNT(*) INTO v_n FROM ensayos_catalogo WHERE codigo = 'SU-01';
        PERFORM t_ok(v_n = 1,
            '10. desde el tenant 2 solo es visible UN SU-01, el propio');
    ELSE
        PERFORM t_skip('10. el SU-01 del vecino invisible', v_motivo);
    END IF;

    -- 11. El mismo RUC de cliente en ambos tenants.
    PERFORM set_config('app.tenant_id', '1', FALSE);
    SELECT COUNT(*) INTO v_n FROM empresas
     WHERE ruc = v_ruc_comun AND tenant_id = 1;
    PERFORM t_ok(v_n = 1, '11. el tenant 1 tiene su cliente con RUC ' || v_ruc_comun);

    PERFORM set_config('app.tenant_id', v_t2::TEXT, FALSE);
    SELECT COUNT(*) INTO v_n FROM empresas
     WHERE ruc = v_ruc_comun AND tenant_id = v_t2;
    PERFORM t_ok(v_n = 1,
        '11. el tenant 2 tiene otro cliente con el MISMO RUC: el RUC no es unico global');

    IF v_rls_vale THEN
        SELECT COUNT(*) INTO v_n FROM empresas WHERE ruc = v_ruc_comun;
        PERFORM t_ok(v_n = 1,
            '11. desde el tenant 2 solo es visible UNA empresa con ese RUC, la propia');
    ELSE
        PERFORM t_skip('11. el cliente del vecino invisible', v_motivo);
    END IF;

    -- 12. El email de usuario SÍ sigue siendo único de forma global.
    --     Es deliberado, no un descuido: el login es global. El mismo correo
    --     en dos laboratorios haría ambigua la autenticación.
    --
    --     La version anterior leia el email con un subselect sobre
    --     usuarios WHERE id = 1 — el usuario `sistema`, cuyo tenant_id es NULL.
    --     Bajo la politica estricta de usuarios ese usuario es invisible, y con
    --     razon: el subselect devolvia 0 filas, no se insertaba nada, no habia
    --     UNIQUE que violar y la prueba informaba "la BD lo permitio" sin que la
    --     regla se hubiera ejercido ni una sola vez.
    --
    --     Ahora el email se captura CON EL CONTEXTO DEL TENANT 1, de un usuario
    --     real suyo, y viaja a la comprobacion en una variable de plpgsql:
    --     cruza la frontera en memoria, no en una consulta, que es lo que RLS
    --     no puede impedir ni debe.
    --
    --     Y se inserta en el tenant ACTUAL (el 2), no en otro: declarar un
    --     tenant ajeno haria saltar el WITH CHECK de la politica con 42501
    --     ANTES de que la UNIQUE global pudiera dispararse, y la prueba pasaria
    --     por el motivo equivocado.
    --     El usuario de referencia lo crea la propia prueba. No se busca uno
    --     en la semilla porque full_dump solo siembra `sistema`, que es global
    --     — y una prueba que depende de que alguien haya dejado datos sueltos
    --     en la base pasa o falla segun donde se ejecute.
    PERFORM set_config('app.tenant_id', '1', FALSE);
    v_email_t1 := 'aislamiento.t1@lab.test';
    INSERT INTO usuarios (tenant_id, nombres, apellidos, email, rol_id, creado_por)
    VALUES (1, 'Aislamiento', 'Tenant Uno', v_email_t1,
            (SELECT MIN(id) FROM roles), 1);
    SELECT COUNT(*) INTO v_n FROM usuarios WHERE email = v_email_t1;
    PERFORM t_ok(v_n = 1,
        '12. el usuario del tenant 1 existe y lo ve su propio contexto');

    PERFORM set_config('app.tenant_id', v_t2::TEXT, FALSE);
    PERFORM t_bloquea(format(
        'INSERT INTO usuarios (tenant_id, nombres, apellidos, email, rol_id, creado_por)'
        ' VALUES (%s, ''Duplicado'', ''Ajeno'', %L,'
        ' (SELECT MIN(id) FROM roles), 1)', v_t2, v_email_t1),
        '12. repetir en el tenant 2 el email de un usuario del tenant 1', '23505');

    -- ==================================================================
    -- GRUPO E — TABLA HÍBRIDA: plantillas_cotizacion
    -- ==================================================================
    RAISE NOTICE '--- E. Plantillas base vs. propias -------------------------';

    -- 13. Ambos leen las plantillas base (tenant_id IS NULL).
    PERFORM set_config('app.tenant_id', '1', FALSE);
    SELECT COUNT(*) INTO v_n FROM plantillas_cotizacion WHERE tenant_id IS NULL;
    PERFORM t_ok(v_n = 3, '13. el tenant 1 ve las 3 plantillas base del producto');
    PERFORM set_config('app.tenant_id', v_t2::TEXT, FALSE);
    SELECT COUNT(*) INTO v_n FROM plantillas_cotizacion WHERE tenant_id IS NULL;
    PERFORM t_ok(v_n = 3, '13. el tenant 2 ve las mismas 3 plantillas base');

    -- 14. Ninguno puede modificar una plantilla base.
    --     HOY NO HAY NADA EN EL ESQUEMA QUE LO IMPIDA: plantillas_cotizacion
    --     solo tiene b_tocar, trg_auditar y a_max_activas. Ningún trigger
    --     protege las filas con tenant_id IS NULL. Depende por completo del
    --     WITH CHECK de la política RLS que traiga 0004.
    IF v_rls_vale THEN
        PERFORM t_bloquea(
            'UPDATE plantillas_cotizacion SET nombre = ''Secuestrada'' WHERE tenant_id IS NULL',
            '14. modificar una plantilla base del producto', '42501');
    ELSE
        PERFORM t_skip('14. modificar una plantilla base del producto',
            v_motivo || '; ademas HOY NINGUN TRIGGER LO IMPIDE, depende por entero de RLS');
    END IF;

    -- 15. Una cotización no puede usar la plantilla privada de otro tenant.
    --     Estructural: lo impone el trigger a_validar_plantilla de 0003.
    INSERT INTO plantillas_cotizacion (slug, nombre, terminos_condiciones, activo, creado_por)
    VALUES ('privada_t2', 'Plantilla privada del tenant 2', 'Terminos propios.', FALSE, 1)
    RETURNING id INTO v_plant_t2;

    PERFORM set_config('app.tenant_id', '1', FALSE);
    PERFORM t_bloquea(format(
        'SELECT fn_crear_cotizacion(%s, NULL, NULL, ''Plantilla ajena'', %s,' ||
        ' ''[{"ensayo_id":%s,"cantidad":1}]''::jsonb)',
        v_emp1, v_plant_t2, v_ens1),
        '15. cotizacion del tenant 1 con la plantilla privada del tenant 2', '42501');

    -- ==================================================================
    -- GRUPO F — AUDITORÍA
    -- ==================================================================
    RAISE NOTICE '--- F. Auditoria -------------------------------------------';

    -- 16. La auditoría del tenant 2 no es visible desde el tenant 1.
    IF v_rls_vale THEN
        SELECT COUNT(*) INTO v_n FROM auditoria WHERE tenant_id = v_t2;
        PERFORM t_ok(v_n = 0, '16. el rastro del tenant 2 no se ve desde el tenant 1');
    ELSE
        PERFORM t_skip('16. auditoria del vecino invisible', v_motivo);
    END IF;

    -- 17. Los cambios globales (tenant_id NULL) los ven los dos.
    --     Un rol del producto o una plantilla base no pertenecen a nadie: su
    --     rastro debe ser visible para todos, o cada laboratorio tendría un
    --     hueco inexplicable en su historial ante un auditor ISO 17025.
    IF v_rls_vale THEN
        SELECT COUNT(*) INTO v_n FROM auditoria WHERE tenant_id IS NULL;
        PERFORM t_ok(v_n > 0, '17. los cambios globales si son visibles desde el tenant 1');
    ELSE
        PERFORM t_skip('17. cambios globales visibles para ambos',
            v_motivo || '; depende ademas de que auditoria.tenant_id admita NULL (decision A)');
    END IF;

    -- ==================================================================
    -- GRUPO G — ZONA HORARIA (estructural)
    -- ==================================================================
    RAISE NOTICE '--- G. Zona horaria por tenant -----------------------------';

    -- 18. fn_hoy_lima() resuelve la zona del tenant, no una fija del servidor.
    PERFORM set_config('app.tenant_id', '1', FALSE);
    v_fecha1 := fn_hoy_lima();
    PERFORM set_config('app.tenant_id', v_t2::TEXT, FALSE);
    v_fecha2 := fn_hoy_lima();

    PERFORM t_ok(
        (SELECT zona_horaria FROM tenants WHERE id = 1) <>
        (SELECT zona_horaria FROM tenants WHERE id = v_t2),
        '18. los dos tenants tienen zonas horarias distintas configuradas');
    PERFORM t_ok(
        v_fecha1 = (now() AT TIME ZONE (SELECT zona_horaria FROM tenants WHERE id = 1))::date
        AND v_fecha2 = (now() AT TIME ZONE (SELECT zona_horaria FROM tenants WHERE id = v_t2))::date,
        '18. fn_hoy_lima() usa la zona de cada tenant, no una constante del servidor');

    RAISE NOTICE '--- FIN ----------------------------------------------------';
    RAISE NOTICE '';
    RAISE NOTICE 'Recordatorio: todo SKIP es una fuga NO verificada, no una';
    RAISE NOTICE 'verificada correcta. La suite no esta completa hasta que se';
    RAISE NOTICE 'ejecute con el rol de aplicacion de 0004 sin ningun SKIP.';
END
$aislamiento$;

DROP FUNCTION IF EXISTS t_ok(BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS t_skip(TEXT, TEXT);
DROP FUNCTION IF EXISTS t_bloquea(TEXT, TEXT, TEXT);
