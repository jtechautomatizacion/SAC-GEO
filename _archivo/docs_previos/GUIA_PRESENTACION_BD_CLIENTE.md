# 📊 Guía de Presentación: Base de Datos Cotizador GTQC

## Propósito
Este documento te ayuda a presentar la arquitectura de la base de datos al cliente de forma clara y profesional.

---

## 🎯 Estructura General (Vista de 30,000 pies)

La base de datos está organizada en **11 tablas** que trabajan juntas para gestionar:
- **Datos del Cliente**: Empresas, contactos, personas
- **Catálogos Maestros**: Ensayos, paquetes, plantillas
- **Transacciones**: Cotizaciones, items, descuentos
- **Seguimiento**: Descargas, envíos, auditoría

**Tres Categorías de Tablas:**
```
📚 3 TABLAS MAESTRAS (datos base, reutilizables)
├─ ENSAYOS_CATALOGO: Todos los ensayos disponibles con normas
├─ PAQUETES_CATALOGO: Servicios prearmados
└─ PLANTILLAS: 3 modelos (Estándar, Premium, Express)

🎯 1 TABLA CENTRAL (la transacción principal)
└─ COTIZACIONES: El documento que genera cada cotización

📋 7 TABLAS DE DETALLES Y SOPORTE
├─ COTIZACION_ITEMS: Líneas de cada cotización
├─ DESCUENTOS: Descuentos aplicados
├─ COTIZACION_DESCARGAS: Historial de descargas (offline/online)
├─ COTIZACION_ENVIOS: Historial de envíos (WhatsApp/Email)
├─ EMPRESAS: Información de clientes
├─ CONTACTOS: Personas autorizadas en cada empresa
└─ PERSONAS: Representantes y usuarios del sistema
```

---

## 🔄 Cómo Funciona: El Flujo Completo

### **Paso 1: Cliente se Registra → TABLA EMPRESAS + CONTACTOS**
```
Ejemplo: "ABC Constructora S.A.C."
├─ EMPRESAS.ruc = 20123456789
├─ EMPRESAS.nombre = "ABC Constructora"
└─ CONTACTOS.nombre = "Juan Pérez" (persona que solicita cotización)
   └─ CONTACTOS.telefono = "+51 999 888 777"
```

### **Paso 2: Usuario Abre Cotizador → TABLA PLANTILLAS**
```
Elige uno de 3 modelos:
├─ 🧪 ESTÁNDAR (30 días, 50-50 pago, básico)
├─ ⭐ PREMIUM (45 días, flexible, con soporte)
└─ ⚡ EXPRESS (15 días, 100% adelanto, 48h)

Se guarda en: COTIZACIONES.id_plantilla
```

### **Paso 3: Selecciona Ensayos → TABLA ENSAYOS_CATALOGO + COTIZACION_ITEMS**
```
De la lista de ensayos disponibles:
├─ ENSAYOS_CATALOGO.nombre = "Ensayo Compresión"
├─ ENSAYOS_CATALOGO.norma = "NTP 339.034"
├─ ENSAYOS_CATALOGO.precio_base = 150.00

Se añade a la cotización:
└─ COTIZACION_ITEMS.id_ensayo = 5
   ├─ COTIZACION_ITEMS.cantidad = 1
   ├─ COTIZACION_ITEMS.precio = 150.00
   └─ COTIZACION_ITEMS.norma = "NTP 339.034" (referencia rápida)
```

### **Paso 4: Aplica Descuento → TABLA DESCUENTOS**
```
El cliente dice: "Dame 10% de descuento"
└─ DESCUENTOS.monto = 36.50 (se calcula como 10% de Subtotal+IGV)

Cálculo automático:
├─ Subtotal = 150.00
├─ IGV = 27.00 (Subtotal × 18%)
├─ Total Antes = 177.00
├─ Descuento = -36.50
└─ TOTAL FINAL = 140.50
```

### **Paso 5: Descarga o Envía → COTIZACION_DESCARGAS + COTIZACION_ENVIOS**
```
El usuario elige:
├─ Descargar Offline (guarda PDF local)
│  └─ Se registra en COTIZACION_DESCARGAS
│     ├─ tipo = "offline"
│     ├─ fecha = "2026-09-24"
│     └─ ubicacion = "App Mobile"
│
├─ Descargar Online (genera PDF en servidor)
│  └─ Se registra en COTIZACION_DESCARGAS
│     ├─ tipo = "online"
│     └─ url = "https://servidor.com/pdf/cot_12345.pdf"
│
├─ Enviar WhatsApp
│  └─ Se registra en COTIZACION_ENVIOS
│     ├─ canal = "whatsapp"
│     ├─ destinatario = "+51 999 888 777"
│     └─ fecha_envio = "2026-09-24 14:30"
│
└─ Enviar Email
   └─ Se registra en COTIZACION_ENVIOS
      ├─ canal = "email"
      ├─ destinatario = "contacto@abcconstructora.com"
      └─ fecha_envio = "2026-09-24 14:31"
```

---

## 📋 Detalles de Cada Tabla

### **TABLA: EMPRESAS** 🏢
**Propósito**: Guardar datos de empresas cliente  
**Campos Clave**:
- `id` (PK): Identificador único
- `ruc` (UNIQUE): Registro Único de Contribuyente (validado con SUNAT)
- `nombre`: Razón social
- `direccion`: Dirección física
- `ciudad`: Lima, Arequipa, etc.

**Ejemplo**:
```
ID | RUC          | NOMBRE              | CIUDAD
1  | 20123456789  | ABC Constructora    | Lima
2  | 20987654321  | XYZ Inmobiliaria    | Arequipa
```

---

### **TABLA: CONTACTOS** 👤
**Propósito**: Personas autorizadas dentro de cada empresa  
**Campos Clave**:
- `id_empresa` (FK): Relaciona a EMPRESAS
- `nombre`: Nombre completo
- `apellido`: Apellido
- `cargo`: "Jefe de Proyecto", "Gerente de Compras"
- `telefono`: Celular (para WhatsApp)
- `email`: Correo corporativo

**Relación**: 1 Empresa → N Contactos  
**Ejemplo**: ABC Constructora tiene 3 contactos (Juan Pérez, María López, Carlos Díaz)

---

### **TABLA: PERSONAS** 👨‍💼
**Propósito**: Usuarios internos (tu equipo de laboratorio)  
**Campos Clave**:
- `id`: Identificador
- `nombre`: Nombre del usuario
- `email`: Email corporativo (@gtqc.com)
- `rol`: "admin", "cotizador", "técnico"
- `activo`: true/false

---

### **TABLA: ENSAYOS_CATALOGO** 🔬
**Propósito**: Catálogo maestro de todos los ensayos disponibles  
**Campos Clave**:
- `id` (PK): Identificador único
- `nombre`: "Compresión", "Flexión", "Adherencia"
- `descripcion`: Detalles técnicos
- `norma`: **NUEVO** - Norma técnica (NTP 339.034, NTP 339.045, etc.)
- `precio_base`: Precio unitario
- `tiempo_entrega_dias`: Cuántos días tarda

**Importancia de `norma`**:
- Se muestra al cliente en cada línea de la cotización
- El cliente ve QUÉ norma aplicará su ensayo
- Aumenta credibilidad y transparencia

---

### **TABLA: PAQUETES_CATALOGO** 📦
**Propósito**: Combos de ensayos prearmados  
**Campos Clave**:
- `id`: Identificador
- `nombre`: "Paquete Estructural", "Paquete Control"
- `descripcion`: Qué incluye
- `servicios_incluidos`: JSON con lista de ensayos

**Ejemplo**: "Paquete Estructural" incluye:
- Compresión (NTP 339.034)
- Flexión (NTP 339.045)
- Módulo de Elasticidad

---

### **TABLA: PLANTILLAS** 📄
**Propósito**: Los 3 modelos de cotización (sólo varían términos)  
**Campos Clave**:
- `id`: PL001, PL002, PL003
- `nombre`: "Estándar", "Premium", "Express"
- `logo`: 🧪, ⭐, ⚡
- `terminosCondiciones`: El **ÚNICO campo que cambia**

**IMPORTANTE**: Formato, logo en header, estructura de datos → **IDÉNTICOS**  
Solo cambian los términos legales en la Pantalla 4 (Resumen).

---

### **TABLA: COTIZACIONES** 🎯 **(LA TABLA CENTRAL)**
**Propósito**: Cada cotización es un documento independiente  
**Campos Clave**:
- `id` (PK): Identificador único (p.ej., "COT-20260924-001")
- `id_empresa` (FK): A qué empresa pertenece
- `id_contacto` (FK): Quién la solicita
- `id_plantilla` (FK): Qué modelo usa (Estándar/Premium/Express)
- `subtotal`: Suma de todos los items
- `igv`: 18% del subtotal
- `descuento`: Si aplica
- `total`: Total final
- `vigencia_dias`: Días que es válida (30/45/15 según plantilla)
- `estado`: "borrador", "enviada", "aceptada", "rechazada"
- `fecha_creacion`: Cuándo se creó
- `fecha_vencimiento`: Cuándo vence

---

### **TABLA: COTIZACION_ITEMS** 📍
**Propósito**: Cada línea dentro de una cotización  
**Campos Clave**:
- `id_cotizacion` (FK): A qué cotización pertenece
- `tipo`: "ensayo" o "paquete"
- `id_ensayo` o `id_paquete` (FK): Qué ensayo/paquete es
- `cantidad`: Cuántas veces se repite
- `precio_unitario`: Precio del ensayo
- `norma` (NEW): Norma técnica aplicada
- `subtotal`: cantidad × precio

**Relación**: 1 Cotización → N Items

---

### **TABLA: DESCUENTOS** 💰
**Propósito**: Registrar descuentos aplicados  
**Campos Clave**:
- `id_cotizacion` (FK): A qué cotización
- `monto`: Cantidad a descontar
- `tipo`: "porcentaje" o "monto_fijo"
- `razon`: "Cliente frecuente", "Volumen", etc.

**Cálculo Correcto**:
```
Descuento se aplica al TOTAL (después de IGV):
├─ Subtotal = 1000.00
├─ IGV (18%) = 180.00
├─ Subtotal + IGV = 1180.00
├─ Descuento (10%) = -118.00
└─ TOTAL FINAL = 1062.00  ✅
```

---

### **TABLA: COTIZACION_DESCARGAS** ⬇️
**Propósito**: Auditoría de descargas (PDF offline/online)  
**Campos Clave**:
- `id_cotizacion` (FK): Qué cotización se descargó
- `tipo`: "offline" o "online"
- `fecha_descarga`: Cuándo
- `ubicacion`: "Mobile", "Servidor"

---

### **TABLA: COTIZACION_ENVIOS** 📧
**Propósito**: Auditoría de envíos (WhatsApp/Email)  
**Campos Clave**:
- `id_cotizacion` (FK): Qué cotización se envió
- `canal`: "whatsapp" o "email"
- `destinatario`: Número o correo
- `fecha_envio`: Cuándo se envió
- `estado`: "enviado", "entregado", "error"

---

## 🔗 Las 7 Relaciones Clave

| Relación | Significado |
|----------|------------|
| **EMPRESAS → CONTACTOS** | 1 empresa tiene N contactos |
| **EMPRESAS → COTIZACIONES** | 1 empresa solicita N cotizaciones |
| **CONTACTOS → COTIZACIONES** | 1 contacto crea N cotizaciones |
| **PLANTILLAS → COTIZACIONES** | 1 plantilla se usa en N cotizaciones |
| **COTIZACIONES → ITEMS** | 1 cotización tiene N items |
| **ENSAYOS_CATALOGO → ITEMS** | 1 ensayo aparece en N items |
| **COTIZACIONES → DESCARGAS/ENVIOS** | 1 cotización → N descargas/envíos |

---

## 💡 Ventajas de Esta Estructura

✅ **Normalización**: Sin datos redundantes  
✅ **Escalabilidad**: Fácil agregar nuevos ensayos, plantillas, clientes  
✅ **Auditoría Completa**: Sé quién descargó qué y cuándo  
✅ **Flexibilidad de Plantillas**: Añade modelos sin duplicar la lógica  
✅ **Integraciones**: Conecta con SUNAT (RUC), WhatsApp, Email sin problemas  
✅ **Reportes**: Genera análisis por cliente, ensayo, período, plantilla  
✅ **Seguridad**: Roles (admin/cotizador/técnico) en tabla PERSONAS  

---

## 🎬 Casos de Uso Reales

### **Caso 1: Cliente Frecuente**
```
1. Juan (contacto de ABC Constructora) entra al cotizador
2. Selecciona plantilla ⭐ PREMIUM (45 días, flexible)
3. Añade 5 ensayos: Compresión, Flexión, Adherencia, Porosidad, etc.
4. Aplica 15% descuento (cliente frecuente)
5. Total: $2,100 → Descuento -$318 = $1,782
6. Descarga PDF offline
7. Sistema registra: descarga offline el 2026-09-24 14:45
8. Usuario luego envía por WhatsApp
9. Sistema registra: envío WhatsApp a +51 999888777 el 2026-09-24 14:46
10. ABC Constructora recibe, acepta, y aprueban la cotización
11. Sistema cambia estado a "aceptada"
12. Dashboard del cliente muestra: 1 cotización aceptada este mes
```

### **Caso 2: Proyecto Urgente**
```
1. María (XYZ Inmobiliaria) necesita resultado YA
2. Selecciona ⚡ EXPRESS (15 días, 48h de entrega)
3. Añade paquete: "Paquete Estructural" (incluye 3 ensayos preseleccionados)
4. Sistema automáticamente muestra normas: NTP 339.034, NTP 339.045
5. Sin descuento (pago al inicio)
6. Descarga + Envía por Email
7. Laboratorio recibe, atiende en 48 horas
8. Envía resultados por Email
9. María tiene constancia de entrega
```

---

## 📊 Dashboard del Cliente

Con esta BD, el cliente ve:
- **Stat Cards**: Total gastado, cotizaciones aprobadas, últimos 30 días
- **Gráficos**: Gastos por mes, ensayos más usado, tendencias
- **Tabla**: Listado de todas sus cotizaciones (estado, fecha, monto)
- **Filtros**: Por período, plantilla, estado

---

## 🚀 Siguientes Pasos (Backend)

Para implementar en producción:
1. **Crear BD real** (MySQL, PostgreSQL, etc.)
2. **API REST** (Node.js, Python): GET/POST/PUT/DELETE cotizaciones
3. **Integración SUNAT**: Validar RUC automáticamente
4. **PDF Real**: Usar librería pdfkit o similar
5. **WhatsApp Business API**: Envíos automáticos
6. **Email**: Plantillas HTML, adjuntar PDF
7. **Autenticación**: Login de usuarios
8. **Tokens de Sesión**: JWT o similar

---

## 🎓 Para Explicar al Cliente

**Script de Presentación** (3-5 minutos):

> "La base de datos tiene 11 tablas organizadas en 3 categorías:  
> - **Maestras**: Ensayos, paquetes, plantillas (tus catálogos)  
> - **Central**: Cotizaciones (la transacción)  
> - **Detalles**: Items, descuentos, auditoría (trazabilidad)  
>
> Cuando generamos una cotización, ocurre esto:  
> 1. Se crea en COTIZACIONES con cliente y plantilla  
> 2. Añadimos items en COTIZACION_ITEMS con ensayos y **normas técnicas**  
> 3. Aplicamos descuentos en DESCUENTOS (correctamente, sobre el total)  
> 4. Cuando descargas o envías, queda registrado en DESCARGAS/ENVIOS  
>
> Esto te permite:
> - Ver qué cliente pidió qué ensayo  
> - Saber si aceptó la cotización  
> - Generar reportes por período  
> - Auditar cada descarga y envío  
> - Añadir nuevos ensayos/plantillas sin afectar cotizaciones viejas  
>
> ¿Preguntas sobre alguna parte?"

---

**Archivo generado**: 2026-09-24  
**Versión**: 1.0 - Presentación Inicial  
**Destinatario**: Cliente GTQC Laboratorio de Testing
