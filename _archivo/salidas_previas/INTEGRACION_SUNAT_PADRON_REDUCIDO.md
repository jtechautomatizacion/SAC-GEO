# Integración SUNAT - Padrón Reducido de Contribuyentes

## 1. Introducción

Este documento especifica la integración de la PWA Presupuestos GTQC con la **API del Padrón Reducido de SUNAT** para validación automática de RUCs y obtención de datos de empresas en Perú.

### Objetivo
Validar RUCs de clientes en tiempo real y autocompletar:
- Razón Social
- Domicilio Fiscal
- Actividad Principal
- Estado del Contribuyente

### Beneficios
- Reducción de errores en datos de cliente
- Velocidad en creación de presupuestos
- Cumplimiento regulatorio (datos actualizados)
- Caché local para funcionamiento sin internet

---

## 2. API SUNAT - Padrón Reducido

### 2.1 Opciones de Integración con SUNAT

SUNAT ofrece varias opciones para consultar el padrón:

#### Opción A: API REST Directa (Recomendada)
- **Endpoint:** `https://e-consultaruc.sunat.gob.pe/cl-ti-itmrconsruc/jcrMantenimiento`
- **Método:** POST / GET
- **Autenticación:** Usuario/Contraseña (gestión de usuario SUNAT)
- **Rate Limit:** 1000 requests/día (plan básico)
- **Costo:** Gratis para consultas básicas

#### Opción B: Web Scraping (No Recomendado)
- Consumo de HTML desde portal web de SUNAT
- Frágil ante cambios de UI
- Posible bloqueo de IPs por SUNAT

#### Opción C: Provider Tercero (APIs Marketplace)
- **Ejemplo:** Api.ruc.com.pe, Sumapi, Apilabs
- **Ventaja:** Interfaz simplificada, mejor tasa de éxito
- **Costo:** ~$0.05 a $0.20 por consulta
- **Mejor para:** Si SUNAT API es compleja de configurar

**DECISIÓN:** Usar Opción A (API SUNAT) como primaria + fallback a provider tercero

---

## 3. Especificación Técnica API SUNAT

### 3.1 Endpoint Principal

```
POST https://e-consultaruc.sunat.gob.pe/cl-ti-itmrconsruc/jcrMantenimiento
Content-Type: application/x-www-form-urlencoded
```

### 3.2 Parámetros de Solicitud

| Parámetro | Tipo | Requerido | Descripción |
|-----------|------|----------|------------|
| nroRuc | String | ✓ | RUC sin guiones (11 dígitos) |
| usrSolesol | String | ✓ | Usuario SUNAT (debe registrarse previamente) |
| pwdSolesol | String | ✓ | Contraseña SUNAT (encriptada) |
| radsolesol | String | ✗ | Radicación de solicitud (puede generarse) |
| rucsolicitud | String | ✗ | RUC de la empresa solicitante (GTQC) |

### 3.3 Respuesta Exitosa (Ejemplo)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="...">
  <SOAP-ENV:Body>
    <ns2:getDataResponse xmlns:ns2="...">
      <return>
        <ddp_ciiu>6201</ddp_ciiu>
        <ddp_departamento>LIMA</ddp_departamento>
        <ddp_direccion>AV. PRINCIPAL 123 PISO 5</ddp_direccion>
        <ddp_distrito>SAN ISIDRO</ddp_distrito>
        <ddp_estaddr>01</ddp_estaddr>
        <ddp_estblk>01</ddp_estblk>
        <ddp_estdomicilio>01</ddp_estdomicilio>
        <ddp_estjuridica>02</ddp_estjuridica>
        <ddp_estprov>01</ddp_estprov>
        <ddp_estado>ACTIVO</ddp_estado>
        <ddp_jdescestablecimiento>PRINCIPAL</ddp_jdescestablecimiento>
        <ddp_jdescestblk>ACTIVO</ddp_jdescestblk>
        <ddp_jdescestdomicilio>DOMICILIO REGISTRADO</ddp_jdescestdomicilio>
        <ddp_jdescestjuridica>SOCIEDAD ANÓNIMA CERRADA</ddp_jdescestjuridica>
        <ddp_jdescestprov>ACTIVO</ddp_jdescestprov>
        <ddp_jdescestado>ACTIVO</ddp_jdescestado>
        <ddp_jdescprov>LIMA</ddp_jdescprov>
        <ddp_jrazsoc>EMPRESA ABC S.A.C.</ddp_jrazsoc>
        <ddp_nroddd>20123456789</ddp_nroddd>
        <ddp_provincia>LIMA</ddp_provincia>
        <ddp_tpoestadomp>01</ddp_tpoestadomp>
        <ddp_ubigeo>150000</ddp_ubigeo>
        <ddp_vinculacion>00</ddp_vinculacion>
        <p_data_error></p_data_error>
        <p_is_repetida>0</p_is_repetida>
      </return>
    </ns2:getDataResponse>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
```

### 3.4 Mapeo de Campos (XML → Aplicación)

```javascript
const mapearRespuestaSUNAT = (xmlResponse) => {
  return {
    ruc: xmlResponse.ddp_nroddd,
    razonSocial: xmlResponse.ddp_jrazsoc,
    domicilio: `${xmlResponse.ddp_direccion} ${xmlResponse.ddp_distrito}`,
    distrito: xmlResponse.ddp_distrito,
    provincia: xmlResponse.ddp_provincia,
    departamento: xmlResponse.ddp_departamento,
    ciiu: xmlResponse.ddp_ciiu,  // Código actividad
    estado: xmlResponse.ddp_jdescestado,  // ACTIVO / SUSPENSO / BAJA
    tipoJuridica: xmlResponse.ddp_jdescestjuridica,
    establecimiento: xmlResponse.ddp_jdescestablecimiento,
    ubigeo: xmlResponse.ddp_ubigeo,
    estadoValidacion: 'ACTIVO' // o INACTIVO / BAJA
  };
};
```

### 3.5 Códigos de Error

| Código | Significado | Acción |
|--------|-------------|--------|
| 0 | Consulta exitosa | Usar datos retornados |
| 1 | RUC no encontrado | Mostrar "RUC no existe en SUNAT" |
| 2 | Parámetros inválidos | Validar formato RUC (11 dígitos) |
| 3 | Usuario/Contraseña inválidos | Verificar credenciales SUNAT |
| 99 | Error de servidor SUNAT | Reintentary/usar fallback |

---

## 4. Arquitectura de Integración

### 4.1 Diagrama de Flujo

```
┌─────────────────────────────────────────────────────────────┐
│ PWA PRESUPUESTOS (CLIENTE - BROWSER)                        │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ Usuario ingresa RUC (11 dígitos)                         ││
│ │ Validación formato: /^\d{11}$/                           ││
│ └──────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ ¿Hay internet?                                           ││
│ │ navigator.onLine === true                               ││
│ └──────────────────────────────────────────────────────────┘│
│            │                          │                      │
│        SÍ (Online)                   NO (Offline)           │
│            │                          │                      │
│            ▼                          ▼                      │
│ ┌──────────────────────┐  ┌──────────────────────────┐    │
│ │ Buscar en caché      │  │ Buscar en IndexedDB      │    │
│ │ IndexedDB primero    │  │ (RUCs consultados antes) │    │
│ │ (1000ms timeout)     │  │ (instantáneo)            │    │
│ └──────────────────────┘  └──────────────────────────┘    │
│            │                          │                      │
│  ┌─────────▼──────────┐     ┌────────▼─────────┐           │
│  │ ¿RUC en caché?     │     │ ¿RUC encontrado? │           │
│  │ Y no expirado      │     │ en caché local   │           │
│  │ (max 30 días)      │     │                  │           │
│  └────┬──────┬────────┘     └────┬─────┬───────┘           │
│       │      │                   │     │                    │
│     SÍ│      │NO              SÍ │     │NO                  │
│       │      │                   │     │                    │
│       ▼      ▼                   ▼     ▼                    │
│    ┌──────────────────┐    ┌──────────────────────────┐   │
│    │ Usar datos       │    │ Mostrar campo vacío      │   │
│    │ almacenados      │    │ + icono "Sincronizando" │   │
│    │ (instantáneo)    │    │ (modo offline)           │   │
│    └──────────────────┘    └──────────────────────────┘   │
│            │                          │                      │
│            └──────────────┬───────────┘                      │
│                           ▼                                  │
│                 ┌──────────────────────┐                     │
│                 │ Backend esperando... │                     │
│                 │ (Queue offline queue) │                     │
│                 └──────────────────────┘                     │
└─────────────────────────────────────────────────────────────┘
         [Conexión online]
                │
                ▼
┌─────────────────────────────────────────────────────────────┐
│ BACKEND NODE.JS / EXPRESS                                   │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ POST /api/consultas/ruc-sunat                           ││
│ │ Body: { ruc: "20123456789" }                            ││
│ └──────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ Verificar rate limit (redisLimit)                       ││
│ │ Max: 1000/día por usuario                               ││
│ └──────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ Hacer llamada a SUNAT API                               ││
│ │ POST https://e-consultaruc.sunat.gob.pe/...            ││
│ │ Auth: (usuario, password) encriptado                    ││
│ │ Timeout: 5 segundos                                     ││
│ └──────────────────────────────────────────────────────────┘│
│                          │                                   │
│         ┌────────────────┼────────────────┐                 │
│         │                │                │                 │
│      Éxito            Timeout           Error              │
│         │                │                │                 │
│         ▼                ▼                ▼                 │
│    ┌───────────┐  ┌──────────────┐  ┌──────────────┐      │
│    │ Respuesta │  │ Intenta API  │  │ Intenta      │      │
│    │ XML       │  │ provider     │  │ provider     │      │
│    │ OK        │  │ tercero      │  │ tercero      │      │
│    └───────────┘  └──────────────┘  └──────────────┘      │
│         │                │                │                 │
│         └────────────────┼────────────────┘                 │
│                          ▼                                   │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ Parsear respuesta XML                                   ││
│ │ Mapear a JSON estándar                                  ││
│ └──────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ Guardar en caché Redis (24 horas)                       ││
│ │ Guardar en DB PostgreSQL (histórico)                    ││
│ └──────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ Retornar JSON al cliente                                ││
│ │ { ruc, razonSocial, domicilio, estado, ... }           ││
│ └──────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
         [Respuesta JSON]
                │
                ▼
┌─────────────────────────────────────────────────────────────┐
│ PWA CLIENTE                                                 │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ Guardar en IndexedDB con TTL (30 días)                  ││
│ │ Completar automáticamente campos:                        ││
│ │ - Razón Social                                           ││
│ │ - Domicilio                                              ││
│ │ - Distrito / Provincia                                   ││
│ │ Validar estado: ¿ACTIVO?                                ││
│ │ - Si ACTIVO: ✓ (continuar)                              ││
│ │ - Si otro: ⚠ (advertencia al usuario)                   ││
│ └──────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ Presupuesto listo para continuar                        ││
│ │ Usuario puede agregar items                              ││
│ └──────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Componentes Implicados

#### Cliente (PWA - React)
```javascript
// Archivo: src/services/sunatService.js

export class SUNATService {
  
  // 1. Validación local
  static validateRUC(ruc) {
    return /^\d{11}$/.test(ruc);
  }

  // 2. Consulta con fallback
  static async consultarRUC(ruc) {
    // Primero: IndexedDB (caché local)
    const cached = await this.getCacheLocal(ruc);
    if (cached && !this.isExpired(cached)) {
      return cached;
    }

    // Segundo: Servidor (online)
    if (navigator.onLine) {
      try {
        const response = await fetch('/api/consultas/ruc-sunat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ruc })
        });
        
        if (response.ok) {
          const data = await response.json();
          await this.saveCacheLocal(ruc, data);
          return data;
        }
      } catch (error) {
        console.error('Error consultando SUNAT:', error);
      }
    }

    // Tercero: Offline mode
    return null; // Retorna null si no tiene caché y no hay internet
  }

  // 3. Caché local (IndexedDB)
  static async getCacheLocal(ruc) {
    const db = await openDB('gtqc-presupuestos');
    return await db.get('rucs-consultados', ruc);
  }

  static async saveCacheLocal(ruc, data) {
    const db = await openDB('gtqc-presupuestos');
    await db.put('rucs-consultados', {
      ruc,
      ...data,
      consultadoEn: new Date().toISOString(),
      expiraEn: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
    });
  }

  static isExpired(cached) {
    return new Date(cached.expiraEn) < new Date();
  }
}
```

#### Backend (Node.js - Express)
```javascript
// Archivo: src/routes/consultas.js

router.post('/api/consultas/ruc-sunat', async (req, res) => {
  const { ruc } = req.body;

  // Validación
  if (!/^\d{11}$/.test(ruc)) {
    return res.status(400).json({ error: 'RUC inválido' });
  }

  try {
    // 1. Verificar caché Redis
    const cached = await redis.get(`ruc:${ruc}`);
    if (cached) {
      return res.json(JSON.parse(cached));
    }

    // 2. Llamar a SUNAT API
    const dataSUNAT = await consultarSUNAT(ruc);
    
    // 3. Mapear respuesta
    const dataMapped = mapearRespuestaSUNAT(dataSUNAT);

    // 4. Guardar en caché (24 horas)
    await redis.setex(`ruc:${ruc}`, 86400, JSON.stringify(dataMapped));

    // 5. Guardar en BD (histórico)
    await db.query(
      'INSERT INTO consultas_ruc (ruc, razonSocial, estado, consultado_en) VALUES ($1, $2, $3, NOW())',
      [ruc, dataMapped.razonSocial, dataMapped.estado]
    );

    // 6. Retornar
    res.json(dataMapped);

  } catch (error) {
    console.error('Error SUNAT:', error);
    
    // Fallback a provider tercero
    try {
      const dataProvider = await consultarProviderTercero(ruc);
      res.json(dataProvider);
    } catch (error2) {
      res.status(500).json({ error: 'No se pudo consultar RUC' });
    }
  }
});
```

---

## 5. Configuración SUNAT

### 5.1 Registro en SUNAT

Para usar la API de SUNAT, GTQC debe:

1. **Registrarse en Portal SUNAT**
   - Ingresar a: https://e-consultaruc.sunat.gob.pe
   - Crear cuenta con RUC de GTQC
   - Generar credenciales (usuario/contraseña)

2. **Configurar Acceso**
   - Solicitar permisos para API programática
   - SUNAT asignará cuota diaria (ej: 1000 consultas/día)
   - Proporcionar IP(s) permitidas del servidor

3. **Documentación de SUNAT**
   - https://www.sunat.gob.pe/orientacionaduanera/web/publico/index.html
   - Manual de uso: "Guía de integración Padrón Reducido"

### 5.2 Variables de Entorno

```bash
# .env archivo

# SUNAT Credentials (encriptadas)
SUNAT_USERNAME="usuario_sunat_encriptado"
SUNAT_PASSWORD="password_sunat_encriptado"
SUNAT_RUC_EMPRESA="20123456789"  # RUC de GTQC

# Rate Limiting
SUNAT_RATE_LIMIT_PER_DAY=1000
SUNAT_RATE_LIMIT_PER_MINUTE=10

# Fallback Provider
PROVIDER_API_KEY="api_key_tercero"
PROVIDER_API_URL="https://api.provider.com/ruc"

# Caché
REDIS_URL="redis://localhost:6379"
CACHE_TTL_HOURS=24
```

### 5.3 Credenciales Seguras

**IMPORTANTE:** Las credenciales SUNAT NO deben exponerse en frontend

```javascript
// Archivo: src/utils/encryption.js

const crypto = require('crypto');

class EncryptionService {
  
  static encrypt(text, key) {
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv('aes-256-cbc', Buffer.from(key), iv);
    let encrypted = cipher.update(text, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    return iv.toString('hex') + ':' + encrypted;
  }

  static decrypt(text, key) {
    const parts = text.split(':');
    const iv = Buffer.from(parts[0], 'hex');
    const decipher = crypto.createDecipheriv('aes-256-cbc', Buffer.from(key), iv);
    let decrypted = decipher.update(parts[1], 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
  }
}

module.exports = EncryptionService;
```

---

## 6. Manejo de Errores y Fallback

### 6.1 Matriz de Fallback

```
Intento 1: SUNAT API Oficial
  ├─ Éxito → Usar respuesta
  └─ Falla (timeout, error 3xx, etc)
        │
        ▼
Intento 2: Provider API Tercero (sumapi, apilabs)
  ├─ Éxito → Usar respuesta
  └─ Falla
        │
        ▼
Intento 3: Caché Redis (si existe)
  ├─ Éxito → Usar (aunque esté expirado)
  └─ Falta
        │
        ▼
Retorno: { error: 'RUC no validable', permitir_manual: true }
```

### 6.2 Estados Posibles en Respuesta

```javascript
{
  // Caso 1: Consulta exitosa
  status: "ok",
  ruc: "20123456789",
  razonSocial: "EMPRESA ABC S.A.C.",
  estado: "ACTIVO",  // ✓ Permitir uso
  ...
}

// Caso 2: RUC no encontrado
{
  status: "not_found",
  ruc: "20123456789",
  error: "RUC no existe en SUNAT"
}

// Caso 3: RUC inactivo
{
  status: "ok",
  ruc: "20123456789",
  razonSocial: "EMPRESA XYZ S.A.",
  estado: "BAJA",  // ⚠ Advertencia
  warning: "Empresa dada de baja"
}

// Caso 4: Error general
{
  status: "error",
  error: "No se pudo validar RUC",
  fallback: true  // Usar caché o permitir manual
}
```

---

## 7. Implementación Paso a Paso

### Fase 1: Configuración Básica (Semana 1)
- [ ] Registrar GTQC en portal SUNAT
- [ ] Obtener credenciales y cuota
- [ ] Configurar variables de entorno
- [ ] Implementar encriptación de credenciales

### Fase 2: Backend (Semana 2)
- [ ] Endpoint `/api/consultas/ruc-sunat`
- [ ] Integración SUNAT API (llamada SOAP/REST)
- [ ] Implementar Redis caché
- [ ] Implementar rate limiting
- [ ] Logging y auditoría de consultas

### Fase 3: Frontend (Semana 3)
- [ ] Componente de validación RUC
- [ ] IndexedDB para caché local
- [ ] Handlers offline/online
- [ ] UI feedback (cargando, error, éxito)
- [ ] Autocompletado de campos

### Fase 4: Testing (Semana 4)
- [ ] Tests unitarios (validación RUC)
- [ ] Tests integración (SUNAT API)
- [ ] Tests offline (caché IndexedDB)
- [ ] Pruebas con proveedores tercero
- [ ] Load testing (1000 req/día)

---

## 8. Costos y Consideraciones

| Aspecto | Opción | Costo | Notas |
|---------|--------|-------|-------|
| **API SUNAT** | Oficial | Gratis | Cuota limitada, requiere registro |
| **Fallback** | SumaPI | $0.05-0.10 por consulta | Para después de agotar cuota SUNAT |
| **Almacenamiento** | Redis | $5-10/mes | Para caché servidor |
| **BD Histórico** | PostgreSQL | Incluido | Tabla `consultas_ruc` |
| **Total Mensual** | - | ~$10-20/mes | Muy bajo costo |

---

## 9. Métricas y Monitoreo

```javascript
// Dashboard de SUNAT Integration

Métrica: Éxito de consultas
- Total consultas/día: 200
- Exitosas (SUNAT): 180 (90%)
- Fallback provider: 15 (7.5%)
- Error: 5 (2.5%)

Métrica: Tiempo de respuesta
- SUNAT API: 2-3 segundos
- Caché Redis: 50ms
- Provider tercero: 1-2 segundos

Métrica: Ratio de caché
- Consultas desde caché: 70% (sin llamar servidor)
- Consultas nuevas: 30%

Métrica: Errors
- Rate limit excedido: < 1%
- Timeout: < 2%
- RUC no encontrado: 5-10%
```

---

## 10. Ejemplos de Implementación

### Ejemplo: Componente React

```javascript
// src/components/RUCValidator.jsx

import React, { useState } from 'react';
import { SUNATService } from '../services/sunatService';

export const RUCValidator = ({ onSuccess, onError }) => {
  const [ruc, setRuc] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [data, setData] = useState(null);

  const handleValidate = async (e) => {
    e.preventDefault();
    
    if (!SUNATService.validateRUC(ruc)) {
      setError('RUC debe tener 11 dígitos');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await SUNATService.consultarRUC(ruc);
      
      if (result?.status === 'error') {
        setError(result.error);
        setData(null);
      } else {
        setData(result);
        onSuccess?.(result);
      }
    } catch (err) {
      setError('Error al consultar RUC');
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleValidate}>
      <input
        type="text"
        value={ruc}
        onChange={(e) => setRuc(e.target.value)}
        placeholder="Ingrese RUC (11 dígitos)"
        maxLength="11"
      />
      
      <button type="submit" disabled={loading}>
        {loading ? 'Validando...' : 'Validar RUC'}
      </button>

      {error && <div className="error">{error}</div>}
      
      {data && (
        <div className="success">
          <p>✓ {data.razonSocial}</p>
          <p>{data.domicilio}</p>
          {data.estado !== 'ACTIVO' && (
            <p className="warning">⚠ Estado: {data.estado}</p>
          )}
        </div>
      )}
    </form>
  );
};
```

