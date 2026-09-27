# Sistema de Paquetes vs Unidades - Guía Detallada

## 1. Introducción

Tu presupuesto actual tiene **DOS modelos de precios mixtos**:

1. **PAQUETES (Tarifa Cerrada)** - Ej: "Exploración directa del subsuelo" = Precio por CLIENTE
2. **UNIDADES (Tarifa por Cantidad)** - Ej: "Perfil Estratigráfico" = S/ 70 × cantidad

La PWA debe manejar **AMBOS sistemas en el mismo presupuesto**, de forma flexible y automática.

---

## 2. Análisis de Tu Presupuesto Actual

### 2.1 Tabla Original (Tal como la compartiste)

```
REFERENCIA: [Tu presupuesto actual]

ITEM | DESCRIPCIÓN | ASTM-NTP | UND | CANTIDAD | COSTO UNITARIO (S/.) | COSTO TOTAL (S/.)
-----|-------------|----------|-----|----------|----------------------|------------------

1. ESTUDIO DE SUELOS

1    | Exploración directa del subsuelo mediante excavación (calicatas) min. 4 m - | 339.162 | UND. | 4.0 | CLIENTE | CLIENTE
2    | PERFIL ESTRATIGRÁFICO CON ENSAYO 4m (por estrato) | NTP 050 | UND. | 4.0 | S/ 70.00 | S/280.00
3    | ENSAYO DE TRIAXIAL | 339.166 | UND. | 2.0 | S/ 650.00 | S/1,300.00
4    | ENSAYO DE ANALISIS GRANULOMETRICO POR TAMIZADO Y CLASIFICACION SUCS. | 339.128 | UND. | 4.0 | S/ 150.00 | S/600.00
5    | ENSAYO DE LIMITE LIQUIDO, LIMITE PLASTICO E INDICE DE PLASTICIDAD. | 339.129 | UND. | 4.0 | S/ 150.00 | S/600.00
6    | ENSAYOS QUÍMICOS (CONTENIDO DE SALES SOLUBLES - SULFATOS...) | 339.178, 339.152, 339.177 | UND | 1.0 | S/ 280.00 | S/280.00

2. ADMINISTRACIÓN Y LOGÍSTICA

1    | INFORME DE CAPACIDAD | - | UND. | 1.0 | S/ 800.00 | S/800.00
2    | MOVILIZACIÓN (TRASLADO DE MUESTRAS) | - | UND. | 1.0 | S/ 90.00 | S/90.00
3    | SEGUROS DEL PERSONAL SCTR | - | UND. | 3.0 | INCLUYE | INCLUYE

SUBTOTAL: S/3,950.00
IGV 18%: S/711.00
TOTAL: S/4,661.00
```

### 2.2 Análisis por Fila

| # | DESCRIPCIÓN | MODELO | PRECIO | CANTIDAD | SUBTOTAL | NOTAS |
|---|---|---|---|---|---|---|
| 1 | Exploración directa | **PAQUETE** | CLIENTE (a definir) | 4.0 | CLIENTE | Precio variable según cliente |
| 2 | Perfil Estratigráfico | **UNIDAD** | S/ 70.00 | 4.0 | S/ 280.00 | Precio × Cantidad |
| 3 | Ensayo Triaxial | **UNIDAD** | S/ 650.00 | 2.0 | S/ 1,300.00 | Precio × Cantidad |
| 4 | Análisis Granulométrico | **UNIDAD** | S/ 150.00 | 4.0 | S/ 600.00 | Precio × Cantidad |
| 5 | Ensayo Límites | **UNIDAD** | S/ 150.00 | 4.0 | S/ 600.00 | Precio × Cantidad |
| 6 | Ensayos Químicos | **UNIDAD** | S/ 280.00 | 1.0 | S/ 280.00 | Precio × Cantidad |
| 7 | Informe de Capacidad | **PAQUETE** | S/ 800.00 | 1.0 | S/ 800.00 | Tarifa cerrada |
| 8 | Movilización | **UNIDAD** | S/ 90.00 | 1.0 | S/ 90.00 | Precio × Cantidad (flexible) |
| 9 | Seguros del Personal | **INCLUYE** | INCLUYE | 3.0 | INCLUYE | Servicio incluido, no cobra |

---

## 3. Configuración en la PWA

### 3.1 Estructura de Datos (Base de Datos)

Cada servicio en el catálogo debe tener esta estructura:

```json
{
  "id": "svc_001",
  "nombre": "Perfil Estratigráfico con Ensayo",
  "descripcion": "Por estrato, mínimo 4m",
  "norma": "NTP 050",
  
  "tipoVenta": "UNIDAD",  // O "PAQUETE", "INCLUYE"
  
  // Si UNIDAD:
  "precioUnitario": 70.00,
  "cantidadEditable": true,
  "unidadMedida": "UND",
  
  // Si PAQUETE:
  "precioPaquete": 800.00,
  "cantidadFija": 1,
  "cantidadEditable": false,
  
  // Si INCLUYE:
  "cobrable": false,
  "mostrarEnPresupuesto": true,
  
  "activo": true,
  "createdAt": "2026-09-01T10:00:00Z"
}
```

### 3.2 Ejemplo: Item de UNIDAD

```javascript
// ITEM: Perfil Estratigráfico
const itemUnidad = {
  id: "svc_002",
  nombre: "Perfil Estratigráfico con Ensayo 4m",
  norma: "NTP 050",
  
  tipoVenta: "UNIDAD",
  precioUnitario: 70.00,
  cantidadEditable: true,
  unidadMedida: "UND",
  
  // Usuario puede cambiar:
  cantidadEnPresupuesto: 4,
  
  // Cálculo automático:
  subtotal: 4 * 70.00, // = S/ 280.00
};

// En la PWA:
console.log(`${itemUnidad.nombre}`);
console.log(`Precio: S/ ${itemUnidad.precioUnitario} × ${itemUnidad.cantidadEnPresupuesto} = S/ ${itemUnidad.subtotal}`);
// OUTPUT: Perfil Estratigráfico con Ensayo 4m
//         Precio: S/ 70.00 × 4 = S/ 280.00
```

### 3.3 Ejemplo: Item de PAQUETE

```javascript
// ITEM: Informe de Capacidad
const itemPaquete = {
  id: "svc_007",
  nombre: "Informe de Capacidad",
  
  tipoVenta: "PAQUETE",
  precioPaquete: 800.00,
  cantidadFija: 1,
  cantidadEditable: false, // Usuario NO puede cambiar
  
  // En la PWA:
  cantidadEnPresupuesto: 1, // Siempre 1
  
  // Cálculo automático:
  subtotal: 800.00, // Siempre el precio del paquete
};

// En la PWA:
console.log(`${itemPaquete.nombre}`);
console.log(`Tarifa: S/ ${itemPaquete.precioPaquete} (cantidad fija: 1)`);
// OUTPUT: Informe de Capacidad
//         Tarifa: S/ 800.00 (cantidad fija: 1)
```

### 3.4 Ejemplo: Item de CLIENTE (Precio a definir)

```javascript
// ITEM: Exploración directa
const itemCliente = {
  id: "svc_001",
  nombre: "Exploración directa del subsuelo mediante excavación (calicatas) min. 4m",
  norma: "339.162",
  
  tipoVenta: "CLIENTE", // Precio especial por cliente
  cantidadEnPresupuesto: 4,
  
  // El usuario debe ingresar el precio:
  precioClienteIngresado: null, // Usuario lo define
  
  // Cálculo automático (si usuario ingresa precio):
  subtotal: null, // Será: precioClienteIngresado × cantidadEnPresupuesto (si aplica)
};

// En la PWA:
console.log(`${itemCliente.nombre}`);
console.log(`Precio: A DEFINIR POR CLIENTE`);
console.log(`Cantidad: ${itemCliente.cantidadEnPresupuesto}`);
// OUTPUT: Exploración directa...
//         Precio: A DEFINIR POR CLIENTE
//         Cantidad: 4
```

### 3.5 Ejemplo: Item de INCLUYE (No Cobra)

```javascript
// ITEM: Seguros del Personal
const itemIncluye = {
  id: "svc_009",
  nombre: "Seguros del Personal SCTR",
  
  tipoVenta: "INCLUYE",
  cobrable: false, // No afecta el total
  mostrarEnPresupuesto: true, // Pero aparece en el PDF (como referencia)
  
  // No tiene precio unitario
  // No afecta cálculos
};

// En la PWA:
console.log(`${itemIncluye.nombre}`);
console.log(`Estado: INCLUYE (sin costo adicional)`);
// OUTPUT: Seguros del Personal SCTR
//         Estado: INCLUYE (sin costo adicional)
```

---

## 4. Comportamiento en la PWA (Interfaz)

### 4.1 Tabla de Items (Editabilidad por Tipo)

```html
<!-- UNIDAD: Usuario PUEDE cambiar cantidad -->
<tr>
  <td>2</td>
  <td>Perfil Estratigráfico</td>
  <td><span class="badge badge-unidad">UNIDAD</span></td>
  <td>
    <input type="number" value="4" min="1" onchange="recalcular()">
    <!-- Campo HABILITADO -->
  </td>
  <td>S/ 70.00</td>
  <td>S/ 280.00 <small>(recalculado)</small></td>
</tr>

<!-- PAQUETE: Usuario NO PUEDE cambiar cantidad -->
<tr>
  <td>7</td>
  <td>Informe de Capacidad</td>
  <td><span class="badge badge-paquete">PAQUETE</span></td>
  <td>
    <input type="number" value="1" min="1" disabled>
    <!-- Campo DESHABILITADO -->
  </td>
  <td>S/ 800.00</td>
  <td>S/ 800.00 <small>(fijo)</small></td>
</tr>

<!-- CLIENTE: Usuario DEBE ingresar precio -->
<tr>
  <td>1</td>
  <td>Exploración directa...</td>
  <td><span class="badge badge-cliente">CLIENTE</span></td>
  <td>
    <input type="number" value="4" min="1" onchange="recalcular()">
    <!-- Campo HABILITADO para cantidad -->
  </td>
  <td>
    <input type="number" placeholder="Ingresar precio" onchange="recalcular()">
    <!-- Campo HABILITADO para precio -->
  </td>
  <td>
    <span id="subtotal-1">Calcular</span>
    <!-- Se actualiza cuando usuario ingresa precio -->
  </td>
</tr>

<!-- INCLUYE: Usuario NO VE campos editables -->
<tr>
  <td>9</td>
  <td>Seguros del Personal SCTR</td>
  <td><span class="badge badge-incluye">INCLUYE</span></td>
  <td colspan="4">
    <small style="color: #999;">(Sin costo adicional - Incluido en el servicio)</small>
  </td>
</tr>
```

### 4.2 Lógica de Cálculo (JavaScript)

```javascript
// Función para calcular subtotal según tipo de venta
function calcularSubtotal(item) {
  switch(item.tipoVenta) {
    
    case 'UNIDAD':
      // Subtotal = Precio Unitario × Cantidad
      return item.precioUnitario * item.cantidadEnPresupuesto;
    
    case 'PAQUETE':
      // Subtotal = Precio Paquete (cantidad siempre 1)
      return item.precioPaquete;
    
    case 'CLIENTE':
      // Subtotal = Precio Ingresado × Cantidad (si aplica)
      if (item.precioClienteIngresado) {
        return item.precioClienteIngresado * item.cantidadEnPresupuesto;
      }
      return null; // Aún no definido
    
    case 'INCLUYE':
      // No afecta el total
      return 0;
    
    default:
      return 0;
  }
}

// Ejemplo de uso
const items = [
  { tipoVenta: 'UNIDAD', precioUnitario: 70, cantidadEnPresupuesto: 4 },
  { tipoVenta: 'PAQUETE', precioPaquete: 800 },
  { tipoVenta: 'INCLUYE' },
];

items.forEach(item => {
  console.log(`Subtotal: S/ ${calcularSubtotal(item)}`);
});
// OUTPUT:
// Subtotal: S/ 280
// Subtotal: S/ 800
// Subtotal: S/ 0
```

---

## 5. Configuración en Panel de Admin

### 5.1 Pantalla de Creación de Servicios

```
┌─────────────────────────────────────────────┐
│ CREAR NUEVO SERVICIO                        │
├─────────────────────────────────────────────┤
│                                             │
│ Nombre del Servicio: [____________]         │
│ Descripción: [____________________]         │
│ Norma/Código: [____________________]        │
│                                             │
│ TIPO DE VENTA: ○ UNIDAD ○ PAQUETE           │
│                ○ CLIENTE ○ INCLUYE          │
│                                             │
├─────────────────────────────────────────────┤
│ SI SELECCIONA "UNIDAD":                    │
│ • Precio Unitario: [_____]                  │
│ • Unidad Medida: [dropdown: UND, M, KG...] │
│ • ☑ Cantidad Editable en Presupuestos       │
│                                             │
├─────────────────────────────────────────────┤
│ SI SELECCIONA "PAQUETE":                   │
│ • Precio Paquete: [_____]                   │
│ • ☐ Cantidad Editable (unchecked)           │
│                                             │
├─────────────────────────────────────────────┤
│ SI SELECCIONA "CLIENTE":                   │
│ • ☑ Usuario debe ingresar precio            │
│ • ☑ Cantidad editable                       │
│                                             │
├─────────────────────────────────────────────┤
│ SI SELECCIONA "INCLUYE":                   │
│ • ☐ Cobrable (unchecked)                    │
│ • ☑ Mostrar en Presupuesto (checked)        │
│                                             │
├─────────────────────────────────────────────┤
│ Activo: ☑                                   │
│ [Guardar]  [Cancelar]                      │
└─────────────────────────────────────────────┘
```

### 5.2 Catálogo de Servicios (Admin)

```
┌─────────────────────────────────────────────────────────────┐
│ CATÁLOGO DE SERVICIOS                                       │
├─────────────────────────────────────────────────────────────┤
│ [+ Crear Nuevo Servicio]                                    │
│                                                             │
│ ID  | NOMBRE | TIPO | PRECIO | EDITABLE | ACCIONES       │
│─────┼────────┼──────┼────────┼──────────┼──────────        │
│ 001 │Perfil  │ UNID │ S/70   │ ☑        │ ✏️ 🗑️            │
│ 002 │Ensayo  │ UNID │ S/650  │ ☑        │ ✏️ 🗑️            │
│ 003 │Informe │ PAQ  │ S/800  │ ☐        │ ✏️ 🗑️            │
│ 004 │Explor. │ CLI  │ PRECIO │ ☑        │ ✏️ 🗑️            │
│ 005 │Seguros │ INC  │ —      │ —        │ ✏️ 🗑️            │
│                                                             │
│ [Filtrar] [Buscar]                                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Flujo Completo: Desde Catálogo a Presupuesto

### 6.1 Paso 1: Admin Crea Catálogo

```
ADMIN GTQC
   ↓
Crea servicios en catálogo:
  • Perfil Estratigráfico = UNIDAD, S/ 70
  • Ensayo Triaxial = UNIDAD, S/ 650
  • Informe Capacidad = PAQUETE, S/ 800
  • Exploración Directa = CLIENTE (precio a definir)
   ↓
Servicio guardado en BD
```

### 6.2 Paso 2: Ejecutivo Crea Presupuesto

```
EJECUTIVO GTQC
   ↓
Abre PWA → "Nuevo Presupuesto"
   ↓
Valida RUC cliente (SUNAT) → Datos se llenan automáticamente
   ↓
Comienza a agregar servicios del catálogo:
  
  1️⃣ Agrega "Perfil Estratigráfico"
     - Tipo: UNIDAD
     - Cantidad: 4 (usuario edita)
     - Precio: S/ 70 (fijo)
     - Subtotal: S/ 280 (automático)
  
  2️⃣ Agrega "Ensayo Triaxial"
     - Tipo: UNIDAD
     - Cantidad: 2 (usuario edita)
     - Precio: S/ 650 (fijo)
     - Subtotal: S/ 1,300 (automático)
  
  3️⃣ Agrega "Informe Capacidad"
     - Tipo: PAQUETE
     - Cantidad: 1 (FIJA, no editable)
     - Precio: S/ 800 (fijo)
     - Subtotal: S/ 800 (automático)
  
  4️⃣ Agrega "Exploración Directa"
     - Tipo: CLIENTE
     - Cantidad: 4 (usuario edita)
     - Precio: [Usuario ingresa S/ X] ← ACCIÓN REQUERIDA
     - Subtotal: S/ (X × 4) (automático una vez ingresa precio)
   ↓
Presupuesto listo con todos los datos
   ↓
Sistema calcula:
  - Subtotal total: S/ (280 + 1,300 + 800 + (X × 4))
  - IGV: Subtotal × 18%
  - TOTAL: Subtotal + IGV
   ↓
Ejecutivo genera PDF y envía al cliente
```

### 6.3 Paso 3: Cliente Recibe Presupuesto

```
El PDF muestra exactamente:

┌─────────────────────────────────────────┐
│ PRESUPUESTO BUD-2026-0001               │
├─────────────────────────────────────────┤
│                                         │
│ 1. Perfil Estratigráfico                │
│    4 × S/ 70.00 = S/ 280.00             │
│                                         │
│ 2. Ensayo Triaxial                      │
│    2 × S/ 650.00 = S/ 1,300.00          │
│                                         │
│ 3. Informe de Capacidad                 │
│    1 × S/ 800.00 = S/ 800.00            │
│                                         │
│ 4. Exploración Directa (por calicatas)  │
│    4 × S/ [PRECIO CLIENTE] = [TOTAL]    │
│                                         │
│ ─────────────────────────────────────   │
│ SUBTOTAL: S/ [TOTAL]                    │
│ IGV 18%: S/ [IGV]                       │
│ TOTAL: S/ [FINAL]                       │
│                                         │
│ Válido por: 15 días                     │
│ Términos y Condiciones: [...]           │
└─────────────────────────────────────────┘
```

---

## 7. Casos Especiales

### 7.1 ¿Qué pasa si cambio la cantidad?

**Caso: UNIDAD**
```
Usuario cambia Perfil Estratigráfico de 4 a 6:
  Antes: 4 × S/ 70 = S/ 280
  Después: 6 × S/ 70 = S/ 420
  Sistema recalcula automáticamente ✓
```

**Caso: PAQUETE**
```
Usuario intenta cambiar Informe de Capacidad a 2:
  Campo DESHABILITADO → No puede cambiar ✗
  Siempre será: 1 × S/ 800 = S/ 800
```

**Caso: CLIENTE**
```
Usuario ingresa cantidad 4, pero aún no precio:
  Subtotal = PENDIENTE
  Cuando ingresa precio (ej: S/ 150):
  4 × S/ 150 = S/ 600 (se calcula automáticamente)
```

### 7.2 ¿Qué pasa con INCLUYE?

```
"Seguros del Personal SCTR" = INCLUYE
  • Aparece en presupuesto (como referencia)
  • NO suma a totales
  • NO editable
  • Propósito: informar al cliente qué servicios están incluidos
```

### 7.3 ¿Puedo mezclar tipos en un presupuesto?

**SÍ**, absolutamente. Tu presupuesto actual es un buen ejemplo:

```
Presupuesto = Mezcla UNIDADES + PAQUETES + CLIENTE + INCLUYE

✓ Perfil Estratigráfico = UNIDAD
✓ Ensayo Triaxial = UNIDAD
✓ Ensayos Químicos = UNIDAD
✓ Exploración Directa = CLIENTE
✓ Informe Capacidad = PAQUETE
✓ Movilización = UNIDAD
✓ Seguros = INCLUYE

La PWA maneja todos simultáneamente y calcula el total correctamente.
```

---

## 8. Validaciones y Reglas de Negocio

### 8.1 Validaciones en Formulario

| Campo | Validación | Error |
|-------|-----------|-------|
| **UNIDAD - Cantidad** | Número > 0 | "Cantidad debe ser mayor a 0" |
| **UNIDAD - Cantidad** | Máximo 1000 | "Cantidad máxima: 1000" |
| **CLIENTE - Precio** | Número >= 0 | "Precio no puede ser negativo" |
| **CLIENTE - Precio** | Máximo 999,999 | "Precio muy alto, verifique" |
| **RUC Cliente** | 11 dígitos | "RUC debe tener 11 dígitos" |
| **RUC Cliente** | Validar SUNAT | "RUC no encontrado en SUNAT" |

### 8.2 Reglas de Cálculo

```javascript
// REGLA 1: Si tipo es UNIDAD
if (item.tipoVenta === 'UNIDAD') {
  subtotal = item.precioUnitario * item.cantidadEnPresupuesto;
  // Validar: cantidad > 0
}

// REGLA 2: Si tipo es PAQUETE
if (item.tipoVenta === 'PAQUETE') {
  subtotal = item.precioPaquete;
  // Validar: cantidad siempre 1
  // No permitir editar cantidad
}

// REGLA 3: Si tipo es CLIENTE
if (item.tipoVenta === 'CLIENTE') {
  if (item.precioClienteIngresado > 0) {
    subtotal = item.precioClienteIngresado * item.cantidadEnPresupuesto;
  } else {
    subtotal = null; // Aún no definido
  }
}

// REGLA 4: Si tipo es INCLUYE
if (item.tipoVenta === 'INCLUYE') {
  subtotal = 0; // No afecta total
  // No mostrar en cálculos de IGV/total
}

// TOTAL DEL PRESUPUESTO
totalPresupuesto = sumaDeSubtotales + (sumaDeSubtotales * 0.18); // +IGV
```

---

## 9. Términos y Condiciones (Ejemplo)

Se mostrará en cada presupuesto automáticamente:

```
TÉRMINOS Y CONDICIONES:

1. La presente cotización tiene validez de 15 días desde su emisión.

2. Precios expresados en nuevos soles (S/.), incluyen IGV 18%.

3. Pago al 100% antes del inicio del servicio.
   (O: 50% adelanto + 50% a la entrega, según acuerdo)

4. Cambios posteriores a la aceptación podrán generar cargos 
   adicionales.

5. La validez de esta cotización está sujeta a la disponibilidad 
   de recursos y condiciones climáticas favorables.

6. Una vez aceptado, el presupuesto será considerado como una 
   orden de servicio.

7. GTQC se reserva el derecho de modificar estas condiciones 
   sin previo aviso.

8. Transporte y logística incluida solo hasta el laboratorio.
   Trabajos en campo sujetos a accesibilidad.
```

---

## 10. Tabla Resumen: Tipos de Venta

| TIPO | USO | PRECIO | CANTIDAD | EDITABLE | EJEMPLO |
|------|-----|--------|----------|----------|---------|
| **UNIDAD** | Servicios repetibles, cantidad variable | Fijo por unidad | Variable | ✓ Sí | Ensayo S/ 650 × cantidad |
| **PAQUETE** | Servicios integrales, tarifa cerrada | Fijo total | 1 (fija) | ✗ No | Informe completo = S/ 800 |
| **CLIENTE** | Precios especiales por cliente | Ingresa usuario | Variable | ✓ Sí | Exploración = Precio a definir |
| **INCLUYE** | Servicios incluidos sin costo | Sin precio | — | ✗ No | Seguros del personal |

---

## 11. Chequeo Final para la Reunión

Antes de presentar al cliente, verificar:

- [ ] ¿El catálogo de servicios está completo?
- [ ] ¿Cada servicio tiene configurado su tipo (UNIDAD/PAQUETE/CLIENTE/INCLUYE)?
- [ ] ¿Los precios estándares están correctos?
- [ ] ¿Los servicios "CLIENTE" están identificados (para que usuario ingrese precio)?
- [ ] ¿Los servicios "INCLUYE" están claros?
- [ ] ¿Los términos y condiciones están finalizados?
- [ ] ¿Se probó el flujo completo en la PWA?

---

## 12. Beneficios para GTQC

✅ **Flexibilidad Total:** Mezcla de modelos de precios en un solo presupuesto

✅ **Sin Errores Manuales:** Todos los cálculos son automáticos

✅ **Rápido:** Presupuestos en minutos, no en horas

✅ **Profesional:** PDFs consistentes y personalizados

✅ **Offline:** Funciona sin internet en el campo

✅ **Fácil:** Interfaz simple para ejecutivos sin entrenamiento

✅ **Auditable:** Historial completo de cambios

✅ **Escalable:** Agregar nuevos servicios cuando sea necesario

