# PWA - PRESUPUESTOS GTQC
## Progressive Web App para Generación Automática de Presupuestos
**Implementación Moderna | 2026**

---

## 1. ¿QUÉ ES UNA PWA?

Una **Progressive Web App (PWA)** es una aplicación web que se comporta como una app nativa:

### Características Principales:
```
┌─────────────────────────────────────────────────────┐
│  PWA = Web + App Nativa (Lo mejor de ambas)        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ✅ Funciona en navegador (Chrome, Firefox, Edge)   │
│  ✅ Instalable en escritorio/móvil como app        │
│  ✅ Funciona SIN conexión a internet (Offline)     │
│  ✅ Acceso a hardware del dispositivo              │
│  ✅ Push notifications                             │
│  ✅ Sincronización en background                   │
│  ✅ Carga rápida (< 2 segundos)                    │
│  ✅ Responsive en cualquier pantalla               │
│  ✅ NO requiere App Store                          │
│  ✅ Una sola codebase (Web = Móvil)               │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 2. ¿POR QUÉ PWA PARA GTQC?

### Comparación: App Nativa vs PWA vs Web

| Aspecto | App Nativa | PWA | Web Tradicional |
|---------|------------|-----|-----------------|
| **Costo Desarrollo** | USD 10-15K | USD 4-6K ⭐ | USD 3-4K |
| **Tiempo** | 10-12 semanas | 5-7 semanas ⭐ | 4-6 semanas |
| **Mantener 2 códigos** | Sí (iOS+Android) | NO ⭐ | N/A |
| **Funciona Offline** | Sí | Sí ⭐ | NO |
| **Instalable** | Sí | Sí ⭐ | NO |
| **No necesita App Store** | NO | Sí ⭐ | N/A |
| **Actualización** | Manual/App Store | Automática ⭐ | Automática |
| **Push Notifications** | Sí | Sí ⭐ | NO |
| **Performance** | Excelente | Excelente ⭐ | Bueno |
| **Acceso Hardware** | Sí | Sí (cámara, GPS) | Limitado |

### 🏆 **PWA ES LA MEJOR OPCIÓN PARA GTQC**

**Razones:**
1. ✅ **Costo moderado**: USD 4,500-6,000 (sin app store costs)
2. ✅ **Un solo código**: Funciona web + móvil + tablet
3. ✅ **Offline**: Genera presupuestos sin internet
4. ✅ **Instalable**: Ícono en pantalla inicio (parece app nativa)
5. ✅ **Rápido**: Carga en < 2 segundos (cached)
6. ✅ **Actualizaciones**: Automáticas, sin gestión de versiones
7. ✅ **Distribución**: Link directo (no necesita App Store)

---

## 3. ARQUITECTURA PWA

### 3.1 Stack Tecnológico PWA

```
┌─────────────────────────────────────────────────┐
│  CLIENTE (Browser / Móvil)                      │
├─────────────────────────────────────────────────┤
│                                                 │
│  HTML5 + CSS3 + JavaScript                     │
│  ├─ Service Worker (offline, caching)          │
│  ├─ Web App Manifest (instalable)              │
│  ├─ Responsive Design (mobile-first)           │
│  └─ localStorage + IndexedDB (datos locales)   │
│                                                 │
│  FRAMEWORKS:                                    │
│  ├─ React.js / Vue.js / Angular               │
│  ├─ Tailwind CSS (diseño responsive)           │
│  ├─ PWA kit (herramientas PWA)                │
│  └─ jsPDF / pdfkit (generación PDF)           │
│                                                 │
└────────────────┬────────────────────────────────┘
                 │ HTTPS + REST API
                 ↓
┌─────────────────────────────────────────────────┐
│  SERVIDOR (Backend)                            │
├─────────────────────────────────────────────────┤
│                                                 │
│  Node.js/Express O Python/Django               │
│  ├─ API REST endpoints                         │
│  ├─ JWT Authentication                         │
│  ├─ Generación PDF (backend)                   │
│  └─ Envío de emails                            │
│                                                 │
│  BASE DE DATOS:                                 │
│  ├─ PostgreSQL (producción)                    │
│  ├─ Backups automáticos                        │
│  └─ Replicación para HA                        │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 4. COMPONENTES CLAVE DE UNA PWA

### 4.1 Service Worker (El corazón de la PWA)

```javascript
// archivo: public/service-worker.js

const CACHE_NAME = 'presupuestos-gtqc-v1';
const urlsToCache = [
  '/',
  '/index.html',
  '/css/styles.css',
  '/js/app.js',
  '/logo.png',
  '/manifest.json'
];

// Instalación del Service Worker
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      console.log('Cache abierto');
      return cache.addAll(urlsToCache);
    })
  );
});

// Interceptar requests (Offline-First Strategy)
self.addEventListener('fetch', event => {
  event.respondWith(
    caches.match(event.request).then(response => {
      // Si está en cache, devolver del cache
      if (response) {
        return response;
      }
      
      // Si no, hacer request al servidor
      return fetch(event.request).then(response => {
        // Cachear la nueva respuesta
        if (!response || response.status !== 200) {
          return response;
        }
        
        const responseClone = response.clone();
        caches.open(CACHE_NAME).then(cache => {
          cache.put(event.request, responseClone);
        });
        
        return response;
      }).catch(() => {
        // Si no hay conexión y no está cacheado
        return caches.match('/offline.html');
      });
    })
  );
});
```

**Beneficio**: Funciona offline, carga instantáneamente

### 4.2 Web App Manifest (Instalación)

```json
// archivo: public/manifest.json

{
  "name": "Presupuestos Group Total Quality Control",
  "short_name": "Presupuestos GTQC",
  "description": "Sistema automático de generación de presupuestos",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#0066cc",
  "orientation": "portrait-primary",
  
  "icons": [
    {
      "src": "/icons/icon-192x192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/icons/icon-512x512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/icons/icon-maskable-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    }
  ],
  
  "screenshots": [
    {
      "src": "/screenshots/screenshot1.png",
      "sizes": "540x720",
      "type": "image/png",
      "form_factor": "narrow"
    },
    {
      "src": "/screenshots/screenshot2.png",
      "sizes": "1280x720",
      "type": "image/png",
      "form_factor": "wide"
    }
  ],
  
  "categories": ["productivity", "business"],
  "screenshots": [...],
  "scope": "/",
  "lang": "es-PE"
}
```

**Beneficio**: 
- ✅ Instalable en escritorio/móvil
- ✅ Aparece como app nativa
- ✅ Personalizable (colores, nombre, ícono)

### 4.3 HTML Head (Meta tags PWA)

```html
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  
  <!-- PWA Meta Tags -->
  <meta name="description" content="Sistema de presupuestos automático">
  <meta name="theme-color" content="#0066cc">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="Presupuestos GTQC">
  
  <!-- Manifest -->
  <link rel="manifest" href="/manifest.json">
  
  <!-- Icons -->
  <link rel="icon" type="image/png" href="/icons/icon-192x192.png">
  <link rel="apple-touch-icon" href="/icons/icon-192x192.png">
  
  <!-- Service Worker -->
  <script>
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('/service-worker.js');
      });
    }
  </script>
  
  <title>Presupuestos GTQC</title>
</head>
<body>
  <div id="root"></div>
</body>
</html>
```

---

## 5. FLUJO DE USUARIO CON PWA

### Instalación en Móvil (Android)

```
Usuario abre presupuestos.grouptqc.com
        ↓
Chrome muestra:
"Instalar Presupuestos GTQC"
        ↓
Usuario toca "Instalar"
        ↓
App se instala en pantalla inicio
        ↓
Usuario abre desde ícono
        ↓
App se abre a pantalla completa (sin barra de navegación)
        ↓
Funciona como app nativa ✅
```

### Instalación en Escritorio (Windows/Mac)

```
Usuario abre presupuestos.grouptqc.com en Chrome
        ↓
Chrome muestra:
"Instalar Presupuestos GTQC"
        ↓
Usuario toca ícono "Instalar"
        ↓
Se crea acceso directo en Escritorio
        ↓
App se abre en ventana separada (sin barra de navegación)
        ↓
Funciona como app nativa ✅
```

---

## 6. ESTRATEGIA DE CACHING (Offline)

### Cache-First Strategy (Para elementos estáticos)

```javascript
// Para archivos CSS, JS, imágenes (cambian poco)
// Sirve del cache, actualiza en background
fetch event handler:
1. ¿Está en cache? → Devolver del cache
2. Ir a servidor, cachear resultado
3. Si no hay internet → Usar cache viejo
```

### Network-First Strategy (Para datos dinámicos)

```javascript
// Para presupuestos, clientes (datos críticos)
fetch event handler:
1. Intentar ir a servidor (HTTPS)
2. Si no hay respuesta → Usar cache
3. Guardar en local storage para offline
4. Sincronizar cuando hay internet
```

### Actualización Automática

```javascript
// El navegador detecta cambios en service-worker.js
// Automáticamente descarga la nueva versión
// Sin que el usuario tenga que hacer nada
// (Como las actualizaciones de Chrome, pero instantáneo)
```

---

## 7. FUNCIONALIDAD OFFLINE

### Escenario 1: Usuario está en Oficina (con internet)

```
Abre PWA → Carga desde servidor → Cachea automáticamente
                ↓
         Genera presupuesto
         (datos del servidor)
                ↓
         Descarga PDF
         (generado en backend)
```

### Escenario 2: Usuario está en Terreno (sin internet)

```
Abre PWA → Carga desde cache
              ↓
      ¿Cliente existe en cache local? → SÍ
              ↓
      Genera presupuesto (datos guardados)
              ↓
      PDF se genera LOCALMENTE (en el navegador)
              ↓
      Usuario puede ver/descargar PDF offline
              ↓
      Cuando hay internet:
      - Sincroniza datos nuevo
      - Sube presupuestos creados offline
```

### IndexedDB para Sincronización

```javascript
// Guardar datos localmente (mucho más capacidad que localStorage)
const db = indexedDB.open('presupuestos-gtqc');

// Guardar presupuesto offline
db.store('presupuestos').add({
  id: 123,
  codigo: 'GTQC/26/999',
  cliente: {...},
  items: [...],
  estado: 'sincronizado_offline',
  timestamp: Date.now()
});

// Cuando vuelve internet, background sync
self.addEventListener('sync', event => {
  if (event.tag === 'sync-presupuestos') {
    event.waitUntil(syncPresupuestos());
  }
});
```

---

## 8. INICIO RÁPIDO DE LA APP

### Métricas de Performance

```
Carga web tradicional:    ~4-5 segundos
Carga PWA (primera vez):  ~2-3 segundos
Carga PWA (subsecuentes): < 500ms ⚡ (desde cache)

El service worker cachea:
├─ HTML (estructura)
├─ CSS (estilos)
├─ JavaScript (lógica)
├─ Imágenes (logo, iconos)
└─ Datos básicos (clientes, servicios)

Resultado: App ultrarrápida
```

### Lighthouse Score (Google)

```
PWA bien implementada:
├─ Performance:   95+ / 100
├─ Accessibility: 95+ / 100
├─ Best Practices: 95+ / 100
├─ SEO:           95+ / 100
└─ PWA:           ✅ Installable
```

---

## 9. FUNCIONALIDADES PWA PARA GTQC

### 9.1 Notificaciones Push

```javascript
// Notificar cuando presupuesto es aceptado por cliente
self.registration.showNotification('Presupuesto Aceptado', {
  body: 'ALDEM S.A.C. aceptó presupuesto GTQC/26/326',
  icon: '/icons/icon-192x192.png',
  badge: '/icons/badge-72x72.png',
  tag: 'presupuesto-aceptado',
  requireInteraction: true // Usuario debe interactuar
});
```

**Casos de uso:**
- ✅ Presupuesto fue aceptado/rechazado
- ✅ Recordatorio de presupuestos por vencer
- ✅ Nuevo cliente disponible
- ✅ Error en sincronización de datos

### 9.2 Acceso a Cámara (Foto de Cliente)

```javascript
// Capturar foto del cliente durante reunión
const canvas = await navigator.mediaDevices
  .getUserMedia({ video: { facingMode: "environment" } });

// Tomar foto y guardarla en el presupuesto
const photo = await capturePhoto(canvas);
presupuesto.foto_cliente = photo;
```

**Beneficio**: Fotos de campo/referencia en presupuesto

### 9.3 Geolocalización

```javascript
// Guardar ubicación automática del presupuesto
navigator.geolocation.getCurrentPosition(position => {
  presupuesto.ubicacion = {
    lat: position.coords.latitude,
    lng: position.coords.longitude,
    timestamp: new Date()
  };
});
```

**Beneficio**: Mapas de clientes/proyectos

### 9.4 Compartir Presupuesto (Web Share API)

```javascript
// Botón "Compartir" en móvil (abre opciones nativas)
navigator.share({
  title: 'Presupuesto GTQC/26/326',
  text: 'Presupuesto para ALDEM S.A.C.',
  url: 'https://presupuestos.grouptqc.com/26/326'
});
```

---

## 10. ESTRUCTURA DE CARPETAS (PWA)

```
presupuestos-gtqc/
├── public/
│   ├── index.html
│   ├── manifest.json
│   ├── service-worker.js
│   ├── offline.html
│   ├── logo.png
│   └── icons/
│       ├── icon-192x192.png
│       ├── icon-512x512.png
│       └── icon-maskable-192.png
│
├── src/
│   ├── components/
│   │   ├── Dashboard.jsx
│   │   ├── PresupuestoForm.jsx
│   │   ├── ClienteSelector.jsx
│   │   ├── PDFViewer.jsx
│   │   └── ...
│   ├── services/
│   │   ├── api.js (llamadas a servidor)
│   │   ├── offline.js (manejo offline)
│   │   ├── pdfGenerator.js (PDF local)
│   │   └── sync.js (sincronización)
│   ├── db/
│   │   └── indexedDB.js (base de datos local)
│   ├── App.jsx
│   └── index.jsx
│
├── backend/
│   ├── routes/
│   │   ├── auth.js
│   │   ├── clientes.js
│   │   ├── servicios.js
│   │   └── presupuestos.js
│   ├── controllers/
│   ├── models/
│   ├── services/
│   │   ├── pdf-generator.js
│   │   └── email-service.js
│   └── server.js
│
├── package.json
├── .env
└── README.md
```

---

## 11. DEPLOYMENT PWA

### 11.1 Hosting Recomendado

```
OPCIÓN 1: Vercel (Recomendado para PWA)
├─ Hosting: Gratis + $20/mes (pro)
├─ CDN global: SÍ
├─ HTTPS: Automático
├─ Certificados: Gratis
├─ Edge Functions: Sí
└─ Perfecto para PWA ✅

OPCIÓN 2: Firebase Hosting
├─ Hosting: Gratis + pago por uso
├─ CDN: Global
├─ HTTPS: Automático
├─ Backend: Firebase Cloud Functions
└─ Muy bueno para PWA ✅

OPCIÓN 3: Heroku + Netlify (Frontend)
├─ Frontend en Netlify (gratis)
├─ Backend en Heroku ($7/mes)
├─ Base de datos: AWS RDS ($15/mes)
└─ Total: ~$25/mes
```

### 11.2 Checklist Deployment

```
├─ [ ] manifest.json válido
├─ [ ] service-worker.js funcional
├─ [ ] HTTPS configurado (obligatorio)
├─ [ ] Icons en todas las resoluciones
├─ [ ] Meta tags correctas
├─ [ ] API endpoints HTTPS
├─ [ ] CORS configurado
├─ [ ] Lighthouse score > 90
├─ [ ] Testing en móvil (Android + iOS)
└─ [ ] Documentación lista
```

---

## 12. COMPARATIVA: PWA vs Otros

### Presupuestos GTQC - Implementación

| Aspecto | Web Tradicional | App Nativa (iOS+Android) | PWA ⭐ |
|---------|-----------------|-------------------------|-------|
| **Costo desarrollo** | USD 3,500 | USD 15,000 | USD 4,500 |
| **Tiempo** | 4-6 sem | 12-16 sem | 5-7 sem |
| **Codebase único** | Sí | NO (2 códigos) | Sí ⭐ |
| **Instalable** | NO | Sí | Sí ⭐ |
| **Funciona offline** | NO | Sí | Sí ⭐ |
| **Push notif** | NO | Sí | Sí ⭐ |
| **Distribución** | Link | App Store | Link ⭐ |
| **Actualización** | Automática | Manual | Automática ⭐ |
| **Acceso hardware** | Limitado | Full | Parcial ⭐ |
| **Mantenimiento** | 1 código | 2 códigos | 1 código ⭐ |
| **Costo/año mantenimiento** | $1,200 | $2,400 | $1,200 ⭐ |
| **Año 1 total** | $4,700 | $17,400 | $5,700 ⭐ |
| **ROI** | 3 meses | 6 meses | 2 meses ⭐ |

**PWA = MEJOR OPCIÓN** ✅

---

## 13. INSTALACIÓN Y USO FINAL

### Usuarios Finales - Cómo instalan

**En Android:**
```
1. Abren presupuestos.grouptqc.com en Chrome
2. Ven botón "Instalar" (o menú ⋮ → Instalar)
3. Tocan "Instalar"
4. App aparece en pantalla inicio
5. La abren desde el ícono
6. ¡Funciona como app nativa!
```

**En iPhone/iPad:**
```
1. Abren presupuestos.grouptqc.com en Safari
2. Tocan compartir (↗)
3. Seleccionan "Agregar a pantalla inicio"
4. App aparece en pantalla inicio
5. ¡Se abre a pantalla completa!
```

**En Windows/Mac:**
```
1. Abren presupuestos.grouptqc.com en Chrome
2. Ven botón "Instalar" (arriba a la derecha)
3. Tocan "Instalar"
4. Se crea acceso en escritorio
5. ¡Se abre en ventana sin navegador!
```

---

## 14. SEGURIDAD PWA

### 14.1 Requisitos Obligatorios

```
✅ HTTPS (obligatorio)
   └─ Service Worker solo funciona en HTTPS
   └─ Certificados SSL/TLS gratis con Let's Encrypt

✅ Valid manifest.json
   └─ Validado con PWA Builder de Microsoft

✅ Autenticación JWT
   └─ Tokens en localStorage/sessionStorage
   └─ Refresh tokens con rotación

✅ CORS bien configurado
   └─ Solo dominio permitido
   └─ Headers de seguridad

✅ Rate limiting
   └─ 5 intentos login fallidos = bloqueo 15 min
```

### 14.2 Encriptación

```
En tránsito:
├─ HTTPS / TLS 1.2+
├─ API endpoints HTTPS
└─ No transmitir datos sensibles en URLs

En reposo (IndexedDB):
├─ Datos sensibles encriptados
├─ Service workers no tienen acceso directo
└─ localStorage solo para tokens (corta duración)
```

---

## 15. ROADMAP: PWA PRESUPUESTOS GTQC

### Fase 1 (Semana 1-2): Setup & Backend
```
├─ [ ] Configurar proyecto React + Vite
├─ [ ] Setup backend Node.js/Express
├─ [ ] Database PostgreSQL
├─ [ ] APIs REST endpoints
└─ [ ] Autenticación JWT
```

### Fase 2 (Semana 3-4): Frontend & PWA
```
├─ [ ] Componentes React
├─ [ ] Service Worker
├─ [ ] Manifest.json
├─ [ ] Caching strategy
└─ [ ] Offline functionality
```

### Fase 3 (Semana 5): PDF & Features
```
├─ [ ] Generación PDF (jsPDF)
├─ [ ] Notificaciones push
├─ [ ] Cámara + geolocalización
└─ [ ] Web Share API
```

### Fase 4 (Semana 6): Testing & Deployment
```
├─ [ ] Testing (unit + E2E)
├─ [ ] Lighthouse scoring
├─ [ ] Pruebas en móviles reales
├─ [ ] Deploy a Vercel/Firebase
└─ [ ] Documentación final
```

---

## 16. COSTOS FINALES PWA

### Desarrollo
```
Frontend (React + PWA):        USD 2,000
Backend (Node.js + APIs):      USD 1,500
PDF Generator:                 USD 400
Diseño/UI:                     USD 600
Testing:                       USD 400
────────────────────────────────────────
TOTAL DESARROLLO:              USD 4,900
```

### Infraestructura (Año 1)
```
Hosting (Vercel):              USD 20/mes  = USD 240/año
Base de datos (AWS RDS):       USD 15/mes  = USD 180/año
Email service (Mailgun):       USD 0-10/mes = USD 0-120/año
CDN:                           Incluido en Vercel
Certificados SSL:              Gratis (Let's Encrypt)
Backups:                       Incluido en RDS
────────────────────────────────────────
TOTAL INFRAESTRUCTURA/AÑO:     USD 420/año
```

### Mantenimiento (Año 1+)
```
Soporte técnico:               USD 30/mes  = USD 360/año
Bug fixes & updates:           USD 20/mes  = USD 240/año
Mejoras menores:               USD 15/mes  = USD 180/año
────────────────────────────────────────
TOTAL MANTENIMIENTO/AÑO:       USD 780/año
```

### PRESUPUESTO TOTAL PWA
```
Año 1:  USD 4,900 (desarrollo) + USD 420 (infra) + USD 780 (mant) = USD 6,100
Año 2+: USD 420 (infra) + USD 780 (mant) = USD 1,200/año

ROI: 3 meses ✅
```

---

## 17. PRESENTACIÓN AL CLIENTE

### Propuesta PWA

```
PRESUPUESTOS GTQC - PROPUESTA FINAL
═══════════════════════════════════════════════

TECNOLOGÍA: Progressive Web App (PWA)

BENEFICIOS:
✅ Funciona en web + móvil + tablet (UN SOLO CÓDIGO)
✅ Instalable (parece app nativa)
✅ Funciona SIN internet (offline-first)
✅ Carga en < 2 segundos (ultra rápido)
✅ Notificaciones push
✅ Actualización automática
✅ NO necesita App Store
✅ Compatible Android + iPhone + Windows + Mac

COSTO: USD 4,900 desarrollo + USD 420/año mantenimiento
TIEMPO: 6 semanas
ROI: 3 meses

ENTREGA:
├─ PWA funcionando 100%
├─ Documentación completa
├─ Capacitación a 5 usuarios
└─ 3 meses soporte técnico

¿Quieren más información?
```

---

## 18. CONCLUSIÓN

### ¿Por qué PWA para Presupuestos GTQC?

**Es la MEJOR solución porque:**

1. ✅ **Costo óptimo**: USD 4,900 (no USD 10-15K como app nativa)
2. ✅ **Tiempo razonable**: 6 semanas (no 12+ semanas)
3. ✅ **Un solo código**: Mantener una sola codebase
4. ✅ **Instalable**: Se ve como app nativa
5. ✅ **Offline**: Funciona sin internet
6. ✅ **Rápido**: Carga en < 2 segundos
7. ✅ **Moderno**: Tecnología 2026, no legacy
8. ✅ **Escalable**: Soporta miles de usuarios
9. ✅ **Seguro**: HTTPS + JWT + encriptación
10. ✅ **ROI rápido**: 3 meses

### Comparativa Final

```
App Nativa:    Caro, lento, complicado, dos códigos
Web Tradicional: Barato, pero sin funciones modernas
PWA:           ⭐ LO MEJOR DE AMBOS MUNDOS ⭐
```

---

**RECOMENDACIÓN FINAL:**

🚀 **IMPLEMENTAR COMO PWA**

Es la solución más moderna, económica, rápida y flexible para Presupuestos GTQC.

---

