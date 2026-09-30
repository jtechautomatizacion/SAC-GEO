"""Aplicación FastAPI de SAC-GEO.

Esqueleto de la fase 5B: pool, transacción central y dependencias.
SIN endpoints de negocio — esos llegan con la autenticación (fase 6).
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from typing import Annotated

from fastapi import FastAPI, Query

from sacgeo.api import errors
from sacgeo.api.query import SinParametros
from sacgeo.api.v1 import (
    acreditacion,
    auth,
    catalogo,
    categorias,
    clientes,
    clientes_escritura,
    plantillas,
    usuarios,
)
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
app.include_router(categorias.router, prefix="/api/v1")

# Comparte el prefijo /catalogo con el router anterior, y no es un descuido:
# exige `acreditacion.read`, no `catalogo.read`. Colgar la ruta del router de
# catálogo le habría dado el permiso equivocado en silencio — y entonces
# cualquiera con catalogo.read leería el historial ISO 17025.
app.include_router(acreditacion.router, prefix="/api/v1")

# Clientes: empresas, sus contactos y personas naturales. Solo lectura.
app.include_router(clientes.router, prefix="/api/v1")

# Usuarios y plantillas, SOLO LECTURA (fase 7G). G-2 bloquea la escritura de
# roles, no la consulta; N-2 afecta a la FK de cotizaciones, no a leer plantillas.
app.include_router(usuarios.router, prefix="/api/v1")
app.include_router(plantillas.router, prefix="/api/v1")

# PRIMER WRITE de negocio (fase 7I). Router APARTE del de lectura porque
# exige `clientes.manage`, no `clientes.read`: si compartieran router, quien
# pudiera consultar la cartera de clientes podría crear empresas en ella.
app.include_router(clientes_escritura.router, prefix="/api/v1")


@app.get("/salud")
async def salud(_: Annotated[SinParametros, Query()]) -> dict[str, object]:
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
    async def salud_rol(_: Annotated[SinParametros, Query()]) -> dict[str, object]:
        return await verificar_rol_seguro()
