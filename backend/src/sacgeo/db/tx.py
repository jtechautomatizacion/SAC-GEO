"""Transacción con contexto de tenant. PUNTO ÚNICO del sistema.

Ningún otro módulo abre transacciones ni fija el contexto. Si algún endpoint
necesita hablar con PostgreSQL, recibe de aquí una transacción ya
contextualizada — no puede olvidarse de fijar el tenant porque no es él quien
lo fija.

------------------------------------------------------------------------------
POR QUÉ set_config(..., true) Y NO "SET LOCAL"
------------------------------------------------------------------------------
SET LOCAL no admite parámetros. Esto NO es SQL válido:

    SET LOCAL app.tenant_id = %s          -- ← error de sintaxis

La tentación es interpolar el valor en la cadena, y eso es concatenación de
SQL. Hoy el tenant_id es un entero que sale de nuestra propia base, así que no
es explotable; pero es exactamente el patrón que un día recibe un valor de otro
sitio.

set_config('app.tenant_id', %s, true) es EQUIVALENTE a SET LOCAL, acepta
parámetros ligados, y elimina la categoría entera del problema. Cuesta lo
mismo.

------------------------------------------------------------------------------
POR QUÉ "true" (LOCAL) Y NO DE SESIÓN
------------------------------------------------------------------------------
Un SET de sesión sobrevive al COMMIT. La conexión vuelve al pool con el tenant
todavía puesto y la siguiente petición —posiblemente de OTRO laboratorio— lo
hereda. Es una fuga entre clientes causada por una palabra.

Con LOCAL, PostgreSQL descarta el valor al COMMIT y al ROLLBACK. No hay que
acordarse de limpiarlo.

Nota: SET LOCAL fuera de un bloque de transacción emite un WARNING y no hace
nada. Por eso aquí el contexto se fija SIEMPRE después de abrir la transacción.
El diseño falla cerrado: sin contexto, fn_app_tenant() lanza 42501 y la
petición muere ruidosamente, en vez de devolver cero filas —que se confundiría
con "no hay datos".
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from psycopg import AsyncConnection

from sacgeo.db.pool import obtener_pool

log = logging.getLogger(__name__)

_SET_CONTEXTO = "SELECT set_config(%s, %s, true)"


@asynccontextmanager
async def transaccion(
    tenant_id: int,
    usuario_id: int,
    ip_origen: str | None = None,
) -> AsyncIterator[AsyncConnection]:
    """Abre una transacción con el contexto de tenant ya establecido.

    El tenant_id DEBE venir resuelto en el servidor desde la identidad
    autenticada. Esta función no valida autorización: para cuando se la llama,
    esa decisión ya se tomó en security/tenant.py.

    Al salir hace COMMIT; ante cualquier excepción, ROLLBACK. En ambos casos el
    contexto se descarta solo.
    """
    if tenant_id is None:
        raise ValueError("transaccion() exige un tenant_id resuelto en el servidor")
    if usuario_id is None:
        raise ValueError("transaccion() exige un usuario_id de la sesión autenticada")

    pool = obtener_pool()
    async with pool.connection() as conn:
        # psycopg abre la transacción aquí; los set_config van DENTRO.
        async with conn.transaction():
            async with conn.cursor() as cur:
                await cur.execute(_SET_CONTEXTO, ("app.tenant_id", str(tenant_id)))
                await cur.execute(_SET_CONTEXTO, ("app.usuario_id", str(usuario_id)))
                if ip_origen:
                    await cur.execute(_SET_CONTEXTO, ("app.ip_origen", ip_origen))
            yield conn


async def leer_contexto(conn: AsyncConnection) -> dict[str, str | None]:
    """Devuelve el contexto visible en esta conexión. Para pruebas y diagnóstico.

    El segundo argumento TRUE de current_setting evita que falle cuando el GUC
    no está definido: devuelve NULL, que es justo lo que queremos comprobar
    después de un COMMIT.
    """
    async with conn.cursor() as cur:
        await cur.execute(
            """
            SELECT current_setting('app.tenant_id',  true),
                   current_setting('app.usuario_id', true),
                   current_setting('app.ip_origen',  true)
            """
        )
        tenant, usuario, ip = await cur.fetchone()
    return {"tenant_id": tenant, "usuario_id": usuario, "ip_origen": ip}
