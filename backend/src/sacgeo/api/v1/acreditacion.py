"""Acreditación ISO 17025 de un ensayo: estado vigente + historial.

No es un adorno del catálogo. La acreditación es lo que permite al laboratorio
cobrar más y lo primero que le revisa un auditor, y por eso el historial es
append-only y solo `fn_cambiar_acreditacion()` puede tocarlo: un UPDATE directo
está bloqueado por trigger, para que el estado actual y el historial no puedan
divergir.

------------------------------------------------------------------------------
POR QUÉ ESTE ROUTER ESTÁ SEPARADO DE catalogo.py
------------------------------------------------------------------------------
La ruta vive bajo `/catalogo/{public_id}/acreditacion`, pero el permiso que
exige es **`acreditacion.read`**, no `catalogo.read`. El router de `catalogo.py`
declara `catalogo.read` a nivel de router, así que colgar esta ruta de él le
habría dado el permiso equivocado sin que nadie lo notara — y habría bastado
con que alguien tuviera `catalogo.read` para leer el historial de acreditación.

Son dos routers con el mismo prefijo y permisos distintos. No hay ambigüedad de
rutas: `/catalogo/{id}` y `/catalogo/{id}/acreditacion` difieren en un segmento.

`catalogo.py` no se ha tocado.

------------------------------------------------------------------------------
POR QUÉ HAY UN JOIN CON ensayos_catalogo
------------------------------------------------------------------------------
`vw_acreditacion_vigente` expone `ensayo_id` —el id técnico— y NO `public_id`.
El id interno no sale nunca de la API, así que hace falta el par público. La
fase 7C decidió resolverlo con un JOIN en la consulta y no modificando la
vista: cambiarla sería una migración, y las tres ya planificadas (`0008`,
`0009`, `0010`) tienen prioridad.

El JOIN va por el PAR `(id, tenant_id)`, no por el id a secas. Es el patrón de
FK compuesta del esquema: hace imposible cruzar el historial de un ensayo con
la ficha de otro laboratorio, aunque RLS fallara.
"""

from __future__ import annotations

import logging
from datetime import date, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from psycopg import AsyncConnection
from psycopg.rows import dict_row
from pydantic import BaseModel, Field

from sacgeo.api.deps import get_db_tx, require_permission
from sacgeo.api.query import SinParametros

log = logging.getLogger(__name__)

router = APIRouter(
    prefix="/catalogo",
    tags=["acreditación"],
    dependencies=[Depends(require_permission("acreditacion.read"))],
    responses={
        401: {"description": "no autenticado"},
        403: {"description": "sin el permiso acreditacion.read"},
    },
)


# ---------------------------------------------------------------- salida ----

class CambioAcreditacion(BaseModel):
    """Un hecho del historial. Append-only: esto no se edita nunca.

    NO lleva `registrado_por`: es un `usuarios.id`, un identificador técnico, y
    publicarlo sería exactamente lo que la decisión de los tres identificadores
    prohíbe. Quién hizo el cambio está en `auditoria`, que tiene su propio
    endpoint pendiente y su propio permiso.
    """

    acreditado: bool
    motivo: str | None = None
    vigente_desde: date
    registrado_en: datetime


class AcreditacionResponse(BaseModel):
    public_id: UUID
    codigo: str
    nombre: str
    acreditado: bool = Field(description="Estado vigente hoy, hora de Lima.")
    vigente_desde: date | None = Field(
        default=None, description="Desde cuándo rige el estado vigente."
    )
    motivo: str | None = None
    coherente: bool = Field(
        description=(
            "El estado de la ficha coincide con el último hecho del historial. "
            "Falso significaría que alguien logró separarlos, que es justo lo "
            "que invalida el registro ante un auditor."
        )
    )
    historial: list[CambioAcreditacion]


# --------------------------------------------------------------- consultas --
#
# Sin ningún "WHERE tenant_id": lo impone RLS sobre ensayos_catalogo y
# ensayo_acreditacion_historial, a partir del contexto que fijó get_db_tx.
#
# `e.activo` sí se exige, y por coherencia con GET /catalogo/{public_id}: si un
# ensayo desactivado respondiera aquí y 404 allí, la diferencia revelaría que
# ese UUID existe y está de baja. Una filtración pequeña, pero gratuita.

_SQL_VIGENTE = """
    SELECT e.public_id, v.codigo, v.nombre,
           v.estado_actual, v.vigente_desde, v.motivo, v.coherente
      FROM vw_acreditacion_vigente v
      JOIN ensayos_catalogo e
        ON e.id = v.ensayo_id AND e.tenant_id = v.tenant_id
     WHERE e.public_id = %(public_id)s AND e.activo
"""

# Orden descendente: lo más reciente primero, que es como se lee un historial.
# `id` desempata dos cambios con la misma fecha de vigencia — sin él, dos
# hechos del mismo día podrían salir en cualquier orden.
_SQL_HISTORIAL = """
    SELECT h.acreditado, h.motivo, h.vigente_desde, h.registrado_en
      FROM ensayo_acreditacion_historial h
      JOIN ensayos_catalogo e
        ON e.id = h.ensayo_id AND e.tenant_id = h.tenant_id
     WHERE e.public_id = %(public_id)s AND e.activo
     ORDER BY h.vigente_desde DESC, h.id DESC
"""

_NO_ENCONTRADO = HTTPException(
    status_code=status.HTTP_404_NOT_FOUND,
    detail="no encontrado",
)


@router.get(
    "/{public_id}/acreditacion",
    response_model=AcreditacionResponse,
    summary="Acreditación de un ensayo",
    responses={404: {"description": "no existe o no pertenece a este laboratorio"}},
)
async def obtener_acreditacion(
    public_id: UUID,
    _: Annotated[SinParametros, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> AcreditacionResponse:
    """Estado de acreditación vigente de un ensayo y su historial completo.

    Un ensayo de OTRO laboratorio responde 404, nunca 403 — la fila no existe
    para esta sesión, así que el 404 es la respuesta literal y no una ficción
    defensiva.

    Las dos consultas van en la MISMA transacción: el estado vigente y el
    historial que lo respalda tienen que salir de la misma instantánea, o el
    `coherente` que se devuelve podría no corresponder a la lista que se
    devuelve con él.
    """
    parametros = {"public_id": str(public_id)}

    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_VIGENTE, parametros)
        fila = await cur.fetchone()
        if fila is None:
            raise _NO_ENCONTRADO
        await cur.execute(_SQL_HISTORIAL, parametros)
        historial = await cur.fetchall()

    return AcreditacionResponse(
        public_id=fila["public_id"],
        codigo=fila["codigo"],
        nombre=fila["nombre"],
        acreditado=fila["estado_actual"],
        vigente_desde=fila["vigente_desde"],
        motivo=fila["motivo"],
        coherente=fila["coherente"],
        historial=[
            CambioAcreditacion(
                acreditado=h["acreditado"],
                motivo=h["motivo"],
                vigente_desde=h["vigente_desde"],
                registrado_en=h["registrado_en"],
            )
            for h in historial
        ],
    )
