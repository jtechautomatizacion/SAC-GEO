# 📋 Guía de Plantillas - Cotizador

## 3 Plantillas Disponibles

El cotizador ahora incluye **3 plantillas profesionales** que difieren SOLO en Términos y Condiciones. El formato, logo y estructura son idénticos.

---

## 🧪 **PLANTILLA 1: ESTÁNDAR**
```
Selector: 🧪 Estándar
ID: PL001

Características:
✓ Validez: 30 días
✓ Pago: 50% al inicio, 50% al término
✓ Precios incluyen IGV (18%)
✗ No incluye transporte de muestras
✗ Sujeto a disponibilidad de equipos

Ideal para: Clientes ocasionales, proyectos pequeños
```

---

## ⭐ **PLANTILLA 2: PREMIUM**
```
Selector: ⭐ Premium
ID: PL002

Características:
✓ Validez: 45 días
✓ Pago: Flexible según acuerdo
✓ Precios incluyen IGV (18%) Y TRANSPORTE
✓ Incluye informe ejecutivo
✓ Soporte técnico por 30 días
✓ Garantía de precisión: ±2%

Ideal para: Clientes frecuentes, proyectos grandes
```

---

## ⚡ **PLANTILLA 3: EXPRESS**
```
Selector: ⚡ Express
ID: PL003

Características:
✓ Validez: 15 días (URGENTE)
✓ Pago: 100% al inicio
✓ Precios incluyen IGV (18%)
✓ Entrega de resultados en 48 horas
✗ Sin cambios posteriores
✗ Muestras retenidas por 7 días

Ideal para: Proyectos urgentes, respuestas rápidas
```

---

## 🔄 ¿Cómo Cambiar de Plantilla?

1. **En el Cotizador**, ve al **HEADER**
2. Encontrarás un selector: **"Plantilla:"**
3. Selecciona la que necesites:
   - 🧪 Estándar
   - ⭐ Premium
   - ⚡ Express
4. Los **Términos y Condiciones** se actualizarán automáticamente en la **Pantalla 4 (Resumen)**

---

## 📄 Qué Permanece Igual

```
IDÉNTICO EN LAS 3 PLANTILLAS:
✓ Formato de cotización
✓ Logo (🧪 / ⭐ / ⚡ en el header)
✓ Estructura de datos del cliente
✓ Layout de items cotizados
✓ Cálculos de subtotal, IGV, descuentos
✓ Diseño del PDF
```

---

## 💾 Almacenamiento en Base de Datos

```sql
CREATE TABLE PLANTILLAS (
    id VARCHAR(10) PRIMARY KEY,      -- PL001, PL002, PL003
    nombre VARCHAR(50),               -- Estándar, Premium, Express
    empresa VARCHAR(100),             -- GTQC Laboratorio de Testing
    logo VARCHAR(10),                 -- 🧪, ⭐, ⚡
    terminosCondiciones TEXT,         -- ÚNICO en cada plantilla
);
```

---

## 🎯 Caso de Uso

**Escenario**: Cliente pide cotización urgente
1. Abres cotizador
2. Cambias a plantilla **⚡ Express**
3. Cargas cliente, ensayos y items
4. En Pantalla 4, ve los términos Express (48h, pago al inicio)
5. Descarga PDF con esos términos
6. Envía por WhatsApp o email

**Escenario**: Cliente frecuente con presupuesto grande
1. Cambias a plantilla **⭐ Premium**
2. Los términos muestran: validez 45 días, pago flexible, soporte incluido
3. Impresiona al cliente con servicios adicionales

---

## 📱 Pantallas del Cotizador (5 Total)

```
PANTALLA 1: Cliente y Proyecto
    ├─ Selector de Plantilla ← AQUÍ CAMBIAS
    ├─ Tipo Cliente (RUC/DNI)
    └─ Datos del Proyecto

PANTALLA 2: Ensayos y Paquetes
    └─ Catálogo con normas técnicas

PANTALLA 3: Descuentos e IGV
    └─ Cálculo automático

PANTALLA 4: Resumen y PDF
    ├─ Vista previa con datos cliente
    ├─ Items cotizados
    ├─ Totales
    └─ TÉRMINOS Y CONDICIONES ← De la plantilla seleccionada

PANTALLA 5: Acciones
    ├─ Descargar Offline
    ├─ Descargar Online
    ├─ Enviar WhatsApp
    └─ Enviar Email
```

---

## ✅ Mejoras Implementadas

1. **3 Plantillas**: Estándar, Premium, Express
2. **Selector en Header**: Cambio rápido entre plantillas
3. **Términos Dinámicos**: Se actualizan en PDF según plantilla
4. **Descuentos Corregidos**: Se aplican al TOTAL (no subtotal)
5. **Normas en Ensayos**: Cada ensayo muestra su norma técnica
6. **Pantalla 5**: Botones de descarga y envío
7. **Mobile-First**: Diseño optimizado para celular
8. **Responsive**: Funciona en cualquier dispositivo

---

## 🚀 Próximos Pasos (Backend)

Para producción, necesitarás:
- [ ] Conectar a BD real (no mock)
- [ ] Integrar API SUNAT para RUC
- [ ] Generar PDFs reales (pdfkit, etc.)
- [ ] Implementar WhatsApp Business API
- [ ] Implementar Email con attachments
- [ ] Dashboard del cliente (ya incluido en versión anterior)

---

**Archivo**: `cotizador_con_plantillas.html`  
**Versión**: 1.0 con 3 Plantillas + Pantalla 5  
**Probado**: ✅ Desktop + Mobile (390x844px)
