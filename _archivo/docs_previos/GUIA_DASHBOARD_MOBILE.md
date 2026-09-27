# 📱 Guía: Dashboard Mobile-First PWA (390x844px)

## Optimizaciones Aplicadas

El dashboard ya ha sido completamente optimizado para funcionar como una **Progressive Web App (PWA)** en celulares pequeños.

---

## 🎨 Layout en Móvil (390x844px)

### **Navegación (Sidebar → Bottom Navigation)**

**Escritorio (≥769px):**
```
┌─────────────────────────────────────┐
│ SIDEBAR (280px a la izquierda)      │
├─────────────────────────────────────┤
│ 📊 Cotizador                        │
│ 📈 Dashboard                        │
│ 📋 Mis Cotizaciones                 │
│ ⏱️ Historial                        │
│ 📊 Reportes                         │
│ ⚙️ Configuración                    │
└─────────────────────────────────────┘
         CONTENIDO PRINCIPAL
```

**Móvil (<480px - estilo app nativa):**
```
┌─────────────────────────┐
│   CONTENIDO PRINCIPAL   │
│  (Dashboard/Tabla/etc)  │
│                         │
│                         │
└─────────────────────────┘
┌─────────────────────────┐
│ 📈 │ 📋 │ ⏱️ │ 📊 │ ⚙️  │ ← NAV BAR (inferior)
└─────────────────────────┘
```

**Ventajas:**
- ✅ Navegación en la parte inferior (patrón iOS/Android)
- ✅ Más espacio para contenido
- ✅ Más fácil de tocar con pulgar

---

## 📊 Stat Cards en Móvil

**Escritorio: Grid de 4 columnas**
```
┌──────────┬──────────┬──────────┬──────────┐
│  Total   │Aprobadas │Rechazadas│  Valor   │
│    8     │    5     │    2     │ S/ 45K   │
└──────────┴──────────┴──────────┴──────────┘
```

**Tablet: Grid de 2 columnas**
```
┌──────────┬──────────┐
│  Total   │Aprobadas │
│    8     │    5     │
├──────────┼──────────┤
│Rechazadas│  Valor   │
│    2     │ S/ 45K   │
└──────────┴──────────┘
```

**Móvil: Stack de 1 columna (390px)**
```
┌──────────────────┐
│     Total: 8     │
├──────────────────┤
│   Aprobadas: 5   │
├──────────────────┤
│   Rechazadas: 2  │
├──────────────────┤
│   Valor: S/ 45K  │
└──────────────────┘
```

---

## 🎯 Leyenda de Estados en Móvil

**Desktop: 2x2 Grid**
```
┌──────────────┬──────────────┐
│ 🟢 Aceptada  │ 🟡 Emitida   │
├──────────────┼──────────────┤
│ 🔴 Rechazada │ ⚫ Cancelada  │
└──────────────┴──────────────┘
```

**Móvil (<480px): Stack vertical (1 column)**
```
┌──────────────────────────┐
│ 🟢 Aceptada              │
│    Cliente aprobó...     │
│    [✅ Activa]           │
├──────────────────────────┤
│ 🟡 Emitida               │
│    Esperando respuesta... │
│    [⏳ Pendiente]        │
├──────────────────────────┤
│ 🔴 Rechazada             │
│    Cliente rechazó...     │
│    [❌ Cerrada]          │
├──────────────────────────┤
│ ⚫ Cancelada              │
│    Anulada internamente... │
│    [🚫 Archivada]        │
└──────────────────────────┘
```

**Cada card ocupa el 100% del ancho disponible**, perfecto para leer en vertical.

---

## 📈 Gráficos en Móvil

**Desktop: 2x2 Grid**
```
┌─────────────┬─────────────┐
│ Estado Pie  │ Evolución   │
├─────────────┼─────────────┤
│ Proyectos   │ Mensual     │
└─────────────┴─────────────┘
```

**Móvil (<480px): Stack vertical**
```
┌──────────────────────┐
│  📊 Estado (Doughnut)│
│  Altura: 200px       │
├──────────────────────┤
│  📈 Evolución (Line) │
│  Altura: 200px       │
├──────────────────────┤
│  🎯 Proyectos (Bar)  │
│  Altura: 200px       │
├──────────────────────┤
│  📅 Mensual (Bar)    │
│  Altura: 200px       │
└──────────────────────┘
```

**Alturas optimizadas**: 200px en móvil (vs 300px en desktop) para no hacer scroll excesivo.

---

## 📋 Tabla de Cotizaciones en Móvil

**Desktop: Todas las columnas visibles**
```
┌──────┬─────────┬────────┬────────┬────────┬──────┬────────┬────────┐
│ Nº   │Proyecto │Cliente │ Monto  │Estado │Fecha│Validez│Acciones│
├──────┼─────────┼────────┼────────┼────────┼──────┼────────┼────────┤
│COT-1 │Edificio │ACME    │S/8.5k  │✅     │1Sep │30 días│Ver PDF │
└──────┴─────────┴────────┴────────┴────────┴──────┴────────┴────────┘
```

**Móvil (<480px): Adaptada con scroll horizontal**
```
┌───────────────────────────────┐
│ COT-2024-001                  │
│ Edificio Central Lima         │
│ ACME S.A.C.                   │
│ S/ 8,500 | ✅ ACEPTADA        │
│ 1 Sep | 30 días               │
│ [Ver]  [PDF]                  │
├───────────────────────────────┤
│ COT-2024-002                  │
│ Centro Comercial Arequipa     │
│ Ing. Moderna E.I.R.L.         │
│ S/ 12,300 | ✅ ACEPTADA       │
│ 5 Sep | 30 días               │
│ [Ver]  [PDF]                  │
└───────────────────────────────┘
```

- Fuente más pequeña (10-11px)
- Padding reducido (6-8px)
- Botones en columna vertical
- Scroll horizontal disponible si es necesario

---

## 🎛️ Filtros en Móvil

**Desktop: Horizontal (flex-wrap)**
```
┌─────────────────────────────────────────────┐
│ Buscar... │ Estado ▼ │ Desde ... │ Hasta ... │
└─────────────────────────────────────────────┘
```

**Móvil (<480px): Stack vertical**
```
┌──────────────────────┐
│ Buscar...            │
├──────────────────────┤
│ Estado ▼             │
├──────────────────────┤
│ Desde ...            │
├──────────────────────┤
│ Hasta ...            │
└──────────────────────┘
```

- Cada filtro ocupa 100% ancho
- Inputs más grandes (8px padding vs 6px)
- Más fácil de usar con un dedo

---

## 🔒 Viewport y Meta Tags (PWA)

El dashboard incluye:
```html
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
```

**Esto asegura:**
- ✅ Se escala correctamente en cualquier tamaño
- ✅ No se hace zoom automático
- ✅ Funciona en 390x844px (móvil estándar Android)
- ✅ Se puede instalar como app (PWA)

---

## 📱 Breakpoints Usados

```css
/* Desktop (>768px) */
@media (min-width: 769px) {
  .stats-grid { grid: 4 columnas }
  .legend-grid { grid: 2x2 }
  .sidebar { fixed left, 280px wide }
}

/* Tablet (481px - 768px) */
@media (max-width: 768px) {
  .stats-grid { grid: 1 columna }
  .legend-grid { grid: 1 columna }
  .sidebar { top, horizontal }
  .charts-grid { grid: 1 columna }
}

/* Móvil Pequeño (<480px) - OPTIMIZADO */
@media (max-width: 480px) {
  .sidebar { fixed bottom, 100% wide, 60px alto }
  .nav-menu { flex: row, gap: 0 }
  .nav-item { flex-direction: column, text-align: center }
  .chart-content { height: 200px }
  table { font-size: 10px }
}
```

---

## 🎯 Casos de Uso

### **Caso 1: Ejecutivo revisa en Uber (iPhone 12 mini)**
```
1. Abre app → Ve Dashboard en 1 segundo
2. Lee Stat Cards: "8 cotizaciones, 5 aprobadas"
3. Toca Leyenda para entender estados
4. Desliza a gráficos si quiere más detalle
5. Toca "Mis Cotizaciones" (nav inferior)
6. Busca una cotización rápidamente
7. Toca "Ver" para detalles
8. Descarga PDF directo al celular
```

### **Caso 2: Cliente en oficina (iPad)**
```
1. Abre dashboard en navegador
2. Ve todo a la izquierda (sidebar completo)
3. Leyenda en grid 2x2 bien visible
4. Gráficos grandes y legibles
5. Tabla con todas las columnas
6. Imprime o descarga si lo necesita
```

---

## ✅ Testing en Móvil

### **Chrome DevTools:**
```
1. F12 → Device Toolbar
2. Select "iPhone 12" o "Galaxy S21"
3. Viewport: 390x844
4. Verifica:
   ✓ Nav bar inferior aparece
   ✓ Stat cards apilados verticalmente
   ✓ Leyenda legible (no overflow)
   ✓ Gráficos se ven sin scroll horizontal
   ✓ Tabla responde a toques
```

### **En tu celular:**
```
1. Abre cotizador_completo_4pantallas_v2.html
2. Desliza a Dashboard
3. Verifica:
   ✓ Navegación inferior funciona
   ✓ Toca cada icono → cambia sección
   ✓ Scroll suave
   ✓ Sin zoom forzado
   ✓ Botones accesibles
```

---

## 🚀 Optimizaciones Incluidas

| Aspecto | Desktop | Móvil | Mejora |
|--------|---------|-------|--------|
| **Sidebar** | Lateral (280px) | Inferior (60px) | +35% más contenido |
| **Stat Cards** | 4 columnas | 1 columna | 100% ancho |
| **Leyenda** | Grid 2x2 | Stack 1 col | Más legible |
| **Gráficos** | 500x300px | 390x200px | Menos scroll |
| **Tabla** | Todas columnas | Condensada | Toque fácil |
| **Padding** | 24-30px | 10-15px | Compacto |
| **Fuentes** | 14-16px | 10-11px | Legible aún |
| **Botones** | 12x24px | 8x20px | Dedos preciso |

---

## 📐 Resoluciones Soportadas

```
✅ 320px (iPhone SE)
✅ 375px (iPhone 12)
✅ 390px (Galaxy S21) ← OPTIMIZADO
✅ 412px (iPhone 13 Pro)
✅ 540px (Tablets pequeñas)
✅ 768px (Tablets grandes)
✅ 1024px (Desktop)
✅ 1920px (Monitores)
```

---

## 💡 Recomendaciones de Uso

1. **Para Cliente**: Abre en móvil para ver lo responsive que es
2. **Para Presentación**: Usa Desktop para ver más detalles a la vez
3. **Para Testing**: Usa DevTools con 390x844px (Galaxy S21)
4. **Para PWA**: Puedes "Instalar" como app en el home screen

---

**Dashboard Version**: 2.1 - Mobile Optimized  
**Fecha**: 2026-09-24  
**Soportado en**: Cualquier dispositivo moderno (iOS/Android)
