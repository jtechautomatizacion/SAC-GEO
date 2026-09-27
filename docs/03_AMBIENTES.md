# Ambientes — SAC-GEO

> Registro de herramientas y ambientes de ejecución. Versiones verificadas directamente en la máquina de desarrollo el 2026-09-27; no se documentan versiones sin comprobar.

---

## 1. Ambiente de desarrollo (DEV) — local

Windows con Docker Desktop, sin conexión a producción ni al VPS. Datos ficticios únicamente.

### Sistema operativo
- Windows 11 Home Single Language, build 10.0.26200

### Herramientas verificadas

| Herramienta | Versión detectada | Notas |
|---|---|---|
| Git | 2.55.0.windows.3 | — |
| Docker Desktop (CLI) | 29.7.2 | Daemon se inicia bajo demanda, no en autostart al momento de esta auditoría |
| Docker Compose | v5.5.1 (plugin `docker compose`) | — |
| WSL2 | 2.7.14.0 (kernel 6.18.33.2) | Distribuciones: `Ubuntu` (default) y `docker-desktop`, ambas versión 2 |
| Node.js | v24.18.0 | No usado todavía por el proyecto; disponible en la máquina |
| npm | 11.16.0 | ídem |
| Python | **dos instalaciones** — 3.12.10 (`AppData\Local\Programs\Python\Python312\python.exe`) y 3.13.7 (vía `py` launcher / Microsoft Store alias) | **Sin fijar.** La versión definitiva para el backend FastAPI se decide en la fase 5 (Backend/API), no antes |
| psql (cliente nativo) | no instalado | No es necesario para esta fase: la conexión a PostgreSQL se hace vía contenedor / herramientas GUI (DBeaver, extensión VS Code, etc.) |
| Flutter SDK | no instalado | Corresponde a la fase de frontend (fase 8). No instalar antes |
| Dart | no instalado | Se instala junto con Flutter SDK |
| Java/JDK | no instalado | Solo se evaluará si Flutter lo requiere para alguna plataforma (Android) |
| VS Code | 1.137.0 | Extensiones Python ya presentes (`ms-python.python`, `pylance`, `debugpy`). Faltan extensiones de Docker/Flutter/PostgreSQL — se instalarán cuando corresponda a cada fase |

### Infraestructura Docker de este proyecto

Definida en [`docker-compose.yml`](../docker-compose.yml):

| Servicio | Imagen | Puerto host | Volumen |
|---|---|---|---|
| `postgres` | `postgres:16` | `5432` (configurable vía `POSTGRES_PORT`) | `sac-geo-postgres-data` (persistente) |

Red propia: `sac-geo-net` (no comparte red con otros proyectos Docker de la máquina).

**Contenedores de otros proyectos detectados en la máquina (no tocar):** `restomind-sunat` (proyecto `restomind-saas`, puerto `127.0.0.1:8100`). SAC-GEO no interactúa con él ni comparte red ni volúmenes.

FastAPI **no** está incluido todavía en `docker-compose.yml`: se agregará cuando exista código de backend que levantar (fase 5).

---

## 2. Ambiente de pruebas (TEST)

**Pendiente de preparar.** Cuando se configure, seguirá este procedimiento:

- Reconstrucción completa desde `database/full_dump.sql` (schema + funciones + triggers + índices/vistas + seeds)
- Ejecución de `database/98_pruebas.sql` (71 pruebas funcionales, deben quedar todas en verde)
- Ejecución de `database/99_verificacion.sql` (37 controles de integridad; 35 deben dar cero, los 2 restantes son informativos, ver `docs/AUDITORIA_BD_v3.md §9`)
- Datos exclusivamente ficticios, generados por los seeds del proyecto

---

## 3. Ambiente de staging (STAGING)

**Pendiente.** No definido todavía — depende de decisiones de la fase 3 (evaluación de motor e infraestructura) que sigue abierta.

---

## 4. Ambiente de producción (PRODUCCIÓN)

**Pendiente.** Corre en un VPS. Este repositorio y este ambiente de desarrollo **no tienen ninguna conexión** con él: ni credenciales, ni túneles, ni scripts de despliegue configurados todavía.

---

## 5. Reglas de esta documentación

- Ninguna versión aquí se documenta sin haber sido verificada por comando real en la máquina.
- Las credenciales de cualquier ambiente (dev, test, staging, producción) nunca se escriben en este archivo ni en ningún archivo versionado. Ver `.env.example` para el formato de referencia sin secretos.
- Cambios de versión de herramientas que puedan afectar el proyecto (o el resto de la máquina) requieren aprobación explícita antes de aplicarse.
