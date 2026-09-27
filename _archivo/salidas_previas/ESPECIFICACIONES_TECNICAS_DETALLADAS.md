# ESPECIFICACIONES TÉCNICAS DETALLADAS
## Sistema de Generación Automática de Presupuestos
**Para: Group Total Quality Control S.A.C.**
**Versión: 1.0 | Confidencial**

---

## 1. REQUISITOS FUNCIONALES

### 1.1 GESTIÓN DE USUARIOS
```
UC-001: Autenticación de Usuario
├─ Login con email/contraseña
├─ Recuperación de contraseña
├─ Roles: Admin, Gerente, Vendedor
└─ Permisos según rol

UC-002: Gestión de Perfiles
├─ Ver perfil
├─ Editar perfil
├─ Cambiar contraseña
└─ Historial de actividad
```

### 1.2 GESTIÓN DE CLIENTES
```
UC-003: CRUD Clientes
├─ Crear nuevo cliente
│  ├─ Nombre empresa (obligatorio)
│  ├─ RUC (obligatorio, validación)
│  ├─ Teléfono
│  ├─ Email
│  ├─ Asesor comercial (dropdown de usuarios)
│  ├─ Lugar de obra
│  └─ Contacto principal
├─ Editar cliente
├─ Eliminar cliente (soft delete)
└─ Ver historial de presupuestos del cliente

UC-004: Búsqueda y Filtros
├─ Buscar por nombre
├─ Filtrar por asesor
├─ Filtrar por lugar de obra
└─ Filtrar por RUC
```

### 1.3 GESTIÓN DE SERVICIOS/ITEMS
```
UC-005: CRUD Servicios
├─ Crear servicio
│  ├─ Nombre (obligatorio)
│  ├─ Categoría (Suelos, Concreto, Químicos, etc)
│  ├─ Descripción
│  ├─ Norma aplicable (ASTM, NTP, MTC)
│  ├─ Precio unitario (obligatorio)
│  ├─ Unidad de medida (UND, DÍA, M, M², etc)
│  └─ Estado (Activo/Inactivo)
├─ Editar servicio
├─ Deshabilitar servicio (sin eliminar históricos)
└─ Historial de cambios de precio

UC-006: Categorización de Servicios
├─ 1. ESTUDIO DE SUELOS
│  ├─ Exploración directa (calicatas)
│  ├─ Perfil estratigráfico
│  ├─ Análisis granulométrico
│  ├─ Límites de Atterberg
│  ├─ Triaxial
│  └─ Ensayos químicos
├─ 2. ENSAYOS DE CONCRETO
│  ├─ Diseño de mezcla
│  ├─ Agregados (grueso/fino)
│  ├─ Resistencia a compresión
│  ├─ Asentamiento (Slump)
│  └─ Otros ensayos
└─ 3. ADMINISTRACIÓN Y LOGÍSTICA
   ├─ Informe de capacidad
   ├─ Movilización
   └─ Seguros SCTR
```

### 1.4 GENERACIÓN DE PRESUPUESTOS
```
UC-007: Crear Presupuesto (Flujo Principal)
├─ Step 1: Seleccionar Cliente
│  ├─ Dropdown con lista de clientes existentes
│  ├─ Opción "Crear Cliente Nuevo"
│  └─ Auto-completar datos (RUC, contacto, etc)
│
├─ Step 2: Seleccionar Servicios
│  ├─ Tabla dinámica con campos:
│  │  ├─ Checkbox (seleccionar)
│  │  ├─ Item (auto-numerado)
│  │  ├─ Descripción (readonly del servicio)
│  │  ├─ Norma (readonly del servicio)
│  │  ├─ Cantidad (input numérico)
│  │  ├─ Costo Unitario (editable, default del servicio)
│  │  ├─ Costo Total (auto-calculado)
│  │  └─ Botón Eliminar Fila
│  ├─ Botón "Agregar Servicio" (abre modal)
│  ├─ Modal: Listado de servicios con buscador
│  └─ Botón "Agregar Servicio Personalizado"
│
├─ Step 3: Revisar Totales
│  ├─ Subtotal (suma de costos totales)
│  ├─ IGV (18%)
│  ├─ TOTAL FINAL
│  └─ Vista previa PDF en tiempo real
│
├─ Step 4: Configuraciones Adicionales
│  ├─ Validez de oferta (días)
│  ├─ Notas adicionales
│  ├─ Datos bancarios (default de empresa)
│  └─ Términos y condiciones (default)
│
└─ Step 5: Guardar y Descargar
   ├─ Guardar como Borrador
   ├─ Guardar y Enviar (email)
   ├─ Descargar PDF
   └─ Vista previa antes de guardar
```

### 1.5 GENERACIÓN DE PDF
```
UC-008: Renderización de PDF
├─ Encabezado
│  ├─ Logo (sin watermark) [50px height]
│  ├─ Nombre empresa: "GROUP TOTAL QUALITY CONTROL"
│  ├─ Certificaciones ISO (4 badges)
│  └─ Código: GTQC-COT-01 | Rev: 02 | Fecha: Agosto 2025
│
├─ Sección Cliente
│  ├─ Tabla 2 columnas:
│  │  ├─ Col 1: Proyecto, Fecha, Cliente, Atención, RUC(cliente), Teléfono, Correo
│  │  └─ Col 2: Razón Social, Asesor, RUC(empresa), Teléfono(emp), Correo(emp), Presupuesto N°, Código
│  │
├─ Tabla de Items (flexible)
│  ├─ Columnas: ITEM | DESCRIPCIÓN | ASTM-NTP | UND | CANTIDAD | COSTO UNIT. | COSTO TOTAL
│  ├─ Ancho fijo: ['5%', '40%', '15%', '12%', '14%', '14%']
│  ├─ Filas de items (dinámico 5-50)
│  ├─ Row de Subtotal
│  ├─ Row de IGV 18%
│  └─ Row de TOTAL (bold)
│
├─ Sección Condiciones de Pago
│  ├─ Validez: 15 días
│  ├─ Condición: 50% adelanto, 50% antes entrega
│  ├─ Número de cuentas bancarias
│  ├─ CCI Interbank, BBVA, Banco de la Nación
│  └─ Instrucciones de depósito
│
├─ Términos y Condiciones
│  ├─ Plazo estimado de ejecución
│  ├─ Confidencialidad e imparcialidad
│  ├─ Quejas y sugerencias
│  └─ Horario de atención
│
├─ Pie de Página
│  ├─ Logo INACAL
│  ├─ Información de acreditación
│  ├─ Teléfono, Email, Dirección
│  └─ Footer: "La copia impresa es no controlada"
│
└─ Propiedades PDF
   ├─ Orientación: Portrait
   ├─ Tamaño: A4
   ├─ Márgenes: 20mm
   ├─ Codificación: UTF-8
   ├─ Compresión: Activada
   └─ Nombre: "GTQC-26-{id_presupuesto}.pdf"
```

### 1.6 HISTORIAL Y REPORTES
```
UC-009: Ver Historial de Presupuestos
├─ Tabla con columnas:
│  ├─ Fecha creación
│  ├─ Código presupuesto
│  ├─ Cliente
│  ├─ Monto total
│  ├─ Estado (Borrador, Enviado, Vigente, Vencido)
│  ├─ Creado por
│  ├─ Acciones (Ver, Editar, Descargar, Duplicar, Eliminar)
│  └─ Búsqueda y filtros
│
├─ Ver Detalle de Presupuesto
│  └─ Permite editar y re-generar PDF
│
├─ Duplicar Presupuesto
│  └─ Crea una copia para reutilizar
│
└─ Eliminar Presupuesto
   └─ Soft delete (mantiene histórico)

UC-010: Reportes
├─ Reporte de Presupuestos por Período
├─ Reporte de Ingresos (proyectados vs reales)
├─ Reporte de Servicios Más Solicitados
├─ Reporte de Clientes Más Activos
└─ Exportar datos (CSV, Excel)
```

---

## 2. REQUISITOS NO FUNCIONALES

### 2.1 SEGURIDAD
- Encriptación de contraseñas (bcrypt)
- Tokens JWT para sesiones
- HTTPS obligatorio
- CORS configurado
- Rate limiting en login (5 intentos / 15 minutos)
- Protección contra SQL Injection
- Validación de inputs en todos los campos
- Backup automático diario
- 2FA opcional para admin

### 2.2 RENDIMIENTO
- Carga de página principal: < 2 segundos
- Generación de PDF: < 3 segundos
- Respuesta de API: < 500ms (p95)
- Búsqueda de clientes: auto-complete con < 100ms
- Base de datos indexada por:
  - id_cliente
  - id_presupuesto
  - fecha_creacion
  - estado

### 2.3 DISPONIBILIDAD
- Uptime: 99.9%
- SLA respuesta: 4 horas hábiles
- Mantenimiento: ventana 22:00-23:00 domingo

### 2.4 ESCALABILIDAD
- Soportar 100+ usuarios concurrentes
- Generar 1000+ presupuestos/mes
- Almacenamiento: 10GB año 1
- CDN para assets estáticos

---

## 3. ARQUITECTURA DEL SISTEMA

### 3.1 DIAGRAMA DE CAPAS
```
┌─────────────────────────────────────────┐
│  CAPA PRESENTACIÓN (Frontend)           │
│  React / Vue.js                         │
│  ├─ Dashboard                           │
│  ├─ Formularios (Clientes, Servicios)   │
│  ├─ Editor de Presupuestos              │
│  ├─ Visualizador PDF                    │
│  └─ Reportes                            │
└──────────────┬──────────────────────────┘
               │ API REST / GraphQL
               ↓
┌─────────────────────────────────────────┐
│  CAPA APLICACIÓN (Backend)              │
│  Node.js/Express o Python/Django        │
│  ├─ AuthService                         │
│  ├─ ClienteService                      │
│  ├─ ServicioService                     │
│  ├─ PresupuestoService                  │
│  ├─ PDFGeneratorService                 │
│  ├─ EmailService                        │
│  └─ ReportService                       │
└──────────────┬──────────────────────────┘
               │ ORM (Sequelize/SQLAlchemy)
               ↓
┌─────────────────────────────────────────┐
│  CAPA DATOS (Base de Datos)             │
│  PostgreSQL                             │
│  ├─ Tabla: usuarios                     │
│  ├─ Tabla: clientes                     │
│  ├─ Tabla: servicios                    │
│  ├─ Tabla: presupuestos                 │
│  └─ Tabla: detalle_presupuestos         │
└─────────────────────────────────────────┘
```

### 3.2 FLUJO DE DATOS
```
Usuario →  Frontend  →  REST API  →  Backend  →  BD
  ↓         React        HTTP       Node.js   PostgreSQL
  │
Completa           Valida              Crea
Formulario         + Envía           Registros
  │
  ↓
Previsualizador ← PDF Generator ← Datos BD
  │                   ↓
  ↓            Renderiza Template
  │            Embebido HTML→PDF
  ↓
Descarga PDF
  │
  └──→ Email (optional)
```

---

## 4. MODELOS DE DATOS

### 4.1 TABLA: USUARIOS
```sql
CREATE TABLE usuarios (
  id_usuario SERIAL PRIMARY KEY,
  nombre VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  rol ENUM('admin', 'gerente', 'vendedor') DEFAULT 'vendedor',
  estado BOOLEAN DEFAULT TRUE,
  fecha_creacion TIMESTAMP DEFAULT NOW(),
  fecha_modificacion TIMESTAMP DEFAULT NOW(),
  ultimo_login TIMESTAMP,
  INDEXES: email, rol
);
```

### 4.2 TABLA: CLIENTES
```sql
CREATE TABLE clientes (
  id_cliente SERIAL PRIMARY KEY,
  nombre_empresa VARCHAR(255) NOT NULL,
  ruc VARCHAR(11) NOT NULL UNIQUE,
  telefono VARCHAR(20),
  email VARCHAR(255),
  asesor_comercial_id INT REFERENCES usuarios(id_usuario),
  lugar_obra VARCHAR(255),
  contacto_principal VARCHAR(255),
  estado BOOLEAN DEFAULT TRUE,
  fecha_creacion TIMESTAMP DEFAULT NOW(),
  fecha_modificacion TIMESTAMP DEFAULT NOW(),
  INDEXES: ruc, nombre_empresa, asesor_comercial_id
);
```

### 4.3 TABLA: SERVICIOS
```sql
CREATE TABLE servicios (
  id_servicio SERIAL PRIMARY KEY,
  nombre_servicio VARCHAR(255) NOT NULL,
  categoria VARCHAR(100),
  descripcion TEXT,
  norma_aplicable VARCHAR(50),
  precio_unitario DECIMAL(10, 2) NOT NULL,
  unidad_medida VARCHAR(20),
  estado BOOLEAN DEFAULT TRUE,
  fecha_creacion TIMESTAMP DEFAULT NOW(),
  fecha_ultima_actualizacion TIMESTAMP DEFAULT NOW(),
  creado_por INT REFERENCES usuarios(id_usuario),
  INDEXES: categoria, nombre_servicio
);
```

### 4.4 TABLA: PRESUPUESTOS
```sql
CREATE TABLE presupuestos (
  id_presupuesto SERIAL PRIMARY KEY,
  codigo VARCHAR(50) NOT NULL UNIQUE,
  id_cliente INT NOT NULL REFERENCES clientes(id_cliente),
  fecha_creacion TIMESTAMP DEFAULT NOW(),
  fecha_modificacion TIMESTAMP DEFAULT NOW(),
  estado ENUM('borrador', 'enviado', 'vigente', 'vencido', 'aceptado') DEFAULT 'borrador',
  subtotal DECIMAL(12, 2),
  igv DECIMAL(12, 2),
  total DECIMAL(12, 2),
  usuario_creador INT REFERENCES usuarios(id_usuario),
  usuario_modificador INT REFERENCES usuarios(id_usuario),
  validez_dias INT DEFAULT 15,
  notas_adicionales TEXT,
  ruta_pdf VARCHAR(500),
  INDEXES: codigo, id_cliente, estado, fecha_creacion
);
```

### 4.5 TABLA: DETALLE_PRESUPUESTOS
```sql
CREATE TABLE detalle_presupuestos (
  id_detalle SERIAL PRIMARY KEY,
  id_presupuesto INT NOT NULL REFERENCES presupuestos(id_presupuesto) ON DELETE CASCADE,
  num_item INT,
  id_servicio INT REFERENCES servicios(id_servicio),
  descripcion_personalizada TEXT,
  cantidad DECIMAL(10, 2),
  costo_unitario DECIMAL(10, 2),
  costo_total DECIMAL(12, 2),
  norma VARCHAR(50),
  INDEXES: id_presupuesto
);
```

---

## 5. APIs REST (Endpoints)

### 5.1 AUTENTICACIÓN
```
POST   /api/auth/login
POST   /api/auth/logout
POST   /api/auth/refresh-token
POST   /api/auth/forgot-password
POST   /api/auth/reset-password
GET    /api/auth/me (autenticado)
```

### 5.2 CLIENTES
```
GET    /api/clientes (lista paginada)
GET    /api/clientes/{id}
POST   /api/clientes (crear)
PUT    /api/clientes/{id} (actualizar)
DELETE /api/clientes/{id} (soft delete)
GET    /api/clientes/search?q=... (búsqueda)
GET    /api/clientes/{id}/presupuestos (historial)
```

### 5.3 SERVICIOS
```
GET    /api/servicios (lista con filtros)
GET    /api/servicios/{id}
POST   /api/servicios (crear)
PUT    /api/servicios/{id} (actualizar)
DELETE /api/servicios/{id} (deshabilitar)
GET    /api/servicios/categorias (listado)
GET    /api/servicios/search?q=... (búsqueda)
```

### 5.4 PRESUPUESTOS
```
GET    /api/presupuestos (lista con filtros)
GET    /api/presupuestos/{id}
POST   /api/presupuestos (crear)
PUT    /api/presupuestos/{id} (actualizar)
DELETE /api/presupuestos/{id} (soft delete)
POST   /api/presupuestos/{id}/generar-pdf (generar)
GET    /api/presupuestos/{id}/pdf (descargar)
POST   /api/presupuestos/{id}/enviar-email
POST   /api/presupuestos/{id}/duplicar
GET    /api/presupuestos/{id}/historial (versiones)
```

### 5.5 REPORTES
```
GET    /api/reportes/presupuestos-por-periodo
GET    /api/reportes/ingresos
GET    /api/reportes/servicios-populares
GET    /api/reportes/clientes-activos
GET    /api/reportes/exportar?formato=csv|xlsx
```

---

## 6. VISTAS Y COMPONENTES PRINCIPALES

### 6.1 DASHBOARD
```
┌─────────────────────────────────────┐
│  Bienvenida + KPIs                  │
├─────────────────────────────────────┤
│                                     │
│  Presupuestos Hoy: 5                │
│  Total Generado Este Mes: S/ 25,000 │
│  Clientes Activos: 12               │
│                                     │
├─────────────────────────────────────┤
│  Acciones Rápidas                   │
├─────────────────────────────────────┤
│  [+ Nuevo Presupuesto] [+ Cliente]  │
│  [Ver Historial]       [Reportes]   │
└─────────────────────────────────────┘
```

### 6.2 FORMULARIO DE PRESUPUESTO
```
┌─────────────────────────────────────┐
│  NUEVO PRESUPUESTO                  │
├─────────────────────────────────────┤
│                                     │
│  Step 1: Seleccionar Cliente        │
│  ┌─────────────────────────────────┐│
│  │ [▼ Seleccionar cliente...]      ││
│  │                                 ││
│  │ ALDEM S.A.C. (RUC: 20422696548) ││
│  │ EMPRESA MINERA (RUC: 20489324955)││
│  │                                 ││
│  │ [+ Crear nuevo cliente]         ││
│  └─────────────────────────────────┘│
│                                     │
│  [SIGUIENTE →]                      │
│                                     │
└─────────────────────────────────────┘
```

---

## 7. ESPECIFICACIONES DE INTEGRACIÓN

### 7.1 GENERACIÓN DE PDF (librería: pdfkit)
```javascript
// Archivo: services/pdfGenerator.js

const PDFDocument = require('pdfkit');

exports.generarPresupuesto = async (datos) => {
  const doc = new PDFDocument({
    size: 'A4',
    margin: 20
  });

  // 1. Encabezado
  doc.image('logo.png', 20, 20, { width: 100 });
  doc.fontSize(16).text('GROUP TOTAL QUALITY CONTROL', 130, 30);
  
  // 2. Datos Cliente (tabla)
  doc.fontSize(10);
  dibujarTablaCliente(doc, datos.cliente);
  
  // 3. Tabla de Items
  dibujarTablaItems(doc, datos.items);
  
  // 4. Totales
  doc.text(`SUBTOTAL: S/ ${datos.subtotal}`, { align: 'right' });
  doc.text(`IGV 18%: S/ ${datos.igv}`, { align: 'right' });
  doc.fontSize(12).text(`TOTAL: S/ ${datos.total}`, { align: 'right' });
  
  // 5. Términos y condiciones
  doc.pageBreak();
  doc.fontSize(10).text(datos.terminos);
  
  // 6. Pie de página
  doc.fontSize(8).text('La copia impresa es no controlada', { align: 'center' });

  return doc;
};
```

### 7.2 ENVÍO DE EMAIL
```javascript
// Integración con nodemailer

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: process.env.SMTP_PORT,
  secure: true,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  }
});

// Enviar presupuesto por email
await transporter.sendMail({
  from: 'presupuestos@grouptqc.com',
  to: cliente.email,
  subject: `Presupuesto ${codigo}`,
  html: template,
  attachments: [{
    filename: `${codigo}.pdf`,
    path: rutaPDF
  }]
});
```

---

## 8. CONSIDERACIONES DE IMPLEMENTACIÓN

### 8.1 MIGRACIONES DE BASE DE DATOS
```bash
# Crear tablas iniciales
npm run db:migrate:up

# Seed data (servicios estándar)
npm run db:seed:servicios

# Seed data (usuarios demo)
npm run db:seed:usuarios
```

### 8.2 VARIABLES DE ENTORNO
```
NODE_ENV=production
DATABASE_URL=postgresql://user:pass@host:5432/dbname
JWT_SECRET=xxxxxxxxxxxxx
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=presupuestos@grouptqc.com
SMTP_PASS=xxxxxxxxxxxxx
AWS_S3_BUCKET=presupuestos-gtqc
AWS_REGION=us-east-1
```

### 8.3 DEPENDENCIAS PRINCIPALES
```json
{
  "dependencies": {
    "express": "^4.18.0",
    "sequelize": "^6.32.0",
    "pg": "^8.10.0",
    "jsonwebtoken": "^9.0.0",
    "bcryptjs": "^2.4.3",
    "pdfkit": "^0.13.0",
    "nodemailer": "^6.9.0",
    "react": "^18.2.0",
    "axios": "^1.4.0"
  }
}
```

---

## 9. TESTING

### 9.1 COBERTURA DE TESTS
- Unit Tests: 80% de funciones críticas
- Integration Tests: APIs principales
- E2E Tests: Flujos de usuario completos
- Performance Tests: Generación de PDF

### 9.2 Herramientas
```
Jest (testing framework)
Supertest (HTTP assertions)
Puppeteer (E2E testing)
```

---

## 10. DOCUMENTACIÓN A ENTREGA

1. ✅ README.md (instalación y setup)
2. ✅ API Documentation (Swagger/OpenAPI)
3. ✅ User Manual (guía de usuario)
4. ✅ Admin Guide (configuración)
5. ✅ Developer Guide (para futuros mantenimientos)
6. ✅ Database Schema (ERD)

---

**Fin del documento técnico**

