"""Defecto D-3 — `DISCARD ALL` contra los prepared statements de psycopg3.

El fallo original, medido en la fase 7B:

    pool con reset = ROLLBACK + DISCARD ALL
      → psycopg prepara `SELECT set_config(%s, %s, true)` tras 5 ejecuciones
        → DISCARD ALL borra el statement DEL SERVIDOR
          → la caché de psycopg (del CLIENTE) sigue creyendo que existe
            → SQLSTATE 26000: prepared statement "_pg3_0" does not exist

`set_config` corre dos o tres veces por petición desde `db/tx.py`, así que el
umbral se alcanzaba en la CUARTA petición de cualquier endpoint autenticado.
No era un problema del catálogo: era un problema de todo endpoint que reutilice
una conexión del pool, latente desde que el pool existe.

Estos tests fijan las dos propiedades que la corrección debe sostener a la vez:
que ocho peticiones seguidas sobre la MISMA conexión no rompan, y que la
conexión siga volviendo al pool sin estado. Arreglar lo primero quitando
`DISCARD ALL` habría roto lo segundo.
"""

import psycopg
import pytest

from sacgeo.db import pool as pool_mod
from sacgeo.db.tx import leer_contexto, transaccion

# Muy por encima del umbral de psycopg (5). Con el defecto presente, el fallo
# aparecía en la vuelta 4; doce vueltas no dejan lugar a la casualidad.
VUELTAS = 12


@pytest.fixture
async def pool_de_una_conexion_real(bd_auth_desechable, url_app, monkeypatch):
    """Pool de UNA sola conexión contra el esquema real, como `sacgeo_app`.

    `max_size=1` es lo que hace la prueba concluyente: con varias conexiones,
    las peticiones se reparten y ninguna llegaría a acumular las ejecuciones
    necesarias para que psycopg preparase nada. La reutilización tiene que ser
    forzosa, no probable.
    """
    from sacgeo.config import settings

    monkeypatch.setattr(settings, "database_url", url_app)
    monkeypatch.setattr(settings, "pool_min_size", 1)
    monkeypatch.setattr(settings, "pool_max_size", 1)
    monkeypatch.setattr(pool_mod, "_pool", None)

    p = await pool_mod.abrir_pool()
    yield p
    await pool_mod.cerrar_pool()


async def test_d3_ocho_peticiones_seguidas_no_rompen(pool_de_una_conexion_real):
    """12 transacciones consecutivas sobre la MISMA conexión, sin 26000.

    Cada vuelta es una petición completa en lo que al pool respecta: abre
    transacción, fija los tres `set_config`, consulta, cierra, y la conexión
    vuelve al pool pasando por `DISCARD ALL`. Es exactamente la secuencia que
    fallaba.
    """
    for vuelta in range(1, VUELTAS + 1):
        try:
            async with transaccion(1, 1, "127.0.0.1") as conn:
                async with conn.cursor() as cur:
                    await cur.execute("SELECT count(*) FROM ensayos_catalogo")
                    await cur.fetchone()
        except psycopg.Error as e:
            pytest.fail(
                f"vuelta {vuelta}: SQLSTATE {e.sqlstate} — {e}. "
                "D-3 ha vuelto: el pool prepara sentencias que DISCARD ALL borra."
            )


async def test_d3_la_conexion_es_realmente_la_misma(pool_de_una_conexion_real):
    """La prueba anterior solo vale si la conexión se reutiliza de verdad.

    Con `max_size=1` debería serlo, pero conviene demostrarlo: si el pool
    estuviera descartando y recreando la conexión en cada vuelta —que es lo que
    ocurre cuando el reset falla—, no habría reutilización, psycopg no
    prepararía nada y el test anterior pasaría sin probar nada en absoluto.
    """
    vistos = set()
    for _ in range(VUELTAS):
        async with transaccion(1, 1) as conn:
            async with conn.cursor() as cur:
                await cur.execute("SELECT pg_backend_pid()")
                (pid,) = await cur.fetchone()
        vistos.add(pid)

    assert len(vistos) == 1, (
        f"el pool usó {len(vistos)} conexiones distintas: no se está reutilizando, "
        "así que el test de D-3 no demostraría nada"
    )


async def test_d3_no_se_prepara_ninguna_sentencia(pool_de_una_conexion_real):
    """La causa raíz, comprobada en el servidor y no por sus efectos.

    `pg_prepared_statements` lista lo que la sesión tiene preparado. Si la
    corrección se revirtiera, aquí habría al menos una fila después de repetir
    la misma consulta doce veces, y este test señalaría la causa directamente
    en vez de dejar que reaparezca como un 26000 intermitente en otro sitio.
    """
    for _ in range(VUELTAS):
        async with transaccion(1, 1) as conn:
            async with conn.cursor() as cur:
                await cur.execute("SELECT count(*) FROM ensayos_catalogo")
                await cur.fetchone()

    async with transaccion(1, 1) as conn:
        assert conn.prepare_threshold is None, (
            "la preparación automática está activa: D-3 puede reaparecer"
        )
        async with conn.cursor() as cur:
            await cur.execute("SELECT count(*) FROM pg_prepared_statements")
            (preparadas,) = await cur.fetchone()

    assert preparadas == 0, f"la sesión tiene {preparadas} sentencias preparadas"


async def test_d3_el_contexto_sigue_sin_contaminar(pool_de_una_conexion_real):
    """La corrección NO debilita el aislamiento entre peticiones.

    Es la mitad que se podría haber perdido "arreglando" D-3 por el camino
    fácil: quitar `DISCARD ALL` habría hecho desaparecer el 26000 y, con él, la
    red que impide que una conexión vuelva al pool con estado.

    Se comprueba con la MISMA conexión —max_size=1— y con tenants distintos en
    vueltas sucesivas: si algo sobreviviera, la segunda vuelta vería el tenant
    de la primera.
    """
    for tenant, usuario in ((1, 1), (1, 2), (1, 1)):
        async with transaccion(tenant, usuario, "10.0.0.1") as conn:
            dentro = await leer_contexto(conn)
            assert dentro["tenant_id"] == str(tenant)
            assert dentro["usuario_id"] == str(usuario)

        # Fuera de la transacción, con la conexión ya devuelta al pool.
        pool = pool_mod.obtener_pool()
        async with pool.connection() as conn:
            fuera = await leer_contexto(conn)

        assert fuera["tenant_id"] in (None, ""), fuera
        assert fuera["usuario_id"] in (None, ""), fuera
        assert fuera["ip_origen"] in (None, ""), fuera
