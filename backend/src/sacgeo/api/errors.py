"""Traducción de errores de PostgreSQL a HTTP.

Dos reglas que gobiernan este archivo:

1. Ningún mensaje de PostgreSQL llega al cliente. El detalle va al log con un
   identificador de correlación que el cliente sí recibe, para soporte.

2. Un recurso de otro tenant responde 404, nunca 403. Un 403 confirmaría que
   el recurso existe, y eso convierte el endpoint en un oráculo para enumerar
   la cartera de clientes de la competencia.

   Con RLS activa, además, el 404 no es una ficción defensiva: es la respuesta
   literalmente verdadera. La fila no existe para esa sesión.
"""

from __future__ import annotations

import logging
import uuid

from fastapi import Request
from fastapi.responses import JSONResponse
from psycopg import errors as pg

log = logging.getLogger(__name__)

# SQLSTATE → (HTTP, mensaje público)
_MAPA: dict[str, tuple[int, str]] = {
    "23503": (409, "referencia inválida"),          # foreign_key_violation
    "23505": (409, "ya existe un registro equivalente"),  # unique_violation
    "23514": (422, "la operación no cumple una regla del sistema"),  # check_violation
    "23001": (422, "la operación no está permitida en este estado"),  # restrict_violation
    "22P02": (422, "formato de dato inválido"),     # invalid_text_representation
    "P0002": (404, "no encontrado"),                # no_data_found
}


def _correlacion() -> str:
    return uuid.uuid4().hex[:12]


async def manejar_error_postgres(request: Request, exc: Exception) -> JSONResponse:
    ref = _correlacion()
    sqlstate = getattr(exc, "sqlstate", None)

    # 42501 aquí NO es culpa del cliente: significa que la transacción se abrió
    # sin contexto de tenant, o que RLS rechazó una escritura que el backend no
    # debió intentar. Es un bug nuestro y merece alerta, no un 403.
    if sqlstate == "42501":
        log.error("ref=%s FALTA CONTEXTO DE TENANT o RLS rechazó: %s", ref, exc)
        return JSONResponse(
            status_code=500,
            content={"error": "error interno", "ref": ref},
        )

    http, mensaje = _MAPA.get(sqlstate, (500, "error interno"))
    log.error("ref=%s sqlstate=%s %s", ref, sqlstate, exc)
    return JSONResponse(status_code=http, content={"error": mensaje, "ref": ref})


def registrar(app) -> None:
    app.add_exception_handler(pg.Error, manejar_error_postgres)
