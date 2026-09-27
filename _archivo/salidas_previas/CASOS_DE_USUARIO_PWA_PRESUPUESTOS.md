# Casos de Usuario - PWA Presupuestos GTQC

## Descripción General
Documento que detalla los 10 casos de usuario principales para la PWA de gestión de presupuestos con integración SUNAT. Cada caso incluye actores, precondiciones, flujo principal, flujos alternativos y postcondiciones.

---

## UC-001: Crear Nuevo Presupuesto

**Actor Principal:** Ejecutivo de Ventas / Cotizador

**Precondiciones:**
- Usuario autenticado en la PWA
- Datos de empresa (GTQC) ya configurados en el sistema
- Acceso a internet (opcional para creación inicial)

**Flujo Principal:**
1. Usuario selecciona "Nuevo Presupuesto" desde menú principal
2. Sistema genera automáticamente:
   - Número de presupuesto (formato: BUD-YYYY-NNNN)
   - Código único (timestamp + random)
   - Fecha de generación (fecha actual)
3. Se carga plantilla vacía con:
   - **Lado Izquierdo (Estático):** Logo GTQC, nombre empresa, dirección, teléfono
   - **Centro:** Badges ISO (certificaciones estáticas)
   - **Lado Derecho (Datos de Empresa):** Razón social, RUC, teléfono contacto, email
4. Sistema coloca cursor en campo "RUC Cliente"
5. Usuario ve formulario vacío listo para datos de cliente

**Postcondiciones:**
- Presupuesto nuevo creado en IndexedDB (estado: BORRADOR)
- ID de presupuesto generado y asignado
- Formulario listo para entrada de datos

**Excepciones:**
- Sin internet: Se crea localmente, sincronización pendiente
- Conflicto de números: Sistema genera nuevo número automáticamente

---

## UC-002: Validar RUC Cliente (Integración SUNAT)

**Actor Principal:** Ejecutivo de Ventas / Sistema

**Precondiciones:**
- Presupuesto en estado BORRADOR
- Campo "RUC Cliente" está enfocado
- RUC válido ingresado (11 dígitos)

**Flujo Principal:**
1. Usuario ingresa 11 dígitos en campo "RUC Cliente"
2. Sistema valida formato (11 números)
3. Si con internet:
   - Llamada a SUNAT API (padrón reducido)
   - API retorna: Razón Social, Domicilio, Actividad, Estado
4. Si sin internet:
   - Búsqueda en caché local IndexedDB (RUCs consultados previamente)
   - Si encontrado: muestra datos en caché
   - Si no encontrado: muestra campo deshabilitado + ícono de espera
5. Campos se completan automáticamente:
   - Razón Social (cliente)
   - Dirección (cliente)
   - Teléfono (si disponible en SUNAT)

**Flujo Alternativo (RUC Inválido):**
1. Sistema muestra error: "RUC no válido en SUNAT"
2. Usuario puede:
   - Reintentar con otro RUC
   - Ingresar datos manualmente (desabilita validación SUNAT)

**Flujo Alternativo (Sin Internet):**
1. Sistema busca en caché local
2. Si no existe en caché: muestra mensaje "Será validado cuando haya conexión"
3. Usuario puede continuar con campos vacíos o ingresar manualmente

**Postcondiciones:**
- Datos de cliente completados (automáticos o manuales)
- RUC validado o marcado como "pendiente validación"
- Si online: RUC almacenado en caché local para futuras consultas

---

## UC-003: Cargar Datos de Empresa desde SUNAT (Automático)

**Actor Principal:** Sistema

**Precondiciones:**
- UC-002 completado exitosamente
- RUC válido en SUNAT
- Respuesta de API recibida

**Flujo Principal:**
1. Sistema recibe respuesta de SUNAT API:
   ```
   {
     "ruc": "20123456789",
     "razonSocial": "EMPRESA ABC S.A.C.",
     "domicilio": "Av. Principal 123, Lima",
     "actividad": "Servicios de consultoría",
     "estado": "ACTIVO"
   }
   ```
2. Sistema mapea campos SUNAT a formulario:
   - razonSocial → input "Razón Social Cliente"
   - domicilio → input "Dirección Cliente"
   - actividad → campo informativo (mostrar debajo de RUC)
   - estado → validar que sea "ACTIVO", si no: advertencia

3. Sistema actualiza campos UI de forma progresiva:
   - Primero RUC ✓
   - Luego Razón Social (fade-in)
   - Luego Dirección (fade-in)

4. Datos almacenados en IndexedDB:
   - Tabla: `ClientesConsultados`
   - Campos: ruc, razonSocial, domicilio, actividad, estado, fechaConsulta

**Postcondiciones:**
- Formulario cliente completo automáticamente
- RUC almacenado en caché local (índice por RUC)
- Timestamp de consulta registrado

---

## UC-004: Agregar Items/Servicios al Presupuesto

**Actor Principal:** Ejecutivo de Ventas

**Precondiciones:**
- Presupuesto abierto
- Datos de cliente validados (UC-002/UC-003 completado)
- Usuario en sección "Detalles del Presupuesto"

**Flujo Principal:**
1. Usuario selecciona botón "+ Agregar Servicio"
2. Sistema abre modal con opciones:
   - Catálogo de servicios predefinidos (dropdown)
   - O ingreso manual de descripción
3. Usuario selecciona o escribe:
   - Descripción del servicio
   - Cantidad
   - Precio unitario
4. Sistema calcula automáticamente:
   - Subtotal por línea (Cantidad × Precio)
5. Usuario puede agregar múltiples items
6. Cada item puede:
   - Editarse (hacer clic en fila)
   - Eliminarse (icono X)
   - Duplicarse (para servicios similares)

**Flujo Alternativo (Catálogo):**
1. Si usuario selecciona de catálogo:
   - Descripción se completa automáticamente
   - Precio base se carga (puede ser editado)

**Postcondiciones:**
- Tabla de items actualizada
- Cada item tiene: ID único, descripción, cantidad, precio, subtotal
- Totales recalculados

---

## UC-005: Calcular Totales y Aplicar Descuentos

**Actor Principal:** Sistema / Ejecutivo de Ventas

**Precondiciones:**
- Mínimo 1 item agregado en presupuesto
- Usuario en sección de totales

**Flujo Principal:**
1. Sistema calcula automáticamente en tiempo real:
   - **Subtotal:** Suma de todos los subtotales de items
   - **IGV:** Subtotal × 18% (configurable por usuario)
   - **Total Final:** Subtotal + IGV

2. Usuario puede aplicar descuentos:
   - % Descuento (aplicado al Subtotal)
   - $ Descuento Fijo
   - Descuento por Línea (individual por item)

3. Sistema recalcula: Total Final = (Subtotal - Descuento) + IGV

4. Validaciones:
   - Descuento no puede ser > Subtotal
   - Campo "Observaciones de Descuento" (requerido si hay descuento > 10%)

5. Visualización de desglose:
   ```
   Subtotal:          S/ 5,000.00
   (-) Descuento:     S/ (500.00)
   Subtotal Neto:     S/ 4,500.00
   IGV (18%):         S/ 810.00
   TOTAL:             S/ 5,310.00
   
   Válido por:        15 días
   Fecha vencimiento: 2026-09-26
   ```

**Postcondiciones:**
- Todos los totales actualizados y visualizados
- Datos de descuento almacenados
- Presupuesto refleja cálculos correctos

---

## UC-006: Generar PDF (Cliente - Offline)

**Actor Principal:** Ejecutivo de Ventas / Sistema

**Precondiciones:**
- Presupuesto completado (todos los campos requeridos)
- Usuario solicita "Descargar PDF" o "Vista Previa"

**Flujo Principal:**
1. Sistema valida presupuesto:
   - Datos cliente válidos ✓
   - Mínimo 1 item ✓
   - Totales calculados ✓

2. Sistema genera PDF usando **jsPDF** (lado cliente):
   - **Lado Izquierdo:** Logo GTQC (sin marca de agua) + Datos empresa
   - **Centro:** Certificaciones ISO (estáticas)
   - **Lado Derecho:** Datos de empresa + RUC
   - **Cuerpo:** Tabla con items del presupuesto
   - **Pie:** Términos y condiciones, fecha validez, totalciones
   - Fuente: Arial 10pt, márgenes: 10mm, colores corporativos GTQC

3. Generación **offline** (< 1 segundo):
   - Ejecuta en browser del usuario
   - Sin llamadas a servidor
   - Funciona sin internet

4. Opciones post-generación:
   - Descargar (navegador estándar)
   - Vista previa (modal)
   - Enviar por email (requiere backend)

**Flujo Alternativo (Con Errores):**
- Si falta datos: Modal con campos requeridos en rojo
- Usuario completa campos faltantes
- Reintenta generación

**Postcondiciones:**
- PDF generado con nombre: `PRESUPUESTO_BUD-YYYY-NNNN_CLIENTE.pdf`
- Archivo disponible para descargar
- Metadatos registrados (fecha generación, usuario, versión)

---

## UC-007: Generar PDF Profesional (Servidor - Versión Auditable)

**Actor Principal:** Ejecutivo de Ventas / Administrador

**Precondiciones:**
- Presupuesto completado
- Usuario tiene acceso a internet
- Usuario selecciona "Generar PDF Profesional" o "Enviar Oficial"
- Presupuesto alcanza estado PRE_APROBADO o APROBADO

**Flujo Principal:**
1. Usuario selecciona "Generar Oficial" desde presupuesto
2. Sistema envía JSON del presupuesto al servidor:
   ```json
   {
     "id": "BUD-2026-0001",
     "cliente": {...},
     "items": [...],
     "totales": {...},
     "generadoPor": "usuario@gtqc.com",
     "timestamp": "2026-09-11T14:30:00Z"
   }
   ```

3. Backend (Node.js + PDFKit):
   - Recibe JSON y valida
   - Genera PDF profesional con:
     - Formato idéntico a cliente pero con mejor compresión
     - Firma digital (opcional, si está configurado)
     - QR con código de presupuesto (verificable)
     - Número de serie único (para auditoría)
   - Almacena PDF en base de datos (blob) o S3
   - Registra auditoría: quién generó, cuándo, desde dónde

4. Sistema retorna al cliente:
   - URL descargable del PDF profesional
   - Hash de integridad (SHA256)
   - Código de verificación

5. Presupuesto cambia estado a OFICIAL

**Postcondiciones:**
- PDF profesional almacenado en servidor
- Presupuesto marcado como OFICIAL
- Registro de auditoría completo
- URL descargable disponible (válido 30 días)

---

## UC-008: Enviar Presupuesto por Email

**Actor Principal:** Ejecutivo de Ventas

**Precondiciones:**
- Presupuesto generado (PDF disponible)
- Email del cliente registrado
- Conexión a internet disponible

**Flujo Principal:**
1. Usuario selecciona "Enviar por Email"
2. Sistema abre modal pre-completado con:
   - Email cliente (desde SUNAT o ingresado manualmente)
   - Asunto: "Presupuesto BUD-YYYY-NNNN - GTQC"
   - Cuerpo plantilla profesional:
     ```
     Estimado [RAZÓN SOCIAL],
     
     Adjunto encontrará nuestro presupuesto para su proyecto.
     
     Presupuesto N°: BUD-YYYY-NNNN
     Proyecto: [NOMBRE PROYECTO]
     Monto Total: S/ [TOTAL]
     Válido por: 15 días
     
     Cualquier duda, nos contacta.
     
     Cordialmente,
     GTQC
     ```
   - Archivo: PDF (cliente o profesional)

3. Usuario puede:
   - Modificar asunto
   - Modificar cuerpo
   - Agregar emails adicionales (CC/BCC)
   - Agregar archivos adjuntos

4. Usuario selecciona "Enviar"
5. Sistema valida:
   - Email válido
   - Conexión a internet
6. Llamada a backend:
   - NodeMailer o SendGrid
   - Envía email con PDF adjunto
7. Sistema registra:
   - Timestamp de envío
   - Email destino
   - Estado "Enviado"

**Flujo Alternativo (Sin Internet):**
- Presupuesto se marca como "Pendiente Envío"
- Cuando hay internet: se envía automáticamente (background sync)

**Postcondiciones:**
- Email enviado exitosamente
- Registro de envío en presupuesto
- Presupuesto cambio estado a "ENVIADO"

---

## UC-009: Guardar Presupuesto Offline

**Actor Principal:** Sistema / Ejecutivo de Ventas

**Precondiciones:**
- Presupuesto abierto
- Cambios realizados por usuario
- Usuario sin conexión a internet (opcional)

**Flujo Principal:**
1. Usuario realiza cambios en presupuesto:
   - Agregar/eliminar items
   - Cambiar cantidades
   - Aplicar descuentos
   - Etc.

2. Sistema detecta cambios automáticamente:
   - Listener en cada input
   - Debounce de 500ms

3. Para CADA cambio:
   - Guarda automáticamente en **IndexedDB** (tabla: `Presupuestos`)
   - No muestra modal de guardado (transparente)
   - Icono de "Guardado" aparece brevemente (feedback visual)

4. Estructura en IndexedDB:
   ```javascript
   {
     id: "BUD-2026-0001",
     estado: "BORRADOR",
     cliente: {...},
     items: [...],
     totales: {...},
     ultimaModificacion: timestamp,
     usuarioModifico: "user@gtqc.com",
     sincronizado: false,
     pendienteSincronizacion: false
   }
   ```

5. Si presupuesto no se envía a servidor:
   - Se mantiene localmente
   - Si usuario limpia caché: presupuesto se pierde (advertencia al salir)

**Postcondiciones:**
- Presupuesto guardado en IndexedDB
- Datos seguros localmente
- Cambios listos para sincronización cuando haya internet

---

## UC-010: Sincronizar Presupuestos (Background Sync)

**Actor Principal:** Service Worker / Sistema

**Precondiciones:**
- Presupupuestos guardados en IndexedDB (offline)
- Cambios no sincronizados (pendienteSincronizacion = true)
- Conexión a internet recuperada

**Flujo Principal:**
1. Service Worker detecta evento **online** (navigator.onLine)

2. Sistema identifica presupuestos no sincronizados:
   ```javascript
   SELECT * FROM Presupuestos WHERE pendienteSincronizacion = true
   ```

3. Para cada presupuesto pendiente:
   - Intenta sincronizar con servidor (POST /api/presupuestos/{id}/sync)
   - Envía JSON con estado actual

4. Server procesa sincronización:
   - Valida datos
   - Compara timestamps
   - Si no hay conflicto: actualiza en PostgreSQL
   - Si hay conflicto: registra ambas versiones (merge)

5. Respuesta del servidor:
   ```json
   {
     "status": "synced",
     "id": "BUD-2026-0001",
     "serverTimestamp": "2026-09-11T15:00:00Z",
     "conflictResolved": false
   }
   ```

6. Sistema actualiza IndexedDB:
   - pendienteSincronizacion = false
   - sincronizado = true
   - serverTimestamp = valor recibido

7. Usuario ve notificación (toast):
   - "Presupuesto sincronizado exitosamente"

**Flujo Alternativo (Conflicto de Versiones):**
1. Si hay conflicto (usuario editó tanto localmente como en otro dispositivo):
   - Sistema muestra diálogo: "Conflicto de sincronización"
   - Opción 1: Usar versión local
   - Opción 2: Usar versión servidor
   - Opción 3: Ver diferencias (diff)

2. Usuario selecciona opción
3. Sistema resuelve conflicto y sincroniza versión final

**Flujo Alternativo (Error de Servidor):**
- Si servidor responde error: reintenta cada 30 segundos
- Máximo 5 reintentos
- Si falla después de 5: muestra notificación "Error de sincronización, reintenta más tarde"

**Postcondiciones:**
- Todos los presupuestos offline sincronizados con servidor
- Base de datos PostgreSQL actualizada
- IndexedDB marcado como sincronizado
- Usuario vé confirmación visual

---

## Matriz de Estados de Presupuesto

| Estado | Descripción | Permite Edición | Permite Eliminar |
|--------|-------------|-----------------|-----------------|
| BORRADOR | Presupuesto en creación | ✓ | ✓ |
| COMPLETO | Todos campos requeridos | ✓ | ✓ |
| PRE_APROBADO | Aprobado internamente | ✗ | ✗ |
| OFICIAL | PDF oficial generado | ✗ | ✗ |
| ENVIADO | Enviado a cliente | ✗ | ✗ |
| ACEPTADO | Cliente aceptó | ✗ | ✗ |
| RECHAZADO | Cliente rechazó | ✗ | ✓ (reactivar) |
| ARCHIVADO | Cierre administrativo | ✗ | ✗ |

---

## Matriz Acceso/Permisos

| Rol | Crear | Editar | Generar PDF | Enviar | Aprobar | Eliminar |
|-----|-------|--------|------------|--------|---------|----------|
| Ejecutivo Ventas | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| Gerente | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Admin | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Cliente (Lectura) | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |

