-- ============================================================================
-- GTQC — DATOS BASE  ·  v3.0     (archivo 5 de 6; tras 03_indexes_views.sql)
-- ============================================================================
-- Roles, usuario del sistema, las 4 categorías del laboratorio con sus 14
-- subcategorías y las 3 plantillas de cotización.
-- El catálogo de 87 ensayos y los 13 paquetes van en 05_seed_ensayos.sql.
-- ============================================================================

-- El contexto de aplicación durante la carga: todo queda a nombre del usuario
-- del sistema, y así la auditoría de los seeds es identificable.
SET app.usuario_id = '1';

-- Roles y usuario del sistema van en UNA transacción con la FK de auditoría
-- diferida: el trigger que audita el alta de los roles referencia al usuario 1,
-- que todavía no existe en ese instante. Al confirmar, ya existe y la FK cuadra.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- ----------------------------------------------------------------------------
-- Roles del producto (es_sistema = TRUE: no se eliminan ni cambian de código)
-- ----------------------------------------------------------------------------
INSERT INTO roles (id, codigo, nombre, descripcion, es_sistema) VALUES
    (1, 'admin',       'Administrador', 'Acceso total: catálogo, usuarios, configuración', TRUE),
    (2, 'comercial',   'Comercial',     'Crea y gestiona cotizaciones y clientes', TRUE),
    (3, 'laboratorio', 'Laboratorio',   'Lectura de cotizaciones + gestiona la acreditación de ensayos', TRUE),
    (4, 'lectura',     'Solo lectura',  'Consulta dashboard e historial', TRUE);
SELECT setval(pg_get_serial_sequence('roles','id'), (SELECT MAX(id) FROM roles));

-- ----------------------------------------------------------------------------
-- Usuario del sistema (id = 1)
-- ----------------------------------------------------------------------------
-- Es el autor de los seeds y el valor al que cae fn_app_usuario() cuando el
-- backend no fijó app.usuario_id. No tiene password_hash: no puede iniciar
-- sesión, solo existe para que la autoría nunca quede en NULL.
INSERT INTO usuarios (id, nombres, apellidos, email, rol_id, activo, creado_por) VALUES
    (1, 'Sistema', 'GTQC', 'sistema@gtqc.local', 1, TRUE, NULL);
SELECT setval(pg_get_serial_sequence('usuarios','id'), (SELECT MAX(id) FROM usuarios));

COMMIT;

-- ----------------------------------------------------------------------------
-- Categorías del catálogo
-- ----------------------------------------------------------------------------
-- El prefijo de Concreto es 'AG' porque su catálogo histórico se codifica
-- desde Agregados (AG-01 … AG-42). Cambiarlo ahora rompería 42 códigos ya
-- emitidos en cotizaciones reales, así que R4 lo deja fijo a propósito.
INSERT INTO categorias_ensayo (slug, nombre, prefijo_codigo, icono, color_hex, orden, creado_por) VALUES
    ('suelos',      'Suelos',      'SU', '🟤', '#92400e', 1, 1),
    ('concreto',    'Concreto',    'AG', '⬜', '#64748b', 2, 1),
    ('asfalto',     'Asfalto',     'AS', '⬛', '#1e293b', 3, 1),
    ('albanileria', 'Albañilería', 'AL', '🧱', '#b91c1c', 4, 1);

-- ----------------------------------------------------------------------------
-- Subcategorías (14) — el orden es el que verá el usuario en los chips
-- ----------------------------------------------------------------------------
INSERT INTO subcategorias_ensayo (categoria_id, nombre, orden, creado_por)
SELECT c.id, s.sub, s.ord, 1
  FROM categorias_ensayo c
  JOIN (VALUES
        ('suelos',      'Estándares y Especiales', 1),
        ('suelos',      'Químicos',                2),
        ('suelos',      'Paquetes',                3),
        ('suelos',      'Campo',                   4),
        ('concreto',    'Agregado',                1),
        ('concreto',    'Químicos Agregado',       2),
        ('concreto',    'Químicos Agua',           3),
        ('concreto',    'Fresco y Endurecido',     4),
        ('concreto',    'Paquetes',                5),
        ('concreto',    'In-Situ (Campo)',         6),
        ('asfalto',     'Mezclas Asfálticas',      1),
        ('asfalto',     'Paquetes',                2),
        ('asfalto',     'Campo',                   3),
        ('albanileria', 'Ladrillos',               1)
  ) AS s(slug, sub, ord) ON s.slug = c.slug;

-- ----------------------------------------------------------------------------
-- Plantillas de cotización (máximo 3 activas, lo exige a_max_activas)
-- ----------------------------------------------------------------------------
INSERT INTO plantillas_cotizacion (slug, nombre, icono, validez_dias_sugerida, terminos_condiciones, creado_por) VALUES
    ('estandar', 'Estándar', '🧪', 15,
     'Validez de la cotización: 15 días calendario. Forma de pago: 50% adelanto, 50% contra entrega de informe.', 1),
    ('premium',  'Premium',  '⭐', 30,
     'Validez de la cotización: 30 días calendario. Pago flexible según acuerdo. Incluye informe ejecutivo y soporte técnico por 30 días.', 1),
    ('express',  'Express',  '⚡', 7,
     'Validez de la cotización: 7 días calendario. Pago 100% adelantado. Entrega de resultados en 48 horas.', 1);
