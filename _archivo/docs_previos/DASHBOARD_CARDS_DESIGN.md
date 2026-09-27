# 🎴 Dashboard con Tarjetas (Cards) - Diseño Mobile-First

## ✨ Cambio Principal: Tabla → Tarjetas

**ANTES: Tabla tradicional**
```
┌──────┬─────────┬────────┬────────┬────────┬──────┬────────┬────────┐
│ Nº   │Proyecto │Cliente │ Monto  │Estado │Fecha│Validez│Acciones│
├──────┼─────────┼────────┼────────┼────────┼──────┼────────┼────────┤
│COT-1 │Edificio │ACME    │S/8.5k  │✅     │1Sep │30 días│Ver PDF │
└──────┴─────────┴────────┴────────┴────────┴──────┴────────┴────────┘
```
❌ Difícil de leer en móvil, mucho scroll horizontal

---

**AHORA: Tarjetas visuales**
```
┌─────────────────────────────────────┐
│ COT-2024-001              ✅ ACEPTADA│
├─────────────────────────────────────┤
│ Edificio Central Lima               │
│ 👤 Constructora ACME S.A.C.         │
├─────────────────────────────────────┤
│ MONTO      │ VALIDEZ   │ EMISIÓN   │ ITEMS │
│ S/ 8,500   │ 30 días   │ 1 Sep     │ 5     │
├─────────────────────────────────────┤
│  [👁️ Ver]      [📥 PDF]             │
└─────────────────────────────────────┘
```
✅ Legible en móvil, información clara, visual

---

## 📱 Cómo se ve en cada dispositivo

### **Desktop (≥769px)**
```
┌──────────────┬──────────────┬──────────────┐
│  TARJETA 1   │  TARJETA 2   │  TARJETA 3   │ ← 3 tarjetas por fila
│              │              │              │
├──────────────┼──────────────┼──────────────┤
│  TARJETA 4   │  TARJETA 5   │  TARJETA 6   │
│              │              │              │
└──────────────┴──────────────┴──────────────┘

Grid: minmax(280px, 1fr) - Ancho automático
```

### **Tablet (481-768px)**
```
┌──────────────┬──────────────┐
│  TARJETA 1   │  TARJETA 2   │ ← 2 tarjetas por fila
│              │              │
├──────────────┼──────────────┤
│  TARJETA 3   │  TARJETA 4   │
│              │              │
├──────────────┼──────────────┤
│  TARJETA 5   │  TARJETA 6   │
│              │              │
└──────────────┴──────────────┘

Grid: minmax(250px, 1fr) - Un poco más compactas
```

### **Móvil (<480px) ← OPTIMIZADO**
```
┌──────────────────────────────┐
│        TARJETA 1             │ ← 1 tarjeta por fila
│      (100% ancho)            │
├──────────────────────────────┤
│        TARJETA 2             │
│      (100% ancho)            │
├──────────────────────────────┤
│        TARJETA 3             │
│      (100% ancho)            │
└──────────────────────────────┘

Grid: 1fr - Ocupa todo el espacio
```

---

## 🎨 Anatomía de una Tarjeta

```
┌──────────────────────────────────────┐
│ COT-2024-005              ⭐ ACEPTADA│ ← Número + Badge estado
├──────────────────────────────────────┤
│ Centro Médico Cusco                  │ ← Nombre proyecto (destacado)
│ 👤 Constructora ACME S.A.C.          │ ← Cliente (subtítulo)
├──────────────────────────────────────┤
│ MONTO  │ VALIDEZ  │ EMISIÓN  │ ITEMS │ ← 4 datos clave en grid
│ S/9.8k │ 30 días  │ 8 Sep    │ 6     │
├──────────────────────────────────────┤
│    [👁️ Ver Detalles]  [📥 Descargar] │ ← Botones de acción
└──────────────────────────────────────┘
```

### **Componentes:**
1. **Card Header**: Número + Badge de estado
2. **Proyecto**: Nombre grande y legible
3. **Cliente**: Subtítulo con icono
4. **Divider**: Línea separadora visual
5. **Info Grid**: 4 datos (Monto, Validez, Fecha, Items)
6. **Footer**: 2 botones de acción

---

## 🎯 Estados Visuales con Colores

Cada tarjeta tiene un color de borde izquierdo según su estado:

### **🟢 ACEPTADA (Verde)**
```
┌─ Verde (#16a34a)
│
├─ Fondo: Blanco + gradiente verde claro
├─ Badge: Verde oscuro
├─ Borde izquierdo: Verde
│
└─ Usuario verá: "¡Aprobada, procede!" ✓
```

### **🟡 EMITIDA (Amarillo)**
```
┌─ Amarillo (#f59e0b)
│
├─ Fondo: Blanco + gradiente amarillo claro
├─ Badge: Marrón oscuro
├─ Borde izquierdo: Amarillo
│
└─ Usuario verá: "Esperando respuesta" ⏳
```

### **🔴 RECHAZADA (Rojo)**
```
┌─ Rojo (#dc2626)
│
├─ Fondo: Blanco + gradiente rojo claro
├─ Badge: Rojo oscuro
├─ Borde izquierdo: Rojo
│
└─ Usuario verá: "Cliente dijo que no" ❌
```

### **⚫ CANCELADA (Gris)**
```
┌─ Gris (#6b7280)
│
├─ Fondo: Blanco + gradiente gris claro
├─ Badge: Gris oscuro
├─ Borde izquierdo: Gris
│
└─ Usuario verá: "Anulada" 🚫
```

---

## ✨ Efectos Interactivos

### **Hover (Desktop)**
```
ANTES:                     DESPUÉS:
┌────────────────┐        ┌────────────────┐
│  TARJETA       │        │  TARJETA       │ ↑ Sube
│                │   →    │                │ 📦 Más sombra
└────────────────┘        └────────────────┘
                          (transform: translateY(-4px))
```

### **Active (Móvil)**
```
Cuando presionas un botón:
┌────────────────┐
│  TARJETA       │
│ [👁️ Ver] ← Cambia a color más oscuro
└────────────────┘
(:active { background: color más saturado })
```

---

## 📊 Comparativa: Tabla vs Tarjetas

| Aspecto | Tabla | Tarjetas |
|---------|-------|----------|
| **Móvil** | ❌ Scroll horizontal | ✅ Legible sin scroll |
| **Datos por vista** | ❌ Todos (apretados) | ✅ Solo los clave |
| **Visual** | ⚪ Plano, aburrido | 🎨 Colorido, amigable |
| **Toque fácil** | ❌ Botones pequeños | ✅ Botones grandes |
| **Responsive** | ⚠️ Difícil | ✅ Natural |
| **Desktop** | ✅ Bueno | ✅ Bueno |
| **Filtros** | ✅ Encima | ✅ Encima |
| **Paginación** | ✅ Abajo | ✅ Abajo |

---

## 🚀 Ventajas del Nuevo Diseño

### **Para Usuario Móvil:**
1. ✅ **Fácil de leer**: Una tarjeta por toque, información clara
2. ✅ **Rápido de procesar**: Colores indican estado de un vistazo
3. ✅ **Botones grandes**: Imposible equivocarse al tocar
4. ✅ **Sin scroll horizontal**: Solo scroll vertical (natural)
5. ✅ **Visual atractivo**: Gradientes y colores hacen que se vea profesional

### **Para Usuario Desktop:**
1. ✅ **Más información visible**: 3 tarjetas a la vez
2. ✅ **Fácil comparar**: Lado a lado
3. ✅ **Hover effects**: Interactividad clara
4. ✅ **Escalable**: Si hay 20 cotizaciones, 20 tarjetas
5. ✅ **Moderno**: Diseño actual (cards son el estándar)

---

## 💾 Ejemplo de Datos en Tarjeta

```
Cotización: {
  id: "COT-2024-005",
  proyecto: "Centro Médico Cusco",
  cliente: "Constructora ACME S.A.C.",
  monto: 9800,
  estado: "aceptada",
  fechaEmision: "2024-09-08",
  validez: 30,
  items: 6
}

Renderizado como:
┌──────────────────────────────────────┐
│ COT-2024-005              ✅ ACEPTADA│
├──────────────────────────────────────┤
│ Centro Médico Cusco                  │
│ 👤 Constructora ACME S.A.C.          │
├──────────────────────────────────────┤
│ MONTO  │ VALIDEZ  │ EMISIÓN  │ ITEMS │
│ S/9.8k │ 30 días  │ 8 Sep    │ 6     │
├──────────────────────────────────────┤
│    [👁️ Ver]      [📥 PDF]            │
└──────────────────────────────────────┘
```

---

## 🔧 Personalización Fácil

Si quieres cambiar algo:

### **Cambiar colores por estado:**
```css
.cotizacion-card.aceptada {
    border-left-color: #16a34a;  ← Cambia aquí
    background: linear-gradient(135deg, #ffffff 0%, #f0fdf4 100%);  ← O aquí
}
```

### **Cambiar tamaño de tarjetas:**
```css
.table-wrapper {
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    /* minmax(280px, 1fr) = mínimo 280px, máximo 1fr */
    /* Cambia 280px a 300px para más grandes, 250px para más pequeñas */
}
```

### **Cambiar espaciado:**
```css
.table-wrapper {
    gap: 16px;  ← Espacio entre tarjetas
    padding: 0 24px;  ← Márgenes laterales
}
```

---

## 📋 Checklist de Testing

### **Escritorio (Chrome DevTools):**
- [ ] Abre dashboard → Sección "Mis Cotizaciones"
- [ ] Deberías ver 3-4 tarjetas por fila
- [ ] Hover sobre tarjeta → Sube y más sombra
- [ ] Click "Ver" → Abre modal con detalles
- [ ] Click "PDF" → Descarga (simulado)
- [ ] Scroll abajo → Ve más tarjetas

### **Tablet (iPad):**
- [ ] Resize a 768px → 2 tarjetas por fila
- [ ] Sigue siendo legible
- [ ] Botones fáciles de tocar

### **Móvil (390x844px):**
- [ ] Resize a 390px → 1 tarjeta por fila (100% ancho)
- [ ] **IMPORTANTE**: No hay scroll horizontal
- [ ] Tarjeta completa visible sin scroll (excepto info)
- [ ] Botones grandes y fáciles de tocar
- [ ] Colores claros del estado
- [ ] Scroll vertical suave

---

## 🎁 Bonus: Animaciones Suaves

Las tarjetas tienen transiciones CSS suaves:

```css
transition: all 0.3s;  /* Suave en desktop */
transition: none;      /* Instante en móvil (mejor UX) */
```

---

## 📐 Resoluciones Soportadas

```
✅ 320px (iPhone SE)      → 1 tarjeta
✅ 375px (iPhone 12)      → 1 tarjeta
✅ 390px (Galaxy S21)     → 1 tarjeta  ← OPTIMIZADO
✅ 540px (Tablet pequeña) → 2 tarjetas
✅ 768px (iPad)           → 2 tarjetas
✅ 1024px (Desktop)       → 3 tarjetas
✅ 1920px (Monitor)       → 4+ tarjetas
```

---

## 🎯 Caso de Uso Real

**Ejecutivo en avión revisa sus cotizaciones:**
```
1. Abre app en iPhone (390px)
2. Ve dashboard → Navega a "Mis Cotizaciones"
3. Ve una tarjeta por vez → Lee toda la info sin esfuerzo
4. Desplaza hacia abajo → Próxima tarjeta
5. Ve color verde: "¡Aprobada! ✅"
6. Toca [👁️ Ver] → Modal con detalles completos
7. Toca [📥 PDF] → Descarga PDF para revisar después
8. Vuelve a lista → Continúa revisando otras
9. 5 minutos después: Ha revisado 8 cotizaciones sin problema
```

**vs. Con tabla:**
```
1. Abre tabla en iPhone
2. ¿Dónde está el número? ← Scroll derecha
3. ¿Dónde está el cliente? ← Scroll derecha
4. ¿Dónde está el monto? ← Scroll derecha
5. Toca botón "Ver" → Casi no se ve, toca mal
6. Frustrado, deja de revisar
```

---

## ✅ Conclusión

El nuevo diseño con **tarjetas es ideal para PWA móvil** porque:
- 📱 **Móvil**: Una columna, 100% legible, sin scroll horizontal
- 💻 **Desktop**: Múltiples columnas, información clara, moderno
- 🎨 **Visual**: Colores indican estado de un vistazo
- 👆 **Touch-friendly**: Botones grandes y fáciles
- 🚀 **Escalable**: Funciona con 5 o 100 cotizaciones

**Archivo**: `dashboard_cliente_cotizaciones.html`  
**Version**: 2.2 - Card-Based Design  
**Fecha**: 2026-09-24
