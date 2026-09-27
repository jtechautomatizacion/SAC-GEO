-- ============================================================================
-- GTQC — SUITE DE PRUEBAS FUNCIONALES DE LA BD  ·  v3.0
-- ============================================================================
-- Ejercita las reglas sobre datos reales: correlativos, snapshots, máquina de
-- estados, acreditación con historial, congelado de documentos emitidos,
-- aislamiento empresa/contacto y auditoría con usuario real.
--
-- Uso:   psql -d gtqc_v3 -f 98_pruebas.sql
-- Cada control imprime PASS o FAIL. No debe quedar ningún FAIL.
-- ============================================================================

\set QUIET on
SET client_min_messages = NOTICE;

CREATE OR REPLACE FUNCTION t_ok(p_cond BOOLEAN, p_msg TEXT) RETURNS VOID AS $$
BEGIN
    IF p_cond THEN RAISE NOTICE 'PASS  %', p_msg;
    ELSE           RAISE WARNING 'FAIL  %', p_msg; END IF;
END; $$ LANGUAGE plpgsql;

-- Comprueba que una operación PROHIBIDA efectivamente se bloquea.
CREATE OR REPLACE FUNCTION t_bloquea(p_sql TEXT, p_msg TEXT) RETURNS VOID AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE WARNING 'FAIL  % — la BD lo permitió', p_msg;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS  % — bloqueado: %', p_msg, left(replace(SQLERRM, E'\n', ' '), 70);
    END;
END; $$ LANGUAGE plpgsql;


DO $pruebas$
DECLARE
    v_emp1 INT; v_emp2 INT; v_ct1 INT; v_ct2 INT; v_ct_otra INT; v_per INT;
    v_user2 INT; v_plant INT;
    v_cot1 INT; v_cot2 INT; v_num1 VARCHAR; v_num2 VARCHAR;
    v_su02 INT; v_su08 INT; v_su20 INT; v_ag01 INT; v_nuevo VARCHAR; v_nuevo2 VARCHAR; v_nid INT;
    v_t NUMERIC; v_x INT; v_txt TEXT; v_b BOOLEAN;
BEGIN
    RAISE NOTICE '--- 0. Preparación ------------------------------------------';
    PERFORM set_config('app.usuario_id', '1', FALSE);

    INSERT INTO usuarios (nombres, apellidos, email, rol_id, creado_por)
    VALUES ('Ana', 'Quispe', 'ana@gtqc.pe', 2, 1) RETURNING id INTO v_user2;

    INSERT INTO empresas (ruc, razon_social, telefono, email, creado_por) VALUES
        ('20123456789', 'Constructora ALDEM S.A.C.', '987654321', 'obras@aldem.pe', 1)
        RETURNING id INTO v_emp1;
    INSERT INTO empresas (ruc, razon_social, creado_por) VALUES
        ('20987654321', 'Minera Cerro Pasco S.A.', 1) RETURNING id INTO v_emp2;

    INSERT INTO contactos (empresa_id, dni, nombres, apellidos, cargo, email, creado_por)
    VALUES (v_emp1, '45678912', 'Luis', 'Ramírez', 'Jefe de obra', 'luis@aldem.pe', 1)
        RETURNING id INTO v_ct1;
    INSERT INTO contactos (empresa_id, nombres, apellidos, cargo, creado_por)
    VALUES (v_emp1, 'Marta', 'Flores', 'Compras', 1) RETURNING id INTO v_ct2;
    INSERT INTO contactos (empresa_id, nombres, apellidos, creado_por)
    VALUES (v_emp2, 'Jorge', 'Núñez', 1) RETURNING id INTO v_ct_otra;

    INSERT INTO personas (dni, nombres, apellidos, celular, creado_por)
    VALUES ('10203040', 'Carmen', 'Aliaga', '999888777', 1) RETURNING id INTO v_per;

    SELECT id INTO v_plant FROM plantillas_cotizacion WHERE slug = 'estandar';
    SELECT id INTO v_su02 FROM ensayos_catalogo WHERE codigo = 'SU-02';
    SELECT id INTO v_su08 FROM ensayos_catalogo WHERE codigo = 'SU-08';
    SELECT id INTO v_su20 FROM ensayos_catalogo WHERE codigo = 'SU-20';   -- paquete
    SELECT id INTO v_ag01 FROM ensayos_catalogo WHERE codigo = 'AG-01';

    RAISE NOTICE '--- 1. Validación de formato en la propia BD ----------------';
    PERFORM t_bloquea(format('INSERT INTO empresas (ruc, razon_social, creado_por) VALUES (%L, %L, 1)',
                             '12345', 'RUC corto S.A.'), 'RUC con formato inválido');
    PERFORM t_bloquea(format('INSERT INTO personas (dni, nombres, apellidos, creado_por) VALUES (%L, %L, %L, 1)',
                             'ABC12345', 'X', 'Y'), 'DNI no numérico');
    PERFORM t_bloquea(format('INSERT INTO empresas (ruc, razon_social, email, creado_por) VALUES (%L, %L, %L, 1)',
                             '20111111111', 'Mail malo S.A.', 'no-es-un-correo'), 'Email sin formato');
    PERFORM t_bloquea(format('UPDATE ensayos_catalogo SET precio_base = -50 WHERE id = %s', v_su02),
                      'Precio negativo');

    RAISE NOTICE '--- 2. Correlativo de cotización (atómico, sin MAX+1) -------';
    SELECT c.numero, c.cotizacion_id INTO v_num1, v_cot1
      FROM fn_crear_cotizacion(v_emp1, v_ct1, NULL, 'Vivienda multifamiliar - Surco',
             v_plant,
             jsonb_build_array(
                jsonb_build_object('ensayo_id', v_su02, 'cantidad', 4),
                jsonb_build_object('ensayo_id', v_su08, 'cantidad', 1),
                jsonb_build_object('ensayo_id', v_su20, 'cantidad', 2))) c;
    SELECT c.numero, c.cotizacion_id INTO v_num2, v_cot2
      FROM fn_crear_cotizacion(NULL, NULL, v_per, 'Ampliación de vivienda', v_plant,
             jsonb_build_array(jsonb_build_object('ensayo_id', v_ag01, 'cantidad', 3))) c;

    PERFORM t_ok(v_num1 = 'COT-' || EXTRACT(YEAR FROM fn_hoy_lima())::TEXT || '-001',
                 'primera cotización numerada ' || v_num1);
    PERFORM t_ok(v_num2 LIKE '%-002', 'segunda cotización numerada ' || v_num2);
    PERFORM t_ok((SELECT ultimo FROM correlativos WHERE ambito='cotizacion') = 2,
                 'el contador quedó en 2');
    PERFORM t_ok(fn_siguiente_numero_cotizacion(2031) = 'COT-2031-001',
                 'la serie se reinicia por año (COT-2031-001)');

    RAISE NOTICE '--- 3. Aritmética del documento ------------------------------';
    SELECT total INTO v_t FROM cotizaciones WHERE id = v_cot1;
    PERFORM t_ok(v_t = (SELECT round(SUM(subtotal) * 1.18, 2) FROM cotizacion_items WHERE cotizacion_id = v_cot1),
                 'total = suma de ítems + IGV 18% (S/ ' || v_t || ')');
    PERFORM t_bloquea(format('UPDATE cotizacion_items SET subtotal = 1 WHERE cotizacion_id = %s', v_cot1),
                      'subtotal de ítem que no es cantidad x precio');

    RAISE NOTICE '--- 4. Snapshot: el pasado no se mueve ----------------------';
    SELECT componentes_snapshot::TEXT INTO v_txt FROM cotizacion_items
     WHERE cotizacion_id = v_cot1 AND es_paquete_snapshot;
    PERFORM t_ok(v_txt LIKE '%SU-01%' AND v_txt LIKE '%SU-03%',
                 'el ítem-paquete guardó la foto de sus componentes con código');
    PERFORM t_ok((SELECT jsonb_array_length(componentes_snapshot) FROM cotizacion_items
                   WHERE cotizacion_id = v_cot1 AND es_paquete_snapshot) =
                 (SELECT COUNT(*) FROM paquete_componentes WHERE ensayo_id = v_su20),
                 'la foto tiene tantos componentes como el paquete ese día');
    PERFORM t_ok((SELECT COUNT(*) FROM cotizacion_items
                   WHERE cotizacion_id = v_cot1 AND categoria_snapshot = 'Suelos') = 3,
                 'los 3 ítems congelaron su categoría');

    -- Se corrige el catálogo DESPUÉS de emitir
    UPDATE ensayos_catalogo SET precio_base = 999.00, norma = 'ASTM D2216-XX' WHERE id = v_su02;
    PERFORM t_ok((SELECT precio_unitario FROM cotizacion_items
                   WHERE cotizacion_id = v_cot1 AND ensayo_id = v_su02) = 12.00,
                 'la cotización emitida conserva su precio (S/ 12) tras cambiar el catálogo');
    PERFORM t_ok((SELECT norma_snapshot FROM cotizacion_items
                   WHERE cotizacion_id = v_cot1 AND ensayo_id = v_su02) = 'ASTM D2216',
                 'la cotización emitida conserva su norma histórica');
    PERFORM t_ok((SELECT norma FROM vw_paquete_detalle
                   WHERE paquete_codigo = 'SU-20' AND componente_codigo = 'SU-02') = 'ASTM D2216-XX',
                 'el paquete VIVO sí ve la norma corregida (una sola fuente de verdad)');
    UPDATE ensayos_catalogo SET precio_base = 12.00, norma = 'ASTM D2216' WHERE id = v_su02;

    RAISE NOTICE '--- 5. Documento emitido = congelado ------------------------';
    PERFORM t_bloquea(format('UPDATE cotizaciones SET subtotal = 1, igv = 0.18, total = 1.18 WHERE id = %s', v_cot1),
                      'cambiar importes de una cotización emitida');
    PERFORM t_bloquea(format('UPDATE cotizaciones SET empresa_id = %s WHERE id = %s', v_emp2, v_cot1),
                      'cambiar el cliente de una cotización emitida');
    PERFORM t_bloquea(format('INSERT INTO cotizacion_items (cotizacion_id, orden, codigo_snapshot, nombre_snapshot, categoria_snapshot, acreditado_snapshot, cantidad, precio_unitario, subtotal) VALUES (%s, 99, ''X-01'', ''Colado'', ''Suelos'', FALSE, 1, 10, 10)', v_cot1),
                      'agregar un ítem a una cotización emitida');
    PERFORM t_bloquea(format('DELETE FROM cotizaciones WHERE id = %s', v_cot1),
                      'eliminar una cotización');
    PERFORM t_bloquea(format('UPDATE cotizaciones SET numero = ''COT-2026-999'' WHERE id = %s', v_cot1),
                      'renumerar una cotización ya emitida');

    RAISE NOTICE '--- 6. Máquina de estados ----------------------------------';
    PERFORM fn_cambiar_estado_cotizacion(v_cot1, 'aceptada', 'Orden de compra 4471');
    PERFORM t_ok((SELECT estado FROM cotizaciones WHERE id = v_cot1) = 'aceptada', 'emitida → aceptada');
    PERFORM t_ok((SELECT COUNT(*) FROM cotizacion_historial_estados WHERE cotizacion_id = v_cot1) = 3,
                 'el historial registró borrador → emitida → aceptada');
    PERFORM t_ok((SELECT nota FROM cotizacion_historial_estados
                   WHERE cotizacion_id = v_cot1 ORDER BY id DESC LIMIT 1) = 'Orden de compra 4471',
                 'el historial guardó la nota del cambio');
    PERFORM t_bloquea(format('SELECT fn_cambiar_estado_cotizacion(%s, ''emitida'')', v_cot1),
                      'aceptada → emitida (estado terminal)');
    PERFORM t_bloquea(format('UPDATE cotizaciones SET estado = ''emitida'' WHERE id = %s', v_cot1),
                      'saltarse la máquina de estados con UPDATE directo');
    PERFORM t_bloquea('UPDATE cotizacion_historial_estados SET estado = ''rechazada'' WHERE id = 1',
                      'reescribir el historial de estados');

    RAISE NOTICE '--- 7. Aislamiento empresa / contacto ----------------------';
    PERFORM t_bloquea(format('SELECT fn_crear_cotizacion(%s, %s, NULL, ''Cruzada'', %s, ''[{"ensayo_id":%s,"cantidad":1}]''::jsonb)',
                             v_emp1, v_ct_otra, v_plant, v_su02),
                      'cotización de la Empresa A con el contacto de la Empresa B');
    PERFORM t_bloquea(format('SELECT fn_crear_cotizacion(NULL, %s, %s, ''Mixta'', %s, ''[{"ensayo_id":%s,"cantidad":1}]''::jsonb)',
                             v_ct1, v_per, v_plant, v_su02),
                      'persona natural con contacto de empresa');
    PERFORM t_bloquea(format('SELECT fn_crear_cotizacion(%s, NULL, %s, ''Dos clientes'', %s, ''[{"ensayo_id":%s,"cantidad":1}]''::jsonb)',
                             v_emp1, v_per, v_plant, v_su02),
                      'cotización con empresa Y persona a la vez');

    RAISE NOTICE '--- 8. Acreditación con historial (ISO 17025) --------------';
    PERFORM t_bloquea(format('UPDATE ensayos_catalogo SET acreditado = FALSE WHERE id = %s', v_su02),
                      'cambiar la acreditación con UPDATE directo');
    PERFORM fn_cambiar_acreditacion(v_su02, FALSE, 'Alcance retirado por INACAL', DATE '2026-06-01', v_user2);
    PERFORM t_ok((SELECT acreditado FROM ensayos_catalogo WHERE id = v_su02) = FALSE,
                 'fn_cambiar_acreditacion movió el estado actual');
    PERFORM t_ok(fn_acreditado_en_fecha(v_su02, DATE '2026-03-15') = TRUE,
                 'reconstrucción histórica: SU-02 estaba acreditado el 15/03/2026');
    PERFORM t_ok(fn_acreditado_en_fecha(v_su02, DATE '2026-08-15') = FALSE,
                 'reconstrucción histórica: ya no lo estaba el 15/08/2026');
    PERFORM t_ok((SELECT acreditado_snapshot FROM cotizacion_items
                   WHERE cotizacion_id = v_cot1 AND ensayo_id = v_su02) = TRUE,
                 'la cotización emitida sigue diciendo "acreditado" (era cierto ese día)');
    PERFORM t_bloquea('UPDATE ensayo_acreditacion_historial SET acreditado = TRUE WHERE id = 1',
                      'reescribir el historial de acreditación');

    RAISE NOTICE '--- 9. Borrado: lo que tiene historia no se borra ----------';
    PERFORM t_bloquea(format('DELETE FROM ensayos_catalogo WHERE id = %s', v_su02),
                      'eliminar un ensayo ya cotizado');
    PERFORM t_bloquea('DELETE FROM ensayos_catalogo WHERE codigo = ''SU-03''',
                      'eliminar un ensayo que es componente de un paquete');
    PERFORM t_bloquea('DELETE FROM categorias_ensayo WHERE slug = ''suelos''',
                      'eliminar una categoría con ensayos');
    PERFORM t_bloquea('DELETE FROM subcategorias_ensayo WHERE nombre = ''Paquetes'' AND categoria_id = (SELECT id FROM categorias_ensayo WHERE slug=''suelos'')',
                      'eliminar una subcategoría con ensayos');
    PERFORM t_bloquea(format('DELETE FROM usuarios WHERE id = %s', v_user2),
                      'eliminar un usuario referenciado por la auditoría');
    PERFORM t_bloquea('DELETE FROM roles WHERE codigo = ''admin''', 'eliminar un rol del sistema');

    RAISE NOTICE '--- 10. Códigos de ensayo: no se reutilizan ----------------';
    v_nuevo := fn_crear_ensayo(
        (SELECT se.id FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
          WHERE ce.slug='suelos' AND se.nombre='Campo'),
        'Ensayo de penetración estándar (SPT)', 'ASTM D1586', 'UND', 180, TRUE, v_user2);
    PERFORM t_ok(v_nuevo = 'SU-29', 'ensayo nuevo tomó SU-29 (el catálogo llegaba a SU-28)');
    SELECT id INTO v_nid FROM ensayos_catalogo WHERE codigo = v_nuevo;
    DELETE FROM ensayos_catalogo WHERE id = v_nid;
    PERFORM t_ok(NOT EXISTS (SELECT 1 FROM ensayos_catalogo WHERE codigo = 'SU-29'),
                 'un ensayo sin uso sí se puede eliminar');
    v_nuevo2 := fn_crear_ensayo(
        (SELECT se.id FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
          WHERE ce.slug='suelos' AND se.nombre='Campo'),
        'Veleta de campo', 'ASTM D2573', 'UND', 90, FALSE, v_user2);
    PERFORM t_ok(v_nuevo2 = 'SU-30',
                 'el código eliminado NO se reutiliza: el siguiente es SU-30, no SU-29');

    RAISE NOTICE '--- 11. Paquetes: reglas P1–P5 ------------------------------';
    PERFORM t_bloquea(format('SELECT fn_crear_paquete(
            (SELECT se.id FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id=se.categoria_id
              WHERE ce.slug=''suelos'' AND se.nombre=''Paquetes''),
            ''Paquete de uno'', ''UND'', 100, FALSE, ''[{"ensayo_id":%s,"cantidad":1}]''::jsonb, 1)', v_su02),
        'paquete con un solo componente (P4)');
    PERFORM t_bloquea(format('SELECT fn_crear_paquete(
            (SELECT se.id FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id=se.categoria_id
              WHERE ce.slug=''suelos'' AND se.nombre=''Paquetes''),
            ''Paquete anidado'', ''UND'', 100, FALSE, ''[{"ensayo_id":%s,"cantidad":1},{"ensayo_id":%s,"cantidad":1}]''::jsonb, 1)',
            v_su20, v_su02),
        'paquete que incluye otro paquete (P2)');
    v_nuevo := fn_crear_paquete(
        (SELECT se.id FROM subcategorias_ensayo se JOIN categorias_ensayo ce ON ce.id = se.categoria_id
          WHERE ce.slug='suelos' AND se.nombre='Paquetes'),
        'Paquete Geotecnia básica', 'UND', 180, FALSE,
        jsonb_build_array(jsonb_build_object('ensayo_id', v_su02, 'cantidad', 3),
                          jsonb_build_object('ensayo_id', v_su08, 'cantidad', 1),
                          jsonb_build_object('ensayo_id', v_ag01, 'cantidad', 1)),
        v_user2);
    PERFORM t_ok((SELECT componentes FROM vw_paquetes_resumen WHERE codigo = v_nuevo) = 3,
                 'paquete ' || v_nuevo || ' creado con 3 componentes amarrados');
    PERFORM t_ok((SELECT ahorro_pct FROM vw_paquetes_resumen WHERE codigo = v_nuevo) > 0,
                 'el paquete ahorra frente a comprar los ensayos por separado');
    PERFORM t_ok(EXISTS (SELECT 1 FROM vw_paquete_detalle
                          WHERE paquete_codigo = v_nuevo AND componente_codigo = 'AG-01'),
                 'P5: un paquete de Suelos puede incluir un ensayo de Concreto');

    RAISE NOTICE '--- 12. Auditoría: quién, qué y cuándo ---------------------';
    PERFORM set_config('app.usuario_id', v_user2::TEXT, FALSE);
    PERFORM set_config('app.ip_origen', '190.234.1.77', FALSE);
    SELECT precio_base INTO v_t FROM ensayos_catalogo WHERE id = v_su08;   -- precio antes del cambio
    UPDATE ensayos_catalogo SET precio_base = 45.00 WHERE id = v_su08;
    SELECT usuario_id INTO v_x FROM auditoria
     WHERE tabla='ensayos_catalogo' AND registro_id = v_su08 AND accion='UPDATE'
     ORDER BY id DESC LIMIT 1;
    PERFORM t_ok(v_x = v_user2, 'el cambio de precio quedó a nombre del usuario real, no del creador');
    SELECT array_to_string(campos_cambiados, ',') INTO v_txt FROM auditoria
     WHERE tabla='ensayos_catalogo' AND registro_id = v_su08 AND accion='UPDATE'
     ORDER BY id DESC LIMIT 1;
    PERFORM t_ok(v_txt LIKE '%precio_base%', 'la auditoría dice qué campo cambió: ' || v_txt);
    PERFORM t_ok((SELECT ip_origen FROM auditoria ORDER BY id DESC LIMIT 1) = '190.234.1.77',
                 'la auditoría registró la IP de origen');
    PERFORM t_ok((SELECT (datos_anteriores->>'precio_base')::NUMERIC FROM auditoria
                   WHERE tabla='ensayos_catalogo' AND registro_id = v_su08 AND accion='UPDATE'
                   ORDER BY id DESC LIMIT 1) = v_t,
                 'la auditoría guardó el valor anterior (S/ ' || v_t || ')');
    PERFORM t_bloquea('UPDATE auditoria SET usuario_id = 1 WHERE id = 1', 'modificar la auditoría');
    PERFORM t_bloquea('DELETE FROM auditoria WHERE id = 1', 'eliminar una fila de auditoría');
    PERFORM t_bloquea('SELECT fn_purgar_auditoria(fn_hoy_lima())', 'purgar auditoría reciente (< 365 días)');

    RAISE NOTICE '--- 13. Catálogo: R2, R4, R5 ------------------------------';
    PERFORM set_config('app.usuario_id', '1', FALSE);
    PERFORM t_bloquea('UPDATE categorias_ensayo SET prefijo_codigo = ''XX'' WHERE slug = ''suelos''',
                      'cambiar el prefijo de una categoría con ensayos (R4)');
    PERFORM t_bloquea('INSERT INTO categorias_ensayo (slug, nombre, prefijo_codigo, creado_por) VALUES (''suelos2'', ''SUELOS'', ''SX'', 1)',
                      'categoría con nombre duplicado ignorando mayúsculas (R5)');
    PERFORM t_bloquea('INSERT INTO ensayos_catalogo (codigo, categoria_id, subcategoria_id, nombre, precio_base, creado_por)
                       SELECT ''ZZ-01'', ce.id, se.id, ''Código ajeno'', 10, 1
                         FROM categorias_ensayo ce JOIN subcategorias_ensayo se ON se.categoria_id = ce.id
                        WHERE ce.slug = ''suelos'' LIMIT 1',
                      'ensayo con código que no respeta el prefijo de su categoría (R4)');
    v_x := fn_crear_categoria('Geotecnia', 'GE', '🧪', '#16a34a', 1);
    PERFORM t_ok((SELECT COUNT(*) FROM subcategorias_ensayo WHERE categoria_id = v_x AND nombre='General') = 1,
                 'R2: la categoría nueva nace con su subcategoría "General"');
    PERFORM t_bloquea(format('UPDATE subcategorias_ensayo SET activo = FALSE WHERE categoria_id = %s', v_x),
                      'desactivar la única subcategoría activa de su categoría (R2)');

    RAISE NOTICE '--- 14. Dashboard por periodo -----------------------------';
    PERFORM t_ok((SELECT total_cotizaciones FROM fn_dashboard_kpis(NULL, NULL)) = 2,
                 'KPIs cuentan 2 cotizaciones emitidas');
    PERFORM t_ok((SELECT valor_aceptado FROM fn_dashboard_kpis(NULL, NULL)) > 0,
                 'KPIs separan el monto aceptado');
    PERFORM t_ok((SELECT COUNT(*) FROM fn_dashboard_kpis(DATE '2000-01-01', DATE '2000-12-31')
                   WHERE total_cotizaciones = 0) = 1,
                 'el filtro de fechas realmente excluye (rango sin datos → 0)');
    PERFORM t_ok((SELECT monto FROM fn_dashboard_por_categoria(NULL, NULL) WHERE categoria_slug='suelos') > 0,
                 'resumen por categoría suma Suelos');
    PERFORM t_ok((SELECT COUNT(*) FROM fn_dashboard_top_clientes(NULL, NULL)) = 2,
                 'top clientes lista empresa y persona natural');
    PERFORM t_ok((SELECT items IS NOT NULL FROM vw_cotizacion_pdf WHERE id = v_cot1),
                 'vw_cotizacion_pdf entrega la cotización completa desde el snapshot');

    RAISE NOTICE '--- 15. Documentos: local y nube --------------------------';
    PERFORM t_bloquea(format('INSERT INTO documentos_externos (cotizacion_id, origen, nombre_archivo, subido_por) VALUES (%s, ''nube'', ''x.pdf'', 1)', v_cot1),
                      'documento en nube sin integración ni URL');
    INSERT INTO documentos_externos (cotizacion_id, origen, tipo_documento, nombre_archivo, subido_por)
    VALUES (v_cot1, 'local', 'cotizacion_pdf', v_num1 || '.pdf', 1);
    PERFORM t_ok((SELECT COUNT(*) FROM documentos_externos WHERE cotizacion_id = v_cot1) = 1,
                 'el PDF local sí se puede registrar (en v2 exigía una nube conectada)');
    INSERT INTO integraciones (titular, proveedor, cuenta_email, token_ref, conectado_por)
    VALUES ('laboratorio', 'google_drive', 'docs@gtqc.pe', 'vault://gtqc/gdrive#v1', 1);
    PERFORM t_ok((SELECT COUNT(*) FROM integraciones WHERE empresa_id IS NULL) = 1,
                 'la nube propia del laboratorio no necesita una empresa cliente');

    RAISE NOTICE '--- FIN ---------------------------------------------------';
END
$pruebas$;

DROP FUNCTION t_ok(BOOLEAN, TEXT);
DROP FUNCTION t_bloquea(TEXT, TEXT);
