# PWA - GENERACIÓN DE PDFs (MÉTODO TÉCNICO DETALLADO)
## Cómo funciona la generación de PDFs en la PWA
**Guía Arquitectónica | Presupuestos GTQC**

---

## 1. VISIÓN GENERAL: DOS ESTRATEGIAS

La PWA tiene **DOS métodos** para generar PDFs:

```
┌─────────────────────────────────────────────────────────┐
│  ESTRATEGIA 1: GENERACIÓN EN CLIENTE (Offline)         │
├─────────────────────────────────────────────────────────┤
│  Donde: En el navegador del usuario                     │
│  Cuándo: Siempre (con o sin internet)                  │
│  Librería: jsPDF + html2pdf                            │
│  Velocidad: Instantáneo (< 1 segundo)                  │
│  Uso: Presupuestos offline                             │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  ESTRATEGIA 2: GENERACIÓN EN SERVIDOR (Online)         │
├─────────────────────────────────────────────────────────┤
│  Donde: En el servidor backend                         │
│  Cuándo: Cuando hay internet                           │
│  Librería: PDFKit / ReportLab                          │
│  Velocidad: 2-3 segundos (incluye red)                 │
│  Uso: PDFs de calidad profesional                      │
└─────────────────────────────────────────────────────────┘
```

---

## 2. MÉTODO 1: GENERACIÓN EN CLIENTE (OFFLINE-FIRST)

### 2.1 Flujo Técnico

```
Usuario llena formulario presupuesto
        ↓
Datos guardados en IndexedDB (local)
        ↓
Presiona "Generar PDF"
        ↓
JavaScript en el navegador
├─ Lee datos de IndexedDB
├─ Genera HTML con estructura del presupuesto
├─ Convierte HTML → PDF (jsPDF)
└─ Descarga el PDF
        ↓
PDF listo en < 1 segundo ⚡
        ↓
¿Hay internet? → Sí → Sincroniza con servidor
            → No → PDF guardado localmente
```

### 2.2 Librerías JavaScript para PDF

#### Opción A: jsPDF (Más simple, menos control)
```javascript
// npm install jspdf html2canvas

import jsPDF from 'jspdf';
import html2canvas from 'html2canvas';

export const generarPDFLocal = async (presupuesto) => {
  // 1. Crear HTML con los datos
  const htmlContent = crearHTMLPresupuesto(presupuesto);
  
  // 2. Convertir HTML a canvas
  const canvas = await html2canvas(document.getElementById('presupuesto'));
  
  // 3. Crear PDF a partir del canvas
  const pdf = new jsPDF({
    orientation: 'portrait',
    unit: 'mm',
    format: 'a4'
  });
  
  // 4. Agregar imagen del canvas al PDF
  const imgData = canvas.toDataURL('image/png');
  pdf.addImage(imgData, 'PNG', 0, 0, 210, 297);
  
  // 5. Descargar
  pdf.save(`GTQC-${presupuesto.codigo}.pdf`);
};
```

**Ventajas:**
- ✅ Simple de implementar
- ✅ Funciona offline
- ✅ Instant speed

**Desventajas:**
- ❌ La calidad depende del navegador
- ❌ Menos control sobre diseño
- ❌ El PDF es una imagen (no editable)

---

#### Opción B: PDFLib (Más control, más complejo)
```javascript
// npm install pdf-lib

import { PDFDocument, rgb, PDFPage } from 'pdf-lib';

export const generarPDFClienteAvanzado = async (presupuesto) => {
  // 1. Crear documento PDF vacío
  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([595, 842]); // A4
  
  // 2. Agregar logo
  const logoImage = await fetch('/logo.png');
  const logoBytes = await logoImage.arrayBuffer();
  const logo = await pdfDoc.embedPng(logoBytes);
  page.drawImage(logo, {
    x: 50,
    y: 750,
    width: 100,
    height: 50
  });
  
  // 3. Agregar texto
  page.drawText('PROPUESTA ECONÓMICA', {
    x: 150,
    y: 750,
    size: 16,
    color: rgb(0, 0, 0)
  });
  
  // 4. Agregar tabla de items
  let y = 700;
  presupuesto.items.forEach((item, idx) => {
    page.drawText(`${idx + 1}`, { x: 50, y, size: 10 });
    page.drawText(item.descripcion, { x: 80, y, size: 10 });
    page.drawText(`S/ ${item.costo_total}`, { x: 500, y, size: 10 });
    y -= 20;
  });
  
  // 5. Agregar totales
  page.drawText(`TOTAL: S/ ${presupuesto.total}`, {
    x: 400,
    y: y - 30,
    size: 14,
    color: rgb(0, 102, 204)
  });
  
  // 6. Guardar PDF
  const pdfBytes = await pdfDoc.save();
  
  // 7. Descargar
  const blob = new Blob([pdfBytes], { type: 'application/pdf' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `GTQC-${presupuesto.codigo}.pdf`;
  link.click();
};
```

**Ventajas:**
- ✅ Control total sobre el diseño
- ✅ PDFs más pequeños
- ✅ Funciona offline
- ✅ Rápido (milisegundos)

**Desventajas:**
- ❌ Más complejo de codificar
- ❌ Menos similar a presupuestos actual

---

### 2.3 Almacenamiento Local (IndexedDB)

```javascript
// Guardar presupuesto generado offline

const guardarPresupuestoLocal = async (presupuesto, pdfBlob) => {
  const db = await idb.openDB('presupuestos-gtqc');
  
  await db.put('presupuestos', {
    id: presupuesto.id,
    codigo: presupuesto.codigo,
    cliente: presupuesto.cliente,
    items: presupuesto.items,
    total: presupuesto.total,
    pdf: pdfBlob,
    fecha_creacion: new Date(),
    estado: 'pendiente_sincronizacion',
    generado_offline: true
  });
  
  console.log(`Presupuesto ${presupuesto.codigo} guardado localmente`);
};

// Ver presupuestos guardados offline
const listarPresupuestosLocal = async () => {
  const db = await idb.openDB('presupuestos-gtqc');
  const presupuestos = await db.getAll('presupuestos');
  
  // Filtrar solo los pendientes de sincronización
  return presupuestos.filter(p => p.estado === 'pendiente_sincronizacion');
};
```

---

## 3. MÉTODO 2: GENERACIÓN EN SERVIDOR (ONLINE)

### 3.1 Flujo Técnico

```
Usuario llena formulario presupuesto
        ↓
Presiona "Generar PDF Profesional"
        ↓
Frontend envía datos al servidor (HTTPS)
        ↓
Backend procesa la solicitud
├─ Valida datos
├─ Genera HTML profesional
├─ Convierte HTML → PDF (PDFKit)
└─ Comprime el PDF
        ↓
Servidor devuelve PDF al navegador
        ↓
Usuario descarga PDF (2-3 segundos)
        ↓
PDF se guarda también en servidor (backup)
```

### 3.2 Código Backend (Node.js + Express)

```javascript
// backend/routes/presupuestos.js

import express from 'express';
import PDFDocument from 'pdfkit';
import fs from 'fs';

const router = express.Router();

// POST /api/presupuestos/generar-pdf
router.post('/generar-pdf', async (req, res) => {
  try {
    const { presupuesto } = req.body;
    
    // 1. Crear documento PDF
    const doc = new PDFDocument({
      size: 'A4',
      margin: 20
    });
    
    // 2. Agregar logo
    doc.image('./public/logo.png', 20, 20, { width: 100 });
    
    // 3. Agregar encabezado
    doc.fontSize(16).text('GROUP TOTAL QUALITY CONTROL', 130, 30);
    doc.fontSize(10).text('PROPUESTA ECONÓMICA', { underline: true });
    
    // 4. Agregar datos del cliente
    doc.fontSize(9);
    dibujarTablaCliente(doc, presupuesto.cliente);
    
    // 5. Agregar tabla de items
    doc.moveTo(20, 200).lineTo(575, 200).stroke(); // Línea separadora
    dibujarTablaItems(doc, presupuesto.items);
    
    // 6. Agregar totales
    const startY = doc.y + 20;
    doc.fontSize(10);
    doc.text(`Subtotal: S/ ${presupuesto.subtotal}`, 
             { align: 'right', width: 100 });
    doc.text(`IGV (18%): S/ ${presupuesto.igv}`, 
             { align: 'right', width: 100 });
    
    doc.fontSize(12).font('Helvetica-Bold');
    doc.text(`TOTAL: S/ ${presupuesto.total}`, 
             { align: 'right', width: 100 });
    
    // 7. Agregar términos y condiciones
    doc.fontSize(8);
    doc.pageBreak();
    doc.text(obtenerTerminosCondiciones(), { wrap: true });
    
    // 8. Generar nombre de archivo único
    const nombreArchivo = `GTQC-${presupuesto.codigo}-${Date.now()}.pdf`;
    const rutaPDF = `./pdfs/${nombreArchivo}`;
    
    // 9. Guardar en servidor
    doc.pipe(fs.createWriteStream(rutaPDF));
    doc.end();
    
    // 10. Esperar a que termine la escritura
    doc.on('end', async () => {
      // Guardar referencia en BD
      await db.query(
        'UPDATE presupuestos SET ruta_pdf = ?, estado = ? WHERE id = ?',
        [rutaPDF, 'generado', presupuesto.id]
      );
      
      // Enviar archivo al cliente
      res.download(rutaPDF, nombreArchivo);
    });
    
    // 11. Manejo de errores
    doc.on('error', (error) => {
      console.error('Error generando PDF:', error);
      res.status(500).json({ error: 'Error generando PDF' });
    });
    
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al generar presupuesto' });
  }
});

// Función helper: Dibujar tabla de cliente
function dibujarTablaCliente(doc, cliente) {
  const data = [
    ['PROYECTO:', cliente.proyecto],
    ['FECHA:', new Date().toLocaleDateString('es-PE')],
    ['CLIENTE:', cliente.nombre_empresa],
    ['RUC:', cliente.ruc],
    ['TELÉFONO:', cliente.telefono],
    ['LUGAR OBRA:', cliente.lugar_obra]
  ];
  
  let y = 80;
  data.forEach(row => {
    doc.text(row[0], 30, y, { width: 80 });
    doc.text(row[1], 130, y, { width: 150 });
    y += 15;
  });
}

// Función helper: Dibujar tabla de items
function dibujarTablaItems(doc, items) {
  const colX = [20, 80, 250, 320, 420, 520];
  const headers = ['ITEM', 'DESCRIPCIÓN', 'NORMA', 'UND', 'COSTO', 'TOTAL'];
  
  // Encabezados
  doc.fontSize(9).font('Helvetica-Bold');
  headers.forEach((header, i) => {
    doc.text(header, colX[i], 220, { width: 60 });
  });
  
  // Items
  doc.font('Helvetica');
  let y = 240;
  items.forEach((item, idx) => {
    doc.fontSize(8);
    doc.text(idx + 1, colX[0], y);
    doc.text(item.descripcion, colX[1], y);
    doc.text(item.norma, colX[2], y);
    doc.text(item.cantidad, colX[3], y);
    doc.text(`S/ ${item.costo_unitario}`, colX[4], y);
    doc.text(`S/ ${item.costo_total}`, colX[5], y, { align: 'right' });
    y += 18;
  });
}

export default router;
```

### 3.3 Llamada desde Frontend

```javascript
// frontend/services/pdfGenerator.js

export const generarPDFServidor = async (presupuesto) => {
  try {
    // Mostrar indicador de carga
    mostrarCargando('Generando PDF profesional...');
    
    // Enviar solicitud al servidor
    const response = await fetch('/api/presupuestos/generar-pdf', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${getToken()}`
      },
      body: JSON.stringify({ presupuesto })
    });
    
    // Manejo de error
    if (!response.ok) {
      throw new Error('Error generando PDF en servidor');
    }
    
    // Obtener PDF como blob
    const blob = await response.blob();
    
    // Descargar el archivo
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `GTQC-${presupuesto.codigo}.pdf`;
    link.click();
    
    // Limpiar
    URL.revokeObjectURL(url);
    
    // Guardar referencia localmente (para offline)
    await guardarPDFlocal(presupuesto, blob);
    
    mostrarExito('PDF generado correctamente');
    
  } catch (error) {
    console.error('Error:', error);
    mostrarError('Error al generar PDF');
  }
};
```

---

## 4. COMPARATIVA: CLIENTE vs SERVIDOR

```
┌──────────────────────────────────────────────────────────┐
│  GENERACIÓN EN CLIENTE (jsPDF)                           │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ✅ Funciona offline (sin servidor)                      │
│  ✅ Instantáneo (< 1 segundo)                            │
│  ✅ No consume recursos del servidor                     │
│  ✅ Privado (datos no suben al servidor)                 │
│  ❌ Menos control sobre diseño                           │
│  ❌ Calidad variable según navegador                     │
│  ❌ Archivos PDF más grandes                             │
│                                                          │
│  USO: Presupuestos temporales, borradores              │
│                                                          │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│  GENERACIÓN EN SERVIDOR (PDFKit)                        │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ✅ Diseño profesional consistente                       │
│  ✅ Control total sobre estilos y layout                 │
│  ✅ PDFs más pequeños (comprimidos)                      │
│  ✅ Backup automático en servidor                        │
│  ✅ Auditabilidad (quién generó, cuándo)               │
│  ❌ Requiere conexión a internet                         │
│  ❌ Más lento (2-3 segundos)                             │
│  ❌ Consume recursos del servidor                        │
│  ❌ Datos suben al servidor                              │
│                                                          │
│  USO: Presupuestos finales, archivos de cliente        │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## 5. FLUJO HÍBRIDO: SINCRONIZACIÓN AUTOMÁTICA

### 5.1 Escenario Completo

```
ESCENARIO: Usuario en terreno sin internet

Paso 1: Crear presupuesto offline
├─ Abre PWA (carga desde cache)
├─ Llena datos del cliente
├─ Selecciona items
└─ Presiona "Generar PDF"
        ↓

Paso 2: PDF se genera en cliente
├─ JavaScript en navegador procesa
├─ jsPDF crea el PDF
├─ Datos + PDF guardados en IndexedDB
└─ Usuario descarga PDF ⚡ (instantáneo)
        ↓

Paso 3: Presupuesto marcado como "pendiente"
├─ Estado: pending_sync
├─ Sincronización pendiente
└─ Visible en lista de "pendientes"
        ↓

Paso 4: Usuario regresa a oficina (con internet)
├─ Servicio de sincronización se activa
├─ Detecta presupuestos pendientes
└─ Inicia sincronización automática
        ↓

Paso 5: Sincronización con servidor
├─ Envía datos al servidor
├─ Servidor genera PDF profesional (PDFKit)
├─ Compara ambos PDFs (cliente vs servidor)
├─ Guarda en BD
├─ Envía confirmación al cliente
└─ Actualiza estado: synced ✅
        ↓

Paso 6: Cliente actualiza localmente
├─ Marca como sincronizado
├─ Reemplaza PDF cliente por servidor
├─ Actualiza en IndexedDB
└─ Usuario notificado ✅
```

### 5.2 Código: Sincronización Automática

```javascript
// frontend/services/sync.js

class SyncService {
  constructor() {
    this.isSyncing = false;
  }
  
  // Detectar cambios de conectividad
  inicializarSync() {
    // Online
    window.addEventListener('online', () => {
      console.log('Conexión establecida');
      this.sincronizarPresupuestos();
    });
    
    // Offline
    window.addEventListener('offline', () => {
      console.log('Sin conexión - Trabajando offline');
    });
  }
  
  // Sincronizar presupuestos pendientes
  async sincronizarPresupuestos() {
    if (this.isSyncing) return;
    this.isSyncing = true;
    
    try {
      const db = await idb.openDB('presupuestos-gtqc');
      
      // 1. Obtener presupuestos pendientes
      const pendientes = await db.getAllFromIndex(
        'presupuestos',
        'estado',
        'pending_sync'
      );
      
      console.log(`Sincronizando ${pendientes.length} presupuestos...`);
      
      // 2. Sincronizar cada uno
      for (const presupuesto of pendientes) {
        try {
          // Generar PDF en servidor
          const response = await fetch('/api/presupuestos/generar-pdf', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${getToken()}`
            },
            body: JSON.stringify({ presupuesto })
          });
          
          if (response.ok) {
            const pdfBlob = await response.blob();
            
            // Actualizar presupuesto localmente
            presupuesto.estado = 'synced';
            presupuesto.pdf = pdfBlob;
            presupuesto.fecha_sincronizacion = new Date();
            
            await db.put('presupuestos', presupuesto);
            
            console.log(`✅ Sincronizado: ${presupuesto.codigo}`);
          }
        } catch (error) {
          console.error(`❌ Error sincronizando ${presupuesto.codigo}:`, error);
          // Reintentar después
        }
      }
      
      console.log('Sincronización completada');
      
    } catch (error) {
      console.error('Error en sincronización:', error);
    } finally {
      this.isSyncing = false;
    }
  }
}

// Inicializar servicio
const syncService = new SyncService();
syncService.inicializarSync();
```

---

## 6. ARQUITECTURA COMPLETA: PWA + PDF

```
┌─────────────────────────────────────────────────────────────┐
│  NAVEGADOR DEL USUARIO (Offline-First)                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Formulario Presupuesto (React)                     │   │
│  │  ├─ Seleccionar Cliente                             │   │
│  │  ├─ Agregar Items                                   │   │
│  │  └─ Vista Previa                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                    ↓ datos                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  IndexedDB (Base de datos local)                    │   │
│  │  ├─ Clientes (guardados)                            │   │
│  │  ├─ Servicios (catálogo)                            │   │
│  │  ├─ Presupuestos (creados)                          │   │
│  │  └─ PDFs (generados)                                │   │
│  └─────────────────────────────────────────────────────┘   │
│                    ↓                                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  GENERACIÓN PDF CLIENTE (jsPDF)                     │   │
│  │  ├─ Lee datos de IndexedDB                          │   │
│  │  ├─ Crea HTML/canvas                                │   │
│  │  ├─ Convierte a PDF                                 │   │
│  │  └─ Descarga instantánea ⚡                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                    ↓                                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Service Worker (Cache + Sync)                      │   │
│  │  ├─ Cache-First (HTML, CSS, JS)                    │   │
│  │  ├─ Network-First (APIs)                            │   │
│  │  ├─ Background Sync (cuando vuelve internet)        │   │
│  │  └─ Notificaciones Push                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                    ↓ HTTPS                                   │
└─────────────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────────────┐
│  SERVIDOR (Backup + Profesional)                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  API REST (Node.js/Express)                         │   │
│  │  ├─ POST /presupuestos (crear)                      │   │
│  │  ├─ POST /presupuestos/generar-pdf (servidor)       │   │
│  │  ├─ GET /presupuestos (listar)                      │   │
│  │  └─ PUT /presupuestos/{id} (sincronizar)            │   │
│  └─────────────────────────────────────────────────────┘   │
│                    ↓                                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  GENERACIÓN PDF SERVIDOR (PDFKit)                   │   │
│  │  ├─ Validar datos                                   │   │
│  │  ├─ Generar HTML profesional                        │   │
│  │  ├─ PDFKit convierte → PDF                          │   │
│  │  ├─ Comprime archivo                                │   │
│  │  └─ Devuelve al cliente                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                    ↓                                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Base de Datos (PostgreSQL)                         │   │
│  │  ├─ Clientes                                        │   │
│  │  ├─ Servicios                                       │   │
│  │  ├─ Presupuestos (historial completo)              │   │
│  │  ├─ Rutas PDFs (backup)                             │   │
│  │  └─ Logs de auditoría                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                    ↓                                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Storage de Archivos (AWS S3 / Google Cloud)        │   │
│  │  ├─ PDFs generados (backup)                         │   │
│  │  ├─ Histórico de versiones                          │   │
│  │  └─ Descargas públicas (firmas clientes)            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. CASOS DE USO ESPECÍFICOS

### Caso 1: Vendedor en Terreno (SIN INTERNET)

```
Lunes 9:00 AM - Vendedor en proyecto ALDEM

1. Abre PWA (ya instalada en móvil)
2. Carga desde cache (< 100ms)
3. Consulta datos cliente (IndexedDB)
4. Agrega 6 servicios
5. Presiona "Generar PDF"
        ↓
   jsPDF genera en cliente (< 1 segundo)
        ↓
6. PDF aparece descargado
7. Lo comparte vía WhatsApp (archivo local)
8. El presupuesto queda en "estado: pending_sync"

Martes 8:00 AM - Vuelve a oficina

9. PWA detecta conexión a internet
10. Background sync se activa automáticamente
11. Envía presupuesto al servidor
12. Servidor genera PDF profesional (PDFKit)
13. Compara versiones:
    - Cliente (jsPDF): básico pero funcional
    - Servidor (PDFKit): profesional con logo limpio
14. Guarda en BD para auditoría
15. Marca como "synced" ✅
16. Cliente notificado vía push notification
```

---

### Caso 2: Gerente en Oficina (CON INTERNET)

```
Miércoles 2:00 PM - Gerente en oficina

1. Abre PWA en escritorio
2. Busca cliente "ALDEM S.A.C."
3. Crea nuevo presupuesto
4. Carga datos completos
5. Presiona "Generar PDF Profesional"
        ↓
   Frontend envía al servidor vía HTTPS
        ↓
   Backend (PDFKit) genera:
   - Logo sin watermark ✅
   - Tabla responsive ✅
   - Cálculos automáticos ✅
   - Firma digital (opcional)
        ↓
6. PDF descargado en 2-3 segundos
7. Lo envía por email directamente desde la app
8. Guarda en historial (BD)
9. Cliente puede descargar versión oficial
```

---

## 8. TABLA COMPARATIVA: CLIENTE vs SERVIDOR

| Aspecto | Cliente (jsPDF) | Servidor (PDFKit) |
|---------|-----------------|-------------------|
| **Disponibilidad** | Siempre (offline) | Solo con internet |
| **Velocidad** | < 1 segundo ⚡ | 2-3 segundos |
| **Diseño** | Básico | Profesional |
| **Control** | Limitado | Total |
| **Logo sin watermark** | Sí (manual) | Sí (nativo) |
| **Formato consistente** | Regular | Excelente |
| **Tamaño archivo** | Más grande | Comprimido |
| **Backup** | Local (IndexedDB) | Servidor (S3) |
| **Auditoría** | No | Sí (logs) |
| **Encriptación** | No | Sí (TLS) |
| **Uso de datos** | Cero | Mínimo |

---

## 9. FLUJO DECISIONAL: ¿CUÁNDO USAR CADA UNO?

```
¿Hay conexión a internet?
        ↓
    Sí → ¿Usuario es gerente/admin?
        ├─ Sí → Generar en SERVIDOR (PDFKit)
        │       ✅ Profesional, auditable, backup
        │
        └─ No → ¿Presupuesto ya fue aprobado?
                ├─ Sí → SERVIDOR (official version)
                │
                └─ No → CLIENTE (jsPDF, rápido)
        
    No (sin internet) → Generar en CLIENTE (jsPDF)
                        ✅ Funciona offline
```

---

## 10. IMPLEMENTACIÓN: PASO A PASO

### Semana 1-2: Setup
```
├─ Instalar jsPDF + PDFLib
├─ Instalar PDFKit en backend
├─ Configurar IndexedDB
└─ Setup Service Worker básico
```

### Semana 3-4: Desarrollo
```
├─ Componente de formulario (React)
├─ Generación cliente (jsPDF)
├─ Generación servidor (PDFKit)
├─ Sincronización automática
└─ Manejo de errores
```

### Semana 5: Testing
```
├─ Test offline (sin internet)
├─ Test online (con internet)
├─ Test sincronización
├─ Calidad de PDFs (visual)
└─ Performance (velocidad)
```

### Semana 6: Deploy
```
├─ Deploy a Vercel (frontend)
├─ Deploy a Heroku (backend)
├─ Configurar AWS S3 (storage)
├─ Testing en móviles reales
└─ Documentación
```

---

## 11. SEGURIDAD EN GENERACIÓN DE PDF

### Cliente (jsPDF)
```
✅ No sube datos al servidor
❌ PDF no encriptado localmente
✅ Datos quedan en navegador del usuario
```

### Servidor (PDFKit)
```
✅ Encriptación TLS en tránsito
✅ Backup encriptado en AWS S3
✅ Logs de auditoría (quién, cuándo, qué)
✅ Validación de permisos (autorización)
❌ Datos temporalmente en servidor
```

**Recomendación**: Los datos sensibles se validan en servidor antes de generar PDF.

---

## 12. CONCLUSIÓN

### La PWA genera PDFs de DOS maneras:

**1. CLIENTE (jsPDF) - Para offline**
- ✅ Instantáneo
- ✅ Sin servidor
- ✅ Funciona sin internet
- ❌ Menos profesional

**2. SERVIDOR (PDFKit) - Para producción**
- ✅ Profesional
- ✅ Auditable
- ✅ Backup automático
- ❌ Requiere internet

### El flujo ideal es:
```
Usuario en terreno → Genera en cliente (jsPDF)
                     ↓ (guardar offline)
                   Cuando vuelve internet
                     ↓
                   Sincroniza automáticamente
                     ↓
                   Servidor genera versión profesional (PDFKit)
                     ↓
                   Cliente actualiza PDF
                     ↓
                   ✅ Tiene dos versiones: rápida + profesional
```

---

**Arquitectura ganadora: Híbrida (Cliente + Servidor)**

