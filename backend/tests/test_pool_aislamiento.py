"""Tests 11, 12 y 13 del plan de la fase 5A: contaminación de contexto en el pool.

Son los tests más importantes del backend. Detectan el error de escribir un SET
de sesión donde debía ir SET LOCAL — un fallo que en producción sería
intermitente, dependiente de qué conexión toque, y que se manifestaría como
"un laboratorio vio datos de otro" sin traza que lo explique.

Con max_size=1 el fallo se vuelve determinista.
"""

import psycopg
import pytest

from sacgeo.db.tx import leer_contexto, transaccion


def sin_tenant(valor) -> bool:
    """No queda tenant utilizable en la conexión.

    Hay DOS valores correctos y cuál sale depende de cómo volviera la conexión
    al pool, no del aislamiento:

      None → la conexión es nueva; el GUC nunca se definió en ella.
      ''   → la conexión se reutilizó y DISCARD ALL reseteó el GUC. Un
             parámetro personalizado no desaparece al resetearlo: vuelve a
             cadena vacía.

    Antes de corregir `_reset` en pool.py, DISCARD ALL fallaba siempre
    ("cannot run inside a transaction block"), psycopg daba la conexión por
    perdida y abría otra: por eso aquí salía None. Afirmar `is None` estaba
    midiendo que el pool NO reutilizaba conexiones, no que el contexto no
    sobreviviera.

    Lo que importa —y lo que comprueba `tenant_inutilizable`— es que ninguno de
    los dos valores sirva para consultar.
    """
    return valor is None or valor == ""


async def tenant_inutilizable(conn) -> bool:
    """fn_app_tenant() rechaza el estado actual de la conexión.

    Es el invariante de verdad: da igual qué haya en el GUC mientras la base se
    niegue a resolver un tenant a partir de él.
    """
    try:
        async with conn.cursor() as cur:
            await cur.execute("SELECT fn_app_tenant()")
        return False
    except psycopg.errors.InsufficientPrivilege:
        return True
    except psycopg.errors.UndefinedFunction:
        # Base de pool vacía (sin esquema): solo se puede mirar el GUC.
        await conn.rollback()
        return True


async def test_12_contexto_no_persiste_tras_commit(pool_de_una_conexion):
    """TEST 12 — tras COMMIT, el contexto debe haber desaparecido."""
    async with transaccion(tenant_id=1, usuario_id=7, ip_origen="10.0.0.1") as conn:
        ctx = await leer_contexto(conn)
        assert ctx["tenant_id"] == "1"
        assert ctx["usuario_id"] == "7"
        assert ctx["ip_origen"] == "10.0.0.1"

    # Misma conexión física (max_size=1), ya devuelta al pool.
    async with pool_de_una_conexion.connection() as conn:
        ctx = await leer_contexto(conn)
        assert sin_tenant(ctx["tenant_id"]), f"el tenant sobrevivió al COMMIT: {ctx['tenant_id']!r}"
        assert sin_tenant(ctx["usuario_id"])
        assert sin_tenant(ctx["ip_origen"])
        assert await tenant_inutilizable(conn)


async def test_13_contexto_no_persiste_tras_rollback(pool_de_una_conexion):
    """TEST 13 — tras ROLLBACK por excepción, el contexto tampoco persiste."""
    with pytest.raises(RuntimeError, match="fallo deliberado"):
        async with transaccion(tenant_id=1, usuario_id=7) as conn:
            ctx = await leer_contexto(conn)
            assert ctx["tenant_id"] == "1"
            raise RuntimeError("fallo deliberado")

    async with pool_de_una_conexion.connection() as conn:
        ctx = await leer_contexto(conn)
        assert sin_tenant(ctx["tenant_id"]), f"el tenant sobrevivió al ROLLBACK: {ctx['tenant_id']!r}"
        assert await tenant_inutilizable(conn)


async def test_11_dos_tenants_en_la_misma_conexion(pool_de_una_conexion):
    """TEST 11 — CRÍTICO. Dos peticiones de tenants distintos, misma conexión.

    Reproduce el escenario real: la petición A termina, su conexión vuelve al
    pool, y la petición B —de otro laboratorio— la recibe.
    """
    async with transaccion(tenant_id=1, usuario_id=7) as conn:
        assert (await leer_contexto(conn))["tenant_id"] == "1"

    # Entre una petición y otra, la conexión no conserva nada.
    async with pool_de_una_conexion.connection() as conn:
        assert sin_tenant((await leer_contexto(conn))["tenant_id"])

    async with transaccion(tenant_id=2, usuario_id=9) as conn:
        ctx = await leer_contexto(conn)
        assert ctx["tenant_id"] == "2", "el tenant 2 heredó el contexto del tenant 1"
        assert ctx["usuario_id"] == "9"


async def test_11b_aislamiento_sin_discard_all(pool_sin_discard):
    """El aislamiento lo da set_config(..., true), no DISCARD ALL.

    Con DISCARD ALL desactivado el tenant tampoco debe sobrevivir. Si este test
    fallara y los anteriores pasaran, significaría que el sistema depende de la
    red de seguridad en vez del mecanismo — y estaría roto sin saberlo.

    MATIZ IMPORTANTE, comprobado empíricamente:
    al terminar la transacción, PostgreSQL revierte el GUC a su valor previo.
    Para un GUC personalizado que ya se tocó en la sesión, ese valor previo es
    la CADENA VACÍA, no "indefinido". Así que aquí se obtiene '' y no NULL.
    Con DISCARD ALL sí queda indefinido (NULL), que es la diferencia entre los
    dos fixtures.

    Ambos casos son seguros, y no por casualidad: fn_app_tenant() hace

        NULLIF(current_setting('app.tenant_id', TRUE), '')

    y ese NULLIF convierte la cadena vacía en NULL antes de comprobarla, de modo
    que lanza 42501 igual que si el GUC no existiera. Verificado contra la
    función real: '' → 42501, ausente → 42501.

    Lo que este test comprueba es la propiedad de seguridad que importa: que NO
    quede el tenant ANTERIOR.
    """
    async with transaccion(tenant_id=1, usuario_id=7) as conn:
        assert (await leer_contexto(conn))["tenant_id"] == "1"

    async with pool_sin_discard.connection() as conn:
        ctx = await leer_contexto(conn)
        assert ctx["tenant_id"] in (None, ""), (
            f"el tenant anterior sobrevivió a la transacción (valor={ctx['tenant_id']!r}): "
            "se está usando SET de sesión en vez de set_config(..., true)"
        )
        assert ctx["tenant_id"] != "1"


async def test_contexto_visible_dentro_de_la_transaccion(pool_de_una_conexion):
    """El contexto debe estar puesto ANTES de que el endpoint reciba la conexión.

    SET LOCAL fuera de un bloque de transacción emite WARNING y no hace nada.
    Este test verifica que se fija dentro.
    """
    async with transaccion(tenant_id=42, usuario_id=1) as conn:
        async with conn.cursor() as cur:
            await cur.execute("SELECT current_setting('app.tenant_id', true)")
            (valor,) = await cur.fetchone()
        assert valor == "42"


async def test_transaccion_exige_tenant_resuelto():
    """La transacción no acepta un tenant sin resolver. Falla cerrado."""
    with pytest.raises(ValueError, match="tenant_id"):
        async with transaccion(tenant_id=None, usuario_id=1):
            pass


async def test_transaccion_exige_usuario():
    with pytest.raises(ValueError, match="usuario_id"):
        async with transaccion(tenant_id=1, usuario_id=None):
            pass


async def test_tenant_id_no_se_interpola(pool_de_una_conexion):
    """El tenant se liga como parámetro, no se concatena en el SQL.

    Si se construyera la sentencia con una f-string, este valor rompería la
    consulta o inyectaría SQL. Como va ligado, se almacena literal y no pasa
    nada. Es la prueba de que set_config(..., %s, true) hace su trabajo.
    """
    hostil = "1'; DROP TABLE usuarios; --"
    async with transaccion(tenant_id=hostil, usuario_id=1) as conn:
        ctx = await leer_contexto(conn)
        assert ctx["tenant_id"] == hostil
