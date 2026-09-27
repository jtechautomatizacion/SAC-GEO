-- ============================================================================
-- GTQC — ÍNDICES Y VISTAS  ·  v3.0   (archivo 4 de 6; tras 02_triggers.sql)
-- ============================================================================
-- Criterio: NO se crea un índice "por si acaso". Cada uno responde a una
-- consulta concreta del sistema, y va anotado con cuál.
--
-- Índices que existían en v2 y aquí NO se repiten, porque eran redundantes:
--   idx_empresas_ruc      → uq_empresas_ruc ya crea el índice
--   idx_personas_dni      → uq_personas_dni ya crea el índice
--   idx_ensayos_codigo    → uq_ensayos_codigo ya crea el índice
--   idx_ensayos_acreditado→ booleano de baja cardinalidad: el planner prefiere
--                           el seq scan; el índice solo costaba escrituras
-- Un UNIQUE constraint YA es un índice. Duplicarlo solo encarece cada INSERT.
--
-- PostgreSQL NO indexa automáticamente las claves ajenas. Por eso sí están
-- todas las FK que se usan para navegar o para borrar en cascada: sin ellas,
-- cada verificación de FK hace un seq scan de la tabla hija.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. CLAVES AJENAS
-- ----------------------------------------------------------------------------
CREATE INDEX idx_usuarios_rol            ON usuarios(rol_id);
CREATE INDEX idx_contactos_empresa       ON contactos(empresa_id);
CREATE INDEX idx_subcategorias_categoria ON subcategorias_ensayo(categoria_id);
CREATE INDEX idx_ensayos_subcategoria    ON ensayos_catalogo(subcategoria_id);
CREATE INDEX idx_ensayos_categoria       ON ensayos_catalogo(categoria_id);
-- paquete_componentes(ensayo_id) ya está cubierto por uq_paquete_componente_orden.
CREATE INDEX idx_componentes_componente  ON paquete_componentes(ensayo_componente_id);
CREATE INDEX idx_cotizaciones_empresa    ON cotizaciones(empresa_id);
CREATE INDEX idx_cotizaciones_persona    ON cotizaciones(persona_id);
CREATE INDEX idx_cotizaciones_contacto   ON cotizaciones(contacto_id);
CREATE INDEX idx_cotizaciones_plantilla  ON cotizaciones(plantilla_id);
CREATE INDEX idx_cotizaciones_creador    ON cotizaciones(creado_por);
-- cotizacion_items(cotizacion_id) ya está cubierto por uq_item_orden.
CREATE INDEX idx_items_ensayo            ON cotizacion_items(ensayo_id);
CREATE INDEX idx_items_categoria         ON cotizacion_items(categoria_id);
CREATE INDEX idx_historial_cotizacion    ON cotizacion_historial_estados(cotizacion_id);
-- ensayo_acreditacion_historial(ensayo_id) ya está cubierto por uq_acreditacion_dia.
CREATE INDEX idx_documentos_cotizacion   ON documentos_externos(cotizacion_id);
CREATE INDEX idx_documentos_integracion  ON documentos_externos(integracion_id);
CREATE INDEX idx_auditoria_usuario       ON auditoria(usuario_id);


-- ----------------------------------------------------------------------------
-- 2. CONSULTAS DEL DASHBOARD Y DE LA LISTA DE COTIZACIONES
-- ----------------------------------------------------------------------------
-- fn_dashboard_* filtran por fecha_emision y descartan borradores.
-- Índice parcial: los borradores no se consultan nunca por fecha, así que no
-- entran al índice y este se mantiene pequeño.
-- [MT] Bajo multi-tenant pasa a (tenant_id, fecha_emision).
CREATE INDEX idx_cotizaciones_fecha
    ON cotizaciones(fecha_emision) WHERE estado <> 'borrador';

-- Lista "Cotizaciones" filtrada por estado + rango de fechas (chips + Desde/Hasta).
-- [MT] → (tenant_id, estado, fecha_emision DESC)
CREATE INDEX idx_cotizaciones_estado_fecha
    ON cotizaciones(estado, fecha_emision DESC);

-- Búsqueda por número de cotización desde la barra de búsqueda.
-- uq_cotizaciones_numero ya sirve para la igualdad exacta; este permite el
-- prefijo ('COT-2026-%') sin depender del collation de la base.
CREATE INDEX idx_cotizaciones_numero_pat
    ON cotizaciones(numero varchar_pattern_ops) WHERE numero IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 3. NAVEGACIÓN DEL CATÁLOGO EN "NUEVA COTIZACIÓN"
-- ----------------------------------------------------------------------------
-- Pestaña de categoría → chip de subcategoría → lista ordenada por código.
-- Solo lo ofrecible entra al índice.
-- [MT] → (tenant_id, categoria_id, subcategoria_id, codigo)
CREATE INDEX idx_catalogo_navegacion
    ON ensayos_catalogo(categoria_id, subcategoria_id, codigo) WHERE activo;

-- Los paquetes son pocos y se listan aparte (pestaña "Paquetes").
CREATE INDEX idx_catalogo_paquetes
    ON ensayos_catalogo(categoria_id) WHERE es_paquete AND activo;


-- ----------------------------------------------------------------------------
-- 4. AUDITORÍA
-- ----------------------------------------------------------------------------
-- "Muéstrame todo lo que pasó con el ensayo 12" y "qué cambió esta semana".
-- [MT] → (tenant_id, tabla, registro_id) y (tenant_id, registrado_en DESC)
CREATE INDEX idx_auditoria_registro ON auditoria(tabla, registro_id);
CREATE INDEX idx_auditoria_fecha    ON auditoria(registrado_en DESC);
-- Rastreo por identificador público (lo que llega desde la API).
CREATE INDEX idx_auditoria_public   ON auditoria(registro_public_id)
    WHERE registro_public_id IS NOT NULL;


-- ============================================================================
-- VISTAS
-- ============================================================================

-- Lo que se ofrece en "Nueva Cotización": activo en los tres niveles, en el
-- orden que definió el usuario.
CREATE VIEW vw_catalogo_disponible AS
SELECT ce.id   AS categoria_id, ce.slug AS categoria_slug, ce.nombre AS categoria,
       ce.icono, ce.color_hex, ce.orden AS orden_categoria,
       se.id   AS subcategoria_id, se.nombre AS subcategoria, se.orden AS orden_subcategoria,
       ec.id   AS ensayo_id, ec.public_id, ec.codigo, ec.nombre, ec.norma,
       ec.unidad, ec.precio_base, ec.es_paquete, ec.acreditado
  FROM ensayos_catalogo ec
  JOIN subcategorias_ensayo se ON se.id = ec.subcategoria_id
  JOIN categorias_ensayo   ce ON ce.id = ec.categoria_id
 WHERE ec.activo AND se.activo AND ce.activo;

-- Detalle de cada paquete. El nombre y la norma del componente salen del
-- ensayo vinculado: una sola fuente de verdad. Si se corrige la norma de
-- SU-03, todos los paquetes que lo incluyen la ven corregida al instante.
CREATE VIEW vw_paquete_detalle AS
SELECT p.id     AS paquete_id,
       p.codigo AS paquete_codigo,
       p.nombre AS paquete,
       pc.orden,
       c.codigo                      AS componente_codigo,
       COALESCE(c.nombre, pc.nombre) AS componente,
       COALESCE(c.norma,  pc.norma)  AS norma,
       pc.cantidad,
       c.precio_base                 AS precio_individual,
       c.activo                      AS componente_activo,
       (pc.ensayo_componente_id IS NOT NULL) AS vinculado
  FROM paquete_componentes pc
  JOIN ensayos_catalogo p      ON p.id = pc.ensayo_id
  LEFT JOIN ensayos_catalogo c ON c.id = pc.ensayo_componente_id;

-- Precio del paquete frente a lo que costarían sus ensayos por separado.
-- ahorro_pct solo tiene sentido cuando TODOS los componentes están vinculados
-- (si alguno es descriptivo no hay precio individual con el que comparar).
CREATE VIEW vw_paquetes_resumen AS
SELECT p.id, p.codigo, p.nombre, p.precio_base AS precio_paquete, p.activo,
       COUNT(pc.id)                    AS componentes,
       COUNT(pc.ensayo_componente_id)  AS vinculados,
       SUM(c.precio_base * pc.cantidad) AS valor_individual,
       CASE WHEN COUNT(pc.id) = COUNT(pc.ensayo_componente_id)
             AND SUM(c.precio_base * pc.cantidad) > 0
            THEN round(100 * (1 - p.precio_base / SUM(c.precio_base * pc.cantidad)), 1)
       END AS ahorro_pct
  FROM ensayos_catalogo p
  LEFT JOIN paquete_componentes pc ON pc.ensayo_id = p.id
  LEFT JOIN ensayos_catalogo c     ON c.id = pc.ensayo_componente_id
 WHERE p.es_paquete
 GROUP BY p.id, p.codigo, p.nombre, p.precio_base, p.activo;

-- Acreditación vigente por ensayo, con desde cuándo. Es la fila del historial
-- que un auditor ISO 17025 quiere ver junto al estado actual.
CREATE VIEW vw_acreditacion_vigente AS
SELECT ec.id AS ensayo_id, ec.codigo, ec.nombre, ec.acreditado AS estado_actual,
       h.acreditado AS estado_historial, h.vigente_desde, h.motivo,
       (ec.acreditado = h.acreditado) AS coherente
  FROM ensayos_catalogo ec
  LEFT JOIN LATERAL (
        SELECT acreditado, vigente_desde, motivo
          FROM ensayo_acreditacion_historial
         WHERE ensayo_id = ec.id AND vigente_desde <= fn_hoy_lima()
         ORDER BY vigente_desde DESC, id DESC LIMIT 1
  ) h ON TRUE;

-- Resumen por categoría a partir del SNAPSHOT del ítem, no del catálogo vivo.
-- Esta es la corrección al defecto A-11 de v2: las vistas de dashboard hacían
-- INNER JOIN contra ensayos_catalogo, así que cualquier ítem cuyo ensayo
-- desapareciera dejaba de sumar y el dashboard reportaba menos dinero del
-- realmente cotizado.
CREATE VIEW vw_resumen_por_categoria AS
SELECT ci.categoria_snapshot AS categoria,
       COUNT(DISTINCT c.id)  AS cotizaciones,
       SUM(ci.cantidad)      AS items,
       SUM(ci.subtotal)      AS monto_cotizado,
       SUM(ci.subtotal) FILTER (WHERE c.estado = 'aceptada') AS monto_aceptado
  FROM cotizacion_items ci
  JOIN cotizaciones c ON c.id = ci.cotizacion_id
 WHERE c.estado <> 'borrador'
 GROUP BY ci.categoria_snapshot;

CREATE VIEW vw_ensayos_mas_cotizados AS
SELECT ci.codigo_snapshot AS codigo, ci.nombre_snapshot AS nombre,
       ci.categoria_snapshot AS categoria,
       COUNT(*)         AS veces_cotizado,
       SUM(ci.cantidad) AS unidades,
       SUM(ci.subtotal) AS monto
  FROM cotizacion_items ci
  JOIN cotizaciones c ON c.id = ci.cotizacion_id
 WHERE c.estado <> 'borrador'
 GROUP BY 1, 2, 3;

-- Auditoría en lenguaje humano: para la pantalla de historial y para responder
-- "¿quién bajó el precio de este ensayo?" sin leer JSON a mano.
CREATE VIEW vw_auditoria_legible AS
SELECT a.id, a.registrado_en, a.tabla, a.registro_id, a.accion,
       (u.nombres || ' ' || u.apellidos) AS usuario, r.codigo AS rol,
       a.ip_origen,
       array_to_string(a.campos_cambiados, ', ') AS campos,
       a.datos_anteriores, a.datos_nuevos
  FROM auditoria a
  JOIN usuarios u ON u.id = a.usuario_id
  JOIN roles    r ON r.id = u.rol_id;

-- Todo lo que necesita el PDF de una cotización, en una sola consulta y
-- SIEMPRE desde el snapshot (nunca desde el catálogo actual).
CREATE VIEW vw_cotizacion_pdf AS
SELECT c.id, c.public_id, c.numero, c.fecha_emision, c.estado, c.moneda,
       c.proyecto_nombre, c.validez_dias,
       COALESCE(e.razon_social, p.nombres || ' ' || p.apellidos) AS cliente,
       COALESCE(e.ruc, p.dni)            AS documento_cliente,
       ct.nombres || ' ' || ct.apellidos AS contacto,
       ct.cargo AS contacto_cargo, ct.email AS contacto_email,
       pl.nombre AS plantilla, pl.terminos_condiciones,
       c.subtotal, c.igv_tasa, c.igv, c.descuento_tipo, c.descuento_monto,
       c.descuento_razon, c.total, c.notas,
       (SELECT jsonb_agg(jsonb_build_object(
                  'orden', i.orden, 'codigo', i.codigo_snapshot,
                  'nombre', i.nombre_snapshot, 'norma', i.norma_snapshot,
                  'unidad', i.unidad_snapshot, 'acreditado', i.acreditado_snapshot,
                  'cantidad', i.cantidad, 'precio', i.precio_unitario,
                  'subtotal', i.subtotal, 'incluye', i.componentes_snapshot)
              ORDER BY i.orden)
          FROM cotizacion_items i WHERE i.cotizacion_id = c.id) AS items
  FROM cotizaciones c
  LEFT JOIN empresas  e  ON e.id  = c.empresa_id
  LEFT JOIN personas  p  ON p.id  = c.persona_id
  LEFT JOIN contactos ct ON ct.id = c.contacto_id
  JOIN plantillas_cotizacion pl ON pl.id = c.plantilla_id;

COMMENT ON VIEW vw_resumen_por_categoria IS
    'Se agrupa por categoria_snapshot del ítem: el dashboard no pierde historia si el catálogo cambia.';
COMMENT ON VIEW vw_cotizacion_pdf IS
    'Fuente única del PDF. Todo sale del snapshot del ítem, nunca del catálogo vivo.';
