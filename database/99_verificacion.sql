-- ============================================================================
-- GTQC — AUDITORÍA AUTOMÁTICA DE LA BASE  ·  v3.0
-- ============================================================================
-- "El SQL ejecutó sin errores" NO es criterio de aceptación. Este archivo
-- interroga los datos: busca huérfanos, duplicados, importes que no cuadran,
-- snapshots incompletos, historial incoherente, correlativos desalineados y
-- tablas de negocio sin auditoría.
--
-- Uso:   psql -d gtqc_v3 -f 99_verificacion.sql
--
-- Cada fila es un control. `hallazgos` = 0 significa que el control pasó.
-- Los controles marcados INFO no son defectos: son cosas que una persona debe
-- mirar (por ejemplo, un paquete que cuesta más que sus partes).
--
-- ----------------------------------------------------------------------------
-- DISCIPLINA DE TENANT  (desde la migración 0003)
-- ----------------------------------------------------------------------------
-- Este archivo es una auditoría DE LA INSTALACIÓN, no de un laboratorio. Debe
-- ver TODOS los tenants: una fila corrupta del tenant 5 hay que encontrarla
-- aunque el operador "esté" en el tenant 1.
--
-- Por eso **este archivo NO ejecuta SET app.tenant_id**, y no debe hacerlo
-- nunca. Hoy daría igual porque RLS todavía no está activa; en cuanto llegue
-- 0004, fijar un tenant convertiría silenciosamente esta auditoría global en la
-- de un solo laboratorio, y los 36 controles restantes pasarían en verde sin
-- haber mirado el resto de la instalación. Sería un falso negativo perfecto.
--
-- Dos consecuencias de esa decisión, resueltas en el propio SQL:
--
--   · Ningún control puede depender de fn_hoy_lima(), que tras 0003 exige
--     contexto de tenant. Afectaba solo a E2, a través de
--     vw_acreditacion_vigente. E2 pasa a resolver su fecha en línea.
--
--   · Los controles de unicidad (A1-A4) y de correlativos (F1-F2) agrupan
--     además POR TENANT. Tras 0003 la unicidad es por laboratorio: que dos
--     tenants tengan ambos SU-01 o COT-2026-001 es correcto, no un duplicado.
--     Sin ese cambio, el segundo tenant encendería cuatro alarmas críticas
--     falsas y, peor, el control dejaría de detectar el duplicado REAL dentro
--     de un mismo tenant.
--
-- La expresión `to_jsonb(t)->>'tenant_id'` se usa para eso: devuelve el tenant
-- cuando la columna existe y NULL cuando no, así que el mismo archivo funciona
-- antes y después de 0003 sin bifurcaciones.
-- ============================================================================

\pset border 2
\pset title 'AUDITORÍA DE INTEGRIDAD — GTQC v3'

WITH controles AS (

-- ─── A. DUPLICADOS Y UNICIDAD ────────────────────────────────────────────────
SELECT 'CRÍTICO' AS sev, 'A1' AS id, 'Códigos de ensayo duplicados' AS control,
       COUNT(*)::TEXT AS hallazgos, COALESCE(string_agg(codigo, ', '), '—') AS detalle
  FROM (SELECT codigo FROM (SELECT codigo, to_jsonb(e)->>'tenant_id' AS tn
                              FROM ensayos_catalogo e) z
         GROUP BY tn, codigo HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'CRÍTICO', 'A2', 'Números de cotización duplicados',
       COUNT(*)::TEXT, COALESCE(string_agg(numero, ', '), '—')
  FROM (SELECT numero FROM (SELECT numero, to_jsonb(c)->>'tenant_id' AS tn
                              FROM cotizaciones c WHERE numero IS NOT NULL) z
         GROUP BY tn, numero HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'CRÍTICO', 'A3', 'RUC o DNI duplicados',
       COUNT(*)::TEXT, COALESCE(string_agg(doc, ', '), '—')
  FROM (SELECT doc FROM (SELECT ruc AS doc, to_jsonb(e)->>'tenant_id' AS tn
                           FROM empresas e) z
         GROUP BY tn, doc HAVING COUNT(*) > 1
        UNION ALL
        SELECT doc FROM (SELECT dni AS doc, to_jsonb(p)->>'tenant_id' AS tn
                           FROM personas p) z
         GROUP BY tn, doc HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'ALTO', 'A4', 'Prefijos de categoría duplicados',
       COUNT(*)::TEXT, COALESCE(string_agg(prefijo_codigo, ', '), '—')
  FROM (SELECT prefijo_codigo FROM (SELECT prefijo_codigo, to_jsonb(c)->>'tenant_id' AS tn
                                      FROM categorias_ensayo c) z
         GROUP BY tn, prefijo_codigo HAVING COUNT(*) > 1) x

-- ─── B. HUÉRFANOS Y REFERENCIAS INVÁLIDAS ────────────────────────────────────
UNION ALL
SELECT 'CRÍTICO', 'B1', 'Contacto de una cotización que no es de su empresa',
       COUNT(*)::TEXT, COALESCE(string_agg(COALESCE(c.numero,'borrador:'||c.id), ', '), '—')
  FROM cotizaciones c
  JOIN contactos ct ON ct.id = c.contacto_id
 WHERE c.empresa_id IS DISTINCT FROM ct.empresa_id
UNION ALL
SELECT 'CRÍTICO', 'B2', 'Ensayo cuya categoría no es la de su subcategoría',
       COUNT(*)::TEXT, COALESCE(string_agg(ec.codigo, ', '), '—')
  FROM ensayos_catalogo ec
  JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
 WHERE se.categoria_id <> ec.categoria_id
UNION ALL
SELECT 'ALTO', 'B3', 'Cotización sin ítems',
       COUNT(*)::TEXT, COALESCE(string_agg(COALESCE(numero,'borrador:'||id), ', '), '—')
  FROM cotizaciones c
 WHERE NOT EXISTS (SELECT 1 FROM cotizacion_items i WHERE i.cotizacion_id = c.id)
UNION ALL
SELECT 'ALTO', 'B4', 'Ítem cuyo código ya no existe en el catálogo',
       COUNT(*)::TEXT, COALESCE(string_agg(DISTINCT i.codigo_snapshot, ', '), '—')
-- El tenant entra en la comparación: si el ítem del laboratorio A cita un
-- código que A ya borró pero que B sí tiene, el control debe encenderse. Sin
-- esto sería un falso NEGATIVO, que es peor que una falsa alarma.
  FROM cotizacion_items i
 WHERE NOT EXISTS (SELECT 1 FROM ensayos_catalogo e
                    WHERE e.codigo = i.codigo_snapshot
                      AND to_jsonb(e)->>'tenant_id' IS NOT DISTINCT FROM to_jsonb(i)->>'tenant_id')
UNION ALL
SELECT 'MEDIO', 'B5', 'Componente de paquete huérfano de texto y de vínculo',
       COUNT(*)::TEXT, COALESCE(string_agg(id::TEXT, ', '), '—')
  FROM paquete_componentes
 WHERE ensayo_componente_id IS NULL AND btrim(COALESCE(nombre,'')) = ''

-- ─── C. ARITMÉTICA DEL DOCUMENTO ─────────────────────────────────────────────
UNION ALL
SELECT 'CRÍTICO', 'C1', 'Ítem cuyo subtotal no es cantidad x precio',
       COUNT(*)::TEXT, COALESCE(string_agg(id::TEXT, ', '), '—')
  FROM cotizacion_items
 WHERE subtotal <> round(cantidad * precio_unitario, 2)
UNION ALL
SELECT 'CRÍTICO', 'C2', 'Cotización cuyo total no cuadra (subtotal + IGV - descuento)',
       COUNT(*)::TEXT, COALESCE(string_agg(COALESCE(numero,'borrador:'||id), ', '), '—')
  FROM cotizaciones
 WHERE total <> round(subtotal + igv - descuento_monto, 2)
UNION ALL
SELECT 'CRÍTICO', 'C3', 'Cotización cuyo subtotal no es la suma de sus ítems',
       COUNT(*)::TEXT, COALESCE(string_agg(COALESCE(c.numero,'borrador:'||c.id), ', '), '—')
  FROM cotizaciones c
 WHERE c.subtotal <> COALESCE((SELECT SUM(i.subtotal) FROM cotizacion_items i
                                WHERE i.cotizacion_id = c.id), 0)
UNION ALL
SELECT 'ALTO', 'C4', 'Cotización cuyo IGV no corresponde a su tasa',
       COUNT(*)::TEXT, COALESCE(string_agg(COALESCE(numero,'borrador:'||id), ', '), '—')
  FROM cotizaciones
 WHERE igv <> round(subtotal * igv_tasa, 2)

-- ─── D. SNAPSHOTS HISTÓRICOS ─────────────────────────────────────────────────
UNION ALL
SELECT 'CRÍTICO', 'D1', 'Ítem de paquete sin la foto de sus componentes',
       COUNT(*)::TEXT, COALESCE(string_agg(codigo_snapshot, ', '), '—')
  FROM cotizacion_items
 WHERE es_paquete_snapshot
   AND (componentes_snapshot IS NULL OR jsonb_array_length(componentes_snapshot) = 0)
UNION ALL
SELECT 'ALTO', 'D2', 'Ítem individual que arrastra componentes (no debería)',
       COUNT(*)::TEXT, COALESCE(string_agg(codigo_snapshot, ', '), '—')
  FROM cotizacion_items
 WHERE NOT es_paquete_snapshot AND componentes_snapshot IS NOT NULL
UNION ALL
SELECT 'ALTO', 'D3', 'Ítem sin categoría congelada (el dashboard lo perdería)',
       COUNT(*)::TEXT, COALESCE(string_agg(codigo_snapshot, ', '), '—')
  FROM cotizacion_items
 WHERE categoria_id IS NULL OR btrim(categoria_snapshot) = ''

-- ─── E. ACREDITACIÓN (ISO 17025) ─────────────────────────────────────────────
UNION ALL
SELECT 'ALTO', 'E1', 'Ensayo sin ninguna fila de historial de acreditación',
       COUNT(*)::TEXT, COALESCE(string_agg(codigo, ', '), '—')
  FROM ensayos_catalogo ec
 WHERE NOT EXISTS (SELECT 1 FROM ensayo_acreditacion_historial h WHERE h.ensayo_id = ec.id)
UNION ALL
-- E2 resolvía su fecha a través de vw_acreditacion_vigente, que llama a
-- fn_hoy_lima(). Tras 0003 esa función exige contexto de tenant, así que E2
-- abortaba — y como los 37 controles son UN SOLO CTE, se caía el archivo
-- entero: no fallaba un control, no se ejecutaba ninguno.
-- Se resuelve en línea con una fecha independiente del tenant. La diferencia
-- frente a la zona horaria de cada laboratorio es, como mucho, un día en el
-- corte; para una auditoría de integridad eso no cambia ningún veredicto, y a
-- cambio el archivo deja de depender del contexto de sesión.
SELECT 'CRÍTICO', 'E2', 'Estado de acreditación que contradice su historial',
       COUNT(*)::TEXT, COALESCE(string_agg(codigo, ', '), '—')
  FROM (
    SELECT ec.codigo, ec.acreditado,
           (SELECT h.acreditado FROM ensayo_acreditacion_historial h
             WHERE h.ensayo_id = ec.id
               AND h.vigente_desde <= (now() AT TIME ZONE 'America/Lima')::date
             ORDER BY h.vigente_desde DESC, h.id DESC LIMIT 1) AS hist
      FROM ensayos_catalogo ec
  ) x
 WHERE hist IS NOT NULL AND acreditado <> hist

-- ─── F. CORRELATIVOS ─────────────────────────────────────────────────────────
-- F1/F2 se agregan por prefijo y por año, y además POR TENANT. Sin el tenant,
-- tras 0003 el contador del laboratorio A se compararía contra el código máximo
-- del laboratorio B: daría alarmas falsas y dejaría de ver el desfase real
-- dentro de un mismo laboratorio. Esto cierra el punto que el skill
-- /multi-tenant dejaba anotado como pendiente.
UNION ALL
SELECT 'CRÍTICO', 'F1', 'Contador de ensayos por debajo del código ya emitido',
       COUNT(*)::TEXT, COALESCE(string_agg(prefijo, ', '), '—')
  FROM (
    SELECT e.prefijo, e.emitido, COALESCE(c.contador, -1) AS contador
      FROM (SELECT to_jsonb(ec)->>'tenant_id' AS tn, ce.prefijo_codigo AS prefijo,
                   MAX(split_part(ec.codigo,'-',2)::INT) AS emitido
              FROM ensayos_catalogo ec JOIN categorias_ensayo ce ON ce.id = ec.categoria_id
             GROUP BY 1, 2) e
      LEFT JOIN (SELECT to_jsonb(co)->>'tenant_id' AS tn, clave,
                        MAX(ultimo) AS contador
                   FROM correlativos co WHERE ambito = 'ensayo' GROUP BY 1, 2) c
             ON c.clave = e.prefijo AND c.tn IS NOT DISTINCT FROM e.tn
  ) x
 WHERE contador < emitido
UNION ALL
SELECT 'CRÍTICO', 'F2', 'Contador de cotizaciones por debajo del número emitido',
       COUNT(*)::TEXT, COALESCE(string_agg(anio, ', '), '—')
  FROM (
    SELECT e.anio, e.emitido, COALESCE(c.contador, -1) AS contador
      FROM (SELECT to_jsonb(co)->>'tenant_id' AS tn,
                   split_part(numero,'-',2) AS anio,
                   MAX(split_part(numero,'-',3)::INT) AS emitido
              FROM cotizaciones co WHERE numero IS NOT NULL GROUP BY 1, 2) e
      LEFT JOIN (SELECT to_jsonb(cr)->>'tenant_id' AS tn, periodo,
                        MAX(ultimo) AS contador
                   FROM correlativos cr WHERE ambito = 'cotizacion' GROUP BY 1, 2) c
             ON c.periodo = e.anio AND c.tn IS NOT DISTINCT FROM e.tn
  ) x
 WHERE contador < emitido

-- ─── G. CATÁLOGO Y PAQUETES ──────────────────────────────────────────────────
UNION ALL
SELECT 'ALTO', 'G1', 'Categoría activa sin ninguna subcategoría activa (R2)',
       COUNT(*)::TEXT, COALESCE(string_agg(nombre, ', '), '—')
  FROM categorias_ensayo ce
 WHERE ce.activo AND NOT EXISTS (SELECT 1 FROM subcategorias_ensayo se
                                  WHERE se.categoria_id = ce.id AND se.activo)
UNION ALL
SELECT 'ALTO', 'G2', 'Código de ensayo que no respeta el prefijo de su categoría (R4)',
       COUNT(*)::TEXT, COALESCE(string_agg(ec.codigo, ', '), '—')
  FROM ensayos_catalogo ec JOIN categorias_ensayo ce ON ce.id = ec.categoria_id
 WHERE ec.codigo !~ ('^' || ce.prefijo_codigo || '-[0-9]{2,4}$')
UNION ALL
SELECT 'ALTO', 'G3', 'Paquete con menos de 2 componentes (P4)',
       COUNT(*)::TEXT, COALESCE(string_agg(codigo, ', '), '—')
  FROM vw_paquetes_resumen WHERE componentes < 2
UNION ALL
SELECT 'CRÍTICO', 'G4', 'Paquete que contiene otro paquete (P2)',
       COUNT(*)::TEXT, COALESCE(string_agg(p.codigo, ', '), '—')
  FROM paquete_componentes pc
  JOIN ensayos_catalogo p ON p.id = pc.ensayo_id
  JOIN ensayos_catalogo c ON c.id = pc.ensayo_componente_id
 WHERE c.es_paquete
UNION ALL
SELECT 'ALTO', 'G5', 'Componentes que no son de un paquete (P1)',
       COUNT(*)::TEXT, COALESCE(string_agg(e.codigo, ', '), '—')
  FROM paquete_componentes pc JOIN ensayos_catalogo e ON e.id = pc.ensayo_id
 WHERE NOT e.es_paquete
UNION ALL
SELECT 'INFO', 'G6', 'Paquete que cuesta MÁS que sus componentes por separado',
       COUNT(*)::TEXT, COALESCE(string_agg(codigo || ' (' || ahorro_pct || '%)', ', '), '—')
  FROM vw_paquetes_resumen WHERE ahorro_pct IS NOT NULL AND ahorro_pct < 0
UNION ALL
SELECT 'INFO', 'G7', 'Componentes descriptivos pendientes de amarrar al catálogo',
       COUNT(*)::TEXT,
       COALESCE(COUNT(*) || ' de ' || (SELECT COUNT(*) FROM paquete_componentes) || ' componentes', '—')
  FROM paquete_componentes WHERE ensayo_componente_id IS NULL
UNION ALL
SELECT 'ALTO', 'G8', 'Paquete activo con algún componente desactivado',
       COUNT(DISTINCT paquete_codigo)::TEXT, COALESCE(string_agg(DISTINCT paquete_codigo, ', '), '—')
  FROM vw_paquete_detalle WHERE componente_activo IS FALSE

-- ─── H. MÁQUINA DE ESTADOS ───────────────────────────────────────────────────
UNION ALL
SELECT 'CRÍTICO', 'H1', 'Cotización no-borrador sin número emitido',
       COUNT(*)::TEXT, COALESCE(string_agg(id::TEXT, ', '), '—')
  FROM cotizaciones WHERE estado <> 'borrador' AND numero IS NULL
UNION ALL
SELECT 'ALTO', 'H2', 'Cotización sin historial de estados',
       COUNT(*)::TEXT, COALESCE(string_agg(COALESCE(numero,'borrador:'||id), ', '), '—')
  FROM cotizaciones c
 WHERE NOT EXISTS (SELECT 1 FROM cotizacion_historial_estados h WHERE h.cotizacion_id = c.id)
UNION ALL
SELECT 'ALTO', 'H3', 'Último estado del historial distinto del estado actual',
       COUNT(*)::TEXT, COALESCE(string_agg(COALESCE(c.numero,'borrador:'||c.id), ', '), '—')
  FROM cotizaciones c
 WHERE c.estado <> COALESCE((SELECT h.estado FROM cotizacion_historial_estados h
                              WHERE h.cotizacion_id = c.id
                              ORDER BY h.registrado_en DESC, h.id DESC LIMIT 1), c.estado)

-- ─── I. AUDITORÍA Y TRAZABILIDAD ─────────────────────────────────────────────
UNION ALL
SELECT 'ALTO', 'I1', 'Tablas de negocio SIN trigger de auditoría',
       COUNT(*)::TEXT, COALESCE(string_agg(t, ', '), '—')
  FROM (VALUES ('usuarios'),('empresas'),('contactos'),('personas'),
               ('categorias_ensayo'),('subcategorias_ensayo'),('ensayos_catalogo'),
               ('paquete_componentes'),('plantillas_cotizacion'),('cotizaciones'),
               ('cotizacion_items'),('integraciones'),('documentos_externos'),('roles')) AS v(t)
 WHERE NOT EXISTS (SELECT 1 FROM pg_trigger tg
                     JOIN pg_class c ON c.oid = tg.tgrelid
                    WHERE c.relname = v.t AND tg.tgname = 'trg_auditar' AND NOT tg.tgisinternal)
UNION ALL
SELECT 'INFO', 'I2', 'Cambios auditados a nombre del usuario "sistema" (backend sin contexto)',
       COUNT(*)::TEXT, COALESCE(COUNT(*) || ' de ' || (SELECT COUNT(*) FROM auditoria) || ' filas', '—')
  FROM auditoria WHERE usuario_id = 1
UNION ALL
-- Solo se exigen índices en las FK de NAVEGACIÓN. Las columnas de autoría
-- (creado_por, actualizado_por, …) apuntan a `usuarios`, y `usuarios` no se
-- puede eliminar (a_no_delete) ni cambia de id, así que esa verificación de FK
-- nunca se dispara: indexarlas solo encarecería cada escritura. La consulta
-- "qué hizo el usuario X" se responde por auditoria(usuario_id), que sí tiene
-- índice. Por eso están excluidas a propósito y no como olvido.
SELECT 'ALTO', 'I3', 'Claves ajenas de navegación sin índice',
       COUNT(*)::TEXT, COALESCE(string_agg(rel || '.' || col, ', '), '—')
  FROM (
    SELECT c.relname AS rel, a.attname AS col
      FROM pg_constraint k
      JOIN pg_class c ON c.oid = k.conrelid
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = k.conkey[1]
     WHERE k.contype = 'f' AND c.relnamespace = 'public'::regnamespace
       AND a.attname NOT IN ('creado_por','actualizado_por','desactivado_por',
                             'registrado_por','conectado_por','subido_por',
                             -- 'asignado_por' (usuario_roles, 0007) es autoria,
                             -- no navegacion: nadie lista las asignaciones POR
                             -- quien las otorgo. Mismo criterio que las seis
                             -- anteriores.
                             'asignado_por')
       AND NOT EXISTS (SELECT 1 FROM pg_index i
                        WHERE i.indrelid = c.oid AND i.indkey[0] = a.attnum)
  ) x

-- ─── J. SEGURIDAD Y SECRETOS ─────────────────────────────────────────────────
UNION ALL
SELECT 'CRÍTICO', 'J1', 'Posible token real guardado en integraciones.token_ref',
       COUNT(*)::TEXT, COALESCE(string_agg(id::TEXT, ', '), '—')
  FROM integraciones
 WHERE token_ref ~ '^(ey[A-Za-z0-9_-]{10,}|ya29\.|[A-Za-z0-9_-]{60,})$'
UNION ALL
SELECT 'ALTO', 'J2', 'Usuario activo sin rol o con rol inexistente',
       COUNT(*)::TEXT, COALESCE(string_agg(email, ', '), '—')
  FROM usuarios u
 WHERE u.activo AND NOT EXISTS (SELECT 1 FROM roles r WHERE r.id = u.rol_id)
UNION ALL
SELECT 'ALTO', 'J3', 'Baja lógica sin fecha de desactivación',
       COUNT(*)::TEXT, COALESCE(string_agg(codigo, ', '), '—')
  FROM ensayos_catalogo WHERE NOT activo AND desactivado_en IS NULL
)
SELECT sev AS "SEV", id AS "#", control AS "CONTROL",
       hallazgos AS "HALLAZGOS", left(detalle, 80) AS "DETALLE"
  FROM controles
 ORDER BY CASE sev WHEN 'CRÍTICO' THEN 1 WHEN 'ALTO' THEN 2 WHEN 'MEDIO' THEN 3 ELSE 4 END, id;


-- ----------------------------------------------------------------------------
-- CONTROLES QUE SOLO APLICAN DESPUÉS DE 0003
-- ----------------------------------------------------------------------------
-- Van fuera del CTE principal porque interrogan objetos que antes de 0003 no
-- existen (`campos_sensibles`, `tenant_id`). Un CTE estático no puede
-- referenciar una tabla ausente ni siquiera para ignorarla, así que se
-- resuelven con SQL dinámico y se saltan solos cuando 0003 no está aplicada.
DO $post0003$
DECLARE
    v_n INT; v_det TEXT;
BEGIN
    IF to_regclass('public.campos_sensibles') IS NULL THEN
        RAISE NOTICE '';
        RAISE NOTICE 'J4/K1 — SIN EJECUTAR: 0003 no esta aplicada. No son fallos.';
        RAISE NOTICE '';
        RETURN;
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '=== CONTROLES POST-0003 ==================================';

    -- ---- J4 · Columnas de nombre sensible que nadie protegio ----------------
    --
    -- Este control existe porque `campos_sensibles` falla ABIERTO: si manana
    -- alguien agrega usuarios.mfa_secret y olvida registrarla, se auditaria en
    -- claro y nadie se enteraria. J4 convierte ese olvido silencioso en un
    -- hallazgo.
    --
    -- Las excepciones se declaran AQUI, en el archivo, y no en una tabla. Es
    -- deliberado: una excepcion guardada en la base la podria insertar quien
    -- comprometiera la base, y serviria exactamente para ocultar el secreto
    -- que este control busca. En el archivo, anadir una excepcion exige un
    -- cambio de codigo que alguien tiene que revisar.
    --
    -- Cada excepcion lleva su motivo. Si el motivo deja de ser cierto, la
    -- excepcion se retira.
    EXECUTE $q$
        SELECT COUNT(*)::INT, COALESCE(string_agg(t||'.'||c, ', '), '-')
          FROM (
            SELECT col.table_name AS t, col.column_name AS c
              FROM information_schema.columns col
             WHERE col.table_schema = 'public'
               AND (col.column_name ILIKE '%password%' OR col.column_name ILIKE '%token%'
                 OR col.column_name ILIKE '%secret%'   OR col.column_name ILIKE '%hash%'
                 OR col.column_name ILIKE '%clave%'    OR col.column_name ILIKE '%credencial%')
               AND (col.table_name, col.column_name) NOT IN (
                     -- Suma de verificacion de un archivo, no un secreto.
                     -- Redactarla destruiria su unico proposito: comprobar que
                     -- el documento no fue alterado.
                     ('documentos_externos','hash_sha256'),
                     -- Referencia a un vault (vault://...), no el token. Y si
                     -- alguien pusiera ahi un token real, redactarlo lo
                     -- ESCONDERIA del control J1, que es el disenado para
                     -- detectarlo. Protegerla seria contraproducente.
                     ('integraciones','token_ref'),
                     -- La "clave" de un correlativo es su discriminante
                     -- ('SU', 'AG', 'GLOBAL'), no una contrasena. El patron
                     -- %clave% se conserva a proposito: en castellano "clave"
                     -- SI significa contrasena, y una futura columna
                     -- clave_acceso debe encender este control.
                     ('correlativos','clave')
                   )
               AND NOT EXISTS (SELECT 1 FROM campos_sensibles s
                                WHERE s.tabla = col.table_name
                                  AND s.columna = col.column_name)
          ) x
    $q$ INTO v_n, v_det;
    IF v_n = 0 THEN
        RAISE NOTICE '  J4  [ALTO]     Columnas sensibles sin proteger ......... 0';
    ELSE
        RAISE WARNING '  J4  [ALTO]     Columnas sensibles SIN PROTEGER: % -> %', v_n, v_det;
    END IF;

    -- ---- K1 · Filas tenant-scoped sin tenant --------------------------------
    -- Las columnas son NOT NULL, asi que esto solo puede encenderse si una
    -- migracion futura las debilita. Es barato y detecta una regresion grave.
    EXECUTE $q$
        SELECT COUNT(*)::INT, COALESCE(string_agg(tbl||'='||n, ', '), '-') FROM (
          SELECT 'empresas' AS tbl, COUNT(*) AS n FROM empresas WHERE tenant_id IS NULL
          UNION ALL SELECT 'cotizaciones', COUNT(*) FROM cotizaciones WHERE tenant_id IS NULL
          UNION ALL SELECT 'cotizacion_items', COUNT(*) FROM cotizacion_items WHERE tenant_id IS NULL
          UNION ALL SELECT 'ensayos_catalogo', COUNT(*) FROM ensayos_catalogo WHERE tenant_id IS NULL
          UNION ALL SELECT 'correlativos', COUNT(*) FROM correlativos WHERE tenant_id IS NULL
        ) y WHERE n > 0
    $q$ INTO v_n, v_det;
    IF v_n = 0 THEN
        RAISE NOTICE '  K1  [CRITICO]  Filas tenant-scoped sin tenant .......... 0';
    ELSE
        RAISE WARNING '  K1  [CRITICO]  Filas tenant-scoped SIN TENANT: %', v_det;
    END IF;

    -- ---- K2 · Usuarios globales de mas ---------------------------------------
    -- tenant_id NULL en usuarios significa "identidad global". Hoy debe haber
    -- exactamente una: el usuario `sistema`. Mas de una seria una via de
    -- escalada, porque bajo la politica RLS hibrida prevista para 0004 una
    -- identidad global es visible desde TODOS los laboratorios.
    EXECUTE $q$ SELECT COUNT(*)::INT, COALESCE(string_agg(email, ', '), '-')
                  FROM usuarios WHERE tenant_id IS NULL $q$ INTO v_n, v_det;
    IF v_n = 1 THEN
        RAISE NOTICE '  K2  [CRITICO]  Usuarios globales ....................... 1 (%)', v_det;
    ELSE
        RAISE WARNING '  K2  [CRITICO]  Se esperaba 1 usuario global, hay %: %', v_n, v_det;
    END IF;

    RAISE NOTICE '';
END
$post0003$;


-- ----------------------------------------------------------------------------
-- RESUMEN DE CARGA
-- ----------------------------------------------------------------------------
\pset title 'INVENTARIO DE DATOS'
SELECT 'categorias'          AS tabla, COUNT(*) AS filas FROM categorias_ensayo
UNION ALL SELECT 'subcategorias', COUNT(*) FROM subcategorias_ensayo
UNION ALL SELECT 'ensayos (total)', COUNT(*) FROM ensayos_catalogo
UNION ALL SELECT 'ensayos (paquetes)', COUNT(*) FROM ensayos_catalogo WHERE es_paquete
UNION ALL SELECT 'ensayos (acreditados)', COUNT(*) FROM ensayos_catalogo WHERE acreditado
UNION ALL SELECT 'componentes de paquete', COUNT(*) FROM paquete_componentes
UNION ALL SELECT 'componentes amarrados', COUNT(*) FROM paquete_componentes WHERE ensayo_componente_id IS NOT NULL
UNION ALL SELECT 'historial acreditacion', COUNT(*) FROM ensayo_acreditacion_historial
UNION ALL SELECT 'plantillas', COUNT(*) FROM plantillas_cotizacion
UNION ALL SELECT 'roles', COUNT(*) FROM roles
UNION ALL SELECT 'usuarios', COUNT(*) FROM usuarios
UNION ALL SELECT 'empresas', COUNT(*) FROM empresas
UNION ALL SELECT 'contactos', COUNT(*) FROM contactos
UNION ALL SELECT 'personas', COUNT(*) FROM personas
UNION ALL SELECT 'cotizaciones', COUNT(*) FROM cotizaciones
UNION ALL SELECT 'items de cotizacion', COUNT(*) FROM cotizacion_items
UNION ALL SELECT 'filas de auditoria', COUNT(*) FROM auditoria
UNION ALL SELECT 'contadores de correlativo', COUNT(*) FROM correlativos;
