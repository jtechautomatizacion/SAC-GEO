"""Categorías y subcategorías del catálogo. El primer nivel de navegación.

`/catalogo` devuelve ensayos y dice a qué categoría pertenece cada uno, pero no
hay forma de listar las categorías en sí — y la app navega como la lista de
precios en Excel del laboratorio: categoría → subcategoría → ensayo. Este
módulo sirve ese primer nivel.

------------------------------------------------------------------------------
POR QUÉ SE LEEN LAS TABLAS Y NO UNA VISTA
------------------------------------------------------------------------------
No existe ninguna vista de categorías, y `vw_catalogo_disponible` no sirve para
esto: parte de `ensayos_catalogo`, así que una categoría **sin ensayos activos
no aparecería en ella**. «Geotecnia» es exactamente ese caso en los datos
reales — existe, tiene su subcategoría, y cero ensayos. Listar categorías desde
esa vista las haría desaparecer justo cuando alguien acaba de crearlas y quiere
llenarlas.

Leer las tablas no debilita nada: `categorias_ensayo` y `subcategorias_ensayo`
tienen RLS `ENABLE` + `FORCE` con la política `p_tenant`, igual que el resto.

------------------------------------------------------------------------------
POR QUÉ NO HAY PAGINACIÓN
------------------------------------------------------------------------------
Y es una decisión, no un olvido. Una categoría es una familia de materiales:
suelos, concreto, asfalto, albañilería, geotecnia. Son cinco. Un laboratorio no
tiene cientos, y sus subcategorías son igual de acotadas. Paginar un conjunto
cerrado añade dos parámetros, dos modos de fallo y un contrato más difícil de
consumir a cambio de nada.

`extra="forbid"` cierra el otro lado: `?limite=10` no se ignora en silencio,
responde 422. Quien lo intente recibe una respuesta clara en vez de creer que
paginó.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from psycopg import AsyncConnection
from psycopg.rows import dict_row
from pydantic import BaseModel, ConfigDict, Field

from sacgeo.api.deps import get_db_tx, require_permission

log = logging.getLogger(__name__)

router = APIRouter(
    prefix="/categorias",
    tags=["catálogo"],
    # El permiso se exige en el ROUTER: un endpoint nuevo en este archivo nace
    # protegido, porque no hay nada que recordar.
    dependencies=[Depends(require_permission("catalogo.read"))],
    responses={
        401: {"description": "no autenticado"},
        403: {"description": "sin el permiso catalogo.read"},
    },
)


# ---------------------------------------------------------------- entrada ---

class FiltroCategorias(BaseModel):
    """Los dos filtros que definió la fase 7C. Ni uno más.

    `extra="forbid"` no es cosmético: sin él, `?tenant_id=2` se ignoraría en
    silencio y el cliente creería estar pidiendo otro laboratorio mientras
    recibe el suyo. Rechazarlo hace visible el intento.
    """

    model_config = ConfigDict(extra="forbid")

    solo_activas: bool = Field(
        default=True,
        description="Excluye categorías y subcategorías desactivadas.",
    )
    incluir_vacias: bool = Field(
        default=True,
        description="Incluye categorías sin ningún ensayo activo.",
    )


# ---------------------------------------------------------------- salida ----

class Subcategoria(BaseModel):
    public_id: UUID
    nombre: str
    orden: int
    activo: bool


class Categoria(BaseModel):
    """Una categoría tal como la ve la API.

    Sin `id` y sin `tenant_id`. El id técnico no sale nunca de la base
    (CLAUDE.md §5): publicar un entero secuencial invita a recorrerlo, que es
    como se produce un IDOR. El tenant es redundante — la sesión ya sabe en qué
    laboratorio opera— y devolverlo solo serviría para que alguien lo tomara
    por un parámetro.
    """

    public_id: UUID
    slug: str
    nombre: str
    prefijo_codigo: str
    icono: str | None = None
    color_hex: str | None = None
    orden: int
    activo: bool
    ensayos: int = Field(description="Ensayos activos en esta categoría.")
    subcategorias: list[Subcategoria]


class CategoriasResponse(BaseModel):
    items: list[Categoria]
    total: int


# --------------------------------------------------------------- consultas --
#
# Sin ningún "WHERE tenant_id": el aislamiento lo impone el motor, vía el
# contexto que fijó get_db_tx y la política p_tenant de ambas tablas. Un filtro
# por tenant en Python sugeriría que el aislamiento depende de esa línea y, sin
# contexto, devolvería una lista vacía en vez del 42501 que corresponde.
#
# Los JOIN entre las dos tablas van por el PAR (tenant_id, id), no por el id a
# secas: es el patrón de FK compuesta del esquema, y hace imposible cruzar una
# subcategoría con la categoría de otro laboratorio.

_SQL_CATEGORIAS = """
    SELECT c.public_id, c.slug, c.nombre, c.prefijo_codigo, c.icono,
           c.color_hex, c.orden, c.activo,
           (SELECT count(*) FROM ensayos_catalogo e
             WHERE e.categoria_id = c.id AND e.tenant_id = c.tenant_id
               AND e.activo) AS ensayos
      FROM categorias_ensayo c
     WHERE (NOT %(solo_activas)s OR c.activo)
       AND (%(incluir_vacias)s OR EXISTS (
               SELECT 1 FROM ensayos_catalogo e
                WHERE e.categoria_id = c.id AND e.tenant_id = c.tenant_id
                  AND e.activo))
     ORDER BY c.orden, c.nombre
"""

_SQL_SUBCATEGORIAS = """
    SELECT c.public_id AS categoria, s.public_id, s.nombre, s.orden, s.activo
      FROM subcategorias_ensayo s
      JOIN categorias_ensayo c
        ON c.id = s.categoria_id AND c.tenant_id = s.tenant_id
     WHERE (NOT %(solo_activas)s OR s.activo)
     ORDER BY c.orden, s.orden, s.nombre
"""

_SQL_CATEGORIA = """
    SELECT c.public_id, c.slug, c.nombre, c.prefijo_codigo, c.icono,
           c.color_hex, c.orden, c.activo,
           (SELECT count(*) FROM ensayos_catalogo e
             WHERE e.categoria_id = c.id AND e.tenant_id = c.tenant_id
               AND e.activo) AS ensayos
      FROM categorias_ensayo c
     WHERE c.public_id = %(public_id)s
"""

_SQL_SUBCATEGORIAS_DE = """
    SELECT s.public_id, s.nombre, s.orden, s.activo
      FROM subcategorias_ensayo s
      JOIN categorias_ensayo c
        ON c.id = s.categoria_id AND c.tenant_id = s.tenant_id
     WHERE c.public_id = %(public_id)s
     ORDER BY s.orden, s.nombre
"""

_NO_ENCONTRADA = HTTPException(
    status_code=status.HTTP_404_NOT_FOUND,
    detail="no encontrado",
)


def _categoria(fila: dict, subs: list[dict]) -> Categoria:
    return Categoria(
        public_id=fila["public_id"],
        slug=fila["slug"],
        nombre=fila["nombre"],
        prefijo_codigo=fila["prefijo_codigo"],
        icono=fila["icono"],
        color_hex=fila["color_hex"],
        orden=fila["orden"],
        activo=fila["activo"],
        ensayos=fila["ensayos"],
        subcategorias=[
            Subcategoria(
                public_id=s["public_id"],
                nombre=s["nombre"],
                orden=s["orden"],
                activo=s["activo"],
            )
            for s in subs
        ],
    )


# ---------------------------------------------------------------- rutas -----

@router.get("", response_model=CategoriasResponse, summary="Listar categorías")
async def listar_categorias(
    filtro: Annotated[FiltroCategorias, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> CategoriasResponse:
    """Devuelve las categorías del laboratorio con sus subcategorías anidadas.

    Dos consultas y un agrupado en memoria, en lugar de un JOIN que repita la
    categoría por cada subcategoría: el conjunto es pequeño y así el anidado no
    depende de reconstruirlo desde filas duplicadas. Las dos van en la MISMA
    transacción, así que ven la misma instantánea.
    """
    parametros = {
        "solo_activas": filtro.solo_activas,
        "incluir_vacias": filtro.incluir_vacias,
    }

    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_CATEGORIAS, parametros)
        categorias = await cur.fetchall()
        await cur.execute(_SQL_SUBCATEGORIAS, {"solo_activas": filtro.solo_activas})
        subcategorias = await cur.fetchall()

    por_categoria: dict[UUID, list[dict]] = defaultdict(list)
    for s in subcategorias:
        por_categoria[s["categoria"]].append(s)

    items = [_categoria(c, por_categoria.get(c["public_id"], [])) for c in categorias]
    return CategoriasResponse(items=items, total=len(items))


@router.get(
    "/{public_id}",
    response_model=Categoria,
    summary="Obtener una categoría",
    responses={404: {"description": "no existe o no pertenece a este laboratorio"}},
)
async def obtener_categoria(
    public_id: UUID,
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> Categoria:
    """Devuelve una categoría por su `public_id`, con sus subcategorías.

    Una categoría de OTRO laboratorio responde 404, nunca 403. Con RLS esa no
    es una respuesta defensiva sino la literal: la fila no existe para esta
    sesión. Un 403 confirmaría que el recurso existe en algún sitio y
    convertiría el endpoint en un oráculo para enumerar la competencia
    probando UUIDs.

    Aquí NO se filtra por `activo`: quien pide una categoría por su
    identificador ya la conoce, y ocultarle que está desactivada le impediría
    verla para reactivarla. El listado sí la excluye por defecto.
    """
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_CATEGORIA, {"public_id": str(public_id)})
        fila = await cur.fetchone()
        if fila is None:
            raise _NO_ENCONTRADA
        await cur.execute(_SQL_SUBCATEGORIAS_DE, {"public_id": str(public_id)})
        subs = await cur.fetchall()

    return _categoria(fila, subs)
