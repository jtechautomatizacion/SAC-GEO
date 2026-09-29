"""Dependencias de FastAPI. La cadena de autorización pasa entera por aquí.

    Request
      └─ get_sesion()          Bearer → JWT válido → sub → fn_sesion_resolver_usuario()
           │                   Devuelve (public_id, usuario_id, tenant_id). SIN contexto:
           │                   es la única consulta que puede hacerse antes de tenerlo.
           └─ get_db_tx()      BEGIN + set_config ×3 → yield → COMMIT/ROLLBACK
                └─ get_current_user()   dentro de ESA transacción, bajo RLS, lee el email
                     └─ Endpoint        recibe la transacción ya contextualizada

Del cliente llega exactamente UNA cosa: un token firmado. Todo lo demás se
deriva en el servidor.

Por qué este orden y no el anterior
-----------------------------------
Hasta 0004 `usuarios` era legible sin contexto, así que `get_current_user` podía
resolver la identidad completa por su cuenta y la transacción venía después. Con
RLS forzada eso dejó de ser cierto: `usuarios` lleva la política estricta
`USING (tenant_id = fn_app_tenant())` y cualquier SELECT sin contexto falla con
42501. Leer el email exige el contexto, y fijar el contexto exige conocer el
tenant — que sale de la propia identidad.

La dependencia de datos se rompe partiendo la resolución en dos:

  · lo mínimo para fijar el contexto (id, tenant_id, activo) sale de
    fn_sesion_resolver_usuario(), SECURITY DEFINER acotada y sin columnas
    sensibles;
  · todo lo demás se lee ya dentro de la transacción, sujeto a la política.

FastAPI cachea cada dependencia por petición, así que `get_db_tx` se resuelve una
sola vez: `get_current_user` y el endpoint comparten la MISMA transacción. No hay
una segunda conexión abierta fuera de ella para datos tenant-scoped.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg import AsyncConnection

from sacgeo.db.pool import obtener_pool
from sacgeo.db.tx import transaccion
from sacgeo.security import jwt as jwt_mod
from sacgeo.security.autenticacion import (
    CredencialesInvalidas,
    UsuarioAutenticado,
    completar_usuario,
    resolver_sesion,
)
from sacgeo.security.tenant import (
    Sesion,
    TenantNoAutorizado,
    resolver_tenant_activo,
)

_bearer = HTTPBearer(auto_error=False)

_NO_AUTENTICADO = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="no autenticado",
    headers={"WWW-Authenticate": "Bearer"},
)
_SIN_ACCESO = HTTPException(
    status_code=status.HTTP_403_FORBIDDEN,
    detail="acceso no autorizado",
)


async def get_sesion(
    credenciales: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> Sesion:
    """Valida el token y resuelve a qué usuario y tenant corresponde.

    El token identifica al usuario y nada más: no lleva tenant, ni rol, ni
    permisos. El estado del usuario se consulta en PostgreSQL EN CADA PETICIÓN,
    no se lee del token, así desactivar una cuenta surte efecto de inmediato
    sobre las peticiones nuevas sin esperar a que el access token expire.

    Todos los fallos —token ausente, firma inválida, expirado, usuario
    inexistente, desactivado, sin tenant— responden el mismo 401.
    """
    if credenciales is None or not credenciales.credentials:
        raise _NO_AUTENTICADO

    try:
        payload = jwt_mod.validar_access_token(credenciales.credentials)
    except jwt_mod.TokenInvalido:
        # El motivo exacto queda en el token, no en la respuesta.
        raise _NO_AUTENTICADO from None

    public_id = payload["sub"]
    pool = obtener_pool()
    try:
        async with pool.connection() as conn:
            usuario_id, tenant_id = await resolver_sesion(conn, public_id)
    except CredencialesInvalidas:
        raise _NO_AUTENTICADO from None

    return Sesion(public_id, usuario_id, tenant_id)


async def get_current_tenant(sesion: Sesion = Depends(get_sesion)) -> int:
    """Devuelve el tenant activo, resuelto en el servidor.

    No acepta ningún tenant propuesto por el cliente: mientras el modelo sea de
    un tenant por usuario, proponer otro no tiene sentido legítimo. Cuando
    llegue `plataforma_accesos`, aquí se leerá la cabecera correspondiente y se
    validará contra la concesión — y ningún endpoint cambiará.
    """
    try:
        return resolver_tenant_activo(sesion, tenant_propuesto=None)
    except TenantNoAutorizado:
        raise _SIN_ACCESO from None


async def get_db_tx(
    request: Request,
    sesion: Sesion = Depends(get_sesion),
    tenant_id: int = Depends(get_current_tenant),
) -> AsyncIterator[AsyncConnection]:
    """Entrega una transacción con el contexto ya fijado.

    El endpoint no fija contexto, no abre conexiones y no hace commit: si
    pudiera, algún día alguno se olvidaría.
    """
    ip = request.client.host if request.client else None
    async with transaccion(tenant_id, sesion.usuario_id, ip) as conn:
        yield conn


async def get_current_user(
    sesion: Sesion = Depends(get_sesion),
    conn: AsyncConnection = Depends(get_db_tx),
) -> UsuarioAutenticado:
    """Completa la identidad DENTRO de la transacción, bajo RLS.

    Depende de `get_db_tx`, no de una conexión propia: el email es un dato
    tenant-scoped y sólo debe leerse con la política de `usuarios` aplicándose.
    Si la política no devolviera la fila, el contexto está mal y la petición se
    rechaza con 401 en lugar de continuar con una identidad incompleta.
    """
    try:
        return await completar_usuario(
            conn, sesion.usuario_id, sesion.public_id, sesion.tenant_id
        )
    except CredencialesInvalidas:
        raise _NO_AUTENTICADO from None


# ============================================================================
# AUTORIZACIÓN RBAC — fase 6B
# ============================================================================
# Hasta aquí la cadena responde "quién eres" y "en qué laboratorio operas".
# Lo que sigue responde "qué puedes hacer", y lo pregunta a PostgreSQL en cada
# petición.
#
# Por qué no va en el token
# -------------------------
# Un permiso dentro del JWT es una foto del momento de iniciar sesión. Retirar
# un rol no surtiría efecto hasta que el token expirase, y durante ese rato el
# sistema seguiría concediendo algo que ya se revocó. `validar_access_token`
# rechaza de hecho cualquier token que traiga `roles`, `permissions` o `scope`,
# así que esta consulta no es una preferencia: es el único origen posible.
#
# Por qué la consulta va DENTRO de get_db_tx
# ------------------------------------------
# `fn_usuario_permisos(p_usuario)` no recibe tenant y no lo necesita: lee
# `usuario_roles`, que tiene RLS ENABLE + FORCE con USING (tenant_id =
# fn_app_tenant()). El aislamiento entre laboratorios lo pone el motor, no esta
# capa. Preguntar por los permisos de un usuario de otro tenant devuelve el
# conjunto vacío, que es denegación; preguntar sin contexto de tenant lanza
# 42501 y la petición muere. Ninguna de las dos ramas concede.
#
# Eso deja de ser cierto en el instante en que alguien abra una conexión propia
# para esta consulta. Por eso depende de `get_db_tx` y no del pool.

_SQL_PERMISOS = "SELECT codigo FROM fn_usuario_permisos(%s)"

# Todo código exigido por un guard queda registrado al construirse. Un test
# comprueba que ninguno de ellos falta en la tabla `permisos`: un código mal
# escrito produciría un 403 permanente indistinguible de "no le corresponde",
# y un endpoint inalcanzable no se nota hasta que alguien lo reclama.
PERMISOS_EXIGIDOS: set[str] = set()


def _registrar(codigos: tuple[str, ...]) -> tuple[str, ...]:
    """Valida la forma de los códigos al construir el guard, no al usarlo.

    Un guard sin códigos es un error de programación con dos lecturas posibles
    —denegar siempre o permitir siempre— y la segunda es un agujero abierto en
    silencio. Se rechaza al importar el módulo, que es cuando se ve.
    """
    if not codigos:
        raise ValueError("un guard de autorización exige al menos un permiso")
    for c in codigos:
        if not isinstance(c, str) or not c.strip():
            raise ValueError(f"código de permiso inválido: {c!r}")
    PERMISOS_EXIGIDOS.update(codigos)
    return codigos


async def _consultar_permisos(conn: AsyncConnection, usuario_id: int) -> frozenset[str]:
    """La consulta, aislada en su propia función para poder contarla y fallarla.

    Los tests necesitan demostrar dos cosas que no se ven desde fuera: que se
    ejecuta UNA vez por petición aunque haya varios guards, y que un fallo de
    base impide ejecutar el endpoint en lugar de degradar a "sin permisos".
    """
    async with conn.cursor() as cur:
        await cur.execute(_SQL_PERMISOS, (usuario_id,))
        filas = await cur.fetchall()
    return frozenset(fila[0] for fila in filas)


async def get_permisos(
    sesion: Sesion = Depends(get_sesion),
    conn: AsyncConnection = Depends(get_db_tx),
) -> frozenset[str]:
    """Los permisos efectivos de esta sesión. UNA consulta por petición.

    El usuario es siempre `sesion.usuario_id`, derivado del token en el
    servidor. Nunca un id del body, de la ruta, de la query ni de una cabecera:
    aceptar uno convertiría la consulta en "dame los permisos de quien yo diga".

    FastAPI cachea las dependencias por petición, así que todos los guards de
    un mismo endpoint comparten este frozenset y el conjunto de permisos no se
    vuelve a pedir. Entre peticiones NO hay caché, y eso es deliberado: retirar
    un rol surte efecto en la petición siguiente, igual que desactivar una
    cuenta.
    """
    return await _consultar_permisos(conn, sesion.usuario_id)


def require_permission(codigo: str):
    """Exige un permiso concreto. Devuelve una dependencia, no un decorador.

        @router.post("/cotizaciones",
                     dependencies=[Depends(require_permission("cotizaciones.create"))])

    Siendo una dependencia, FastAPI la resuelve dentro de la misma cadena —y de
    la misma transacción— y queda además reflejada en el esquema de la API.
    """
    (codigo,) = _registrar((codigo,))

    async def _guarda(permisos: frozenset[str] = Depends(get_permisos)) -> None:
        # Fail-closed: la única rama que deja pasar es la pertenencia al
        # conjunto que devolvió PostgreSQL. Un código inexistente, un usuario
        # sin roles y un usuario de otro tenant producen todos el mismo
        # conjunto sin el código, y por tanto el mismo 403.
        if codigo not in permisos:
            raise _SIN_ACCESO

    return _guarda


def require_any_permission(*codigos: str):
    """Deja pasar con AL MENOS UNO de los permisos indicados.

    Para el caso en que dos autoridades distintas llegan legítimamente a la
    misma lectura. No ejecuta una consulta por permiso: todos los guards leen
    el mismo `get_permisos()` cacheado.
    """
    codigos = _registrar(codigos)
    requeridos = frozenset(codigos)

    async def _guarda(permisos: frozenset[str] = Depends(get_permisos)) -> None:
        if not (requeridos & permisos):
            raise _SIN_ACCESO

    return _guarda


def require_all_permissions(*codigos: str):
    """Exige TODOS los permisos indicados.

    Para operaciones que combinan dos autoridades en un solo paso. El conjunto
    vacío está prohibido en `_registrar`: `set() <= permisos` es verdadero, así
    que un guard sin códigos dejaría pasar a cualquiera.
    """
    codigos = _registrar(codigos)
    requeridos = frozenset(codigos)

    async def _guarda(permisos: frozenset[str] = Depends(get_permisos)) -> None:
        if not requeridos <= permisos:
            raise _SIN_ACCESO

    return _guarda
