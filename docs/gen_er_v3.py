# Genera el diagrama Entidad-Relación de GTQC v3 como SVG dentro de un HTML,
# para renderizarlo después a PNG/PDF con Playwright (render_er.js).
#
# Novedades frente al diagrama de v2:
#   · badge G / T / H en cada tabla: GLOBAL, TENANT-SCOPED, HÍBRIDA
#   · se muestran los identificadores públicos (UUID) y los códigos de negocio
#     como cosas distintas del id técnico
#   · aparece la tabla `correlativos`
#   · se marcan las tablas APPEND-ONLY y las relaciones de pertenencia
from html import escape

W = 300
HEAD = 52
ROW = 22
PAD = 10

ZONES = {
    'cli':  dict(name='👥 CLIENTES',                   fill='#eff6ff', stroke='#bfdbfe', head='#1d4ed8'),
    'cot':  dict(name='📋 COTIZACIONES',               fill='#f5f3ff', stroke='#ddd6fe', head='#6d28d9'),
    'cat':  dict(name='🧪 CATÁLOGO DE ENSAYOS  ·  ✏️ editable desde la app', fill='#fff7ed', stroke='#fed7aa', head='#c2410c'),
    'nube': dict(name='☁️ NUBE (Drive / Office 365)',  fill='#ecfeff', stroke='#a5f3fc', head='#0e7490'),
    'seg':  dict(name='🔒 SEGURIDAD Y AUDITORÍA',      fill='#f1f5f9', stroke='#cbd5e1', head='#334155'),
}

# ámbito: 'T' tenant-scoped · 'G' global · 'H' híbrida
# tipo de campo: 'pk' id técnico · 'uuid' id público · 'cod' código de negocio
#                'fk' relación · 'date' fecha de negocio · '' dato normal
T = [
  ('empresas', 'cli', 'T', 70, 190, '🏢 Empresas', 'empresas', [
     ('id','pk','id técnico (interno)'), ('public_id','uuid','id público (API / URL)'),
     ('ruc','cod','RUC — único por tenant'), ('razon_social','','nombre legal'),
     ('activo','','baja lógica, nunca DELETE')]),
  ('contactos', 'cli', 'T', 70, 440, '🧑‍💼 Contactos', 'contactos', [
     ('id','pk','id técnico'), ('public_id','uuid','id público'),
     ('empresa_id','fk','→ empresa (dueña)'), ('dni','','DNI, único en su empresa'),
     ('nombres','','nombre y apellidos'), ('cargo','','ej. Jefe de obra'),
     ('activo','','baja lógica')]),
  ('personas', 'cli', 'T', 70, 680, '🙋 Personas naturales', 'personas', [
     ('id','pk','id técnico'), ('public_id','uuid','id público'),
     ('dni','cod','DNI — único por tenant'), ('nombres','','nombre y apellidos'),
     ('celular / email','','datos de contacto'), ('activo','','baja lógica')]),

  ('plantillas', 'cot', 'H', 470, 190, '🧾 Plantillas', 'plantillas_cotizacion', [
     ('id','pk','id técnico'), ('public_id','uuid','id público'),
     ('slug','cod','estandar / premium / express'), ('validez_dias_sugerida','','validez por defecto'),
     ('terminos_condiciones','','texto del PDF'), ('activo','','máximo 3 activas')]),
  ('cotizaciones', 'cot', 'T', 470, 460, '📄 Cotizaciones', 'cotizaciones', [
     ('id','pk','id técnico (nunca en la URL)'), ('public_id','uuid','id público (URL y QR)'),
     ('numero','cod','COT-2026-001 — lo emite la BD'), ('fecha_emision','date','fecha real (hora de Lima)'),
     ('empresa_id','fk','→ empresa  (o persona)'), ('contacto_id','fk','→ contacto DE esa empresa'),
     ('persona_id','fk','→ persona  (o empresa)'), ('plantilla_id','fk','→ plantilla'),
     ('proyecto_nombre','','nombre del proyecto'), ('subtotal / igv / total','','cuadrado por CHECK'),
     ('igv_tasa','','la tasa viaja con el documento'), ('estado','','borrador→emitida→aceptada…')]),
  ('items', 'cot', 'T', 850, 460, '🧪 Ensayos cotizados  📌', 'cotizacion_items', [
     ('id','pk','id técnico'), ('cotizacion_id','fk','→ cotización'), ('orden','','orden en el PDF'),
     ('ensayo_id','fk','→ ensayo (solo informativo)'), ('categoria_id','fk','→ categoría congelada'),
     ('codigo / nombre / norma','','FOTO del catálogo'), ('unidad / categoría','','FOTO del catálogo'),
     ('acreditado_snapshot','','acreditación ese día'), ('acreditado_override','','corregido a mano'),
     ('cantidad / precio','','lo que se cobró'), ('componentes_snapshot','','FOTO del paquete')]),
  ('historial', 'cot', 'T', 850, 790, '🕒 Historial de estados  🔒', 'cotizacion_historial_estados', [
     ('id','pk','id técnico'), ('cotizacion_id','fk','→ cotización'),
     ('estado_anterior','','de dónde venía'), ('estado','','a dónde fue'),
     ('nota','','ej. Orden de compra 4471'), ('registrado_por','fk','→ usuario')]),

  ('ensayos', 'cat', 'T', 1250, 190, '🔬 Ensayos (catálogo)', 'ensayos_catalogo', [
     ('id','pk','id técnico'), ('public_id','uuid','id público'),
     ('codigo','cod','SU-01 — prefijo + correlativo'), ('categoria_id','fk','→ categoría'),
     ('subcategoria_id','fk','→ subcategoría'), ('nombre / norma','','ej. ASTM D2216'),
     ('unidad','','UND, PUNT., DÍA…'), ('precio_base','','precio de lista S/'),
     ('acreditado','','estado ACTUAL (INACAL)'), ('es_paquete','','agrupa varios ensayos'),
     ('activo','','desactivar ≠ borrar')]),
  ('categorias', 'cat', 'T', 1620, 190, '🗂️ Categorías  ✏️', 'categorias_ensayo', [
     ('id','pk','id técnico'), ('public_id','uuid','id público'),
     ('slug','cod','suelos, concreto…'), ('nombre','','único (sin mayúsculas)'),
     ('prefijo_codigo','cod','SU, AG — fijo con ensayos'), ('color / icono','','cómo se ve en la app'),
     ('orden','','orden de pestañas'), ('activo','','desactivar ≠ borrar')]),
  ('subcategorias', 'cat', 'T', 1620, 460, '📂 Subcategorías  ✏️', 'subcategorias_ensayo', [
     ('id','pk','id técnico'), ('public_id','uuid','id público'),
     ('categoria_id','fk','→ categoría'), ('nombre','','único en su categoría'),
     ('orden','','orden de los filtros'), ('activo','','desactivar ≠ borrar')]),
  ('acred', 'cat', 'T', 1250, 530, '✅ Historial de acreditación  🔒', 'ensayo_acreditacion_historial', [
     ('id','pk','id técnico'), ('ensayo_id','fk','→ ensayo'),
     ('acreditado','','ganó / perdió el alcance'), ('motivo','','ej. Renovación INACAL'),
     ('vigente_desde','date','una fila por ensayo y día'), ('registrado_por','fk','→ usuario')]),
  ('paquete', 'cat', 'T', 1620, 700, '📦 Ensayos de cada paquete', 'paquete_componentes', [
     ('id','pk','id técnico'), ('ensayo_id','fk','→ el paquete'),
     ('ensayo_componente_id','fk','→ ensayo incluido'), ('cantidad','','ej. 18 briquetas'),
     ('orden','','orden dentro del paquete'), ('nombre / norma','','solo si no está vinculado')]),
  ('correlativos', 'cat', 'T', 1250, 780, '🔢 Correlativos', 'correlativos', [
     ('ambito','pk','cotizacion / ensayo'), ('clave','pk','GLOBAL o prefijo (SU)'),
     ('periodo','pk','año, para reiniciar la serie'), ('ultimo','','contador atómico, sin MAX+1')]),

  ('integraciones', 'nube', 'T', 70, 960, '🔗 Integraciones', 'integraciones', [
     ('id','pk','id técnico'), ('public_id','uuid','id público'),
     ('titular','','laboratorio / cliente'), ('empresa_id','fk','→ empresa (NULL = propia)'),
     ('proveedor','','Google Drive / Office 365'), ('token_ref','','referencia al vault, NO el token'),
     ('estado','','activa / revocada / expirada')]),
  ('documentos', 'nube', 'T', 470, 960, '📁 Documentos emitidos', 'documentos_externos', [
     ('id','pk','id técnico'), ('public_id','uuid','id público'),
     ('cotizacion_id','fk','→ cotización'), ('origen','','local o nube'),
     ('integracion_id','fk','→ integración (si es nube)'), ('tipo_documento','','PDF, certificado, O/C'),
     ('nombre_archivo','','nombre del archivo'), ('hash_sha256','','huella del archivo')]),

  ('auditoria', 'seg', 'T', 850, 1060, '🛡️ Auditoría  🔒', 'auditoria', [
     ('id','pk','id técnico'), ('tabla / registro_id','','qué se tocó'),
     ('registro_public_id','uuid','rastreo desde la API'), ('accion','','INSERT / UPDATE / DELETE'),
     ('campos_cambiados','','qué campos exactamente'), ('datos_anteriores','','cómo estaba'),
     ('datos_nuevos','','cómo quedó'), ('usuario_id','fk','→ usuario real (de la sesión)'),
     ('ip_origen','','desde dónde')]),
  ('usuarios', 'seg', 'T', 1250, 1060, '👤 Usuarios', 'usuarios', [
     ('id','pk','id técnico'), ('public_id','uuid','id público'),
     ('nombres','','nombre y apellidos'), ('email','cod','acceso, único en el sistema'),
     ('rol_id','fk','→ rol'), ('password_hash','','SOLO hash, nunca la clave'),
     ('ultimo_acceso_en','','preparado para el login'), ('activo','','no se elimina, se desactiva')]),
  ('roles', 'seg', 'G', 1620, 1060, '🎫 Roles', 'roles', [
     ('id','pk','id técnico'), ('codigo','cod','admin, comercial,'),
     ('','','laboratorio, lectura'), ('nombre','','etiqueta para la interfaz'),
     ('es_sistema','','rol base: no se elimina')]),
]

box = {}
for key, zone, ambito, x, y, title, sql, fields in T:
    h = HEAD + len(fields) * ROW + PAD
    box[key] = dict(zone=zone, ambito=ambito, x=x, y=y, w=W, h=h,
                    title=title, sql=sql, fields=fields)


def anchor(k, side, frac=0.5):
    b = box[k]
    if side == 'l': return (b['x'], b['y'] + b['h'] * frac)
    if side == 'r': return (b['x'] + b['w'], b['y'] + b['h'] * frac)
    if side == 't': return (b['x'] + b['w'] * frac, b['y'])
    if side == 'b': return (b['x'] + b['w'] * frac, b['y'] + b['h'])


def field_y(k, name):
    b = box[k]
    for i, f in enumerate(b['fields']):
        if f[0] == name:
            return b['y'] + HEAD + i * ROW + ROW / 2 + 2
    raise KeyError(f'{k}.{name}')


E = []
def rel(one, many, label, pts, lpos=None, dash=None):
    E.append(dict(one=one, many=many, label=label, pts=pts, lpos=lpos, dash=dash))

c = box['cotizaciones']
y_emp = field_y('cotizaciones', 'empresa_id')
y_con = field_y('cotizaciones', 'contacto_id')
y_per = field_y('cotizaciones', 'persona_id')
y_pla = field_y('cotizaciones', 'plantilla_id')

# Clientes → Cotizaciones
a = anchor('empresas', 'r', 0.55)
rel('empresas', 'cotizaciones', 'pide', [a, (425, a[1]), (425, y_emp), (c['x'], y_emp)], (425, 300))
a = (box['contactos']['x'] + W, field_y('contactos', 'nombres'))
rel('contactos', 'cotizaciones', 'la recibe', [a, (405, a[1]), (405, y_con), (c['x'], y_con)], (405, 540))
a = anchor('personas', 'r', 0.35)
rel('personas', 'cotizaciones', 'pide', [a, (443, a[1]), (443, y_per), (c['x'], y_per)], (443, 690))
# Empresa → Contactos (pertenencia)
rel('empresas', 'contactos', 'tiene', [anchor('empresas', 'b', 0.45), anchor('contactos', 't', 0.45)])
# Empresa → Integraciones
a = anchor('empresas', 'l', 0.60); b2 = anchor('integraciones', 'l', 0.45)
rel('empresas', 'integraciones', 'conecta su nube', [a, (40, a[1]), (40, b2[1]), b2], (118, 908))
# Plantilla → Cotizaciones
rel('plantillas', 'cotizaciones', 'da formato', [anchor('plantillas', 'b', 0.45), anchor('cotizaciones', 't', 0.45)])
# Cotización → Items / Historial / Documentos
y_ci = field_y('items', 'cotizacion_id')
rel('cotizaciones', 'items', 'congela', [(c['x'] + W, y_ci), (box['items']['x'], y_ci)])
y_hi = field_y('historial', 'cotizacion_id')
a = anchor('cotizaciones', 'r', 0.93)
rel('cotizaciones', 'historial', 'registra', [a, (815, a[1]), (815, y_hi), (box['historial']['x'], y_hi)], (815, 790))
rel('cotizaciones', 'documentos', 'se archiva en', [anchor('cotizaciones', 'b', 0.55), anchor('documentos', 't', 0.55)])
y_di = field_y('documentos', 'integracion_id')
rel('integraciones', 'documentos', 'sube', [(box['integraciones']['x'] + W, y_di), (box['documentos']['x'], y_di)])
# Catálogo
y_ie = field_y('items', 'ensayo_id')
a = anchor('ensayos', 'l', 0.22)
rel('ensayos', 'items', 'se cotiza', [a, (1215, a[1]), (1215, y_ie), (box['items']['x'] + W, y_ie)], (1215, 330))
y_ic = field_y('items', 'categoria_id')
a = anchor('categorias', 'l', 0.92)
rel('categorias', 'items', 'clasifica', [a, (1195, a[1]), (1195, y_ic), (box['items']['x'] + W, y_ic)], (1195, 560))
rel('categorias', 'subcategorias', 'agrupa', [anchor('categorias', 'b', 0.5), anchor('subcategorias', 't', 0.5)])
y_es = field_y('ensayos', 'subcategoria_id')
a = anchor('subcategorias', 'l', 0.55)
rel('subcategorias', 'ensayos', 'contiene', [a, (1585, a[1]), (1585, y_es), (box['ensayos']['x'] + W, y_es)], (1585, 420))
rel('ensayos', 'acred', 'gana / pierde alcance', [anchor('ensayos', 'b', 0.42), anchor('acred', 't', 0.42)])
# Paquetes: el paquete (1) incluye N componentes; un ensayo (1) es parte de N paquetes
y_pq = field_y('paquete', 'ensayo_id'); y_pc = field_y('paquete', 'ensayo_componente_id')
eb = box['ensayos']
a = (eb['x'] + W, eb['y'] + eb['h'] - 46)
rel('ensayos', 'paquete', 'incluye', [a, (1596, a[1]), (1596, y_pq), (box['paquete']['x'], y_pq)], (1585, 702))
a = (eb['x'] + W, eb['y'] + eb['h'] - 20)
rel('ensayos', 'paquete', 'es parte', [a, (1572, a[1]), (1572, y_pc), (box['paquete']['x'], y_pc)], (1585, 655))
# Seguridad
y_ur = field_y('usuarios', 'rol_id')
a = anchor('roles', 'l', 0.5)
rel('roles', 'usuarios', 'asigna', [a, (1585, a[1]), (1585, y_ur), (box['usuarios']['x'] + W, y_ur)], (1585, 1120))
y_au = field_y('auditoria', 'usuario_id')
a = anchor('usuarios', 'l', 0.80)
rel('usuarios', 'auditoria', 'firma cada cambio', [a, (1215, a[1]), (1215, y_au), (box['auditoria']['x'] + W, y_au)], (1215, 1245))

CW, CH = 2010, 1400
out = []
o = out.append
o(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CW} {CH}" width="{CW}" height="{CH}" role="img" '
  'aria-label="Diagrama entidad-relación de la base de datos GTQC v3: clientes, cotizaciones, catálogo de ensayos, '
  'nube y seguridad, con el ámbito global o por tenant de cada tabla.">')
o('''<defs>
  <marker id="one" viewBox="0 0 12 12" refX="6" refY="6" markerWidth="12" markerHeight="12" orient="auto-start-reverse">
    <line x1="6" y1="1" x2="6" y2="11" stroke="#475569" stroke-width="1.8"/>
  </marker>
  <marker id="many" viewBox="0 0 16 16" refX="15" refY="8" markerWidth="16" markerHeight="16" orient="auto">
    <path d="M15,1 L3,8 L15,15 M3,8 L15,8" fill="none" stroke="#475569" stroke-width="1.8"/>
  </marker>
  <filter id="sh" x="-5%" y="-5%" width="110%" height="115%">
    <feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#0f172a" flood-opacity=".10"/></filter>
</defs>''')
o(f'<rect width="{CW}" height="{CH}" fill="#ffffff"/>')

for zk, z in ZONES.items():
    bs = [b for b in box.values() if b['zone'] == zk]
    x0 = min(b['x'] for b in bs) - 22; y0 = min(b['y'] for b in bs) - 50
    x1 = max(b['x'] + b['w'] for b in bs) + 22; y1 = max(b['y'] + b['h'] for b in bs) + 22
    o(f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" rx="18" fill="{z["fill"]}" '
      f'stroke="{z["stroke"]}" stroke-width="1.5"/>')
    o(f'<text x="{x0+18}" y="{y0+30}" font-size="15" font-weight="800" letter-spacing=".06em" '
      f'fill="{z["head"]}">{escape(z["name"])}</text>')

for e in E:
    d = 'M' + ' L'.join(f'{x:.1f},{y:.1f}' for x, y in e['pts'])
    o(f'<path d="{d}" fill="none" stroke="#475569" stroke-width="1.8" '
      f'marker-start="url(#one)" marker-end="url(#many)"/>')

AMB = {'T': ('#065f46', '#d1fae5', 'T'), 'G': ('#3730a3', '#e0e7ff', 'G'), 'H': ('#92400e', '#fef3c7', 'H')}
for k, b in box.items():
    z = ZONES[b['zone']]
    x, y, w, h = b['x'], b['y'], b['w'], b['h']
    o(f'<g filter="url(#sh)"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="#fff" '
      f'stroke="{z["stroke"]}" stroke-width="1.5"/></g>')
    o(f'<path d="M{x},{y+12} a12,12 0 0 1 12,-12 h{w-24} a12,12 0 0 1 12,12 v{HEAD-12} h-{w} z" fill="{z["head"]}"/>')
    o(f'<text x="{x+14}" y="{y+22}" font-size="15.5" font-weight="700" fill="#fff">{escape(b["title"])}</text>')
    o(f'<text x="{x+14}" y="{y+41}" font-size="11" fill="#fff" fill-opacity=".78" '
      f'font-family="DejaVu Sans Mono, monospace">{escape(b["sql"])}</text>')
    fg, bg, lb = AMB[b['ambito']]
    o(f'<rect x="{x+w-32}" y="{y+12}" width="22" height="22" rx="7" fill="{bg}"/>')
    o(f'<text x="{x+w-21}" y="{y+28}" font-size="13" font-weight="800" fill="{fg}" text-anchor="middle">{lb}</text>')
    for i, (name, kind, hint) in enumerate(b['fields']):
        fy = y + HEAD + i * ROW
        if i % 2 == 1:
            o(f'<rect x="{x+1.5}" y="{fy+2}" width="{w-3}" height="{ROW}" fill="#f8fafc"/>')
        ty = fy + ROW / 2 + 6
        icon = {'pk': '🔑', 'uuid': '🆔', 'cod': '🏷️', 'fk': '🔗', 'date': '📅'}.get(kind, '')
        col = {'pk': '#b45309', 'uuid': '#7c3aed', 'cod': '#be123c', 'fk': '#1d4ed8', 'date': '#047857'}.get(kind, '#0f172a')
        wt = '700' if kind else '500'
        if icon:
            o(f'<text x="{x+10}" y="{ty}" font-size="11.5">{icon}</text>')
        o(f'<text x="{x+30}" y="{ty}" font-size="11.5" font-weight="{wt}" fill="{col}" '
          f'font-family="DejaVu Sans Mono, monospace">{escape(name)}</text>')
        o(f'<text x="{x+w-10}" y="{ty}" font-size="11" fill="#64748b" text-anchor="end">{escape(hint)}</text>')

for e in E:
    if e['lpos']:
        lx, ly = e['lpos']
    else:
        (x1, y1), (x2, y2) = e['pts'][0], e['pts'][-1]
        lx, ly = (x1 + x2) / 2, (y1 + y2) / 2
    tw = len(e['label']) * 6.6 + 14
    o(f'<rect x="{lx-tw/2:.1f}" y="{ly-10:.1f}" width="{tw:.1f}" height="20" rx="10" fill="#fff" stroke="#cbd5e1"/>')
    o(f'<text x="{lx:.1f}" y="{ly+4:.1f}" font-size="11.5" font-style="italic" fill="#334155" '
      f'text-anchor="middle">{escape(e["label"])}</text>')

o('<text x="48" y="44" font-size="26" font-weight="800" fill="#0f172a">Base de datos GTQC v3 — Entidades y relaciones</text>')
o('<text x="48" y="70" font-size="13.5" fill="#475569">18 tablas en 5 áreas. Cada caja es una tabla; cada línea, '
  'una relación uno → muchos. El badge dice si la tabla será del producto o de cada laboratorio.</text>')
o('<text x="48" y="90" font-size="13.5" fill="#475569">📌 snapshot: copia congelada, no cambia nunca.  '
  '🔒 append-only: solo se agregan filas, no se corrigen.  ✏️ lo edita el usuario desde la app.</text>')

lx, ly = 1180, 18
o(f'<rect x="{lx}" y="{ly}" width="790" height="86" rx="12" fill="#f8fafc" stroke="#e2e8f0"/>')
o(f'<text x="{lx+16}" y="{ly+24}" font-size="12">🔑</text><text x="{lx+34}" y="{ly+24}" font-size="12" fill="#334155">id técnico</text>')
o(f'<text x="{lx+130}" y="{ly+24}" font-size="12">🆔</text><text x="{lx+148}" y="{ly+24}" font-size="12" fill="#334155">id público (UUID)</text>')
o(f'<text x="{lx+290}" y="{ly+24}" font-size="12">🏷️</text><text x="{lx+308}" y="{ly+24}" font-size="12" fill="#334155">código de negocio</text>')
o(f'<text x="{lx+450}" y="{ly+24}" font-size="12">🔗</text><text x="{lx+468}" y="{ly+24}" font-size="12" fill="#334155">relación</text>')
o(f'<text x="{lx+560}" y="{ly+24}" font-size="12">📅</text><text x="{lx+578}" y="{ly+24}" font-size="12" fill="#334155">fecha del filtro Desde/Hasta</text>')
o(f'<rect x="{lx+14}" y="{ly+34}" width="22" height="20" rx="7" fill="#d1fae5"/>'
  f'<text x="{lx+25}" y="{ly+49}" font-size="12.5" font-weight="800" fill="#065f46" text-anchor="middle">T</text>'
  f'<text x="{lx+44}" y="{ly+49}" font-size="12" fill="#334155">de cada laboratorio (tenant)</text>')
o(f'<rect x="{lx+250}" y="{ly+34}" width="22" height="20" rx="7" fill="#e0e7ff"/>'
  f'<text x="{lx+261}" y="{ly+49}" font-size="12.5" font-weight="800" fill="#3730a3" text-anchor="middle">G</text>'
  f'<text x="{lx+280}" y="{ly+49}" font-size="12" fill="#334155">del producto (global)</text>')
o(f'<rect x="{lx+450}" y="{ly+34}" width="22" height="20" rx="7" fill="#fef3c7"/>'
  f'<text x="{lx+461}" y="{ly+49}" font-size="12.5" font-weight="800" fill="#92400e" text-anchor="middle">H</text>'
  f'<text x="{lx+480}" y="{ly+49}" font-size="12" fill="#334155">híbrida (base + propia)</text>')
o(f'<line x1="{lx+18}" y1="{ly+70}" x2="{lx+88}" y2="{ly+70}" stroke="#475569" stroke-width="1.8" '
  'marker-start="url(#one)" marker-end="url(#many)"/>')
o(f'<text x="{lx+100}" y="{ly+74}" font-size="12" fill="#334155"><tspan font-weight="700">uno → muchos</tspan>'
  '  (una empresa pide muchas cotizaciones)</text>')

o(f'<text x="48" y="{CH-18}" font-size="11.5" fill="#64748b">Toda tabla guarda además quién creó y modificó cada '
  'registro y cuándo (→ usuarios), y todo cambio queda en Auditoría. '
  'Motor: PostgreSQL 14+. Multi-tenant: estructura preparada, sin aplicar (migración 0003).</text>')
o('</svg>')

svg = '\n'.join(out)
html = ('<!doctype html><html><head><meta charset="utf-8">'
        '<style>html,body{margin:0;background:#fff} '
        'svg{display:block; font-family: "DejaVu Sans", "Noto Color Emoji", sans-serif;}</style>'
        f'</head><body>{svg}</body></html>')
open('/home/claude/v3/docs/ER_GTQC_v3.html', 'w', encoding='utf-8').write(html)
open('/home/claude/v3/docs/ER_GTQC_v3.svg', 'w', encoding='utf-8').write(svg)
print('svg generado:', len(svg), 'bytes')
