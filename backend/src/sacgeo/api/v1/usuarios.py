"""Usuarios del laboratorio. SOLO LECTURA.

------------------------------------------------------------------------------
POR QUÉ LEER USUARIOS NO ESTÁ BLOQUEADO POR G-2
------------------------------------------------------------------------------
G-2 dice que `sacgeo_app` conserva `INSERT` y `DELETE` directos sobre
`usuario_roles`, así que un endpoint de ESCRITURA podría saltarse
`fn_asignar_rol()` y con ella la comprobación de `usuarios.assign_role`. Eso
bloquea otorgar y retirar roles, no consultarlos: aquí no se escribe nada.

------------------------------------------------------------------------------
LA POLÍTICA p_login NO ABRE ESTE ENDPOINT
------------------------------------------------------------------------------
`usuarios` tiene DOS políticas, y las políticas permisivas se combinan con OR,
así que merecía una comprobación antes de exponer la tabla:

    p_tenant  TO sacgeo_app    USING (tenant_id = fn_app_tenant())
    p_login   TO sacgeo_auth   USING (true)          ← ¡permisiva y sin filtro!

`p_login` alcanza solo a `sacgeo_auth`, que es **NOLOGIN**: sus privilegios no
se pueden usar salvo a través de `fn_login_buscar()` y
`fn_sesion_resolver_usuario()`, ambas `SECURITY DEFINER` y acotadas a tres o
cinco columnas. La API se conecta como `sacgeo_app`, y para `sacgeo_app` la
única política aplicable es `p_tenant`. Verificado en `pg_policies.roles`, no
supuesto.

------------------------------------------------------------------------------
QUÉ NO SALE, Y POR QUÉ CADA COSA
------------------------------------------------------------------------------
  · `password_hash` — evidente, y además es el único campo que
    `campos_sensibles` redacta en la auditoría;
  · `id`, `tenant_id`, `rol_id`, `creado_por`, `desactivado_por` — ids técnicos;
  · `rol_id` merece una nota aparte: sigue en la tabla como «rol principal» y
    se retirará cuando nada lo lea. Publicarlo invitaría a que un cliente lo
    tomara por LA fuente de autorización, cuando la fuente es `usuario_roles`.
    Los roles salen como lista de códigos.
"""

from __future__ import annotations

import logging
from datetime import datetime
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
    prefix="/usuarios",
    tags=["usuarios"],
    dependencies=[Depends(require_permission("usuarios.read"))],
    responses={
        401: {"description": "no autenticado"},
        403: {"description": "sin el permiso usuarios.read"},
    },
)

_NO_ENCONTRADO = HTTPException(
    status_code=status.HTTP_404_NOT_FOUND,
    detail="no encontrado",
)


def _escapar_like(texto: str) -> str:
    return texto.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


class FiltroUsuarios(BaseModel):
    model_config = ConfigDict(extra="forbid")

    q: str | None = Field(default=None, max_length=100,
                          description="Busca en nombres, apellidos y correo.")
    solo_activos: bool = Field(default=True)
    orden: Literal["nombre", "email", "ultimo_acceso"] = "nombre"
    direccion: Direccion = "asc"
    limite: int = Field(default=50, ge=1, le=200)
    desplazamiento: int = Field(default=0, ge=0)


class Usuario(BaseModel):
    """Sin `password_hash`, sin ids técnicos y sin `rol_id`."""

    public_id: UUID
    nombres: str
    apellidos: str
    email: str
    activo: bool
    ultimo_acceso_en: datetime | None = None
    roles: list[str] = Field(
        description="Códigos de rol asignados. La fuente es `usuario_roles`."
    )


class UsuariosResponse(BaseModel):
    items: list[Usuario]
    total: int
    limite: int
    desplazamiento: int


# Sin "WHERE tenant_id": lo impone p_tenant a partir del contexto.
#
# `roles` se agrega con un subselect correlacionado y no con un JOIN + GROUP BY:
# así una fila sin roles sigue apareciendo con la lista vacía, que es un estado
# legítimo —una cuenta recién creada o suspendida sin desactivar— y no debe
# desaparecer del listado.
_BASE_USUARIOS = """
    SELECT u.public_id, u.nombres, u.apellidos, u.email, u.activo,
           u.ultimo_acceso_en,
           COALESCE((SELECT array_agg(r.codigo ORDER BY r.codigo)
                       FROM usuario_roles ur
                       JOIN roles r ON r.id = ur.rol_id
                      WHERE ur.usuario_id = u.id
                        AND ur.tenant_id = u.tenant_id), '{}') AS roles,
           u.id
      FROM usuarios u
     WHERE (NOT %(solo_activos)s OR u.activo)
       AND (%(patron)s::TEXT IS NULL
            OR u.nombres ILIKE %(patron)s
            OR u.apellidos ILIKE %(patron)s
            OR u.email ILIKE %(patron)s)
"""

_SQL_USUARIOS = componer(
    _BASE_USUARIOS,
    {"nombre": "u.apellidos, u.nombres", "email": "u.email",
     "ultimo_acceso": "u.ultimo_acceso_en"},
    " LIMIT %(limite)s OFFSET %(desplazamiento)s",
)

_SQL_USUARIOS_TOTAL = """
    SELECT count(*) AS total
      FROM usuarios u
     WHERE (NOT %(solo_activos)s OR u.activo)
       AND (%(patron)s::TEXT IS NULL
            OR u.nombres ILIKE %(patron)s
            OR u.apellidos ILIKE %(patron)s
            OR u.email ILIKE %(patron)s)
"""

_SQL_USUARIO = """
    SELECT u.public_id, u.nombres, u.apellidos, u.email, u.activo,
           u.ultimo_acceso_en,
           COALESCE((SELECT array_agg(r.codigo ORDER BY r.codigo)
                       FROM usuario_roles ur
                       JOIN roles r ON r.id = ur.rol_id
                      WHERE ur.usuario_id = u.id
                        AND ur.tenant_id = u.tenant_id), '{}') AS roles,
           u.id
      FROM usuarios u
     WHERE u.public_id = %(public_id)s
"""


def _usuario(f: dict) -> Usuario:
    return Usuario(
        public_id=f["public_id"], nombres=f["nombres"], apellidos=f["apellidos"],
        email=f["email"], activo=f["activo"],
        ultimo_acceso_en=f["ultimo_acceso_en"], roles=list(f["roles"]),
    )


@router.get("", response_model=UsuariosResponse, summary="Listar usuarios")
async def listar_usuarios(
    filtro: Annotated[FiltroUsuarios, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> UsuariosResponse:
    """Usuarios del laboratorio de la sesión.

    El usuario `sistema` (tenant NULL) no aparece, y no hay que excluirlo a
    mano: `p_tenant` exige `tenant_id = fn_app_tenant()`, y NULL no iguala a
    nada. El motor lo deja fuera.
    """
    parametros = {
        "solo_activos": filtro.solo_activos,
        "patron": "%" + _escapar_like(filtro.q) + "%" if filtro.q else None,
        "limite": filtro.limite,
        "desplazamiento": filtro.desplazamiento,
    }
    sql = _SQL_USUARIOS[filtro.orden + ":" + filtro.direccion]

    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_USUARIOS_TOTAL, parametros)
        total = (await cur.fetchone())["total"]
        await cur.execute(sql, parametros)
        filas = await cur.fetchall()

    return UsuariosResponse(
        items=[_usuario(f) for f in filas], total=total,
        limite=filtro.limite, desplazamiento=filtro.desplazamiento,
    )


@router.get("/{public_id}", response_model=Usuario, summary="Obtener un usuario",
            responses={404: {"description": "no existe o es de otro laboratorio"}})
async def obtener_usuario(
    public_id: UUID,
    _: Annotated[SinParametros, Query()],
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> Usuario:
    """Un usuario de OTRO laboratorio responde 404, nunca 403.

    Aquí NO se filtra por `activo`: un administrador tiene que poder ver una
    cuenta desactivada para reactivarla. El listado sí la excluye por defecto.
    """
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(_SQL_USUARIO, {"public_id": str(public_id)})
        fila = await cur.fetchone()
    if fila is None:
        raise _NO_ENCONTRADO
    return _usuario(fila)
