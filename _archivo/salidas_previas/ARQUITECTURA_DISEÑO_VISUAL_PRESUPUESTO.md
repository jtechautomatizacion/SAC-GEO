# Arquitectura de Diseño Visual - PWA Presupuestos GTQC

## 1. Estructura Visual General (Basado en Presupuesto Actual)

### 1.1 Divisiones Principales

El presupuesto tiene 3 secciones bien definidas:

```
┌────────────────────────────────────────────────────────────────┐
│ HEADER (Logo + Datos Estáticos GTQC)                          │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  LADO IZQUIERDO         │    CENTRO        │    LADO DERECHO  │
│  (Logo + Empresa)       │  (Certificación) │  (Datos Empresa) │
│                         │                  │                  │
│  - Logo GTQC (sin marca)│   [ISO 9001]     │  RAZÓN SOCIAL    │
│  - Nombre empresa       │   [ISO 27001]    │  RUC:            │
│  - Dirección            │   [ISO 45001]    │  TELÉFONO:       │
│  - Teléfono             │   [ISO 14001]    │  EMAIL:          │
│                         │                  │  Pres. N°:       │
│                         │                  │  Código:         │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│ SECCIÓN CLIENTE (Dinámico - validación SUNAT)                │
│                                                                │
│ Proyecto: ___________________   Fecha: __/__/____             │
│ Cliente (RUC): _______________                                │
│ Razón Social: ________________                                │
│ Dirección: ____________________                               │
│ Teléfono: _____________________                               │
│ Email: _________________________                              │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│ TABLA DE SERVICIOS/ITEMS (Dinámico)                          │
│                                                                │
│ ┌────┬──────────────┬──────────┬────────┬──────────────┐     │
│ │ #  │ Descripción  │ Cantidad │ Precio │ Subtotal     │     │
│ ├────┼──────────────┼──────────┼────────┼──────────────┤     │
│ │ 1. │ Servicio A   │    2     │ 500.00 │  1,000.00    │     │
│ │ 2. │ Servicio B   │    1     │ 750.00 │    750.00    │     │
│ │ 3. │ Servicio C   │    3     │ 250.00 │    750.00    │     │
│ └────┴──────────────┴──────────┴────────┴──────────────┘     │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│ TOTALES (Derecha alineado)                                   │
│                                                                │
│                       Subtotal:      S/ 2,500.00              │
│                       Descuento:     S/   (250.00)            │
│                       IGV (18%):      S/    405.00             │
│                       ─────────────────────────               │
│                       TOTAL:          S/ 2,655.00              │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│ FOOTER (Observaciones, términos, validez)                    │
│                                                                │
│ Observaciones: ________________________________________       │
│ Válido por: 15 días                                           │
│ Fecha vencimiento: __/__/____                                │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 2. Especificación Detallada por Sección

### 2.1 HEADER - Datos Estáticos GTQC (No cambia)

**Ubicación:** Top del documento
**Altura:** 60-80px
**Fondo:** Blanco
**Bordes:** Línea gris clara (2px) en base

#### Estructura HTML
```html
<header class="presupuesto-header">
  <div class="container">
    <h1>GTQC - QUALITY CONSULTING</h1>
    <p class="subtitle">Soluciones de Calidad y Consultoría</p>
    <p class="contact">
      📞 +51 (1) 123-4567 | 📧 contacto@gtqc.com | 
      🏢 Av. Principal 123, Lima, Perú
    </p>
  </div>
</header>
```

#### Estilos CSS
```css
.presupuesto-header {
  background: #fff;
  border-bottom: 2px solid #ddd;
  padding: 15px 20px;
  margin-bottom: 20px;
}

.presupuesto-header h1 {
  font-size: 20px;
  font-weight: bold;
  color: #333;
  margin: 0 0 5px 0;
  font-family: 'Arial', sans-serif;
}

.presupuesto-header .subtitle {
  font-size: 12px;
  color: #666;
  margin: 0 0 8px 0;
}

.presupuesto-header .contact {
  font-size: 11px;
  color: #999;
  margin: 0;
}
```

---

### 2.2 SECCIÓN PRINCIPAL (3 Columnas)

**Ubicación:** Debajo de header
**Altura:** Flexible (120-150px)
**Disposición:** Grid 3 columnas (1fr 1fr 1fr)

#### 2.2.1 LADO IZQUIERDO - Logo + Datos Empresa (Estático)

```html
<section class="presupuesto-main">
  <div class="column left">
    <!-- Logo GTQC -->
    <div class="logo-container">
      <img 
        src="/assets/logo-gtqc-HD.png" 
        alt="GTQC Logo"
        class="logo"
        width="120"
        height="120"
      />
      <!-- IMPORTANTE: Sin marca de agua -->
    </div>
    
    <!-- Datos Empresa -->
    <div class="empresa-info">
      <p class="empresa-name"><strong>GTQC S.A.C.</strong></p>
      <p class="ruc"><strong>RUC:</strong> 20123456789</p>
      <p class="address">Av. Principal 123, Piso 5</p>
      <p class="address">San Isidro, Lima 27 - Perú</p>
      <p class="phone"><strong>Teléfono:</strong> +51 (1) 123-4567</p>
      <p class="email"><strong>Email:</strong> contacto@gtqc.com</p>
    </div>
  </div>
```

#### Estilos CSS
```css
.presupuesto-main {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 20px;
  padding: 15px;
  border: 1px solid #ddd;
  margin-bottom: 20px;
}

.column.left {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 15px;
}

.logo-container {
  background: #f9f9f9;
  padding: 10px;
  border-radius: 4px;
}

.logo {
  max-width: 100%;
  height: auto;
  filter: none; /* Sin marca de agua */
}

.empresa-info p {
  margin: 3px 0;
  font-size: 11px;
  line-height: 1.4;
  color: #333;
}

.empresa-info .empresa-name {
  font-size: 12px;
  font-weight: bold;
  margin-bottom: 5px;
}
```

**Notas Importantes:**
- Logo debe estar en ALTA RESOLUCIÓN (300dpi mínimo)
- **SIN MARCA DE AGUA** (como solicitaste)
- Ajuste responsivo: En móvil, pasar a 1 columna

---

#### 2.2.2 CENTRO - Certificaciones ISO (Estático)

```html
  <div class="column center">
    <div class="certifications">
      <div class="cert-badge iso9001">
        <span class="cert-label">ISO</span>
        <span class="cert-number">9001</span>
        <span class="cert-desc">Gestión Calidad</span>
      </div>
      
      <div class="cert-badge iso27001">
        <span class="cert-label">ISO</span>
        <span class="cert-number">27001</span>
        <span class="cert-desc">Seguridad Info</span>
      </div>
      
      <div class="cert-badge iso45001">
        <span class="cert-label">ISO</span>
        <span class="cert-number">45001</span>
        <span class="cert-desc">Seguridad Laboral</span>
      </div>
      
      <div class="cert-badge iso14001">
        <span class="cert-label">ISO</span>
        <span class="cert-number">14001</span>
        <span class="cert-desc">Medio Ambiente</span>
      </div>
    </div>
  </div>
```

#### Estilos CSS
```css
.column.center {
  display: flex;
  justify-content: center;
  align-items: center;
}

.certifications {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.cert-badge {
  border: 2px solid #333;
  border-radius: 50%;
  width: 70px;
  height: 70px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  background: #fff;
}

.cert-badge.iso9001 { border-color: #4CAF50; }
.cert-badge.iso27001 { border-color: #2196F3; }
.cert-badge.iso45001 { border-color: #FF9800; }
.cert-badge.iso14001 { border-color: #009688; }

.cert-label {
  font-size: 10px;
  font-weight: bold;
  color: #666;
}

.cert-number {
  font-size: 14px;
  font-weight: bold;
  color: #333;
  margin: 2px 0;
}

.cert-desc {
  font-size: 7px;
  color: #999;
  line-height: 1.1;
}
```

**Consideraciones:**
- Certificaciones estáticas (NO cambian entre presupuestos)
- Colores corporativos por certificación
- En móvil: 2x2 grid sigue funcionando

---

#### 2.2.3 LADO DERECHO - Datos Estáticos Empresa (Estático)

```html
  <div class="column right">
    <div class="empresa-datos-derecha">
      <div class="dato">
        <label>RAZÓN SOCIAL:</label>
        <p>GTQC QUALITY CONSULTING S.A.C.</p>
      </div>
      
      <div class="dato">
        <label>RUC:</label>
        <p>20123456789</p>
      </div>
      
      <div class="dato">
        <label>TELÉFONO:</label>
        <p>+51 (1) 123-4567</p>
      </div>
      
      <div class="dato">
        <label>EMAIL:</label>
        <p>contacto@gtqc.com</p>
      </div>
      
      <div class="dato">
        <label>PRESUPUESTO N°:</label>
        <p class="presupuesto-numero">BUD-2026-0001</p>
      </div>
      
      <div class="dato">
        <label>CÓDIGO:</label>
        <p class="codigo-unico">ABC123XYZ789</p>
      </div>
    </div>
  </div>
</section>
```

#### Estilos CSS
```css
.column.right {
  display: flex;
  flex-direction: column;
  justify-content: flex-start;
}

.empresa-datos-derecha {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.empresa-datos-derecha .dato {
  border-bottom: 1px solid #eee;
  padding: 5px 0;
}

.empresa-datos-derecha label {
  font-size: 10px;
  font-weight: bold;
  color: #666;
  display: block;
  margin-bottom: 2px;
}

.empresa-datos-derecha p {
  font-size: 11px;
  color: #333;
  margin: 0;
  line-height: 1.3;
}

.presupuesto-numero {
  font-size: 13px !important;
  font-weight: bold;
  color: #4CAF50;
}

.codigo-unico {
  font-family: 'Courier New', monospace;
  font-size: 10px !important;
  letter-spacing: 1px;
  color: #999;
}
```

---

### 2.3 SECCIÓN CLIENTE (Dinámico - Validación SUNAT)

**Ubicación:** Bajo sección principal
**Altura:** 150-180px
**Fondo:** #f5f5f5 (gris muy claro)
**Bordes:** 1px solid #ddd

```html
<section class="presupuesto-cliente">
  <h3>INFORMACIÓN DEL CLIENTE</h3>
  
  <div class="cliente-form">
    <!-- Primera fila -->
    <div class="form-row">
      <div class="form-group col-3">
        <label for="proyecto">Proyecto *</label>
        <input 
          type="text" 
          id="proyecto"
          placeholder="Nombre del proyecto"
          required
        />
      </div>
      
      <div class="form-group col-2">
        <label for="fecha">Fecha *</label>
        <input 
          type="date" 
          id="fecha"
          required
        />
      </div>
    </div>

    <!-- Segunda fila -->
    <div class="form-row">
      <div class="form-group col-2">
        <label for="ruc-cliente">RUC Cliente *</label>
        <div class="ruc-input-wrapper">
          <input 
            type="text" 
            id="ruc-cliente"
            placeholder="11 dígitos"
            maxlength="11"
            pattern="\d{11}"
            @input="validarRUC"
            required
          />
          <span class="ruc-status" id="ruc-status">
            <!-- Icono de validación aquí -->
          </span>
        </div>
      </div>
    </div>

    <!-- Tercera fila (auto-completada por SUNAT) -->
    <div class="form-row">
      <div class="form-group col-3">
        <label for="razon-social">Razón Social *</label>
        <input 
          type="text" 
          id="razon-social"
          placeholder="Se completa automáticamente"
          readonly
          data-source="sunat"
        />
      </div>
      
      <div class="form-group col-2">
        <label for="direccion">Dirección</label>
        <input 
          type="text" 
          id="direccion"
          placeholder="Se completa automáticamente"
          readonly
          data-source="sunat"
        />
      </div>
    </div>

    <!-- Cuarta fila -->
    <div class="form-row">
      <div class="form-group col-2">
        <label for="telefono-cliente">Teléfono</label>
        <input 
          type="tel" 
          id="telefono-cliente"
          placeholder="Opcional"
        />
      </div>
      
      <div class="form-group col-3">
        <label for="email-cliente">Email</label>
        <input 
          type="email" 
          id="email-cliente"
          placeholder="Opcional"
        />
      </div>
    </div>
  </div>
</section>
```

#### Estilos CSS
```css
.presupuesto-cliente {
  background: #f5f5f5;
  border: 1px solid #ddd;
  border-radius: 4px;
  padding: 15px;
  margin-bottom: 20px;
}

.presupuesto-cliente h3 {
  font-size: 12px;
  font-weight: bold;
  color: #333;
  margin: 0 0 12px 0;
  text-transform: uppercase;
  border-bottom: 2px solid #4CAF50;
  padding-bottom: 8px;
}

.cliente-form {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.form-row {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 15px;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.form-group.col-2 {
  grid-column: span 2;
}

.form-group.col-3 {
  grid-column: span 3;
}

.form-group label {
  font-size: 10px;
  font-weight: bold;
  color: #666;
  text-transform: uppercase;
}

.form-group input {
  font-size: 11px;
  padding: 8px;
  border: 1px solid #ccc;
  border-radius: 3px;
  font-family: 'Arial', sans-serif;
  transition: border-color 0.2s;
}

.form-group input:focus {
  outline: none;
  border-color: #4CAF50;
  background: #fffef0;
}

.form-group input[readonly] {
  background: #eeeeee;
  color: #666;
  cursor: not-allowed;
}

.form-group input[data-source="sunat"] {
  border: 2px solid #2196F3;
  background: #e3f2fd;
}

/* RUC Input especial */
.ruc-input-wrapper {
  position: relative;
  display: flex;
  align-items: center;
}

.ruc-input-wrapper input {
  flex: 1;
  letter-spacing: 2px;
  font-family: 'Courier New', monospace;
}

.ruc-status {
  position: absolute;
  right: 10px;
  font-size: 16px;
}

.ruc-status.validando::before {
  content: "⏳";
  animation: spin 1s linear infinite;
}

.ruc-status.valido::before {
  content: "✓";
  color: #4CAF50;
}

.ruc-status.error::before {
  content: "✗";
  color: #f44336;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
```

#### JavaScript - Validación RUC
```javascript
// En el componente React

const handleRUCChange = async (value) => {
  setRuc(value);
  
  // Validar formato
  if (!/^\d{11}$/.test(value)) {
    setRucStatus('');
    return;
  }

  // Mostrar estado "validando"
  setRucStatus('validando');

  try {
    const result = await SUNATService.consultarRUC(value);
    
    if (result?.status === 'ok') {
      // Auto-completar campos
      setRazonSocial(result.razonSocial);
      setDireccion(result.domicilio);
      setRucStatus('valido');
      
      // Mostrar advertencia si no está activo
      if (result.estado !== 'ACTIVO') {
        showWarning(`⚠ Estado: ${result.estado}`);
      }
    } else {
      setRucStatus('error');
      showError('RUC no encontrado en SUNAT');
    }
  } catch (error) {
    setRucStatus('error');
    console.error('Error:', error);
  }
};
```

**Características Clave:**
- ✓ Validación RUC en tiempo real
- ✓ Auto-completado de Razón Social y Dirección (desde SUNAT)
- ✓ Indicador visual de validación (✓ ✗ ⏳)
- ✓ Campos readonly para datos autocompletados
- ✓ Fallback manual si no hay internet

---

### 2.4 TABLA DE SERVICIOS/ITEMS

**Ubicación:** Bajo sección cliente
**Altura:** Dinámica (mínimo 150px)
**Bordes:** 1px solid #ddd
**Encabezados:** Fondo #f0f0f0

```html
<section class="presupuesto-items">
  <div class="items-header">
    <h3>DETALLES DEL PRESUPUESTO</h3>
    <button class="btn-agregar-item">+ Agregar Servicio</button>
  </div>

  <table class="items-table">
    <thead>
      <tr>
        <th class="col-numero">#</th>
        <th class="col-descripcion">Descripción</th>
        <th class="col-cantidad">Cantidad</th>
        <th class="col-precio">Precio Unitario</th>
        <th class="col-subtotal">Subtotal</th>
        <th class="col-acciones">Acciones</th>
      </tr>
    </thead>
    
    <tbody id="items-list">
      <!-- Items agregados dinámicamente -->
      <tr class="item-row" data-item-id="1">
        <td class="col-numero">1</td>
        <td class="col-descripcion">
          <input type="text" value="Consultoría en Calidad - ISO 9001" />
        </td>
        <td class="col-cantidad">
          <input type="number" value="2" min="1" />
        </td>
        <td class="col-precio">
          <input type="number" value="500.00" min="0" step="0.01" />
        </td>
        <td class="col-subtotal">
          <span class="subtotal-value">1,000.00</span>
        </td>
        <td class="col-acciones">
          <button class="btn-editar">✏️</button>
          <button class="btn-duplicar">📋</button>
          <button class="btn-eliminar">🗑️</button>
        </td>
      </tr>

      <tr class="item-row" data-item-id="2">
        <td class="col-numero">2</td>
        <td class="col-descripcion">
          <input type="text" value="Auditoría Interna" />
        </td>
        <td class="col-cantidad">
          <input type="number" value="1" min="1" />
        </td>
        <td class="col-precio">
          <input type="number" value="750.00" min="0" step="0.01" />
        </td>
        <td class="col-subtotal">
          <span class="subtotal-value">750.00</span>
        </td>
        <td class="col-acciones">
          <button class="btn-editar">✏️</button>
          <button class="btn-duplicar">📋</button>
          <button class="btn-eliminar">🗑️</button>
        </td>
      </tr>
    </tbody>
  </table>

  <div class="items-footer">
    <p class="items-count">Total de items: <strong>2</strong></p>
  </div>
</section>
```

#### Estilos CSS
```css
.presupuesto-items {
  border: 1px solid #ddd;
  border-radius: 4px;
  overflow: hidden;
  margin-bottom: 20px;
}

.items-header {
  background: #f0f0f0;
  padding: 12px 15px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid #ddd;
}

.items-header h3 {
  font-size: 12px;
  font-weight: bold;
  color: #333;
  margin: 0;
  text-transform: uppercase;
}

.btn-agregar-item {
  background: #4CAF50;
  color: white;
  border: none;
  padding: 6px 12px;
  border-radius: 3px;
  font-size: 11px;
  cursor: pointer;
  transition: background 0.2s;
}

.btn-agregar-item:hover {
  background: #45a049;
}

.items-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 11px;
}

.items-table thead {
  background: #f9f9f9;
  border-bottom: 2px solid #ddd;
}

.items-table th {
  padding: 10px;
  text-align: left;
  font-weight: bold;
  color: #666;
  text-transform: uppercase;
  font-size: 10px;
}

.items-table tbody tr {
  border-bottom: 1px solid #eee;
  transition: background 0.2s;
}

.items-table tbody tr:hover {
  background: #f5f5f5;
}

.items-table td {
  padding: 8px 10px;
}

.items-table input[type="text"],
.items-table input[type="number"] {
  width: 100%;
  padding: 4px;
  border: 1px solid #ccc;
  border-radius: 2px;
  font-size: 11px;
  box-sizing: border-box;
}

.items-table input:focus {
  outline: none;
  border-color: #4CAF50;
  background: #fffef0;
}

.col-numero {
  width: 30px;
  text-align: center;
  color: #999;
}

.col-descripcion {
  min-width: 250px;
}

.col-cantidad {
  width: 80px;
  text-align: center;
}

.col-precio {
  width: 120px;
  text-align: right;
}

.col-subtotal {
  width: 100px;
  text-align: right;
  font-weight: bold;
  color: #4CAF50;
}

.col-acciones {
  width: 100px;
  text-align: center;
}

.col-acciones button {
  background: none;
  border: none;
  cursor: pointer;
  font-size: 14px;
  margin: 0 2px;
  opacity: 0.6;
  transition: opacity 0.2s;
}

.col-acciones button:hover {
  opacity: 1;
}

.items-footer {
  background: #f9f9f9;
  padding: 10px 15px;
  border-top: 1px solid #ddd;
  text-align: right;
  font-size: 11px;
  color: #666;
}

.items-count {
  margin: 0;
}
```

**Características:**
- ✓ Tabla editable en tiempo real
- ✓ Auto-cálculo de subtotales
- ✓ Agregar/eliminar/duplicar items
- ✓ Validación de números
- ✓ Feedback visual (hover, focus)

---

### 2.5 SECCIÓN TOTALES

**Ubicación:** Bajo tabla de items
**Altura:** 120-150px
**Alineación:** Derecha
**Fondo:** Blanco

```html
<section class="presupuesto-totales">
  <div class="totales-container">
    
    <div class="totales-row">
      <span class="label">Subtotal:</span>
      <span class="valor" id="subtotal">S/ 2,500.00</span>
    </div>

    <div class="totales-row descuento">
      <span class="label">(-) Descuento:</span>
      <span class="valor" id="descuento-amount">S/ 0.00</span>
      <div class="descuento-controles">
        <input 
          type="number" 
          id="descuento-percent"
          placeholder="% o $"
          min="0"
          step="0.01"
          @change="calcularDescuento"
        />
        <span class="descuento-tipo">
          <label>
            <input type="radio" name="desc-type" value="percent" checked />
            %
          </label>
          <label>
            <input type="radio" name="desc-type" value="fixed" />
            $
          </label>
        </span>
      </div>
    </div>

    <div class="totales-row highlight">
      <span class="label">Subtotal Neto:</span>
      <span class="valor" id="subtotal-neto">S/ 2,500.00</span>
    </div>

    <div class="totales-row igv">
      <span class="label">IGV (18%):</span>
      <span class="valor" id="igv-amount">S/ 450.00</span>
    </div>

    <div class="totales-row total">
      <span class="label-total">TOTAL FINAL:</span>
      <span class="valor-total" id="total-final">S/ 2,950.00</span>
    </div>

  </div>

  <div class="totales-info">
    <p>
      <strong>Válido por:</strong> 
      <select id="validez-dias">
        <option value="7">7 días</option>
        <option value="15" selected>15 días</option>
        <option value="30">30 días</option>
      </select>
    </p>
    <p>
      <strong>Fecha vencimiento:</strong> 
      <span id="fecha-vencimiento">26/09/2026</span>
    </p>
  </div>
</section>
```

#### Estilos CSS
```css
.presupuesto-totales {
  background: #fff;
  border: 1px solid #ddd;
  border-radius: 4px;
  padding: 20px;
  margin-bottom: 20px;
}

.totales-container {
  max-width: 400px;
  margin-left: auto;
}

.totales-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 0;
  border-bottom: 1px solid #eee;
  font-size: 12px;
}

.totales-row.descuento {
  flex-direction: column;
  align-items: flex-start;
  gap: 8px;
}

.totales-row.highlight {
  background: #f5f5f5;
  padding: 10px;
  margin: 5px -20px;
  border-bottom: 2px solid #ddd;
  border-left: 4px solid #4CAF50;
}

.totales-row.igv {
  color: #666;
}

.totales-row.total {
  background: #4CAF50;
  color: white;
  padding: 12px;
  margin: 10px -20px -20px -20px;
  border-radius: 0 0 4px 4px;
  font-size: 14px;
  font-weight: bold;
}

.label {
  font-weight: 500;
  color: #333;
}

.label-total {
  font-weight: bold;
  color: white;
}

.valor {
  font-weight: bold;
  color: #333;
  text-align: right;
  min-width: 80px;
}

.valor-total {
  font-weight: bold;
  color: white;
  text-align: right;
  font-size: 16px;
}

.descuento-controles {
  width: 100%;
  display: flex;
  gap: 10px;
  align-items: center;
}

.descuento-controles input {
  flex: 1;
  padding: 6px;
  border: 1px solid #ccc;
  border-radius: 3px;
  font-size: 11px;
}

.descuento-tipo label {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  cursor: pointer;
}

.descuento-tipo input {
  cursor: pointer;
  margin: 0;
}

.totales-info {
  margin-top: 15px;
  padding-top: 15px;
  border-top: 1px solid #eee;
}

.totales-info p {
  margin: 5px 0;
  font-size: 11px;
  color: #666;
}

.totales-info select {
  padding: 4px 8px;
  border: 1px solid #ccc;
  border-radius: 3px;
  font-size: 11px;
}

#fecha-vencimiento {
  font-weight: bold;
  color: #f44336;
}
```

**Características:**
- ✓ Cálculo automático de subtotales
- ✓ Descuentos por % o cantidad fija
- ✓ IGV calculado automáticamente (18% configurable)
- ✓ Validez con cálculo automático de vencimiento
- ✓ Indicador visual (fondo verde para total)

---

### 2.6 FOOTER - Observaciones y Términos

**Ubicación:** Pie del documento
**Altura:** Flexible (80-120px)
**Fondo:** #f5f5f5

```html
<section class="presupuesto-footer">
  
  <div class="observaciones">
    <h4>OBSERVACIONES</h4>
    <textarea 
      id="observaciones"
      placeholder="Ingrese observaciones adicionales (opcional)"
      rows="3"
    ></textarea>
  </div>

  <div class="terminos">
    <h4>TÉRMINOS Y CONDICIONES</h4>
    <ul>
      <li>La presente cotización tiene validez de <strong id="validez-label">15 días</strong> desde su emisión</li>
      <li>Precios expresados en nuevos soles (S/), incluyen IGV 18%</li>
      <li>Pago al 100% antes de inicio del servicio</li>
      <li>Cambios posteriores a la aceptación podrán generar cargos adicionales</li>
      <li>GTQC se reserva el derecho de cambiar estas condiciones sin previo aviso</li>
    </ul>
  </div>

  <div class="firmas-area">
    <h4>ACEPTACIÓN</h4>
    <div class="firma-row">
      <div class="firma-box">
        <p>Preparado por:</p>
        <p class="firma-value" id="usuario-actual">[Usuario]</p>
        <p class="fecha-small">Fecha: <span id="fecha-prep">11/09/2026</span></p>
      </div>
      
      <div class="firma-box">
        <p>Cliente:</p>
        <p class="firma-label">________________________</p>
        <p class="firma-label">Nombre y Firma</p>
      </div>
    </div>
  </div>

</section>
```

#### Estilos CSS
```css
.presupuesto-footer {
  background: #f5f5f5;
  border: 1px solid #ddd;
  border-radius: 4px;
  padding: 15px;
  margin-top: 20px;
}

.presupuesto-footer h4 {
  font-size: 11px;
  font-weight: bold;
  color: #333;
  text-transform: uppercase;
  margin: 0 0 8px 0;
  padding-bottom: 5px;
  border-bottom: 1px solid #ddd;
}

.observaciones {
  margin-bottom: 15px;
}

.observaciones textarea {
  width: 100%;
  padding: 8px;
  border: 1px solid #ccc;
  border-radius: 3px;
  font-family: 'Arial', sans-serif;
  font-size: 11px;
  resize: vertical;
  box-sizing: border-box;
}

.observaciones textarea:focus {
  outline: none;
  border-color: #4CAF50;
  background: #fffef0;
}

.terminos {
  margin-bottom: 15px;
}

.terminos ul {
  margin: 8px 0;
  padding-left: 20px;
  font-size: 10px;
  color: #666;
  line-height: 1.6;
}

.terminos li {
  margin: 4px 0;
}

.firmas-area {
  margin-top: 20px;
}

.firma-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
  margin-top: 10px;
}

.firma-box {
  text-align: center;
}

.firma-box p {
  margin: 5px 0;
  font-size: 10px;
  color: #666;
}

.firma-value {
  font-weight: bold;
  color: #333;
  font-size: 11px;
}

.firma-label {
  height: 30px;
  display: flex;
  align-items: flex-end;
  border-bottom: 1px solid #333;
  margin: 5px 0;
}

.fecha-small {
  font-size: 9px;
  color: #999;
}
```

---

## 3. Diseño Responsivo (Móvil)

### 3.1 Breakpoints

```css
/* Desktop (1024px+) */
@media (max-width: 768px) {
  /* Tablet */
  .presupuesto-main {
    grid-template-columns: 1fr 1fr;
  }
  
  .certifications {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 480px) {
  /* Móvil */
  .presupuesto-main {
    grid-template-columns: 1fr;
    gap: 15px;
  }
  
  .certifications {
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  
  .cert-badge {
    width: 60px;
    height: 60px;
  }
  
  .form-row {
    grid-template-columns: 1fr;
  }
  
  .form-group.col-2,
  .form-group.col-3 {
    grid-column: span 1;
  }
  
  .items-table {
    font-size: 9px;
  }
  
  .items-table th,
  .items-table td {
    padding: 5px;
  }
  
  .col-descripcion {
    min-width: 120px;
  }
  
  .col-acciones button {
    font-size: 12px;
  }
  
  .firma-row {
    grid-template-columns: 1fr;
  }
}
```

---

## 4. Paleta de Colores

```css
/* Colores Corporativos GTQC */
:root {
  --primary: #4CAF50;      /* Verde GTQC */
  --secondary: #2196F3;    /* Azul (certificaciones ISO) */
  --danger: #f44336;       /* Rojo (alertas) */
  --warning: #FF9800;      /* Naranja (advertencias) */
  --success: #4CAF50;      /* Verde (validación) */
  
  --text-dark: #333;
  --text-medium: #666;
  --text-light: #999;
  
  --bg-light: #f5f5f5;
  --bg-lightest: #f9f9f9;
  
  --border: #ddd;
  --border-light: #eee;
}
```

---

## 5. Componentes React Reutilizables

### 5.1 Estructura de Carpetas

```
src/
├── components/
│   ├── Presupuesto/
│   │   ├── PresupuestoContainer.jsx
│   │   ├── Header.jsx
│   │   ├── MainSection.jsx
│   │   ├── ClienteSection.jsx
│   │   ├── ItemsTable.jsx
│   │   ├── TotalesSection.jsx
│   │   └── Footer.jsx
│   ├── UI/
│   │   ├── RUCValidator.jsx
│   │   ├── FormGroup.jsx
│   │   ├── TableRow.jsx
│   │   └── Badge.jsx
├── styles/
│   ├── presupuesto.css
│   ├── responsive.css
│   └── colors.css
└── services/
    └── sunatService.js
```

### 5.2 Componente Principal

```javascript
// src/components/Presupuesto/PresupuestoContainer.jsx

import React, { useState, useEffect } from 'react';
import Header from './Header';
import MainSection from './MainSection';
import ClienteSection from './ClienteSection';
import ItemsTable from './ItemsTable';
import TotalesSection from './TotalesSection';
import Footer from './Footer';

export default function PresupuestoContainer() {
  const [presupuesto, setPresupuesto] = useState({
    numero: 'BUD-2026-0001',
    codigo: 'ABC123XYZ789',
    fecha: new Date().toISOString().split('T')[0],
    cliente: {},
    items: [],
    totales: {
      subtotal: 0,
      descuento: 0,
      igv: 0,
      total: 0
    }
  });

  const handleGuardar = async () => {
    // Guardar en IndexedDB
    await db.put('presupuestos', presupuesto);
    showNotification('Presupuesto guardado');
  };

  const handleGenerarPDF = async () => {
    // Generar PDF cliente-side con jsPDF
    const pdf = await generatePDFClient(presupuesto);
    pdf.save(`PRESUPUESTO_${presupuesto.numero}.pdf`);
  };

  return (
    <div className="presupuesto-document">
      <Header />
      <MainSection presupuesto={presupuesto} />
      <ClienteSection presupuesto={presupuesto} onChange={setPresupuesto} />
      <ItemsTable presupuesto={presupuesto} onChange={setPresupuesto} />
      <TotalesSection presupuesto={presupuesto} onChange={setPresupuesto} />
      <Footer presupuesto={presupuesto} />
      
      <div className="acciones-footer">
        <button onClick={handleGuardar}>💾 Guardar</button>
        <button onClick={handleGenerarPDF}>📄 Descargar PDF</button>
        <button onClick={() => window.print()}>🖨️ Imprimir</button>
      </div>
    </div>
  );
}
```

---

## 6. Flujo de Generación de PDF

### Cliente (jsPDF - Offline)
1. Lee datos del presupuesto
2. Renderiza estructura HTML/CSS en PDF
3. Mantiene diseño exacto
4. Descarga instantáneamente

### Servidor (PDFKit - Profesional)
1. Recibe JSON del presupuesto
2. Genera PDF con alta compresión
3. Agrega firma digital (opcional)
4. Almacena en BD
5. Retorna URL descargable

---

## 7. Notas de Implementación

✓ **Logo sin marca de agua**: Usar PNG de alta resolución sin capas de marca
✓ **Formatos consistentes**: Mantener CSS fijo, cambios solo en datos
✓ **Mobile-first**: Diseño responsive desde el principio
✓ **Accesibilidad**: Labels con `<label>`, inputs con IDs únicos
✓ **Performance**: Lazy-load de imágenes, CSS modular
✓ **Seguridad**: Credenciales SUNAT en backend, datos sensibles no en frontend

