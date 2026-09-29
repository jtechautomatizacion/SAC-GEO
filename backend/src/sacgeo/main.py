"""Aplicación FastAPI de SAC-GEO.

Esqueleto de la fase 5B: pool, transacción central y dependencias.
SIN endpoints de negocio — esos llegan con la autenticación (fase 6).
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from sacgeo.api import errors
from sacgeo.api.v1 import auth, catalogo
from sacgeo.config import settings
from sacgeo.db.pool import (
    RolInseguro,
    abrir_pool,
    cerrar_pool,
    obtener_pool,
    verificar_rol_seguro,
)

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)


@asynccontextmanager
async def ciclo_de_vida(app: FastAPI):
    await abrir_pool()
    try:
        informe = await verificar_rol_seguro()
    except RolInseguro:
        # El pool ya está abierto: si se deja así, el arranque falla pero las
        # conexiones quedan vivas. Se cierra antes de propagar para que un
        # arranque abortado no deje nada detrás.
        await cerrar_pool()
        raise
    log.info("rol de conexión: %s", informe)
    yield
    await cerrar_pool()


app = FastAPI(
    title="SAC-GEO API",
    version="0.1.0",
    lifespan=ciclo_de_vida,
)
errors.registrar(app)

# `/auth` se queda donde está, SIN el prefijo /api/v1, y es una decisión, no un
# descuido. Moverlo rompería `POST /auth/login` y `GET /auth/yo`, que ya están
# ejercitados por los tests de extremo a extremo y son el contrato con el que
# se probó toda la cadena de autenticación. Esta fase entrega el catálogo; la
# unificación de rutas es un cambio de contrato público y merece su propia
# decisión, no ir de polizón. Queda anotado como deuda.
app.include_router(auth.router)

# El primer recurso de negocio. Bajo /api/v1 desde el primer día: añadir la
# versión cuando ya hay clientes cuesta mucho más que ponerla ahora.
app.include_router(catalogo.router, prefix="/api/v1")


@app.get("/salud")
async def salud() -> dict[str, object]:
    """Comprueba que la API responde y que PostgreSQL contesta."""
    pool = obtener_pool()
    async with pool.connection() as conn, conn.cursor() as cur:
        await cur.execute("SELECT 1")
        await cur.fetchone()
    return {"estado": "ok", "entorno": settings.entorno}


if settings.es_desarrollo:
    # DIAGNÓSTICO DE DESARROLLO. No se monta fuera de desarrollo: expone el
    # usuario de PostgreSQL y sus atributos de privilegio, que es justo el mapa
    # que un atacante querría para saber si RLS le afecta.
    @app.get("/salud/rol", include_in_schema=False)
    async def salud_rol() -> dict[str, object]:
        return await verificar_rol_seguro()
