"""Clientes: empresas, sus contactos, y personas naturales. Solo lectura.

Es el primer dominio del backend con **tres entidades relacionadas**, y por eso
importa cómo se modela la relación.

------------------------------------------------------------------------------
POR QUÉ UN SOLO RECURSO /clientes CON DOS COLECCIONES
------------------------------------------------------------------------------
El dominio trata empresa y persona natural como ALTERNATIVAS: una cotización
lleva `empresa_id` + `contacto_id`, **o** `persona_id`. Nunca las dos. Por eso
viven bajo el mismo recurso —son dos formas de lo mismo, «a quién le cotizo»—
pero en colecciones separadas, porque sus claves de negocio son distintas: una
empresa se identifica por RUC y una persona por DNI, y mezclarlas obligaría a un
esquema con la mitad de los campos nulos.

`contactos` es un subrecurso de la empresa, no una colección propia: un contacto
sin empresa no existe.

------------------------------------------------------------------------------
LA FK DE TRES COLUMNAS, Y POR QUÉ SE RESPETA EN LOS JOIN
------------------------------------------------------------------------------
`contactos` declara `UNIQUE (tenant_id, empresa_id, id)`, y `cotizaciones` la
referencia entera:

    FOREIGN KEY (tenant_id, empresa_id, contacto_id)
      REFERENCES contactos (tenant_id, empresa_id, id)

Así, que el contacto sea de esa empresa **es imposible de violar**, no una regla
que alguien deba recordar. Los JOIN de este módulo usan el mismo par
`(tenant_id, id)` que el esquema: aunque RLS fallara, un contacto no podría
aparecer bajo la empresa de otro laboratorio.

------------------------------------------------------------------------------
SIN "WHERE tenant_id" EN NINGUNA CONSULTA
------------------------------------------------------------------------------
Lo impone RLS —`p_tenant` con ENABLE+FORCE en las tres tablas— a partir del
contexto que fijó `get_db_tx`. Un filtro en Python sugeriría que el aislamiento
depende de esa línea y, sin contexto, devolvería `200 []` en vez del 500 que
corresponde.

------------------------------------------------------------------------------
NO HAY FUNCIONES SQL DE CASO DE USO PARA CLIENTES
------------------------------------------------------------------------------
A diferencia del catálogo y de las cotizaciones, este dominio no tiene
`fn_crear_empresa` ni equivalentes. Para LEER no cambia nada. Para escribir sí:
sería el primer INSERT desde Python del proyecto, y es una decisión de
arquitectura pendiente. Queda anotado aquí porque es donde se verá.
"""

from __future__ import annotations

import logging
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from psycopg import AsyncConnection
from psycopg.rows import dict_row
from pydantic import BaseModel, ConfigDict, Field

from sacgeo.api.deps import get_db_tx, require_permission
from sacgeo.api.query import Direccion, SinParametros, componer

log = logging.getLogger(__name__)

router = APIRouter(
    prefix="/clientes",
    tags=["clientes"],
    dependencies=[Depends(require_permission("clientes.read"))],
    responses={
        401: {"description": "no autenticado"},
        403: {"description": "sin el permiso clientes.read"},
    },
)

_NO_ENCONTRADO = HTTPException(
    status_code=status.HTTP_404_NOT_FOUND,
    detail="no encontrado",
)


def _escapar_like(texto: str) -> str:
    r"""Neutraliza los comodines de LIKE. El `\` primero, o escaparía al resto.

    Sin esto, `q=%` coincide con toda la cartera de clientes y `q=_` con
    cualquier letra: el filtro diría una cosa y haría otra.
    """
    return texto.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


# =========================================================== EMPRESAS =======

class FiltroEmpresas(BaseModel):
    """Filtros y ordenación, todos tipados y de lista blanca.

    `orden` y `direccion` son `Literal`, así que Pydantic responde 422 a
    cualquier valor que no esté escrito aquí. Ese valor no se interpola en el
    SQL: es la clave de un diccionario de consultas ya compuestas.
    """

    model_config = ConfigDict(extra="forbid")

    q: str | None = Field(default=None, max_length=100,
                          description="Busca en razón social y RUC.")
    solo_activas: bool = Field(default=True)
    orden: Literal["nombre", "ruc", "creado_en"] = "nombre"
    direccion: Direccion = "asc"
    limite: int = Field(default=50, ge=1, le=200)
    desplazamiento: int = Field(default=0, ge=0)


class Contacto(BaseModel):
    public_id: UUID
    dni: str | None = None
    nombres: str
    apellidos: str
    cargo: str | None = None
    celular: str | None = None
    email: str | None = None
    activo: bool


class Empresa(BaseModel):
    """Sin `id` ni `tenant_id`: el id técnico no sale de la base (CLAUDE.md §5)."""

    public_id: UUID
    ruc: str
    razon_social: str
    direccion: str | None = None
    telefono: str | None = None
    email: str | None = None
    activo: bool
    contactos: int = Field(description="Contactos activos de esta empresa.")


class EmpresasResponse(BaseModel):
    items: list[Empresa]
    total: int
    limite: int
    desplazamiento: int


class ContactosResponse(BaseModel):
    empresa: UUID = Field(description="public_id de la empresa dueña.")
    items: list[Contacto]
    total: int


_BASE_EMPRESAS = """
    SELECT e.public_id, e.ruc, e.razon_social, e.direccion, e.telefono,
           e.email, e.activo,
           (SELECT count(*) FROM contactos c
             WHERE c.empresa_id = e.id AND c.tenant_id = e.tenant_id
               AND c.activo) AS contactos,
           e.id
      FROM empresas e
     WHERE (NOT %(solo_activas)s OR e.activo)
       AND (%(patron)s::TEXT IS NULL
            OR e.razon_social ILIKE %(patron)s
            OR e.ruc ILIKE %(patron)s)
"""

_SQL_EMPRESAS = componer(
    _BASE_EMPRESAS,
    {"nombre": "e.razon_social", "ruc": "e.ruc", "creado_en": "e.creado_en"},
    " LIMIT %(limite)s OFFSET %(desplazamiento)s",
)

_SQL_EMPRESAS_TOTAL = """
    SELECT count(*) AS total
      FROM empresas e
     WHERE (NOT %(solo_activas)s OR e.activo)
       AND (%(patron)s::TEXT IS NULL
            OR e.razon_social ILIKE %(patron)s
            OR e.ruc ILIKE %(patron)s)
"""

_SQL_EMPRESA = """
    SELECT e.public_id, e.ruc, e.razon_social, e.direccion, e.telefono,
           e.email, e.activo,
           (SELECT count(*) FROM contactos c
             WHERE c.empresa_id = e.id AND c.tenant_id = e.tenant_id
               AND c.activo) AS contactos,
           e.id
      FROM empresas e
     WHERE e.public_id = %(public_id)s
"""


def _empresa(f: dict) -> Empresa:
    return Empresa(
        public_id=f["public_id"], ruc=f["ruc"], razon_social=f["razon_social"],
        direccion=f["direccion"], telefono=f["telefono"], email=f["email"],
        activo=f["activo"], contactos=f["contactos"],
    )


@router.get("/empresas", response_model=EmpresasResponse, summary="Listar empresas")
async def listar_empresas(
    filtro: Annotated[FiltroEmpresas, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> EmpresasResponse:
    """Empresas cliente del laboratorio de la sesión.

    La consulta se ELIGE, no se construye: `filtro.orden` y `filtro.direccion`
    ya pasaron por el `Literal` de Pydantic y solo sirven para buscar en un
    diccionario de sentencias completas escritas en el código fuente.
    """
    parametros = {
        "solo_activas": filtro.solo_activas,
        "patron": "%" + _escapar_like(filtro.q) + "%" if filtro.q else None,
        "limite": filtro.limite,
        "desplazamiento": filtro.desplazamiento,
    }
    sql = _SQL_EMPRESAS[filtro.orden + ":" + filtro.direccion]

    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_EMPRESAS_TOTAL, parametros)
        total = (await cur.fetchone())["total"]
        await cur.execute(sql, parametros)
        filas = await cur.fetchall()

    return EmpresasResponse(
        items=[_empresa(f) for f in filas], total=total,
        limite=filtro.limite, desplazamiento=filtro.desplazamiento,
    )


@router.get("/empresas/{public_id}", response_model=Empresa,
            summary="Obtener una empresa",
            responses={404: {"description": "no existe o es de otro laboratorio"}})
async def obtener_empresa(
    public_id: UUID,
    _: Annotated[SinParametros, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> Empresa:
    """Una empresa de OTRO laboratorio responde 404, nunca 403.

    Con RLS el 404 es la respuesta literal: la fila no existe para esta sesión.
    Un 403 confirmaría que el RUC está registrado en el sistema y convertiría el
    endpoint en un oráculo para enumerar la cartera de clientes de la
    competencia.
    """
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_EMPRESA, {"public_id": str(public_id)})
        fila = await cur.fetchone()
    if fila is None:
        raise _NO_ENCONTRADO
    return _empresa(fila)


# =========================================================== CONTACTOS ======

_SQL_CONTACTOS = """
    SELECT c.public_id, c.dni, c.nombres, c.apellidos, c.cargo,
           c.celular, c.email, c.activo
      FROM contactos c
      JOIN empresas e ON e.id = c.empresa_id AND e.tenant_id = c.tenant_id
     WHERE e.public_id = %(public_id)s
       AND (NOT %(solo_activos)s OR c.activo)
     ORDER BY c.apellidos, c.nombres, c.id
"""

_SQL_CONTACTO = """
    SELECT c.public_id, c.dni, c.nombres, c.apellidos, c.cargo,
           c.celular, c.email, c.activo, e.public_id AS empresa
      FROM contactos c
      JOIN empresas e ON e.id = c.empresa_id AND e.tenant_id = c.tenant_id
     WHERE c.public_id = %(public_id)s
"""


class FiltroContactos(BaseModel):
    model_config = ConfigDict(extra="forbid")

    solo_activos: bool = Field(default=True)


class ContactoConEmpresa(Contacto):
    empresa: UUID = Field(description="public_id de la empresa dueña.")


def _contacto(f: dict) -> Contacto:
    return Contacto(
        public_id=f["public_id"], dni=f["dni"], nombres=f["nombres"],
        apellidos=f["apellidos"], cargo=f["cargo"], celular=f["celular"],
        email=f["email"], activo=f["activo"],
    )


@router.get("/empresas/{public_id}/contactos", response_model=ContactosResponse,
            summary="Contactos de una empresa",
            responses={404: {"description": "la empresa no existe o es de otro laboratorio"}})
async def listar_contactos(
    public_id: UUID,
    filtro: Annotated[FiltroContactos, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> ContactosResponse:
    """Contactos de una empresa. Sin paginación, y es una decisión.

    Una empresa cliente tiene un puñado de personas de contacto, no miles.
    Paginar un conjunto acotado añade dos parámetros y dos modos de fallo a
    cambio de nada; `extra="forbid"` rechaza `?limite=10` con 422 en vez de
    ignorarlo.

    Se comprueba primero que la EMPRESA sea visible: si no lo es, 404. Sin esa
    comprobación, una empresa ajena devolvería una lista vacía —que es cierta,
    pero distinta del 404 que da su ficha— y esa diferencia sería un oráculo.
    """
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_EMPRESA, {"public_id": str(public_id)})
        if await cur.fetchone() is None:
            raise _NO_ENCONTRADO
        await cur.execute(_SQL_CONTACTOS, {"public_id": str(public_id),
                                           "solo_activos": filtro.solo_activos})
        filas = await cur.fetchall()

    items = [_contacto(f) for f in filas]
    return ContactosResponse(empresa=public_id, items=items, total=len(items))


@router.get("/contactos/{public_id}", response_model=ContactoConEmpresa,
            summary="Obtener un contacto",
            responses={404: {"description": "no existe o es de otro laboratorio"}})
async def obtener_contacto(
    public_id: UUID,
    _: Annotated[SinParametros, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> ContactoConEmpresa:
    """Un contacto por su `public_id`, con la empresa a la que pertenece."""
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_CONTACTO, {"public_id": str(public_id)})
        fila = await cur.fetchone()
    if fila is None:
        raise _NO_ENCONTRADO
    base = _contacto(fila)
    return ContactoConEmpresa(**base.model_dump(), empresa=fila["empresa"])


# =========================================================== PERSONAS =======

class FiltroPersonas(BaseModel):
    model_config = ConfigDict(extra="forbid")

    q: str | None = Field(default=None, max_length=100,
                          description="Busca en nombres, apellidos y DNI.")
    solo_activas: bool = Field(default=True)
    orden: Literal["nombre", "dni", "creado_en"] = "nombre"
    direccion: Direccion = "asc"
    limite: int = Field(default=50, ge=1, le=200)
    desplazamiento: int = Field(default=0, ge=0)


class Persona(BaseModel):
    public_id: UUID
    dni: str
    nombres: str
    apellidos: str
    celular: str | None = None
    email: str | None = None
    empresa_asociada: str | None = Field(
        default=None,
        description="Texto libre. NO es una relación con `empresas`.",
    )
    activo: bool


class PersonasResponse(BaseModel):
    items: list[Persona]
    total: int
    limite: int
    desplazamiento: int


_BASE_PERSONAS = """
    SELECT p.public_id, p.dni, p.nombres, p.apellidos, p.celular, p.email,
           p.empresa_asociada, p.activo, p.id
      FROM personas p
     WHERE (NOT %(solo_activas)s OR p.activo)
       AND (%(patron)s::TEXT IS NULL
            OR p.nombres ILIKE %(patron)s
            OR p.apellidos ILIKE %(patron)s
            OR p.dni ILIKE %(patron)s)
"""

_SQL_PERSONAS = componer(
    _BASE_PERSONAS,
    {"nombre": "p.apellidos, p.nombres", "dni": "p.dni", "creado_en": "p.creado_en"},
    " LIMIT %(limite)s OFFSET %(desplazamiento)s",
)

_SQL_PERSONAS_TOTAL = """
    SELECT count(*) AS total
      FROM personas p
     WHERE (NOT %(solo_activas)s OR p.activo)
       AND (%(patron)s::TEXT IS NULL
            OR p.nombres ILIKE %(patron)s
            OR p.apellidos ILIKE %(patron)s
            OR p.dni ILIKE %(patron)s)
"""

_SQL_PERSONA = """
    SELECT p.public_id, p.dni, p.nombres, p.apellidos, p.celular, p.email,
           p.empresa_asociada, p.activo, p.id
      FROM personas p
     WHERE p.public_id = %(public_id)s
"""


def _persona(f: dict) -> Persona:
    return Persona(
        public_id=f["public_id"], dni=f["dni"], nombres=f["nombres"],
        apellidos=f["apellidos"], celular=f["celular"], email=f["email"],
        empresa_asociada=f["empresa_asociada"], activo=f["activo"],
    )


@router.get("/personas", response_model=PersonasResponse,
            summary="Listar personas naturales")
async def listar_personas(
    filtro: Annotated[FiltroPersonas, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> PersonasResponse:
    """Personas naturales, que cotizan con DNI en lugar de RUC."""
    parametros = {
        "solo_activas": filtro.solo_activas,
        "patron": "%" + _escapar_like(filtro.q) + "%" if filtro.q else None,
        "limite": filtro.limite,
        "desplazamiento": filtro.desplazamiento,
    }
    sql = _SQL_PERSONAS[filtro.orden + ":" + filtro.direccion]

    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_PERSONAS_TOTAL, parametros)
        total = (await cur.fetchone())["total"]
        await cur.execute(sql, parametros)
        filas = await cur.fetchall()

    return PersonasResponse(
        items=[_persona(f) for f in filas], total=total,
        limite=filtro.limite, desplazamiento=filtro.desplazamiento,
    )


@router.get("/personas/{public_id}", response_model=Persona,
            summary="Obtener una persona natural",
            responses={404: {"description": "no existe o es de otro laboratorio"}})
async def obtener_persona(
    public_id: UUID,
    _: Annotated[SinParametros, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> Persona:
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_PERSONA, {"public_id": str(public_id)})
        fila = await cur.fetchone()
    if fila is None:
        raise _NO_ENCONTRADO
    return _persona(fila)
