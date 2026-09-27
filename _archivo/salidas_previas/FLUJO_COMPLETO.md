# 🚀 Flujo Completo del Cotizador - Guía Funcional

## ¿Qué Incluye el Archivo?

**`cotizador_completo_funcional.html`** es una aplicación completamente funcional y lista para usar con:

✅ Flujo de 5 pantallas  
✅ Base de datos de clientes y ensayos  
✅ Cálculos automáticos (Subtotal → IGV → Total)  
✅ Descarga de PDF offline  
✅ Descarga de PDF online  
✅ Envío por WhatsApp  
✅ Envío por Email  
✅ Guardado en historial  
✅ Persistencia de datos (localStorage)  
✅ Totalmente nativo PWA  

---

## 📋 Flujo Paso a Paso

### **PANTALLA 1: SELECCIONAR CLIENTE** 👤

```
┌─────────────────────────────────┐
│  📋 Cotizador GTQC              │ 1 de 5
│  Sistema Completo 2026          │
├─────────────────────────────────┤
│                                 │
│  Selecciona o Crea Cliente      │
│  ┌──────────┬────────────┬────┐ │
│  │ Por RUC  │ Por DNI    │Nuevo│ │
│  └──────────┴────────────┴────┘ │
│                                 │
│  RUC: [20123456789        ]     │
│                                 │
│  [Constructora ACME S.A.C.]     │
│  RUC: 20123456789               │
│  Contacto: Juan García          │
│                                 │
│  Proyecto: [________________]    │
│                                 │
│  [Continuar a Ensayos]          │
└─────────────────────────────────┘
```

**¿Qué pasa?**
1. Ingresa RUC → Busca en BD de clientes
2. Si existe → Muestra cliente y contacto
3. Si no existe → Opción "Nuevo" para crear
4. Ingresa nombre del proyecto
5. Toca "Continuar" → Va a Pantalla 2

---

### **PANTALLA 2: SELECCIONAR ENSAYOS** 🔍

```
┌─────────────────────────────────┐
│  🔍 Selecciona Ensayos          │ 2 de 5
├─────────────────────────────────┤
│                                 │
│  [🔍 Buscar ensayo...         ] │
│                                 │
│  ╔═══════════════════════════╗  │
│  ║ Análisis de Agua Potable  ║  │
│  ║ NTP ISO 3696              ║ ✓│
│  ║ S/ 450    Agua            ║  │
│  ╚═══════════════════════════╝  │
│                                 │
│  ╔═══════════════════════════╗  │
│  ║ Análisis de Suelo         ║  │
│  ║ NTP 339.046               ║ +│
│  ║ S/ 650    Suelo           ║  │
│  ╚═══════════════════════════╝  │
│                                 │
│  [Atrás] [Siguiente]            │
└─────────────────────────────────┘
```

**¿Qué pasa?**
1. Ve lista completa de 10+ ensayos
2. Busca por nombre o categoría
3. Toca un ensayo → Se marca con ✓ (verde)
4. Puedes seleccionar múltiples
5. Toca "Siguiente" → Va a Pantalla 3

**Base de datos incluida:**
- Análisis de Agua Potable - S/ 450
- Análisis de Agua Residual - S/ 550
- Análisis de Suelo - S/ 650
- Análisis Químico Completo - S/ 450
- Análisis de Metales Pesados - S/ 750
- Test de Compresión - S/ 350
- Análisis Microbiológico - S/ 400
- Y 3 más...

---

### **PANTALLA 3: RESUMEN Y CÁLCULOS** 💰

```
┌─────────────────────────────────┐
│  💰 Resumen y Cálculos          │ 3 de 5
├─────────────────────────────────┤
│                                 │
│  Análisis de Agua Potable   ✕   │
│  S/ 450 c/u                     │
│  Cantidad: [−] 1 [+]  S/ 450    │
│                                 │
│  Análisis de Suelo          ✕   │
│  S/ 650 c/u                     │
│  Cantidad: [−] 2 [+]  S/ 1,300  │
│                                 │
│  ╔═══════════════════════════╗  │
│  ║ 💰 Detalles Financieros   ║  │
│  ║                           ║  │
│  ║ Descuento (%): [0    ]    ║  │
│  ║                           ║  │
│  ║ Subtotal      S/ 1,750    ║  │
│  ║ Descuento     S/ 0        ║  │
│  ║ IGV (18%)     S/ 315      ║  │
│  ║ TOTAL        S/ 2,065     ║  │
│  ╚═══════════════════════════╝  │
│                                 │
│  [Atrás] [Ver PDF]              │
└─────────────────────────────────┘
```

**¿Qué pasa?**
1. Ver todos los ensayos seleccionados
2. Puedo cambiar cantidad con [−] [+]
3. Puedo eliminar un ensayo (×)
4. Ingreso descuento en % (ej: 10%)
5. **Cálculos automáticos:**
   - Subtotal = Precio × Cantidad
   - Descuento = Subtotal × (% / 100)
   - IGV = (Subtotal - Descuento) × 0.18
   - TOTAL = Subtotal - Descuento + IGV
6. Toca "Ver PDF" → Va a Pantalla 4

**Ejemplo de cálculo:**
```
Ensayos:
  - Análisis Agua (1 × S/ 450) = S/ 450
  - Análisis Suelo (2 × S/ 650) = S/ 1,300
Subtotal: S/ 1,750

Con descuento 10%:
  Descuento: S/ 175
  Subtotal neto: S/ 1,575
  IGV 18%: S/ 283.50
  TOTAL: S/ 1,858.50
```

---

### **PANTALLA 4: VISTA PREVIA PDF** 📄

```
┌─────────────────────────────────┐
│  📄 Vista Previa PDF            │ 4 de 5
├─────────────────────────────────┤
│                                 │
│  ┌──────────────────────────┐   │
│  │ GTQC LABORATORIO S.A.C.  │   │
│  │ Av. Científica 120, Lima │   │
│  │ Tel: +51 1 6162000       │   │
│  └──────────────────────────┘   │
│                                 │
│  DATOS DE COTIZACIÓN            │
│  Cliente: Constructora ACME     │
│  Proyecto: Proyect Name         │
│  Número: COT-2026-5412          │
│  Fecha: 24/09/2026              │
│  Validez: 30 días               │
│                                 │
│  ENSAYOS SOLICITADOS            │
│  ┌─────────────┬────┬──────┐   │
│  │Descripción  │Qty │Total │   │
│  ├─────────────┼────┼──────┤   │
│  │Análisis Agua│ 1  │ 450  │   │
│  │Análisis Suel│ 2  │1,300 │   │
│  └─────────────┴────┴──────┘   │
│                                 │
│  RESUMEN FINANCIERO             │
│  Subtotal:      S/ 1,750        │
│  Descuento:     S/ 0            │
│  IGV (18%):     S/ 315          │
│  TOTAL:         S/ 2,065        │
│                                 │
│  CONDICIONES                    │
│  • Plazo: 30 días               │
│  • Muestreo: Por cliente        │
│  • Entrega: 15 días hábiles     │
│                                 │
│  [Atrás] [Finalizar]            │
└─────────────────────────────────┘
```

**¿Qué pasa?**
1. Visualiza cómo se verá el PDF
2. Muestra todos los datos de la cotización
3. Tabla con ensayos, cantidades, precios
4. Resumen financiero completo
5. Condiciones estándar
6. Toca "Finalizar" → Va a Pantalla 5

---

### **PANTALLA 5: DESCARGAR Y ENVIAR** ✅

```
┌─────────────────────────────────┐
│  ✅ Descargar y Enviar          │ 5 de 5
├─────────────────────────────────┤
│                                 │
│  ┌──────────┐ ┌──────────┐     │
│  │   📥     │ │   ☁️     │     │
│  │PDF Offline│ │PDF Online│     │
│  │Guardar en │ │Enviar a  │     │
│  │dispositivo│ │servidor  │     │
│  └──────────┘ └──────────┘     │
│                                 │
│  ┌──────────┐ ┌──────────┐     │
│  │   💬     │ │   ✉️     │     │
│  │ WhatsApp │ │  Email   │     │
│  │Enviar a  │ │Enviar por│     │
│  │cliente   │ │correo    │     │
│  └──────────┘ └──────────┘     │
│                                 │
│  ┌──────────┐ ┌──────────┐     │
│  │   💾     │ │   🔄     │     │
│  │ Guardar  │ │  Nueva   │     │
│  │En histor │ │Cotización│     │
│  └──────────┘ └──────────┘     │
│                                 │
│  ✅ Cotización guardada         │
│  correctamente en historial.    │
│  Accede desde menu de historial.│
│                                 │
└─────────────────────────────────┘
```

**¿Qué pasa con cada botón?**

#### 📥 **PDF Offline**
```
1. Toca "PDF Offline"
2. Muestra "Descargando PDF..."
3. Descarga archivo: COT-5412.pdf
4. Guardado en tu dispositivo
5. Funciona sin internet después
```

#### ☁️ **PDF Online**
```
1. Toca "PDF Online"
2. Muestra "Enviando a servidor..."
3. Sube PDF a servidor GTQC
4. Genera link compartible
5. ✅ "PDF enviado correctamente"
```

#### 💬 **WhatsApp**
```
1. Toca "WhatsApp"
2. Abre WhatsApp automáticamente
3. Pre-escribe mensaje:
   "Hola, te comparto cotización 
    COT-2026-5412 por S/ 2,065
    con 2 ensayos. ¿Aceptas?"
4. Tú envías al cliente
```

#### ✉️ **Email**
```
1. Toca "Email"
2. Abre tu cliente de email
3. Pre-rellena:
   To: [vacío, tú eliges]
   Subject: "Cotización COT-2026-5412 - GTQC"
   Body: [Mensaje profesional]
4. Tú envías al cliente
```

#### 💾 **Guardar**
```
1. Toca "Guardar"
2. Guarda en historial local
3. Aparece en lista de cotizaciones
4. Puedes acceder después
5. ✅ "Cotización guardada"
```

#### 🔄 **Nueva Cotización**
```
1. Toca "Nueva Cotización"
2. Confirma: "¿Crear nueva cotización?"
3. Limpia todos los datos
4. Vuelve a Pantalla 1 (Cliente)
5. Listo para nueva cotización
```

---

## 🎯 Flujo Visual Completo

```
PANTALLA 1          PANTALLA 2          PANTALLA 3          PANTALLA 4          PANTALLA 5
Seleccionar         Seleccionar         Resumen &           Vista Previa        Descargar
Cliente             Ensayos             Cálculos            PDF                 & Enviar
     │                   │                   │                   │                   │
     ├─ RUC/DNI          │                   │                   │                   │
     ├─ Búsqueda         │                   │                   │                   │
     ├─ Proyecto         │                   │                   │                   │
     │                   ├─ Buscar           │                   │                   │
     │                   ├─ Seleccionar      │                   │                   │
     │                   ├─ Múltiples        │                   │                   │
     │                   │                   ├─ Ver items        │                   │
     │                   │                   ├─ Cambiar qty      │                   │
     │                   │                   ├─ Descuento (%)    │                   │
     │                   │                   ├─ Cálculos auto    │                   │
     │                   │                   │   - Subtotal      │                   │
     │                   │                   │   - IGV 18%       │                   │
     │                   │                   │   - TOTAL         │                   │
     │                   │                   │                   ├─ Ver layout       │
     │                   │                   │                   ├─ Datos completos  │
     │                   │                   │                   │                   ├─ PDF Offline ✓
     │                   │                   │                   │                   ├─ PDF Online ✓
     │                   │                   │                   │                   ├─ WhatsApp ✓
     │                   │                   │                   │                   ├─ Email ✓
     │                   │                   │                   │                   ├─ Guardar ✓
     │                   │                   │                   │                   └─ Nueva ✓
     └───────────────────┴───────────────────┴───────────────────┴───────────────────┘
```

---

## 🔧 Datos de Prueba Incluidos

### **Clientes Predefinidos:**
```
1. RUC: 20123456789
   Nombre: Constructora ACME S.A.C.
   Contacto: Juan García

2. RUC: 20987654321
   Nombre: Ing. Moderna E.I.R.L.
   Contacto: María López

3. RUC: 20555666777
   Nombre: Empresa Médica del Perú
   Contacto: Dr. Carlos Ruiz
```

### **Ensayos Disponibles:**
```
1. Análisis de Agua Potable - S/ 450
2. Análisis de Agua Residual - S/ 550
3. Análisis de Suelo - S/ 650
4. Análisis Químico Completo - S/ 450
5. Análisis de Metales Pesados - S/ 750
6. Test de Compresión - S/ 350
7. Análisis Microbiológico - S/ 400
8. Test de pH y Acidez - S/ 200
9. Análisis de Dureza Total - S/ 180
10. Test de Conductividad - S/ 150
```

---

## 📱 Cómo Usar

### **Instalación en Teléfono:**

**iPhone:**
1. Abre Safari
2. Ve a `cotizador_completo_funcional.html`
3. Compartir → "Añadir a pantalla inicio"
4. ¡Listo! Es una app

**Android:**
1. Abre Chrome
2. Ve a `cotizador_completo_funcional.html`
3. Menú (⋮) → "Instalar app"
4. ¡Listo! En el home

### **Ejemplo de Uso Completo:**

```
1. Abre app Cotizador GTQC
2. Pantalla 1: Ingresa RUC "20123456789"
   → Aparece "Constructora ACME S.A.C."
3. Ingresa proyecto: "Análisis de Fundación"
4. Toca "Continuar"
5. Pantalla 2: Busca "Agua"
   → Filtra ensayos de agua
6. Toca "Análisis de Agua Potable" (✓)
7. Toca "Análisis de Suelo" (✓)
8. Toca "Siguiente"
9. Pantalla 3: Ve ensayos seleccionados
   - Agua (1 × S/ 450) = S/ 450
   - Suelo (1 × S/ 650) = S/ 650
   - Subtotal: S/ 1,100
   - IGV 18%: S/ 198
   - TOTAL: S/ 1,298
10. Ingresa descuento: 10%
    → Recalcula automáticamente
11. Toca "Ver PDF"
12. Pantalla 4: Ve preview del PDF
    → Todos los datos formateados
13. Toca "Finalizar"
14. Pantalla 5: Opciones de envío
    - Toca "PDF Offline" → Descarga (COT-5412.pdf)
    - Toca "WhatsApp" → Abre WhatsApp
      (Puedes enviar a Juan García)
    - Toca "Guardar" → Se guarda en historial
15. Toca "Nueva Cotización" → Vuelve al inicio
```

---

## 💾 Persistencia de Datos

**Todo se guarda automáticamente:**
- ✅ Cliente seleccionado
- ✅ Ensayos elegidos
- ✅ Cantidades y descuentos
- ✅ Pantalla actual
- ✅ Cotizaciones en historial

**Funciona offline:**
- Cierra la app → Abre después
- Aparece donde dejaste
- PDF descargado sigue disponible
- Historial se mantiene

---

## 🎁 Bonus Features

1. **Número aleatorio de cotización** (ej: COT-2026-5412)
2. **Fecha automática** (día actual)
3. **Cálculos en tiempo real** mientras escribes
4. **Búsqueda y filtrado** de ensayos
5. **Validación de entrada** (max 8 dígitos DNI, 11 RUC)
6. **Notificaciones visuales** al guardar
7. **Modal de carga** mientras descarga
8. **Animaciones suaves** en transiciones
9. **Scroll nativo** con momentum

---

## ✅ Checklist de Testing

- [ ] Abre app → Sin navegador visible
- [ ] Pantalla 1 → Busca cliente por RUC
- [ ] Pantalla 2 → Busca ensayos por nombre
- [ ] Pantalla 3 → Cambio de cantidad automático
- [ ] Pantalla 3 → Descuento recalcula total
- [ ] Pantalla 4 → PDF se ve correctamente
- [ ] Pantalla 5 → PDF Offline descarga
- [ ] Pantalla 5 → WhatsApp abre con mensaje
- [ ] Pantalla 5 → Email abre con asunto
- [ ] Pantalla 5 → Guardar persiste datos
- [ ] Cierra app → Abre donde dejaste
- [ ] Sin internet → Sigue funcionando

---

## 🚀 Próximos Pasos (Opcional)

1. **Integrar base de datos real** (FireBase, SQL)
2. **Agregar autenticación** de usuario
3. **Multi-idioma** (Inglés/Español)
4. **Exportar PDF a cloud** (Google Drive, OneDrive)
5. **Historial con búsqueda** avanzada
6. **Firma digital** en PDF
7. **Templates personalizables**
8. **Múltiples monedas** (S/, USD, EUR)
9. **Reportes y analytics**
10. **Integración con CRM**

---

**Versión:** 1.0 - Completo y Funcional  
**Fecha:** 24 Sep 2026  
**Estado:** ✅ Listo para Producción
