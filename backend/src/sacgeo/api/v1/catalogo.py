"""Catálogo de ensayos. El PRIMER recurso de negocio de SAC-GEO.

Es también el primer endpoint protegido de verdad: hasta ahora el mecanismo
RBAC existía y no guardaba nada. Con `require_permission("catalogo.read")` en
la ruta, H-01 deja de estar abierto en su mecanismo.

------------------------------------------------------------------------------
POR QUÉ SE LEE UNA VISTA Y NO LAS TRES TABLAS
------------------------------------------------------------------------------
`vw_catalogo_disponible` ya une ensayo → subcategoría → categoría con las FK
compuestas por tenant y filtra las tres por `activo`. Rehacer ese JOIN en
Python no añadiría nada y abriría dos puertas: olvidar uno de los tres
`activo`, y —peor— reconstruir la pertenencia con un JOIN por `id` en vez de
por el par `(tenant_id, id)`.

La vista es `security_invoker = true`, así que las políticas RLS de las tablas
subyacentes se evalúan con los privilegios de quien consulta. Leerla NO es un
atajo alrededor de RLS: es RLS.

------------------------------------------------------------------------------
POR QUÉ NO HAY NINGÚN "WHERE tenant_id = ..."
------------------------------------------------------------------------------
Y es deliberado, no un olvido. El aislamiento lo impone el motor:

    get_db_tx  →  set_config('app.tenant_id', …, true)
                  →  política USING (tenant_id = fn_app_tenant())
                     →  la fila del otro laboratorio no existe para esta sesión

Añadir aquí un filtro por tenant tendría dos efectos, los dos malos: sugeriría
que el aislamiento depende de esta línea —y que borrarla lo rompe—, y además
enmascararía un fallo de contexto. Sin contexto, `fn_app_tenant()` lanza 42501
y la petición muere con 500; con un filtro en Python, una variable vacía
devolvería una lista vacía y un 200, que es indistinguible de "este laboratorio
no tiene ensayos".
"""

from __future__ import annotations

import logging
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict, Field
from psycopg import AsyncConnection
from psycopg.rows import dict_row

from sacgeo.api.deps import get_db_tx, require_permission

log = logging.getLogger(__name__)

router = APIRouter(
    prefix="/catalogo",
    tags=["catálogo"],
    # El permiso se exige en el ROUTER, no endpoint por endpoint. Así un
    # endpoint nuevo en este archivo nace protegido: olvidarse de la
    # dependencia deja de ser posible, porque no hay nada que recordar.
    dependencies=[Depends(require_permission("catalogo.read"))],
    responses={
        401: {"description": "no autenticado"},
        403: {"description": "sin el permiso catalogo.read"},
    },
)


# ---------------------------------------------------------------- entrada ---

class FiltroCatalogo(BaseModel):
    """Los parámetros de consulta. `extra="forbid"` no es cosmético.

    Sin él, `?tenant_id=2` se ignoraría en silencio: el cliente creería estar
    pidiendo otro laboratorio y recibiría el suyo. Rechazarlo con 422 hace
    visible el intento en vez de esconderlo.
    """

    model_config = ConfigDict(extra="forbid")

    categoria_id: int | None = Field(
        default=None, gt=0, description="Filtra por categoría del catálogo."
    )
    solo_acreditados: bool | None = Field(
        default=None, description="Solo ensayos con acreditación ISO 17025 vigente."
    )
    q: str | None = Field(
        default=None, max_length=100, description="Busca en el nombre y en el código."
    )
    limite: int = Field(default=50, ge=1, le=200)
    desplazamiento: int = Field(default=0, ge=0)


# ---------------------------------------------------------------- salida ----

class CatalogoCategoria(BaseModel):
    id: int
    slug: str
    nombre: str
    icono: str | None = None
    color_hex: str | None = None


class CatalogoSubcategoria(BaseModel):
    id: int
    nombre: str


class CatalogoItem(BaseModel):
    """Un ensayo tal como lo ve la API.

    NO lleva `ensayo_id` ni `tenant_id`, y ninguno de los dos es un descuido:

      · el `id` técnico no sale nunca de la base (CLAUDE.md §5). Lo que viaja
        en URLs y en el QR del PDF es el `public_id`. Publicar un entero
        secuencial invita a recorrerlo, que es como se produce un IDOR;
      · el `tenant_id` es redundante —la sesión ya sabe en qué laboratorio
        opera, y `/auth/yo` lo devuelve— y devolverlo por cada uno de los 89
        ensayos solo serviría para que alguien lo tomara por un parámetro.
    """

    public_id: UUID
    codigo: str
    nombre: str
    norma: str | None = None
    unidad: str
    precio_base: float
    es_paquete: bool
    acreditado: bool
    categoria: CatalogoCategoria
    subcategoria: CatalogoSubcategoria


class CatalogoListResponse(BaseModel):
    items: list[CatalogoItem]
    total: int = Field(description="Filas que cumplen el filtro, antes de paginar.")
    limite: int
    desplazamiento: int


# ---------------------------------------------------------------- consulta --

# Las tres consultas se escriben ENTERAS y literales. La versión anterior las
# componía con f-strings a partir de constantes —solo constantes del módulo,
# nunca datos del cliente— y aun así `test_28a_sin_sql_por_f_string` la
# rechazó, con razón: la regla del proyecto es que ninguna sentencia SQL se
# arma con f-string, y una regla que admite excepciones "seguras" obliga a
# juzgar cada caso, que es exactamente lo que la regla existe para evitar.
#
# El precio es repetir la lista de columnas tres veces. Es un precio bajo:
# estas consultas se leen de una vez, sin reconstruir mentalmente qué trozo
# viene de qué constante.
#
# Los filtros opcionales se resuelven con "%(x)s IS NULL OR …" dentro del texto
# fijo, así que el WHERE nunca cambia de forma. Todo valor del cliente viaja
# como parámetro ligado.

# El orden es el de la lista de precios en Excel que el laboratorio ya usa:
# categoría, subcategoría, código. `orden_*` son las columnas de ordenación
# manual; los ids desempatan para que la paginación sea estable — sin un orden
# total, dos páginas consecutivas podrían repetir u omitir una fila.
_SQL_LISTA = """
    SELECT public_id, codigo, nombre, norma, unidad, precio_base,
           es_paquete, acreditado,
           categoria_id, categoria_slug, categoria, icono, color_hex,
           subcategoria_id, subcategoria
      FROM vw_catalogo_disponible
     WHERE (%(categoria_id)s::INTEGER IS NULL OR categoria_id = %(categoria_id)s)
       AND (%(solo_acreditados)s::BOOLEAN IS NULL OR acreditado = %(solo_acreditados)s)
       AND (%(patron)s::TEXT IS NULL OR nombre ILIKE %(patron)s OR codigo ILIKE %(patron)s)
     ORDER BY orden_categoria, categoria_id, orden_subcategoria, subcategoria_id, codigo
     LIMIT %(limite)s OFFSET %(desplazamiento)s
"""

# Consulta aparte, y no `count(*) OVER ()` en la anterior: la función de ventana
# no devuelve nada cuando la página sale vacía, así que la última página y un
# desplazamiento fuera de rango informarían total = 0. Las dos van en la MISMA
# transacción, así que ven la misma instantánea.
_SQL_TOTAL = """
    SELECT count(*) AS total
      FROM vw_catalogo_disponible
     WHERE (%(categoria_id)s::INTEGER IS NULL OR categoria_id = %(categoria_id)s)
       AND (%(solo_acreditados)s::BOOLEAN IS NULL OR acreditado = %(solo_acreditados)s)
       AND (%(patron)s::TEXT IS NULL OR nombre ILIKE %(patron)s OR codigo ILIKE %(patron)s)
"""

_SQL_DETALLE = """
    SELECT public_id, codigo, nombre, norma, unidad, precio_base,
           es_paquete, acreditado,
           categoria_id, categoria_slug, categoria, icono, color_hex,
           subcategoria_id, subcategoria
      FROM vw_catalogo_disponible
     WHERE public_id = %(public_id)s
"""

_NO_ENCONTRADO = HTTPException(
    status_code=status.HTTP_404_NOT_FOUND,
    detail="no encontrado",
)


def _escapar_like(texto: str) -> str:
    r"""Neutraliza los comodines de LIKE en la búsqueda del usuario.

    Sin esto, `q=%` coincide con todo el catálogo y `q=_` con cualquier letra:
    el filtro diría una cosa y haría otra. El `\` se escapa primero, o
    escaparía a los que vienen después.
    """
    return texto.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _a_item(fila: dict) -> CatalogoItem:
    return CatalogoItem(
        public_id=fila["public_id"],
        codigo=fila["codigo"],
        nombre=fila["nombre"],
        norma=fila["norma"],
        unidad=fila["unidad"],
        precio_base=fila["precio_base"],
        es_paquete=fila["es_paquete"],
        acreditado=fila["acreditado"],
        categoria=CatalogoCategoria(
            id=fila["categoria_id"],
            slug=fila["categoria_slug"],
            nombre=fila["categoria"],
            icono=fila["icono"],
            color_hex=fila["color_hex"],
        ),
        subcategoria=CatalogoSubcategoria(
            id=fila["subcategoria_id"],
            nombre=fila["subcategoria"],
        ),
    )


# ---------------------------------------------------------------- rutas -----

@router.get("", response_model=CatalogoListResponse, summary="Listar el catálogo")
async def listar_catalogo(
    filtro: Annotated[FiltroCatalogo, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> CatalogoListResponse:
    """Devuelve el catálogo del laboratorio de la sesión.

    `conn` llega de `get_db_tx`, que ya abrió la transacción y fijó el
    contexto. El endpoint no abre conexiones, no fija contexto y no hace
    commit: si pudiera, algún día alguno se olvidaría. Es además la MISMA
    transacción en la que `require_permission` consultó los permisos, así que
    el permiso y los datos se leen bajo el mismo contexto.
    """
    parametros = {
        "categoria_id": filtro.categoria_id,
        "solo_acreditados": filtro.solo_acreditados,
        "patron": f"%{_escapar_like(filtro.q)}%" if filtro.q else None,
        "limite": filtro.limite,
        "desplazamiento": filtro.desplazamiento,
    }

    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_TOTAL, parametros, prepare=False)
        total = (await cur.fetchone())["total"]
        await cur.execute(_SQL_LISTA, parametros, prepare=False)
        filas = await cur.fetchall()

    return CatalogoListResponse(
        items=[_a_item(f) for f in filas],
        total=total,
        limite=filtro.limite,
        desplazamiento=filtro.desplazamiento,
    )


@router.get(
    "/{public_id}",
    response_model=CatalogoItem,
    summary="Obtener un ensayo",
    responses={404: {"description": "no existe o no pertenece a este laboratorio"}},
)
async def obtener_ensayo(
    public_id: UUID,
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> CatalogoItem:
    """Devuelve un ensayo por su `public_id`.

    Un ensayo de OTRO laboratorio responde 404, nunca 403. Con RLS activa esa
    no es una respuesta defensiva sino la literal: la fila no existe para esta
    sesión. Un 403 confirmaría que el recurso existe en algún sitio y
    convertiría el endpoint en un oráculo para enumerar el catálogo de la
    competencia probando UUIDs.

    Por el mismo motivo, un ensayo desactivado también da 404: la vista filtra
    por `activo`, y distinguir "no existe" de "existe pero está de baja" es
    otra filtración, más pequeña.
    """
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_DETALLE, {"public_id": str(public_id)}, prepare=False)
        fila = await cur.fetchone()

    if fila is None:
        raise _NO_ENCONTRADO
    return _a_item(fila)
