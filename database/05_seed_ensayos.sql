-- ============================================================================
-- GTQC — CATÁLOGO DE ENSAYOS  ·  v3.0   (archivo 6 de 6; tras 04_seeds.sql)
-- ============================================================================
-- 87 ensayos y paquetes reales del laboratorio (Suelos, Concreto, Asfalto,
-- Albanileria) con su codigo, norma, unidad, precio y estado de acreditacion,
-- mas los 119 componentes de los 13 paquetes historicos.
--
-- De esos 119 componentes, 74 quedan AMARRADOS a un ensayo real del catalogo
-- (ensayo_componente_id) al final del archivo: asi el nombre y la norma del
-- componente salen del ensayo y hay una sola fuente de verdad. Los 45
-- restantes no tienen todavia un ensayo equivalente vendible (p. ej.
-- "Clasificacion SUCS") y quedan DESCRIPTIVOS a proposito, marcados en la app
-- como "sin vincular" para que el laboratorio decida si crearlos.
--
-- Los ensayos se insertan por slug de categoria + nombre de subcategoria, no
-- por id: el archivo es reproducible sobre una base limpia sin depender de que
-- las secuencias hayan quedado en el mismo numero.
-- ============================================================================

SET app.usuario_id = '1';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-01', ce.id, se.id, 'Análisis granulométrico por tamizado', 'UND', 'ASTM D6913/D6913M', 38.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-02', ce.id, se.id, 'Contenido de Humedad', 'UND', 'ASTM D2216', 12.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-03', ce.id, se.id, 'Límite Líquido', 'UND', 'ASTM D4318', 25.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-04', ce.id, se.id, 'Límite Plástico', 'UND', 'ASTM D4318', 25.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-05', ce.id, se.id, 'Peso volumétrico de suelos cohesivos', 'UND', 'NTP 339.139', 55.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-06', ce.id, se.id, 'Proctor estándar', 'UND', 'MTC E116', 120.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-07', ce.id, se.id, 'Proctor Modificado', 'UND', 'NTP 339.141', 110.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-08', ce.id, se.id, 'CBR', 'UND', 'MTC E132', 150.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-09', ce.id, se.id, 'Equivalente de arena', 'UND', 'NTP 339.146', 80.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-10', ce.id, se.id, 'Pasante la malla N°200', 'UND', 'ASTM D1140', 45.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-11', ce.id, se.id, 'Peso específico relativo', 'UND', 'NTP 339.131', 50.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-12', ce.id, se.id, 'Gravedad específica', 'UND', 'MTC E205', 50.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-13', ce.id, se.id, 'Peso específico', 'UND', 'MTC E206', 50.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-14', ce.id, se.id, 'Permeabilidad', 'UND', 'NTP 339.147', 250.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-15', ce.id, se.id, 'Corte Directo', 'UND', 'NTP 339.171', 200.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Estándares y Especiales';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-16', ce.id, se.id, 'Sales solubles en Suelos y Agua', 'UND', 'NTP 339.152', 80.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Químicos';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-17', ce.id, se.id, 'Sulfatos Solubles en Suelos y Agua', 'UND', 'NTP 339.178', 80.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Químicos';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-18', ce.id, se.id, 'Cloruros Solubles en Suelos y Agua', 'UND', 'NTP 339.177', 80.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Químicos';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-19', ce.id, se.id, 'Determinación del PH en Suelo y Agua', 'UND', 'NTP 339.176', 35.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Químicos';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-20', ce.id, se.id, 'Paquete de Ensayo de Clasificación', 'UND', NULL, 100.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría', 'D6913/D6913M' FROM ensayos_catalogo WHERE codigo = 'SU-20';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Límite Líquido', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-20';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Límite Plástico', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-20';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Contenido de Humedad', 'ASTM D2216' FROM ensayos_catalogo WHERE codigo = 'SU-20';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Clasificación AASHTO', 'ASTM D3282' FROM ensayos_catalogo WHERE codigo = 'SU-20';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Clasificación SUCS', 'ASTM D2487' FROM ensayos_catalogo WHERE codigo = 'SU-20';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-21', ce.id, se.id, 'Paquete de Ensayo de Corte Directo', 'UND', NULL, 350.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría', 'D6913/D6913M' FROM ensayos_catalogo WHERE codigo = 'SU-21';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Límite Líquido', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-21';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Límite Plástico', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-21';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Contenido de Humedad', 'ASTM D2216' FROM ensayos_catalogo WHERE codigo = 'SU-21';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Clasificación SUCS', 'ASTM D2487' FROM ensayos_catalogo WHERE codigo = 'SU-21';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Corte Directo', 'NTP 339.171' FROM ensayos_catalogo WHERE codigo = 'SU-21';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'Ensayo de Densidad Natural', 'NTP 339.143' FROM ensayos_catalogo WHERE codigo = 'SU-21';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-22', ce.id, se.id, 'Paquete de Ensayo de Proctor Modificado', 'UND', NULL, 210.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría', 'D6913/D6913M' FROM ensayos_catalogo WHERE codigo = 'SU-22';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Límite Líquido', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-22';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Límite Plástico', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-22';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Contenido de Humedad', 'ASTM D2216' FROM ensayos_catalogo WHERE codigo = 'SU-22';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Clasificación AASHTO', 'ASTM D3282' FROM ensayos_catalogo WHERE codigo = 'SU-22';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Proctor Modificado', 'NTP 339.141' FROM ensayos_catalogo WHERE codigo = 'SU-22';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-23', ce.id, se.id, 'Paquete de Ensayo de CBR Completo', 'UND', NULL, 400.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría', 'D6913/D6913M' FROM ensayos_catalogo WHERE codigo = 'SU-23';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Límite Líquido', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-23';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Límite Plástico', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-23';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Contenido de Humedad', 'ASTM D2216' FROM ensayos_catalogo WHERE codigo = 'SU-23';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Clasificación AASHTO', 'ASTM D3282' FROM ensayos_catalogo WHERE codigo = 'SU-23';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Proctor Modificado', 'NTP 339.141' FROM ensayos_catalogo WHERE codigo = 'SU-23';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'CBR', 'MTC E132' FROM ensayos_catalogo WHERE codigo = 'SU-23';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-24', ce.id, se.id, 'Paquete de Cantera para Afirmado', 'UND', NULL, 500.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría', 'D6913/D6913M' FROM ensayos_catalogo WHERE codigo = 'SU-24';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Límite Líquido', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-24';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Límite Plástico', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-24';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Contenido de Humedad', 'ASTM D2216' FROM ensayos_catalogo WHERE codigo = 'SU-24';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Clasificación AASHTO', 'ASTM D3282' FROM ensayos_catalogo WHERE codigo = 'SU-24';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Proctor Modificado', 'NTP 339.141' FROM ensayos_catalogo WHERE codigo = 'SU-24';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'CBR', 'MTC E132' FROM ensayos_catalogo WHERE codigo = 'SU-24';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 7, 'Abrasión Los Ángeles', 'MTC E207' FROM ensayos_catalogo WHERE codigo = 'SU-24';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-25', ce.id, se.id, 'Paquete de Cantera para Sub Base', 'UND', NULL, 620.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría', 'D6913/D6913M' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Límite Líquido', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Límite Plástico', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Contenido de Humedad', 'ASTM D2216' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Clasificación SUCS', 'ASTM D2487' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Clasificación AASHTO', 'ASTM D3282' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'Proctor Modificado', 'NTP 339.141' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 7, 'CBR', 'MTC E132' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 8, 'Abrasión Los Ángeles', 'MTC E207' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 9, 'Equivalente de Arena', 'NTP 339.146' FROM ensayos_catalogo WHERE codigo = 'SU-25';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 10, 'Partículas Chatas y Alargadas', 'MTC E223' FROM ensayos_catalogo WHERE codigo = 'SU-25';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-26', ce.id, se.id, 'Paquete de Cantera para Base', 'UND', NULL, 900.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría', 'D6913/D6913M' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Límite Líquido', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Límite Plástico', 'ASTM D4318' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Contenido de Humedad', 'ASTM D2216' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Clasificación SUCS', 'ASTM D2487' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Clasificación AASHTO', 'ASTM D3282' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'Proctor Modificado', 'NTP 339.141' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 7, 'CBR', 'MTC E132' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 8, 'Abrasión Los Ángeles', 'MTC E207' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 9, 'Equivalente de Arena', 'NTP 339.146' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 10, 'Durabilidad al Sulfato de Magnesio', 'NTP 400.016' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 11, 'Partículas Chatas y Alargadas', 'MTC E223' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 12, 'Caras Fracturadas', 'MTC E210' FROM ensayos_catalogo WHERE codigo = 'SU-26';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 13, 'Sales Solubles', 'NTP 339.152' FROM ensayos_catalogo WHERE codigo = 'SU-26';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-27', ce.id, se.id, 'Densidad de Campo (incluye Speedy, no incluye movilidad)', 'UND', 'NTP 339.143', 50.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Campo';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'SU-28', ce.id, se.id, 'Test de Percolación (no incluye excavación)', 'UND', NULL, 280.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'suelos' AND se.nombre = 'Campo';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-01', ce.id, se.id, 'Abrasión Los Ángeles', 'UND', 'MTC E207', 100.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-02', ce.id, se.id, 'Durabilidad al Sulfato de Magnesio', 'UND', 'NTP 400.016', 300.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-03', ce.id, se.id, 'Gravedad específica', 'UND', 'MTC E205', 50.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-04', ce.id, se.id, 'Absorción', 'UND', 'MTC E206', 50.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-05', ce.id, se.id, 'Peso Específico', 'UND', 'MTC E206', 50.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-06', ce.id, se.id, 'Peso Unitario Compactado (PUC)', 'UND', 'NTP 400.017', 40.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-07', ce.id, se.id, 'Peso Unitario Suelto (PUS)', 'UND', 'NTP 400.017', 40.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-08', ce.id, se.id, 'Impurezas Orgánicas', 'UND', 'MTC E213-2016', 70.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-09', ce.id, se.id, 'Equivalente de arena', 'UND', 'NTP 339.146', 80.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-10', ce.id, se.id, 'Terrones de arcilla y partículas friables', 'UND', 'NTP 400.015', 65.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-11', ce.id, se.id, '% de caras fracturadas', 'UND', 'MTC E210', 70.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-12', ce.id, se.id, 'Análisis granulométrico por tamizado', 'UND', 'NTP 400.012', 40.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-13', ce.id, se.id, 'Pasante la malla N°200 por lavado', 'UND', 'NTP 339.132', 40.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-14', ce.id, se.id, 'Contenido de humedad', 'UND', 'NTP 339.185', 12.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-15', ce.id, se.id, 'PH', 'UND', 'NTP 339.176', 15.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-16', ce.id, se.id, 'Sales solubles', 'UND', 'NTP 339.152', 60.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-17', ce.id, se.id, 'Cloruros', 'UND', 'NTP 339.177', 60.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-18', ce.id, se.id, 'Azul de Metileno', 'UND', 'AASHTO TP 300.07', 100.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-19', ce.id, se.id, 'Sulfatos', 'UND', 'NTP 339.178', 6.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-20', ce.id, se.id, 'Carbonatación', 'UND', NULL, 80.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agregado';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-21', ce.id, se.id, 'Sales solubles', 'UND', 'NTP 339.152', 60.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agua';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-22', ce.id, se.id, 'Sulfatos', 'UND', 'NTP 339.178', 60.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agua';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-23', ce.id, se.id, 'Cloruros', 'UND', 'NTP 339.177', 60.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agua';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-24', ce.id, se.id, 'PH', 'UND', 'NTP 339.176', 15.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agua';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-25', ce.id, se.id, 'Temperatura', 'UND', 'DIN 19266', 15.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Químicos Agua';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-26', ce.id, se.id, 'Elaboración de probeta (unidad)', 'UND', NULL, 10.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Fresco y Endurecido';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-27', ce.id, se.id, 'Resistencia a la compresión (espécimen)', 'UND', 'ASTM C39/C39M', 12.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Fresco y Endurecido';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-28', ce.id, se.id, 'Resistencia a la flexión (vigas)', 'UND', 'NTP 339.078', 22.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Fresco y Endurecido';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-29', ce.id, se.id, 'Elaboración de probeta y rotura', 'UND', 'ASTM C39/C39M', 30.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Fresco y Endurecido';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-30', ce.id, se.id, 'Elaboración de vigas y rotura', 'UND', 'NTP 339.078', 35.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Fresco y Endurecido';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-31', ce.id, se.id, 'Tiempo de fraguado', 'UND', 'NTP 339.088', 50.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Fresco y Endurecido';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-32', ce.id, se.id, 'Exudación', 'UND', 'MTC E714', 50.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Fresco y Endurecido';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-33', ce.id, se.id, 'Contenido de aire (Olla Washington)', 'UND', NULL, 70.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Fresco y Endurecido';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-34', ce.id, se.id, 'Paquete de Agregado Global', 'UND', NULL, 1500.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Pasante la Malla 200 por lavado', 'NTP E132' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Terrones de Arcilla y Partículas Desmenuzables', 'NTP 400.015' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Durabilidad al Sulfato de Magnesio', 'NTP 400.016' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Impurezas Orgánicas', 'MTC E213' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Equivalente de Arena', 'NTP 339.146' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Abrasión Los Ángeles', 'MTC E207' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'Porcentaje de Caras Fracturadas', 'MTC E210' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 7, '% de Chatas y Alargadas', 'MTC E223' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 8, 'Sulfatos', 'NTP 339.178' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 9, 'Cloruros', 'NTP 339.177' FROM ensayos_catalogo WHERE codigo = 'AG-34';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 10, 'PH', 'NTP 339.176' FROM ensayos_catalogo WHERE codigo = 'AG-34';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-35', ce.id, se.id, 'Paquete de Agregado Fino', 'UND', NULL, 740.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Pasante la Malla 200 por lavado', 'NTP E132' FROM ensayos_catalogo WHERE codigo = 'AG-35';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Terrones de Arcilla y Partículas Desmenuzables', 'NTP 400.015' FROM ensayos_catalogo WHERE codigo = 'AG-35';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Durabilidad al Sulfato de Magnesio', 'NTP 400.016' FROM ensayos_catalogo WHERE codigo = 'AG-35';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Impurezas Orgánicas', 'MTC E213' FROM ensayos_catalogo WHERE codigo = 'AG-35';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Equivalente de Arena', 'NTP 339.146' FROM ensayos_catalogo WHERE codigo = 'AG-35';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Granulometría en Agregados', 'NTP 400.012' FROM ensayos_catalogo WHERE codigo = 'AG-35';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'Sulfatos', 'NTP 339.178' FROM ensayos_catalogo WHERE codigo = 'AG-35';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 7, 'Cloruros', 'NTP 339.177' FROM ensayos_catalogo WHERE codigo = 'AG-35';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 8, 'Absorción', 'MTC E206' FROM ensayos_catalogo WHERE codigo = 'AG-35';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-36', ce.id, se.id, 'Paquete de Agregado Grueso', 'UND', NULL, 780.0, TRUE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Abrasión Los Ángeles', 'MTC E207' FROM ensayos_catalogo WHERE codigo = 'AG-36';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Terrones de Arcilla y Partículas Desmenuzables', 'NTP 400.015' FROM ensayos_catalogo WHERE codigo = 'AG-36';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Pasante la Malla 200 por lavado', 'NTP E132' FROM ensayos_catalogo WHERE codigo = 'AG-36';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Durabilidad al Sulfato de Magnesio', 'NTP 400.016' FROM ensayos_catalogo WHERE codigo = 'AG-36';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, '% de Caras Fracturadas', 'MTC E210' FROM ensayos_catalogo WHERE codigo = 'AG-36';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, '% de Chatas y Alargadas', 'MTC E223' FROM ensayos_catalogo WHERE codigo = 'AG-36';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'Sulfatos', 'NTP 339.178' FROM ensayos_catalogo WHERE codigo = 'AG-36';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 7, 'Cloruros', 'NTP 339.177' FROM ensayos_catalogo WHERE codigo = 'AG-36';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 8, 'Granulometría en Agregados', 'NTP 400.012' FROM ensayos_catalogo WHERE codigo = 'AG-36';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-37', ce.id, se.id, 'Diseño de Mezcla Práctico', 'UND', NULL, 500.0, TRUE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría en Agregados', 'NTP 400.012' FROM ensayos_catalogo WHERE codigo = 'AG-37';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Contenido de Humedad en Agregados', 'NTP 339.127' FROM ensayos_catalogo WHERE codigo = 'AG-37';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Peso Unitario Suelto', 'NTP 400.017' FROM ensayos_catalogo WHERE codigo = 'AG-37';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Peso Unitario Compactado', 'NTP 400.017' FROM ensayos_catalogo WHERE codigo = 'AG-37';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Peso Específico', 'MTC E206' FROM ensayos_catalogo WHERE codigo = 'AG-37';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Gravedad Específica', 'MTC E205' FROM ensayos_catalogo WHERE codigo = 'AG-37';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'Absorción', 'MTC E205' FROM ensayos_catalogo WHERE codigo = 'AG-37';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 7, 'Elaboración de 04 especímenes (rotos a 3 y 7 días)', 'MTC E702 / ASTM C39/C39M' FROM ensayos_catalogo WHERE codigo = 'AG-37';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-38', ce.id, se.id, 'Diseño de Mezcla Teórico', 'UND', NULL, 350.0, TRUE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría en Agregados', 'NTP 400.012' FROM ensayos_catalogo WHERE codigo = 'AG-38';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Contenido de Humedad en Agregados', 'NTP 339.127' FROM ensayos_catalogo WHERE codigo = 'AG-38';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Peso Unitario Suelto', 'NTP 400.017' FROM ensayos_catalogo WHERE codigo = 'AG-38';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Peso Unitario Compactado', 'NTP 400.017' FROM ensayos_catalogo WHERE codigo = 'AG-38';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Peso Específico', 'MTC E206' FROM ensayos_catalogo WHERE codigo = 'AG-38';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Gravedad Específica', 'MTC E205' FROM ensayos_catalogo WHERE codigo = 'AG-38';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'Absorción', 'MTC E205' FROM ensayos_catalogo WHERE codigo = 'AG-38';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-39', ce.id, se.id, 'Extracción de núcleo diamantina (mín. 3 puntos, no incluye movilidad)', 'UND', 'NTP 339.059 / NTP 339.034', 220.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'In-Situ (Campo)';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-40', ce.id, se.id, 'Esclerometría (mín. 4 puntos, no incluye movilidad)', 'UND', 'NTP 339.181', 50.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'In-Situ (Campo)';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-41', ce.id, se.id, 'Slump - Asentamiento (mín. 5 puntos, no incluye movilidad)', 'UND', 'NTP 339.035', 28.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'In-Situ (Campo)';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AG-42', ce.id, se.id, 'Temperatura de concreto (mín. 5 puntos, no incluye movilidad)', 'UND', 'NTP 339.184', 15.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'concreto' AND se.nombre = 'In-Situ (Campo)';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-01', ce.id, se.id, 'Adherencia en agregado fino (Riedel Weber)', 'UND', 'MTC E220', 130.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Mezclas Asfálticas';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-02', ce.id, se.id, 'Lavado asfáltico', 'UND', 'MTC E502', 350.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Mezclas Asfálticas';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-03', ce.id, se.id, 'Diseño de mezcla Método Marshall (incluye análisis de agregados)', 'UND', 'MTC E504', 2500.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Mezclas Asfálticas';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-04', ce.id, se.id, 'Elaboración de briquetas Marshall (costo por briqueta)', 'UND', 'MTC E504', 60.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Mezclas Asfálticas';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-05', ce.id, se.id, 'Azul de metileno', 'UND', 'AASHTO TP 300-07', 110.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Mezclas Asfálticas';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-06', ce.id, se.id, 'Estabilidad y flujo Marshall (solo rotura de briqueta)', 'UND', 'MTC E504', 80.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Mezclas Asfálticas';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-07', ce.id, se.id, 'Diseño de Mezcla Método Marshall (paquete completo)', 'UND', NULL, 2500.0, TRUE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Paquetes';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 0, 'Granulometría (MAC)', 'MTC E504' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 1, 'Adhesividad', 'MTC E504' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 2, 'Límite Líquido por malla 200 y 40', 'NTP 339.129' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 3, 'Límite Plástico por malla 200 y 40', 'NTP 339.129' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 4, 'Equivalente de Arena', 'NTP 339.146' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 5, 'Impurezas Orgánicas', 'MTC E213' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 6, 'Azul de Metileno', 'INV E235' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 7, 'Sales Solubles', 'NTP 339.152' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 8, 'Abrasión Los Ángeles', 'MTC E207' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 9, 'Durabilidad al Sulfato de Magnesio', 'NTP 339.016' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 10, 'Peso Específico', 'MTC E205' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 11, 'Gravedad Específica', 'MTC E206' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 12, 'Absorción', 'MTC E702' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 13, 'Porcentaje de Caras Fracturadas', 'MTC E210' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 14, '% de Chatas y Alargadas', 'MTC E223' FROM ensayos_catalogo WHERE codigo = 'AS-07';
INSERT INTO paquete_componentes (ensayo_id, orden, nombre, norma)
SELECT id, 15, 'Elaboración de 18 briquetas', 'MTC E504' FROM ensayos_catalogo WHERE codigo = 'AS-07';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-08', ce.id, se.id, 'Extracción de núcleo diamantina (mín. 3 puntos)', 'UND', 'NTP 339.059 (Ext) / NTP 339.034 (Rot)', 200.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Campo';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-09', ce.id, se.id, 'Péndulo Británico (sujeto a evaluación del lugar y tramo)', 'PUNT.', 'MTC E1004', 280.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Campo';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-10', ce.id, se.id, 'Viga Benkelman (sujeto a evaluación del lugar y tramo)', 'PUNT.', 'MTC E1002', 500.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Campo';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AS-11', ce.id, se.id, 'Rugosímetro de Merlin - IRI (sujeto a evaluación del lugar y tramo)', 'DÍA', 'MTC E1002', 300.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'asfalto' AND se.nombre = 'Campo';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AL-01', ce.id, se.id, 'Alabeo', 'UND', 'NTP 339.613', 20.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'albanileria' AND se.nombre = 'Ladrillos';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AL-02', ce.id, se.id, 'Absorción', 'UND', 'NTP 339.613', 20.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'albanileria' AND se.nombre = 'Ladrillos';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AL-03', ce.id, se.id, 'Resistencia', 'UND', 'NTP 339.613', 20.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'albanileria' AND se.nombre = 'Ladrillos';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AL-04', ce.id, se.id, 'Succión', 'UND', 'NTP 339.613', 20.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'albanileria' AND se.nombre = 'Ladrillos';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AL-05', ce.id, se.id, 'Variabilidad dimensional', 'UND', 'NTP 339.613', 15.0, FALSE, FALSE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'albanileria' AND se.nombre = 'Ladrillos';

INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, unidad, norma, precio_base, es_paquete, acreditado, creado_por)
SELECT 'AL-06', ce.id, se.id, 'Compresión de pilas (3 und)', 'UND', 'NTP 339.613', 35.0, FALSE, TRUE, 1
FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
WHERE ce.slug = 'albanileria' AND se.nombre = 'Ladrillos';

-- ============================================================================
-- VINCULACIÓN DE COMPONENTES DE PAQUETES CON ENSAYOS DEL CATÁLOGO
-- ============================================================================
-- Cada componente descriptivo que corresponde a un ensayo vendible queda
-- amarrado a ese ensayo (ensayo_componente_id). Su nombre/norma pasan a leerse
-- del ensayo vinculado, por eso se limpian aquí. Criterio: misma norma + misma
-- raíz de nombre, prefiriendo la categoría del paquete; revisado a mano.
-- 74 de 119 componentes quedan vinculados; el resto sigue descriptivo.

UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-34' AND pc.orden = 1 AND c.codigo = 'AG-10';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-34' AND pc.orden = 2 AND c.codigo = 'AG-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-34' AND pc.orden = 4 AND c.codigo = 'AG-09';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-34' AND pc.orden = 5 AND c.codigo = 'AG-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-34' AND pc.orden = 6 AND c.codigo = 'AG-11';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-35' AND pc.orden = 1 AND c.codigo = 'AG-10';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-35' AND pc.orden = 2 AND c.codigo = 'AG-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-35' AND pc.orden = 4 AND c.codigo = 'AG-09';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-35' AND pc.orden = 5 AND c.codigo = 'AG-12';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-35' AND pc.orden = 8 AND c.codigo = 'AG-04';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-36' AND pc.orden = 0 AND c.codigo = 'AG-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-36' AND pc.orden = 1 AND c.codigo = 'AG-10';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-36' AND pc.orden = 3 AND c.codigo = 'AG-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-36' AND pc.orden = 4 AND c.codigo = 'AG-11';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-36' AND pc.orden = 8 AND c.codigo = 'AG-12';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-37' AND pc.orden = 0 AND c.codigo = 'AG-12';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-37' AND pc.orden = 2 AND c.codigo = 'AG-07';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-37' AND pc.orden = 3 AND c.codigo = 'AG-06';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-37' AND pc.orden = 4 AND c.codigo = 'AG-05';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-37' AND pc.orden = 5 AND c.codigo = 'AG-03';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-38' AND pc.orden = 0 AND c.codigo = 'AG-12';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-38' AND pc.orden = 2 AND c.codigo = 'AG-07';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-38' AND pc.orden = 3 AND c.codigo = 'AG-06';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-38' AND pc.orden = 4 AND c.codigo = 'AG-05';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AG-38' AND pc.orden = 5 AND c.codigo = 'AG-03';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AS-07' AND pc.orden = 8 AND c.codigo = 'AG-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AS-07' AND pc.orden = 13 AND c.codigo = 'AG-11';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 18, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'AS-07' AND pc.orden = 15 AND c.codigo = 'AS-04';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-20' AND pc.orden = 0 AND c.codigo = 'SU-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-20' AND pc.orden = 1 AND c.codigo = 'SU-03';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-20' AND pc.orden = 2 AND c.codigo = 'SU-04';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-20' AND pc.orden = 3 AND c.codigo = 'SU-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-21' AND pc.orden = 0 AND c.codigo = 'SU-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-21' AND pc.orden = 1 AND c.codigo = 'SU-03';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-21' AND pc.orden = 2 AND c.codigo = 'SU-04';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-21' AND pc.orden = 3 AND c.codigo = 'SU-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-21' AND pc.orden = 5 AND c.codigo = 'SU-15';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-22' AND pc.orden = 0 AND c.codigo = 'SU-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-22' AND pc.orden = 1 AND c.codigo = 'SU-03';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-22' AND pc.orden = 2 AND c.codigo = 'SU-04';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-22' AND pc.orden = 3 AND c.codigo = 'SU-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-22' AND pc.orden = 5 AND c.codigo = 'SU-07';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-23' AND pc.orden = 0 AND c.codigo = 'SU-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-23' AND pc.orden = 1 AND c.codigo = 'SU-03';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-23' AND pc.orden = 2 AND c.codigo = 'SU-04';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-23' AND pc.orden = 3 AND c.codigo = 'SU-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-23' AND pc.orden = 5 AND c.codigo = 'SU-07';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-23' AND pc.orden = 6 AND c.codigo = 'SU-08';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-24' AND pc.orden = 0 AND c.codigo = 'SU-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-24' AND pc.orden = 1 AND c.codigo = 'SU-03';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-24' AND pc.orden = 2 AND c.codigo = 'SU-04';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-24' AND pc.orden = 3 AND c.codigo = 'SU-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-24' AND pc.orden = 5 AND c.codigo = 'SU-07';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-24' AND pc.orden = 6 AND c.codigo = 'SU-08';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-24' AND pc.orden = 7 AND c.codigo = 'AG-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-25' AND pc.orden = 0 AND c.codigo = 'SU-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-25' AND pc.orden = 1 AND c.codigo = 'SU-03';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-25' AND pc.orden = 2 AND c.codigo = 'SU-04';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-25' AND pc.orden = 3 AND c.codigo = 'SU-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-25' AND pc.orden = 6 AND c.codigo = 'SU-07';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-25' AND pc.orden = 7 AND c.codigo = 'SU-08';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-25' AND pc.orden = 8 AND c.codigo = 'AG-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-25' AND pc.orden = 9 AND c.codigo = 'SU-09';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 0 AND c.codigo = 'SU-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 1 AND c.codigo = 'SU-03';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 2 AND c.codigo = 'SU-04';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 3 AND c.codigo = 'SU-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 6 AND c.codigo = 'SU-07';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 7 AND c.codigo = 'SU-08';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 8 AND c.codigo = 'AG-01';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 9 AND c.codigo = 'SU-09';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 10 AND c.codigo = 'AG-02';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 12 AND c.codigo = 'AG-11';
UPDATE paquete_componentes pc SET ensayo_componente_id = c.id, cantidad = 1, nombre = NULL, norma = NULL FROM ensayos_catalogo p, ensayos_catalogo c WHERE pc.ensayo_id = p.id AND p.codigo = 'SU-26' AND pc.orden = 13 AND c.codigo = 'SU-16';

-- ============================================================================
-- CIERRE DEL SEED  (v3)
-- ============================================================================

-- 1) Historial de acreditacion inicial para los 87 ensayos.
--    Sin esta fila, fn_acreditado_en_fecha() no podria reconstruir el estado
--    de acreditacion de una cotizacion antigua: el booleano de la tabla dice
--    como esta HOY, el historial dice desde cuando.
INSERT INTO ensayo_acreditacion_historial (ensayo_id, acreditado, motivo, vigente_desde, registrado_por)
SELECT id, acreditado, 'Carga inicial del catalogo (linea base)', DATE '2026-01-01', 1
  FROM ensayos_catalogo;

-- 2) Alineacion de los contadores de correlativo con los codigos ya emitidos.
--    Sin esto el primer ensayo nuevo intentaria llamarse SU-01 y chocaria.
SELECT fn_sincronizar_correlativos_ensayo();

-- 3) Comprobacion inmediata: si algo de lo anterior no cuadra, este bloque
--    detiene la carga en vez de dejar una base "que ejecuto sin errores".
DO $verificar$
DECLARE v_ens INT; v_comp INT; v_vinc INT; v_paq INT; v_hist INT; v_corr INT;
BEGIN
    SELECT COUNT(*) INTO v_ens  FROM ensayos_catalogo;
    SELECT COUNT(*) INTO v_paq  FROM ensayos_catalogo WHERE es_paquete;
    SELECT COUNT(*) INTO v_comp FROM paquete_componentes;
    SELECT COUNT(*) INTO v_vinc FROM paquete_componentes WHERE ensayo_componente_id IS NOT NULL;
    SELECT COUNT(*) INTO v_hist FROM ensayo_acreditacion_historial;
    SELECT COUNT(*) INTO v_corr FROM correlativos WHERE ambito = 'ensayo';

    IF v_ens <> 87 OR v_paq <> 13 OR v_comp <> 119 OR v_vinc <> 74
       OR v_hist <> 87 OR v_corr <> 4 THEN
        RAISE EXCEPTION 'Seed incompleto: ensayos=% (87) paquetes=% (13) componentes=% (119) vinculados=% (74) historial=% (87) contadores=% (4)',
            v_ens, v_paq, v_comp, v_vinc, v_hist, v_corr;
    END IF;
    RAISE NOTICE 'Seed OK: % ensayos, % paquetes, % componentes (% amarrados), % filas de historial, % contadores',
        v_ens, v_paq, v_comp, v_vinc, v_hist, v_corr;
END
$verificar$;
