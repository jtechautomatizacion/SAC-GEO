"""Fail-closed del modo RLS seguro (fase 4A-SEXIES-BIS).

RLS tiene un modo de fallo peculiar: si el rol de conexión puede saltársela, las
políticas siguen existiendo, se ven en `pg_policies`, y no protegen nada. No hay
excepción, no hay log, no hay latencia rara. Las consultas simplemente devuelven
filas de todos los laboratorios.

Eso significa que no existe ninguna prueba en tiempo de ejecución que lo delate:
el único momento en que se puede detectar es el arranque. De ahí que con
REQUIRE_RLS_SAFE_ROLE=true la comprobación ABORTE en vez de advertir.

Los roles de estos tests se crean de verdad en el clúster y se eliminan al
terminar. Se prueba contra PostgreSQL y no contra un doble porque lo que se
está verificando es cómo responde `pg_has_role`, no cómo responde un mock.
"""

import pytest

from sacgeo.db import pool as pool_mod
from sacgeo.db.pool import RolInseguro, verificar_rol_seguro


async def _informe(monkeypatch, url, *, seguro: bool, rol_esperado="sacgeo_app"):
    """Abre un pool contra `url` y ejecuta la comprobación de rol."""
    from sacgeo.config import settings

    monkeypatch.setattr(settings, "database_url", url)
    monkeypatch.setattr(settings, "require_rls_safe_role", seguro)
    monkeypatch.setattr(settings, "rol_aplicacion", rol_esperado)
    monkeypatch.setattr(settings, "pool_min_size", 1)
    monkeypatch.setattr(settings, "pool_max_size", 1)
    monkeypatch.setattr(pool_mod, "_pool", None)

    await pool_mod.abrir_pool()
    try:
        return await verificar_rol_seguro()
    finally:
        await pool_mod.cerrar_pool()


# --- TEST 1 · modo permisivo ------------------------------------------------

async def test_1_modo_permisivo_advierte_y_continua(monkeypatch, url_super, caplog):
    """REQUIRE_RLS_SAFE_ROLE=false: sigue adelante con un rol inseguro.

    Es el comportamiento del entorno de trabajo de hoy y se conserva a
    propósito: 0004 no está aplicado en ninguna base y el único rol del clúster
    es sacgeo_dev, que es superusuario. Exigir el modo seguro ahora dejaría el
    backend sin arrancar.

    Lo que se comprueba es que NO pasa en silencio: queda un aviso en el log.
    """
    with caplog.at_level("WARNING"):
        informe = await _informe(monkeypatch, url_super, seguro=False)

    assert informe["seguro"] is False
    assert informe["conforme"] is False
    assert "AVISO DE SEGURIDAD" in caplog.text


# --- TEST 2 · rol correcto --------------------------------------------------

async def test_2_rol_de_aplicacion_pasa(monkeypatch, url_app):
    """sacgeo_app en modo seguro: arranca.

    Sin superusuario, sin BYPASSRLS, sin tablas propias y con el nombre
    previsto. Si este test fallara, el modo seguro sería inservible: no habría
    ninguna configuración con la que la API pudiera arrancar.
    """
    informe = await _informe(monkeypatch, url_app, seguro=True)

    assert informe["usuario"] == "sacgeo_app"
    assert informe["rol_esperado"] == "sacgeo_app"
    assert informe["superuser"] is False
    assert informe["bypassrls"] is False
    assert informe["tablas_propias"] == 0
    assert informe["seguro"] is True
    assert informe["conforme"] is True


# --- TEST 3-5 · fail-closed -------------------------------------------------

async def test_3_superusuario_no_arranca(monkeypatch, roles_modo_seguro):
    """Un rol SUPERUSER aborta el arranque.

    El superusuario ignora RLS por completo: `check_enable_rls` ni llega a
    consultar las políticas.
    """
    with pytest.raises(RolInseguro) as e:
        await _informe(monkeypatch, roles_modo_seguro["sacgeo_t_super"], seguro=True)
    assert "superusuario" in str(e.value)


async def test_4_bypassrls_no_arranca(monkeypatch, roles_modo_seguro):
    """Un rol con BYPASSRLS aborta el arranque, aunque NO sea superusuario.

    Es el caso más peligroso de los tres porque parece inofensivo: el rol no es
    superusuario, no posee nada, y aun así ninguna política se le aplica.
    """
    with pytest.raises(RolInseguro) as e:
        await _informe(monkeypatch, roles_modo_seguro["sacgeo_t_bypass"], seguro=True)
    assert "BYPASSRLS" in str(e.value)
    assert "superusuario" not in str(e.value)


async def test_5_rol_distinto_no_arranca(monkeypatch, roles_modo_seguro):
    """Un rol sano en privilegios pero que NO es sacgeo_app aborta el arranque.

    No es purismo. `sacgeo_app` no se define sólo por lo que NO puede hacer:
    0004 le da un conjunto acotado de GRANTs, le niega DELETE sobre `usuarios`
    y le niega todo sobre `schema_migrations`. Otro rol cualquiera pasaría el
    control de privilegios y operaría con permisos que nadie diseñó.
    """
    with pytest.raises(RolInseguro) as e:
        await _informe(monkeypatch, roles_modo_seguro["sacgeo_t_otro"], seguro=True)
    msg = str(e.value)
    assert "sacgeo_t_otro" in msg
    assert "rol de aplicación previsto" in msg
    # Falla SÓLO por el nombre: los tres controles de privilegio los pasa.
    assert "superusuario" not in msg
    assert "BYPASSRLS" not in msg


async def test_5b_el_rol_esperado_es_configurable(monkeypatch, roles_modo_seguro):
    """Cambiando ROL_APLICACION, ese mismo rol pasa.

    Confirma que el test 5 falla por la comparación de nombre y no por otra
    propiedad del rol que se hubiera colado sin darnos cuenta.
    """
    informe = await _informe(
        monkeypatch,
        roles_modo_seguro["sacgeo_t_otro"],
        seguro=True,
        rol_esperado="sacgeo_t_otro",
    )
    assert informe["conforme"] is True


# --- TEST 6 · el error no filtra nada ---------------------------------------

async def test_6_el_error_no_expone_credenciales(monkeypatch, roles_modo_seguro, caplog):
    """El mensaje de aborto no contiene la contraseña, el host ni el DSN.

    Este texto acaba en el log de arranque, en el stderr del contenedor y en
    cualquier recolector de trazas. Es uno de los sitios por los que una cadena
    de conexión se filtra sin que nadie la haya impreso a propósito.
    """
    url = roles_modo_seguro["sacgeo_t_bypass"]
    # De postgresql://usuario:CLAVE@host:puerto/base
    clave = url.split("://", 1)[1].split("@", 1)[0].split(":", 1)[1]
    assert len(clave) > 10

    with caplog.at_level("DEBUG"):
        with pytest.raises(RolInseguro) as e:
            await _informe(monkeypatch, url, seguro=True)

    for texto in (str(e.value), caplog.text):
        assert clave not in texto
        assert url not in texto
        assert "postgresql://" not in texto
        assert "password" not in texto.lower()


async def test_6b_el_informe_no_lleva_el_dsn(monkeypatch, url_app):
    """Tampoco el informe que main.py escribe en el log al arrancar bien."""
    from sacgeo.config import settings

    informe = await _informe(monkeypatch, url_app, seguro=True)
    assert set(informe) == {
        "usuario", "rol_esperado", "superuser", "bypassrls",
        "tablas_propias", "seguro", "conforme",
    }
    assert "postgresql://" not in str(informe)
    assert settings.jwt_secret not in str(informe)


# --- La app no llega a servir peticiones ------------------------------------

async def test_la_app_no_arranca_con_rol_inseguro(monkeypatch, roles_modo_seguro):
    """El fail-closed corta el ciclo de vida, no sólo la función suelta.

    Comprobar `verificar_rol_seguro()` por separado no basta: si main.py
    capturara la excepción, la API arrancaría igual y los tests 3-5 estarían
    midiendo algo que no protege nada.
    """
    from sacgeo.config import settings

    monkeypatch.setattr(settings, "database_url", roles_modo_seguro["sacgeo_t_super"])
    monkeypatch.setattr(settings, "require_rls_safe_role", True)
    monkeypatch.setattr(pool_mod, "_pool", None)

    from sacgeo.main import app

    with pytest.raises(RolInseguro):
        async with app.router.lifespan_context(app):
            pytest.fail("la app arrancó con un rol superusuario en modo seguro")

    # Y el pool no se queda abierto detrás de un arranque abortado.
    assert pool_mod._pool is None
