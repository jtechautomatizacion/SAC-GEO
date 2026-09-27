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
-- ============================================================================

\pset border 2
\pset title 'AUDITORÍA DE INTEGRIDAD — GTQC v3'

WITH controles AS (

-- ─── A. DUPLICADOS Y UNICIDAD ────────────────────────────────────────────────
SELECT 'CRÍTICO' AS sev, 'A1' AS id, 'Códigos de ensayo duplicados' AS control,
       COUNT(*)::TEXT AS hallazgos, COALESCE(string_agg(codigo, ', '), '—') AS detalle
  FROM (SELECT codigo FROM ensayos_catalogo GROUP BY codigo HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'CRÍTICO', 'A2', 'Números de cotización duplicados',
       COUNT(*)::TEXT, COALESCE(string_agg(numero, ', '), '—')
  FROM (SELECT numero FROM cotizaciones WHERE numero IS NOT NULL
         GROUP BY numero HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'CRÍTICO', 'A3', 'RUC o DNI duplicados',
       COUNT(*)::TEXT, COALESCE(string_agg(doc, ', '), '—')
  FROM (SELECT ruc AS doc FROM empresas GROUP BY ruc HAVING COUNT(*) > 1
        UNION ALL
        SELECT dni FROM personas GROUP BY dni HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'ALTO', 'A4', 'Prefijos de categoría duplicados',
       COUNT(*)::TEXT, COALESCE(string_agg(prefijo_codigo, ', '), '—')
  FROM (SELECT prefijo_codigo FROM categorias_ensayo
         GROUP BY prefijo_codigo HAVING COUNT(*) > 1) x

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
  FROM cotizacion_items i
 WHERE NOT EXISTS (SELECT 1 FROM ensayos_catalogo e WHERE e.codigo = i.codigo_snapshot)
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
SELECT 'CRÍTICO', 'E2', 'Estado de acreditación que contradice su historial',
       COUNT(*)::TEXT, COALESCE(string_agg(codigo, ', '), '—')
  FROM vw_acreditacion_vigente
 WHERE coherente IS FALSE

-- ─── F. CORRELATIVOS ─────────────────────────────────────────────────────────
-- F1/F2 se agregan por prefijo y por año, no por fila de `correlativos`, para
-- que el control siga funcionando cuando la migración 0003 agregue tenant_id a
-- la PK del contador. Ojo: en ese escenario habrá que re-alcanzar el control
-- POR TENANT (tal como está, detecta un desfase global, no el de un tenant
-- concreto). Está anotado en el checklist del skill /multi-tenant.
UNION ALL
SELECT 'CRÍTICO', 'F1', 'Contador de ensayos por debajo del código ya emitido',
       COUNT(*)::TEXT, COALESCE(string_agg(prefijo, ', '), '—')
  FROM (
    SELECT e.prefijo, e.emitido, COALESCE(c.contador, -1) AS contador
      FROM (SELECT ce.prefijo_codigo AS prefijo,
                   MAX(split_part(ec.codigo,'-',2)::INT) AS emitido
              FROM ensayos_catalogo ec JOIN categorias_ensayo ce ON ce.id = ec.categoria_id
             GROUP BY ce.prefijo_codigo) e
      LEFT JOIN (SELECT clave, MAX(ultimo) AS contador FROM correlativos
                  WHERE ambito = 'ensayo' GROUP BY clave) c ON c.clave = e.prefijo
  ) x
 WHERE contador < emitido
UNION ALL
SELECT 'CRÍTICO', 'F2', 'Contador de cotizaciones por debajo del número emitido',
       COUNT(*)::TEXT, COALESCE(string_agg(anio, ', '), '—')
  FROM (
    SELECT e.anio, e.emitido, COALESCE(c.contador, -1) AS contador
      FROM (SELECT split_part(numero,'-',2) AS anio,
                   MAX(split_part(numero,'-',3)::INT) AS emitido
              FROM cotizaciones WHERE numero IS NOT NULL GROUP BY 1) e
      LEFT JOIN (SELECT periodo, MAX(ultimo) AS contador FROM correlativos
                  WHERE ambito = 'cotizacion' GROUP BY periodo) c ON c.periodo = e.anio
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
                             'registrado_por','conectado_por','subido_por')
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
