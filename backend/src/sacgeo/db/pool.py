"""Pool de conexiones a PostgreSQL.

El pool es el sitio donde una fuga entre laboratorios se vuelve invisible: una
conexión que vuelve al pool con estado de la petición anterior se la entrega
después a otra petición, que puede ser de otro tenant.

Por eso aquí hay dos defensas, y una NO sustituye a la otra:

  1. El contexto se fija SIEMPRE con set_config(..., true), que equivale a
     SET LOCAL y se descarta solo al COMMIT o al ROLLBACK. Eso vive en tx.py.
  2. Al devolver la conexión, este módulo ejecuta ROLLBACK + DISCARD ALL.

La (2) es una red que atrapa un error de la (1). Si el sistema dependiera de
la (2) para estar aislado, ya estaría roto.
"""

from __future__ import annotations

import logging

from psycopg import AsyncConnection
from psycopg_pool import AsyncConnectionPool

from sacgeo.config import settings

log = logging.getLogger(__name__)

_pool: AsyncConnectionPool | None = None


async def _reset(conn: AsyncConnection) -> None:
    """Deja la conexión limpia antes de devolverla al pool.

    DISCARD ALL borra GUCs de sesión, tablas temporales, planes cacheados y
    prepared statements. Tiene un coste pequeño —hay que replanificar— y se
    paga a propósito: es mucho más barato que una fuga entre tenants.

    El autocommit NO es un detalle. psycopg abre una transacción implícita en
    cuanto se ejecuta la primera sentencia, y PostgreSQL rechaza DISCARD ALL
    dentro de un bloque de transacción. Sin esto el reset lanza
    "DISCARD ALL cannot run inside a transaction block", psycopg da la conexión
    por perdida y la recrea: el pool deja de reutilizar nada y la red de
    seguridad que este código promete no llega a ejecutarse nunca.

    El aislamiento no dependía de ella —de eso se encarga set_config(..., true)
    en tx.py— pero una defensa que falla en silencio es peor que no tenerla,
    porque se cuenta con ella.
    """
    await conn.rollback()
    if not settings.pool_discard_all:
        return

    autocommit_previo = conn.autocommit
    await conn.set_autocommit(True)
    try:
        async with conn.cursor() as cur:
            await cur.execute("DISCARD ALL")
    finally:
        # Se restaura el modo para que la siguiente petición encuentre la
        # conexión exactamente como la espera tx.py.
        await conn.set_autocommit(autocommit_previo)


async def _configurar(conn: AsyncConnection) -> None:
    """Desactiva la preparación automática de sentencias. Defecto D-3.

    psycopg3 prepara una consulta en el servidor cuando la ha ejecutado 5 veces
    sobre la misma conexión, y recuerda su nombre en una caché DEL LADO DEL
    CLIENTE. `_reset()` ejecuta `DISCARD ALL`, que borra los prepared
    statements DEL SERVIDOR — pero no esa caché. A partir de ahí psycopg pide
    por nombre algo que ya no existe:

        SQLSTATE 26000 — prepared statement "_pg3_0" does not exist

    No es hipotético. La sentencia que primero alcanza el umbral es
    `SELECT set_config(%s, %s, true)` de `db/tx.py`, que corre dos o tres veces
    por petición: el fallo aparecía en la CUARTA petición de cualquier endpoint
    autenticado. Estaba ahí desde que existe el pool; nadie lo había visto
    porque ninguna prueba encadenaba cuatro peticiones sobre la misma conexión.
    Lo destapó el primer endpoint de negocio, en la fase 7B.

    Dos maneras de arreglarlo, y por qué esta:

      · quitar `DISCARD ALL` haría desaparecer el síntoma y con él la red de
        seguridad que impide que una conexión vuelva al pool con estado. No se
        toca;
      · no preparar nada cuesta exactamente cero AQUÍ, porque con `DISCARD ALL`
        en cada devolución un prepared statement no puede sobrevivir a la
        petición que lo creó. Preparar no ahorraba ninguna replanificación:
        solo podía romperse.

    Se aplica siempre, también con `pool_discard_all` en false. Que el
    comportamiento del pool dependiera de esa bandera es justo el acoplamiento
    sutil que produce sorpresas: la bandera existe para probar que el
    aislamiento NO depende de ella, no para cambiar cómo habla psycopg.
    """
    conn.prepare_threshold = None


async def abrir_pool() -> AsyncConnectionPool:
    global _pool
    if _pool is not None:
        return _pool

    _pool = AsyncConnectionPool(
        conninfo=settings.database_url,
        min_size=settings.pool_min_size,
        max_size=settings.pool_max_size,
        timeout=settings.pool_timeout,
        max_lifetime=settings.pool_max_lifetime,
        max_idle=settings.pool_max_idle,
        # Descarta conexiones rotas ANTES de entregarlas al endpoint.
        check=AsyncConnectionPool.check_connection,
        configure=_configurar,
        reset=_reset,
        open=False,
    )
    await _pool.open(wait=True, timeout=settings.pool_timeout)
    log.info(
        "pool abierto min=%s max=%s discard_all=%s",
        settings.pool_min_size,
        settings.pool_max_size,
        settings.pool_discard_all,
    )
    return _pool


async def cerrar_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def obtener_pool() -> AsyncConnectionPool:
    if _pool is None:
        raise RuntimeError("El pool no está abierto. Falta llamar a abrir_pool().")
    return _pool



class RolInseguro(RuntimeError):
    """El rol de conexión puede saltarse RLS, o no es el rol previsto.

    Es una excepción propia y no un RuntimeError suelto para que main.py pueda
    distinguir este fallo de cualquier otro error de arranque: este NO se
    reintenta y NO se degrada a advertencia.

    El mensaje describe atributos del rol —nombre, si es superusuario, cuántas
    tablas posee— y nunca la cadena de conexión, que lleva la contraseña.
    """


# Comprueba si el rol actual puede saltarse RLS, CONSIDERANDO LA HERENCIA.
#
# Leer pg_roles.rolsuper y pg_roles.rolbypassrls del propio rol no basta: son
# atributos directos, y PostgreSQL decide si aplica RLS con
# has_bypassrls_privilege(), que sí tiene en cuenta la pertenencia a otros
# roles. Un rol NOSUPERUSER NOBYPASSRLS que sea miembro de uno que sí lo sea
# pasaría una comprobación ingenua y no tendría ninguna política aplicada.
#
# pg_has_role(..., 'USAGE') es lo que replica ese criterio: cubre la
# pertenencia directa, la transitiva y la que llega por INHERIT.
#
# Lo mismo con la propiedad de las tablas: el dueño ignora sus propias
# políticas salvo FORCE, y la propiedad también puede llegar por membresía.
_SQL_ROL = """
    SELECT current_user,
           EXISTS (SELECT 1 FROM pg_roles r
                    WHERE r.rolsuper
                      AND pg_has_role(current_user, r.oid, 'USAGE')),
           EXISTS (SELECT 1 FROM pg_roles r
                    WHERE r.rolbypassrls
                      AND pg_has_role(current_user, r.oid, 'USAGE')),
           (SELECT count(*) FROM pg_class c
             WHERE c.relkind = 'r'
               AND c.relnamespace = 'public'::regnamespace
               AND pg_has_role(current_user, c.relowner, 'USAGE'))
"""


async def verificar_rol_seguro() -> dict[str, object]:
    """Comprueba que el rol de conexión no puede saltarse RLS.

    Un rol con BYPASSRLS, superusuario, o propietario de las tablas sin FORCE,
    hace que RLS quede activa y no se aplique. Es un fallo silencioso: las
    políticas existen, se ven en el catálogo, y no protegen nada. No hay
    ninguna señal en tiempo de ejecución — las consultas simplemente devuelven
    filas de todos los laboratorios y nadie se entera.

    Dos comportamientos, según REQUIRE_RLS_SAFE_ROLE:

      false  → advierte y continúa. Es el entorno de trabajo de hoy: 0004 no
               está aplicado en ninguna base y el único rol es sacgeo_dev, que
               es superusuario. NO es una configuración válida en producción
               una vez que 0004 entre.

      true   → aborta el arranque. Se exige además que el rol sea EXACTAMENTE
               settings.rol_aplicacion: un rol que casualmente no sea
               superusuario no es lo mismo que el rol previsto, con sus GRANTs
               acotados.
    """
    pool = obtener_pool()
    async with pool.connection() as conn, conn.cursor() as cur:
        await cur.execute(_SQL_ROL)
        usuario, es_super, bypass, tablas_propias = await cur.fetchone()

    esperado = settings.rol_aplicacion
    nombre_ok = usuario == esperado

    informe = {
        "usuario": usuario,
        "rol_esperado": esperado,
        "superuser": es_super,
        "bypassrls": bypass,
        "tablas_propias": tablas_propias,
        # "seguro" es sólo sobre privilegios: es lo que decide si RLS se aplica.
        "seguro": not (es_super or bypass or tablas_propias > 0),
        # "conforme" añade el nombre: es lo que se exige en modo seguro.
        "conforme": not (es_super or bypass or tablas_propias > 0) and nombre_ok,
    }

    if informe["conforme"]:
        return informe

    motivos = []
    if es_super:
        motivos.append("es superusuario (directo o heredado)")
    if bypass:
        motivos.append("tiene BYPASSRLS (directo o heredado)")
    if tablas_propias > 0:
        motivos.append(
            f"posee {tablas_propias} tablas de public y puede ignorar sus políticas"
        )
    if not nombre_ok:
        motivos.append(f"no es el rol de aplicación previsto ('{esperado}')")

    # Sólo el nombre del rol y sus atributos. NUNCA settings.database_url, que
    # contiene la contraseña: este texto acaba en logs y en trazas de arranque.
    motivo = f"el rol '{usuario}' " + "; ".join(motivos)

    if settings.require_rls_safe_role:
        raise RolInseguro(f"Arranque abortado: {motivo}")

    log.warning(
        "AVISO DE SEGURIDAD: %s. Tolerado porque REQUIRE_RLS_SAFE_ROLE=false; "
        "deja de serlo en cuanto 0004 este aplicado.",
        motivo,
    )
    return informe
