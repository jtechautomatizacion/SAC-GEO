"""La cadena de dependencias completa, contra PostgreSQL con RLS forzada.

Los tests unitarios de este backend prueban cada pieza por separado: el JWT, el
hash, la resolución de sesión, el aislamiento del pool. Ninguno prueba que
encajen. Este archivo recorre el camino real —POST /auth/login, luego
GET /auth/yo con el token— sobre la base desechable y conectado como
`sacgeo_app`, que es el rol con el que corre la API de verdad.

Importa especialmente después de la fase 4A-SEXIES, porque el orden de las
dependencias cambió: `get_current_user` ya no resuelve la identidad por su
cuenta, depende de la transacción. Un error en ese reordenamiento no lo detecta
ningún test unitario; se vería como un 500 al primer despliegue.
"""

import httpx
import pytest

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"


@pytest.fixture
async def cliente(url_app, usuarios_prueba, monkeypatch):
    """Arranca la app apuntando a la base desechable, como `sacgeo_app`."""
    from sacgeo.config import settings
    from sacgeo.db import pool as pool_mod

    monkeypatch.setattr(settings, "database_url", url_app)
    monkeypatch.setattr(pool_mod, "_pool", None)
    # Con `sacgeo_app` el rol YA es seguro: ni superusuario, ni BYPASSRLS, ni
    # dueño de tablas. Se exige de verdad, en vez de dejarlo en advertencia.
    monkeypatch.setattr(settings, "require_rls_safe_role", True)

    from sacgeo.main import app

    async with app.router.lifespan_context(app):
        transporte = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transporte, base_url="http://pruebas"
        ) as c:
            yield c
    await pool_mod.cerrar_pool()


async def test_login_y_yo(cliente):
    """El camino feliz completo: credenciales → token → identidad.

    Que `/auth/yo` devuelva el email es la prueba de que se leyó DENTRO de la
    transacción con el contexto fijado: sin contexto, la política de `usuarios`
    habría dado 42501 y la respuesta sería 500, no 200.
    """
    r = await cliente.post(
        "/auth/login", json={"email": "activo@lab.test", "password": PASSWORD_PRUEBA}
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]

    r = await cliente.get("/auth/yo", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200, r.text
    cuerpo = r.json()
    assert cuerpo["email"] == "activo@lab.test"
    assert cuerpo["tenant_id"] == 1
    # La respuesta no lleva nada más que identidad: ni rol, ni permisos, ni hash.
    assert set(cuerpo) == {"public_id", "email", "tenant_id"}


async def test_yo_sin_token(cliente):
    r = await cliente.get("/auth/yo")
    assert r.status_code == 401


async def test_yo_con_token_basura(cliente):
    r = await cliente.get("/auth/yo", headers={"Authorization": "Bearer no-es-un-jwt"})
    assert r.status_code == 401


async def test_login_de_usuario_inactivo(cliente):
    r = await cliente.post(
        "/auth/login", json={"email": "inactivo@lab.test", "password": PASSWORD_PRUEBA}
    )
    assert r.status_code == 401


async def test_login_del_usuario_sistema(cliente):
    """`sistema` no entra por la puerta principal aunque exista en la tabla."""
    r = await cliente.post(
        "/auth/login",
        json={"email": "sistema@gtqc.local", "password": PASSWORD_PRUEBA},
    )
    assert r.status_code == 401


async def test_el_rol_de_la_api_no_puede_saltarse_rls(cliente):
    """`sacgeo_app` no es superusuario, no tiene BYPASSRLS y no posee tablas.

    Si cualquiera de las tres fuera falsa, las políticas existirían en el
    catálogo y no protegerían nada — el modo de fallo más silencioso de RLS.
    Con require_rls_safe_role activo, el arranque habría abortado y este test
    no llegaría siquiera a ejecutarse.
    """
    from sacgeo.db.pool import verificar_rol_seguro

    informe = await verificar_rol_seguro()
    assert informe["usuario"] == "sacgeo_app"
    assert informe["superuser"] is False
    assert informe["bypassrls"] is False
    assert informe["tablas_propias"] == 0
    assert informe["seguro"] is True
