# 📊 Estados de Cotizaciones y su Relación con la Base de Datos

## ¿Qué tiene que ver con la BD?

**MUCHO.** El campo `estado` en la tabla **COTIZACIONES** es el que controla todo el flujo de aprobación/rechazo. Es una de las columnas más importantes.

---

## 🎯 Los 5 Estados Posibles

```sql
ENUM('borrador', 'emitida', 'aceptada', 'rechazada', 'cancelada')
```

| Estado | Significado | Acción | Visible para Cliente |
|--------|------------|--------|----------------------|
| **borrador** 📝 | Cotización en edición | Usuario edita items, descuentos, datos | ❌ NO |
| **emitida** ✅ | Enviada al cliente | Se descargó PDF o se envió por email/WhatsApp | ✅ SÍ (puede aceptar) |
| **aceptada** 🎉 | Cliente aceptó | Procede a facturación/ejecución | ✅ SÍ (en historial) |
| **rechazada** ❌ | Cliente rechazó | Se archiva, puede crear nueva | ✅ SÍ (en historial) |
| **cancelada** 🚫 | Cancelada por laboratorio | Anulada por razones internas | ✅ SÍ (opcional) |

---

## 🔄 Flujo de Estados

```
┌─────────────┐
│  BORRADOR   │ ← Usuario crea y edita
│     📝      │
└──────┬──────┘
       │
       ├─ Descarga PDF
       ├─ Envía WhatsApp
       └─ Envía Email
       │
       ▼
┌─────────────┐
│   EMITIDA   │ ← Ahora el cliente ve en su dashboard
│      ✅     │
└──────┬──────┘
       │
       ├─ Cliente ACEPTA
       │  └─▶ ACEPTADA 🎉
       │
       ├─ Cliente RECHAZA
       │  └─▶ RECHAZADA ❌
       │
       └─ Laboratorio CANCELA
          └─▶ CANCELADA 🚫
```

---

## 💾 En la Base de Datos

### Tabla: COTIZACIONES

```sql
CREATE TABLE COTIZACIONES (
    id VARCHAR(36) PRIMARY KEY,
    numeroSerie VARCHAR(50) NOT NULL UNIQUE,  -- COT-2024-001
    clienteRuc VARCHAR(11),
    clienteDni VARCHAR(8),
    contactoId VARCHAR(36),
    nombreProyecto VARCHAR(200),
    validezDias INT DEFAULT 30,
    plantilaId VARCHAR(36),
    
    ⭐ estado ENUM('borrador', 'emitida', 'aceptada', 'rechazada', 'cancelada') 
             DEFAULT 'borrador' COMMENT 'Estado de cotización',
    
    fechaCreacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fechaEmision TIMESTAMP,                   -- ← Se llena cuando pasa a EMITIDA
    observaciones TEXT,
    ...
);
```

### Cuando ocurren los cambios:

```sql
-- Paso 1: Usuario crea cotización
INSERT INTO COTIZACIONES 
VALUES (..., estado='borrador', fechaCreacion=NOW(), ...);

-- Paso 2: Usuario descarga o envía
UPDATE COTIZACIONES 
SET estado='emitida', fechaEmision=NOW() 
WHERE id='cot_12345';

-- Paso 3: Cliente acepta (o rechaza)
UPDATE COTIZACIONES 
SET estado='aceptada' 
WHERE id='cot_12345';

-- Paso 4: Se registra en auditoría
-- (tabla COTIZACION_DESCARGAS y COTIZACION_ENVIOS también quedan registradas)
```

---

## 📊 Dashboard del Cliente: ¿Qué Ve?

El dashboard del cliente SOLO muestra cotizaciones en estados: `emitida`, `aceptada`, `rechazada`

**NO ve** las que están en `borrador` (porque aún no se han descargado/enviado).

### Stat Cards (Números en Grande):
```
┌──────────────────┐
│ 12 COTIZACIONES  │ (Total emitidas + aceptadas + rechazadas)
└──────────────────┘

┌──────────────────┐
│ 8 ACEPTADAS 🎉   │ (Las que el cliente aprobó)
└──────────────────┘

┌──────────────────┐
│ 2 RECHAZADAS ❌   │ (Las que el cliente dijo que no)
└──────────────────┘

┌──────────────────┐
│ S/ 28,450.00     │ (Total invertido en aceptadas)
└──────────────────┘
```

### Tabla Filtrable:
```
NÚMERO      | FECHA       | MONTO      | ESTADO      | ACCIÓN
COT-2024-01 | 15 Ago      | S/ 3,200   | ✅ ACEPTADA | Ver Detalles
COT-2024-02 | 18 Ago      | S/ 1,500   | ❌ RECHAZADA| Ver Detalles
COT-2024-03 | 20 Ago      | S/ 2,100   | ✅ ACEPTADA | Ver Detalles
COT-2024-04 | 22 Ago      | S/ 890     | ⏳ EMITIDA  | Pendiente
```

### Gráfico de Estados (Pie Chart):
```
ACEPTADAS:   8 (67%)  ▓▓▓▓▓▓▓░░
RECHAZADAS:  2 (17%)  ▓▓░░░░░░░
EMITIDAS:    2 (17%)  ▓▓░░░░░░░
```

### Gráfico de Tendencia (Line Chart):
```
Gasto por Mes (Solo Aceptadas)
├─ Enero:    S/ 12,000
├─ Febrero:  S/ 15,500
├─ Marzo:    S/ 920
└─ Abril:    S/ [Vacío - sin datos]
```

---

## 🎯 Relación Completa: Tabla COTIZACIONES ↔ Dashboard

```
┌─────────────────────────────┐
│   TABLA: COTIZACIONES       │
├─────────────────────────────┤
│ id                          │
│ numeroSerie: COT-2024-01    │
│ clienteRuc: 20123456789     │
│ monto: 3200.00              │
│ estado: 'aceptada' ⭐       │ ← Este campo determina lo que ve el cliente
│ fechaEmision: 2024-08-15    │
└─────────────────────────────┘
           │
           │ SQL Query:
           │ SELECT * FROM COTIZACIONES 
           │ WHERE clienteRuc='20123456789' 
           │ AND estado IN ('emitida','aceptada','rechazada')
           │
           ▼
┌─────────────────────────────┐
│   DASHBOARD DEL CLIENTE     │
├─────────────────────────────┤
│ Stat Cards:                 │
│ - 8 Aceptadas               │
│ - 2 Rechazadas              │
│                             │
│ Tabla Filtrable:            │
│ - COT-2024-01 ✅ ACEPTADA   │
│ - COT-2024-04 ⏳ EMITIDA    │
│                             │
│ Gráficos:                   │
│ - Pie: Distribución estados │
│ - Line: Gasto por mes       │
└─────────────────────────────┘
```

---

## 🔍 Cuadro de Leyenda (Lo que probablemente falta)

### Opción 1: Tabla de Resumen Estados (Recomendado)

```html
┌─────────────────────────────────────────────────┐
│          LEYENDA DE ESTADOS                     │
├──────────┬──────────┬─────────┬────────────────┤
│ ESTADO   │ SÍMBOLO  │ CANTIDAD│ DESCRIPCIÓN    │
├──────────┼──────────┼─────────┼────────────────┤
│ Emitida  │    ⏳    │   2     │ Pendiente      │
│          │          │         │ respuesta      │
├──────────┼──────────┼─────────┼────────────────┤
│ Aceptada │    ✅    │   8     │ Cliente        │
│          │          │         │ aprobó        │
├──────────┼──────────┼─────────┼────────────────┤
│Rechazada │    ❌    │   2     │ Cliente        │
│          │          │         │ rechazó       │
├──────────┼──────────┼─────────┼────────────────┤
│Cancelada │    🚫    │   0     │ Anulada por    │
│          │          │         │ laboratorio    │
└──────────┴──────────┴─────────┴────────────────┘
```

### Opción 2: Indicadores por Color

```
🟢 ACEPTADA (Verde)        = Cliente dijo SÍ → Procede a ejecución
🟡 EMITIDA (Amarillo)      = Esperando respuesta del cliente
🔴 RECHAZADA (Rojo)        = Cliente dijo NO → Archivar
⚫ CANCELADA (Gris)        = Anulada internamente
```

---

## 💡 Queries Útiles para Reportes

```sql
-- ¿Cuántas cotizaciones por estado?
SELECT estado, COUNT(*) as cantidad
FROM COTIZACIONES
WHERE clienteRuc = '20123456789'
GROUP BY estado;

-- Gasto total por estado (solo aceptadas)
SELECT estado, SUM(monto) as total
FROM COTIZACIONES
WHERE clienteRuc = '20123456789' 
AND estado = 'aceptada'
GROUP BY estado;

-- Cotizaciones aceptadas este mes
SELECT COUNT(*) as aceptadas_mes
FROM COTIZACIONES
WHERE clienteRuc = '20123456789'
AND estado = 'aceptada'
AND MONTH(fechaEmision) = MONTH(NOW())
AND YEAR(fechaEmision) = YEAR(NOW());

-- Tasa de conversión (aceptadas / emitidas)
SELECT 
  (SELECT COUNT(*) FROM COTIZACIONES 
   WHERE estado='aceptada') as aceptadas,
  (SELECT COUNT(*) FROM COTIZACIONES 
   WHERE estado IN ('emitida','aceptada','rechazada')) as total,
  ROUND(
    (SELECT COUNT(*) FROM COTIZACIONES 
     WHERE estado='aceptada') / 
    (SELECT COUNT(*) FROM COTIZACIONES 
     WHERE estado IN ('emitida','aceptada','rechazada')) 
    * 100, 2
  ) as porcentaje;
```

---

## 🎬 Caso de Uso Real

**Scenario: Cliente ABC Constructora revisa su dashboard**

```
1. Entra al dashboard con su RUC: 20123456789

2. Ve en STAT CARDS:
   ├─ 12 Cotizaciones (Total)
   ├─ 8 Aceptadas (66.7%) → S/ 28,450
   ├─ 2 Rechazadas (16.7%)
   └─ 2 Emitidas (16.7%) → Pendientes

3. Filtra por "ACEPTADAS" en la tabla

4. Ve 8 cotizaciones con ✅ estado

5. Haz clic en COT-2024-05 para ver detalles:
   ├─ Fecha: 20 de Agosto 2024
   ├─ Monto: S/ 2,100.00
   ├─ Items: 3 ensayos
   │  ├─ Compresión (NTP 339.034): S/ 800
   │  ├─ Flexión (NTP 339.045): S/ 900
   │  └─ Adherencia: S/ 400
   ├─ Estado: ✅ ACEPTADA
   ├─ Descargada: 20 Ago (offline)
   └─ Enviada por WhatsApp: 20 Ago 14:45

6. Vuelve al gráfico PIE:
   Ve que las aceptadas representan 67% (8 de 12)
   Esto le da confianza: "La mayoría de mis cotizaciones se concretan"
```

---

## 📝 Tabla de Trazabilidad (Auditoría Completa)

La BD permite ver TODO lo que sucedió con una cotización:

```
COTIZACIÓN: COT-2024-05 (S/ 2,100)
├─ Creada: 19 Ago 2024, 09:30 (estado: BORRADOR)
├─ Descargada: 20 Ago 2024, 11:00 (estado → EMITIDA)
├─ Enviada por WhatsApp: 20 Ago 2024, 11:05
│  └─ A: +51 999 888 777 (Juan Pérez)
│  └─ Respuesta: OK ✓
├─ Aceptada: 21 Ago 2024, 09:15 (estado → ACEPTADA)
│  └─ Quien: Juan Pérez (contactoId: cnt_12345)
└─ En ejecución: Laboratorio comienza ensayos

TODO esto está registrado en:
├─ COTIZACIONES.estado = 'aceptada'
├─ COTIZACIONES.fechaEmision = 2024-08-20
├─ COTIZACION_DESCARGAS (registro de descarga offline)
└─ COTIZACION_ENVIOS (registro de envío WhatsApp)
```

---

## 🎨 Propuesta: Mejorar el Dashboard con Leyenda Visual

**Agregar una sección tipo "Card" al dashboard que diga:**

```
╔════════════════════════════════════╗
║     ESTADOS DE COTIZACIÓN          ║
╠════════════════════════════════════╣
║                                    ║
║  🟢 ACEPTADA                       ║
║     Cliente aprobó la cotización   ║
║     Procede a ejecución            ║
║                                    ║
║  🟡 EMITIDA                        ║
║     Enviada al cliente, esperando  ║
║     su respuesta (dentro de plazo) ║
║                                    ║
║  🔴 RECHAZADA                      ║
║     Cliente rechazó la cotización  ║
║     Archivada (sin proceder)       ║
║                                    ║
║  ⚫ CANCELADA                       ║
║     Anulada por el laboratorio     ║
║     (razones internas)             ║
║                                    ║
╚════════════════════════════════════╝
```

---

## ✅ Resumen: BD ↔ Dashboard

| Componente | BD | Dashboard |
|---|---|---|
| **Datos Source** | Tabla COTIZACIONES | Query filtrada por estado |
| **Campo Crítico** | `estado` ENUM | Determina visibilidad |
| **Estados Mostrados** | 5 posibles | 3-4 activos (emitida, aceptada, rechazada) |
| **Stat Cards** | COUNT por estado | 8 aceptadas, 2 rechazadas, 2 emitidas |
| **Tabla Filtrable** | Todos los registros | Filtra por estado, fecha, monto |
| **Gráficos** | Datos agregados | Pie (distribución), Line (tendencia) |
| **Auditoría** | DESCARGAS + ENVIOS | Muestra fecha/canal en modal |

**Conclusión**: El estado en la BD controla TODO. Sin él, no hay dashboard funcional.

---

**Documento:** `ESTADOS_COTIZACIONES_Y_BD.md`  
**Fecha:** 2026-09-24  
**Para:** Explicar relación entre BD y dashboard al cliente
