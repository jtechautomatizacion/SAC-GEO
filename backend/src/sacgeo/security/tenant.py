"""Resolución del tenant activo. PUNTO ÚNICO del sistema.

Ningún otro módulo decide a qué laboratorio pertenece una petición.

El tenant NO viene del token (decisión D-4) ni del cliente. Se lee de
PostgreSQL a partir de la identidad ya autenticada.

------------------------------------------------------------------------------
POR QUÉ ESTA FUNCIÓN EXISTE HOY, SIENDO TAN SIMPLE
------------------------------------------------------------------------------
Hoy un usuario pertenece a un tenant y la respuesta cabe en una línea. La
función existe igualmente porque es el punto de extensión: cuando llegue
`plataforma_accesos` y el Super Admin, esta misma función validará la concesión
y NINGÚN endpoint cambiará, porque ninguno resuelve el tenant por su cuenta.

Si cada endpoint leyera `sesion.tenant_id` directamente, ese día habría que
revisarlos todos y confiar en no olvidar ninguno.
"""

from __future__ import annotations

import logging

log = logging.getLogger(__name__)


class TenantNoAutorizado(Exception):
    """El usuario no tiene acceso al tenant solicitado."""


class Sesion:
    """Lo mínimo que hace falta para poder fijar el contexto de la transacción.

    NO es la identidad completa: falta todo lo tenant-scoped, que sólo puede
    leerse una vez fijado el contexto. Existe para llevar el tenant desde la
    resolución —que ocurre sin contexto— hasta el `set_config` que lo fija.

    Vive en este módulo, y no en `deps`, porque es el dato que alimenta a
    `resolver_tenant_activo()`: tenerlo aquí evita el ciclo de importación y
    deja claro quién es el dueño del tenant.
    """

    __slots__ = ("public_id", "usuario_id", "tenant_id")

    def __init__(self, public_id: str, usuario_id: int, tenant_id: int | None):
        self.public_id = str(public_id)
        self.usuario_id = usuario_id
        self.tenant_id = tenant_id

    def __repr__(self) -> str:
        # Sin email: este objeto acaba en trazas de error.
        return f"<Sesion usuario={self.usuario_id} tenant={self.tenant_id}>"


def resolver_tenant_activo(
    sesion: Sesion,
    tenant_propuesto: int | None = None,
) -> int:
    """Devuelve el tenant sobre el que operará esta petición.

    `tenant_propuesto` es lo que el cliente pidió, si pidió algo. NO es un dato:
    es una petición de acceso, y se valida contra la autorización real.

    Reglas que se conservarán cuando exista el multi-tenant de plataforma:
      · tenant_id IS NULL significa "no pertenece a ningún laboratorio",
        NUNCA "acceso a todos";
      · un tenant propuesto que no coincida con la autorización se rechaza,
        no se ignora en silencio — un rechazo deja rastro, un silencio no.
    """
    if sesion.tenant_id is None:
        # Identidad global (hoy solo el usuario `sistema`). No obtiene sesión.
        log.warning("resolución de tenant para identidad global id=%s", sesion.usuario_id)
        raise TenantNoAutorizado()

    if tenant_propuesto is not None and tenant_propuesto != sesion.tenant_id:
        log.warning(
            "usuario id=%s propuso tenant %s, autorizado %s",
            sesion.usuario_id, tenant_propuesto, sesion.tenant_id,
        )
        raise TenantNoAutorizado()

    return sesion.tenant_id
