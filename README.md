# SAC-GEO

Sistema de cotizaciones multi-tenant para laboratorios de ensayos de materiales. El primer cliente/tenant es **GTQC — Group Total Quality Control S.A.C.**

Ver [CLAUDE.md](CLAUDE.md) para el contexto completo del proyecto, decisiones tomadas y reglas de negocio.

## Estado actual

**Fase 1 — Preparación del ambiente de desarrollo.**

Ver la tabla de fases en [CLAUDE.md §2](CLAUDE.md#2-dónde-estamos-actualizar-al-cerrar-cada-fase).

## Arquitectura actual

```
Windows
  │
  └── Docker Desktop
        │
        └── PostgreSQL DEV
```

FastAPI y Flutter todavía **no** forman parte del ambiente ejecutable de esta fase. Se incorporarán cuando se abran sus respectivas fases (ver CLAUDE.md).

## Requisitos

Herramientas verificadas en el entorno de desarrollo:

| Herramienta | Versión |
|---|---|
| Git | 2.55.0 |
| Docker Desktop | 29.7.2 |
| Docker Compose | v5.5.1 |
| WSL2 | 2.7.14.0 (Ubuntu) |
| Node.js | v24.18.0 |
| Python | 3.12.10 / 3.13.7 (sin fijar aún, ver [docs/03_AMBIENTES.md](docs/03_AMBIENTES.md)) |

Detalle completo en [docs/03_AMBIENTES.md](docs/03_AMBIENTES.md).

## Levantar ambiente

```bash
cp .env.example .env
# editar .env si se desea otra contraseña de desarrollo
docker compose up -d postgres
docker compose ps
```

## Detener ambiente

```bash
docker compose down
```

Esto **no borra** el volumen de datos (`sac-geo-postgres-data`). Los datos persisten entre reinicios.

Para eliminar también los datos (⚠ destructivo, solo si se quiere empezar de cero):

```bash
docker compose down -v
```

## Estado de la BD

- ✅ PostgreSQL de desarrollo preparado y accesible en `localhost:5432`
- ❌ Esquema SAC-GEO/GTQC **todavía no restaurado** en este contenedor
- La restauración (`database/full_dump.sql` + `98_pruebas.sql` + `99_verificacion.sql`) es un paso posterior, pendiente de autorización

## Advertencias de seguridad

- `.env` nunca se versiona (ver `.gitignore`). Solo `.env.example` con valores de ejemplo.
- Las credenciales del contenedor son **exclusivamente de desarrollo local**, no reutilizar en staging/producción.
- Este ambiente no tiene ninguna conexión con el VPS ni con producción.
