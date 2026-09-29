"""Servicio de autenticación. Toda decisión de identidad pasa por aquí.

Dos invariantes que gobiernan el archivo:

  1. Un fallo de login SIEMPRE responde lo mismo, tarde lo que tarde el camino
     interno. Distinguir "usuario inexistente" de "contraseña incorrecta"
     permite enumerar cuentas; distinguirlos por TIEMPO, también.

  2. El tenant NO se decide aquí ni en el token: se lee de PostgreSQL a partir
     de la identidad ya verificada.
"""

from __future__ import annotations

import logging

from psycopg import AsyncConnection

from sacgeo.security import passwords

log = logging.getLogger(__name__)


class CredencialesInvalidas(Exception):
    """Único error que sale del login. Mensaje genérico, siempre el mismo."""


class UsuarioAutenticado:
    """Identidad resuelta en el servidor. Nada de esto viene del cliente."""

    __slots__ = ("id", "public_id", "email", "tenant_id", "activo")

    def __init__(self, id: int, public_id: str, email: str,
                 tenant_id: int | None, activo: bool):
        self.id = id
        self.public_id = str(public_id)
        self.email = email
        self.tenant_id = tenant_id
        self.activo = activo

    def __repr__(self) -> str:
        # Sin email ni hash: este objeto acaba en trazas de error.
        return f"<UsuarioAutenticado id={self.id} tenant={self.tenant_id}>"


# El login tampoco puede consultar `usuarios` directamente: ocurre antes de
# saber el tenant, igual que la resolución de sesión. fn_login_buscar() es la
# excepción acotada para ese caso (D-12). Devuelve cinco columnas — aquí sí
# hace falta password_hash, porque hay una contraseña que verificar — y
# excluye por construcción a las identidades globales y a las cuentas sin
# credencial: el usuario `sistema` no puede iniciar sesión ni aunque el
# backend se equivoque.
_LOGIN_BUSCAR = "SELECT id, public_id, tenant_id, activo, password_hash FROM fn_login_buscar(%s)"

# Resolución de sesión: NO consulta `usuarios` directamente.
#
# Con RLS activa, `usuarios` lleva la política estricta
#     USING (tenant_id = fn_app_tenant())
# y fn_app_tenant() lanza 42501 sin contexto. Pero el contexto solo se puede
# fijar cuando ya se sabe el tenant, y el tenant sale de esta misma consulta.
# No es un problema de orden: es una dependencia de datos.
#
# fn_sesion_resolver_usuario() es la excepción acotada que lo rompe (D-14).
# Devuelve TRES columnas y ninguna sensible: ni password_hash —el token ya
# viene firmado, aquí no hay contraseña que comprobar— ni email ni rol.
_RESOLVER_SESION = "SELECT id, tenant_id, activo FROM fn_sesion_resolver_usuario(%s)"

# El email se lee DESPUÉS, ya dentro de la transacción y bajo RLS. Una función
# SECURITY DEFINER más para esto sería superficie regalada: con el tenant ya
# fijado, la consulta normal basta y la política hace su trabajo.
_SELECT_EMAIL = "SELECT email FROM usuarios WHERE id = %s"


async def autenticar(conn: AsyncConnection, email: str, password: str) -> UsuarioAutenticado:
    """Verifica credenciales. Devuelve la identidad o lanza CredencialesInvalidas.

    El orden de las comprobaciones es deliberado: se verifica SIEMPRE la
    contraseña, incluso cuando ya sabemos que vamos a rechazar, para no dar una
    pista temporal sobre si el usuario existe.
    """
    async with conn.cursor() as cur:
        await cur.execute(_LOGIN_BUSCAR, (email,))
        fila = await cur.fetchone()

    if fila is None:
        # Inexistente, identidad global o cuenta sin credencial: la función ya
        # los filtra. Se gasta el mismo tiempo que en una verificación real
        # para que el atacante no pueda distinguirlos cronometrando.
        passwords.verificar(password, _HASH_SENUELO)
        raise CredencialesInvalidas()

    id_, public_id, tenant_id, activo, password_hash = fila

    # 1 · Sin hash no hay login. ANTES de verificar nada.
    #     fn_login_buscar ya lo filtra, pero comprobarlo aquí evita depender de
    #     cómo reaccione la librería ante un hash None si algo cambiara.
    if password_hash is None:
        passwords.verificar(password, _HASH_SENUELO)
        log.warning("intento de login sobre cuenta sin credencial id=%s", id_)
        raise CredencialesInvalidas()

    # 2 · La contraseña. Siempre se ejecuta, aunque las siguientes fallen.
    password_ok = passwords.verificar(password, password_hash)

    # 3 · Usuario desactivado: mismo error genérico, sin revelar que existe.
    if not activo:
        raise CredencialesInvalidas()

    # 4 · Sin tenant no hay sesión. tenant_id NULL significa "no pertenece a
    #     ningún laboratorio", NUNCA "acceso a todos". La función ya lo filtra;
    #     esto es la segunda barrera.
    if tenant_id is None:
        log.warning("intento de login de identidad global id=%s", id_)
        raise CredencialesInvalidas()

    if not password_ok:
        raise CredencialesInvalidas()

    # El email no se pide a la función —sería una columna más de superficie—.
    # Se usa el que la persona escribió: la consulta lo comparó con
    # lower(email), así que coincide salvo en mayúsculas.
    return UsuarioAutenticado(id_, public_id, email, tenant_id, activo)


async def resolver_sesion(conn: AsyncConnection, public_id: str) -> tuple[int, int]:
    """Resuelve (usuario_id, tenant_id) desde el `sub` del token, SIN contexto.

    Se consulta en CADA petición a propósito: así desactivar un usuario surte
    efecto de inmediato sobre las peticiones nuevas, sin esperar a que expire
    su access token.

    Devuelve una tupla y no un UsuarioAutenticado porque todavía falta el
    email, que solo puede leerse una vez fijado el contexto de tenant.
    """
    async with conn.cursor() as cur:
        await cur.execute(_RESOLVER_SESION, (public_id,))
        fila = await cur.fetchone()

    if fila is None:
        # Inexistente, o identidad global: la función ya filtra
        # tenant_id IS NOT NULL. Ambos casos dan el mismo error.
        raise CredencialesInvalidas()

    usuario_id, tenant_id, activo = fila
    if not activo:
        # Se distingue del caso anterior solo para el log; hacia fuera, 401.
        log.warning("peticion de usuario desactivado id=%s", usuario_id)
        raise CredencialesInvalidas()

    return usuario_id, tenant_id


async def completar_usuario(
    conn: AsyncConnection, usuario_id: int, public_id: str, tenant_id: int
) -> UsuarioAutenticado:
    """Lee el email dentro de la transacción, ya protegido por RLS.

    Si la política no devolviera la fila, algo va mal en el contexto: se trata
    como credencial inválida en vez de continuar con datos incompletos.
    """
    async with conn.cursor() as cur:
        await cur.execute(_SELECT_EMAIL, (usuario_id,))
        fila = await cur.fetchone()

    if fila is None:
        raise CredencialesInvalidas()

    return UsuarioAutenticado(usuario_id, public_id, fila[0], tenant_id, True)


# Hash real de una contraseña que nadie conoce. Solo sirve para que el camino
# "usuario inexistente" cueste lo mismo que el camino "usuario existente".
_HASH_SENUELO = passwords.hashear("senuelo-de-tiempo-constante-no-es-secreto")
