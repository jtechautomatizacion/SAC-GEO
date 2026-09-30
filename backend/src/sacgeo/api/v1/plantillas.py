"""Plantillas de cotización. SOLO LECTURA.

Una plantilla aporta el membrete, los términos y condiciones y la validez
sugerida de una cotización. Quien va a cotizar tiene que poder elegirla.

------------------------------------------------------------------------------
POR QUÉ EL PERMISO ES cotizaciones.read Y NO tenant.config.read
------------------------------------------------------------------------------
Es la decisión menos evidente de este módulo, así que queda escrita.

`tenant.config.read` lo tiene **solo `admin`**, y `admin` —por diseño de `0007`—
NO tiene `cotizaciones.create`. Proteger este listado con `tenant.config.read`
dejaría al `comercial`, que es quien cotiza, sin poder ver de qué plantillas
dispone: el asistente de cotización sería imposible de construir.

El criterio: **leer** el catálogo de plantillas es parte de cotizar;
**cambiarlas** es configurar el laboratorio. Así que la lectura va con
`cotizaciones.read` (los cinco roles) y la futura escritura irá con
`tenant.config.update` (solo `admin`).

⚠ Es una elección de permiso, no un hecho del esquema. Queda marcada para
revisión.

------------------------------------------------------------------------------
RLS HÍBRIDA: LA PLANTILLA PUEDE SER GLOBAL
------------------------------------------------------------------------------
`plantillas_cotizacion` es la única tabla de negocio con política HÍBRIDA:

    p_hibrida  USING (tenant_id IS NULL OR tenant_id = fn_app_tenant())

`tenant_id IS NULL` significa «plantilla base del producto, la ven todos los
laboratorios». Hoy las tres del seed —Estándar, Premium, Express— son
justamente eso. Un laboratorio puede además tener las suyas.

Eso NO se expone como `tenant_id` —que es un id técnico— sino como un booleano
`es_base`, que es la información que un cliente necesita: una plantilla base no
se puede editar desde su laboratorio.

------------------------------------------------------------------------------
N-2 — UNA GARANTÍA QUE AQUÍ NO SE USA, PERO FALTA
------------------------------------------------------------------------------
Esta tabla es la ÚNICA tenant-scoped sin `UNIQUE (tenant_id, id)`, y por eso la
FK de `cotizaciones` no puede ser compuesta:

    cotizaciones_plantilla_id_fkey  FOREIGN KEY (plantilla_id)
        REFERENCES plantillas_cotizacion(id)      ← una sola columna

Mientras `empresa_id`, `persona_id` y `contacto_id` sí lo son. La pertenencia
de la plantilla la sostiene hoy el trigger `a_validar_plantilla` (corregido en
`0005`) y RLS, no una clave.

Para LEER no cambia nada, y este módulo no lo arregla. Está documentado en el
reporte de la fase 7G con su migración propuesta.

------------------------------------------------------------------------------
SIN PAGINACIÓN
------------------------------------------------------------------------------
Un laboratorio tiene tres o cuatro plantillas: el esquema, de hecho, limita
cuántas puede tener activas (`fn_max_plantillas_activas`). Paginar un conjunto
con cupo añade dos parámetros y dos modos de fallo a cambio de nada.
`terminos_condiciones` sí se omite del listado —es texto largo— y solo aparece
en el detalle.
"""

from __future__ import annotations

import logging
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from psycopg import AsyncConnection
from psycopg.rows import dict_row
from pydantic import BaseModel, ConfigDict, Field

from sacgeo.api.deps import get_db_tx, require_permission
from sacgeo.api.query import SinParametros

log = logging.getLogger(__name__)

router = APIRouter(
    prefix="/plantillas",
    tags=["plantillas"],
    dependencies=[Depends(require_permission("cotizaciones.read"))],
    responses={
        401: {"description": "no autenticado"},
        403: {"description": "sin el permiso cotizaciones.read"},
    },
)

_NO_ENCONTRADA = HTTPException(
    status_code=status.HTTP_404_NOT_FOUND,
    detail="no encontrado",
)


class FiltroPlantillas(BaseModel):
    model_config = ConfigDict(extra="forbid")

    solo_activas: bool = Field(default=True)


class Plantilla(BaseModel):
    """`es_base` en lugar de `tenant_id`: el dato sin el identificador."""

    public_id: UUID
    slug: str
    nombre: str
    icono: str | None = None
    validez_dias_sugerida: int | None = None
    activo: bool
    es_base: bool = Field(
        description="Plantilla del producto, común a todos los laboratorios."
    )


class PlantillaDetalle(Plantilla):
    terminos_condiciones: str | None = None


class PlantillasResponse(BaseModel):
    items: list[Plantilla]
    total: int


# Sin "WHERE tenant_id": lo resuelve p_hibrida, que además es la que permite ver
# las plantillas base. Un filtro en Python las habría escondido.
#
# Las propias del laboratorio primero: son las que un usuario reconoce.
_SQL_PLANTILLAS = """
    SELECT p.public_id, p.slug, p.nombre, p.icono, p.validez_dias_sugerida,
           p.activo, (p.tenant_id IS NULL) AS es_base
      FROM plantillas_cotizacion p
     WHERE (NOT %(solo_activas)s OR p.activo)
     ORDER BY (p.tenant_id IS NULL), p.nombre, p.id
"""

_SQL_PLANTILLA = """
    SELECT p.public_id, p.slug, p.nombre, p.icono, p.validez_dias_sugerida,
           p.activo, (p.tenant_id IS NULL) AS es_base, p.terminos_condiciones
      FROM plantillas_cotizacion p
     WHERE p.public_id = %(public_id)s
"""


@router.get("", response_model=PlantillasResponse, summary="Listar plantillas")
async def listar_plantillas(
    filtro: Annotated[FiltroPlantillas, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> PlantillasResponse:
    """Plantillas disponibles: las del laboratorio y las base del producto."""
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_PLANTILLAS, {"solo_activas": filtro.solo_activas})
        filas = await cur.fetchall()

    items = [
        Plantilla(
            public_id=f["public_id"], slug=f["slug"], nombre=f["nombre"],
            icono=f["icono"], validez_dias_sugerida=f["validez_dias_sugerida"],
            activo=f["activo"], es_base=f["es_base"],
        )
        for f in filas
    ]
    return PlantillasResponse(items=items, total=len(items))


@router.get("/{public_id}", response_model=PlantillaDetalle,
            summary="Obtener una plantilla",
            responses={404: {"description": "no existe o es de otro laboratorio"}})
async def obtener_plantilla(
    public_id: UUID,
    _: Annotated[SinParametros, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> PlantillaDetalle:
    """Incluye los términos y condiciones, que el listado omite por tamaño.

    Una plantilla de otro laboratorio responde 404. Una plantilla BASE responde
    200 desde cualquier laboratorio, y eso es correcto: `p_hibrida` la hace
    visible a todos a propósito.
    """
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_PLANTILLA, {"public_id": str(public_id)})
        fila = await cur.fetchone()
    if fila is None:
        raise _NO_ENCONTRADA

    return PlantillaDetalle(
        public_id=fila["public_id"], slug=fila["slug"], nombre=fila["nombre"],
        icono=fila["icono"], validez_dias_sugerida=fila["validez_dias_sugerida"],
        activo=fila["activo"], es_base=fila["es_base"],
        terminos_condiciones=fila["terminos_condiciones"],
    )
