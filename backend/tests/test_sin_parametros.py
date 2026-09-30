"""Fase 7F — ningún endpoint ignora en silencio lo que no entiende.

`extra="forbid"` solo actúa cuando hay un modelo Pydantic de query. Un endpoint
que no declaraba ninguno descartaba sin avisar cualquier parámetro: `?tenant_id=2`
devolvía 200 y el cliente podía creer que había consultado otro laboratorio
mientras recibía el suyo.

**No era un fallo de aislamiento** —el tenant siempre salió del contexto, y el
parámetro no llegaba a ninguna consulta— pero el silencio esconde el intento.
Se detectó en 7D.1 sobre un endpoint; esta suite fija la propiedad para TODOS,
incluidos los que aparezcan mañana.
"""

import httpx
import pytest

from sacgeo.config import settings

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"

# Rutas sin parámetros de consulta legítimos. Cada una debe responder 422 a
# cualquier query, no 200.
UUID_CUALQUIERA = "00000000-0000-4000-8000-000000000000"

RUTAS_SIN_PARAMETROS = [
    "/salud",
    "/auth/yo",
    f"/api/v1/catalogo/{UUID_CUALQUIERA}",
    f"/api/v1/categorias/{UUID_CUALQUIERA}",
    f"/api/v1/catalogo/{UUID_CUALQUIERA}/acreditacion",
    f"/api/v1/catalogo/{UUID_CUALQUIERA}/componentes",
    f"/api/v1/clientes/empresas/{UUID_CUALQUIERA}",
    f"/api/v1/clientes/personas/{UUID_CUALQUIERA}",
    f"/api/v1/clientes/contactos/{UUID_CUALQUIERA}",
    f"/api/v1/usuarios/{UUID_CUALQUIERA}",
    f"/api/v1/plantillas/{UUID_CUALQUIERA}",
]

# Lo que un cliente podría probar. `tenant_id` es el que importa.
PARAMETROS_INTRUSOS = [
    {"tenant_id": 2},
    {"order_by": "id"},
    {"limite": 9999},
    {"admin": "true"},
]


@pytest.fixture
async def cliente(url_app, usuarios_rbac, admin_prueba, monkeypatch):
    from sacgeo.db import pool as pool_mod

    monkeypatch.setattr(settings, "database_url", url_app)
    monkeypatch.setattr(pool_mod, "_pool", None)
    monkeypatch.setattr(settings, "require_rls_safe_role", True)

    from sacgeo.main import app

    async with app.router.lifespan_context(app):
        transporte = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transporte, base_url="http://pruebas") as c:
            yield c
    await pool_mod.cerrar_pool()


async def _token(cliente, email: str) -> str:
    r = await cliente.post("/auth/login", json={"email": email, "password": PASSWORD_PRUEBA})
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


@pytest.mark.parametrize("ruta", RUTAS_SIN_PARAMETROS)
async def test_parametro_intruso_da_422(cliente, usuarios_rbac, admin_prueba, ruta):
    """Un parámetro desconocido se rechaza, no se descarta.

    El 422 llega antes que el 404 del UUID inexistente, pero DESPUÉS del 403 de
    RBAC — y ese orden es el correcto: quien no tiene el permiso no debe
    aprender nada del contrato, ni siquiera qué parámetros existen. Por eso cada
    ruta se prueba con un usuario que SÍ puede entrar: `/usuarios` con el
    administrador, el resto con el lector.
    """
    email = admin_prueba["email"] if "/usuarios" in ruta else usuarios_rbac["lector_email"]
    t = await _token(cliente, email)
    cab = {"Authorization": f"Bearer {t}"}

    for params in PARAMETROS_INTRUSOS:
        r = await cliente.get(ruta, headers=cab, params=params)
        assert r.status_code == 422, (
            f"{ruta} con {params} devolvió {r.status_code}: se ignoró en silencio"
        )


@pytest.mark.parametrize("ruta", RUTAS_SIN_PARAMETROS)
async def test_sin_parametros_el_endpoint_sigue_funcionando(cliente, usuarios_rbac, ruta):  # noqa: E501
    """La corrección no rompe la ruta: sin query responde lo que corresponda.

    Un 422 universal —incluso sin parámetros— sería una regresión peor que el
    problema que se arregla. Aquí se acepta cualquier código que NO sea 422.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(ruta, headers={"Authorization": f"Bearer {t}"})
    assert r.status_code != 422, f"{ruta} rechaza incluso una petición sin parámetros"
    # 403 es legítimo en `/usuarios`: el rol `lectura` no tiene usuarios.read.
    # Lo que se comprueba aquí es que NO sea 422.
    assert r.status_code in (200, 403, 404), f"{ruta} devolvió {r.status_code}: {r.text}"


async def test_el_422_no_filtra_informacion(cliente, usuarios_rbac):
    """El rechazo no revela si el recurso existe ni nada del esquema."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    cab = {"Authorization": f"Bearer {t}"}

    r = await cliente.get(f"/api/v1/catalogo/{UUID_CUALQUIERA}", headers=cab,
                          params={"tenant_id": 2})
    assert r.status_code == 422
    crudo = r.text.lower()
    for prohibido in ("select", "from ", "postgres", "psycopg", "traceback",
                      "password", "sqlstate", "ensayos_catalogo"):
        assert prohibido not in crudo, f"el 422 filtró {prohibido!r}"


async def test_sin_autenticacion_el_401_manda(cliente):
    """Sin token, el 401 llega antes que el 422: no se filtra el contrato."""
    for ruta in RUTAS_SIN_PARAMETROS:
        if ruta == "/salud":
            continue  # público a propósito
        r = await cliente.get(ruta, params={"tenant_id": 2})
        assert r.status_code == 401, f"{ruta} devolvió {r.status_code} sin token"


async def test_ninguna_ruta_nueva_queda_sin_modelo_de_query(cliente):
    """Guarda contra la reaparición del problema.

    Recorre el esquema OpenAPI y comprueba que toda ruta de `/api/v1` está en
    una de las TRES categorías de contrato. Una ruta nueva que no declare el
    suyo aparece aquí y no en producción — es lo que pasó con
    `/clientes/contactos` al añadirlo en 7I.1, y por eso hay una tercera
    categoría en vez de un parche.
    """
    esquema = (await cliente.get("/openapi.json")).json()

    colecciones_con_filtros = {
        "/api/v1/catalogo",
        "/api/v1/categorias",
        "/api/v1/clientes/empresas",
        "/api/v1/clientes/personas",
        "/api/v1/clientes/empresas/{public_id}/contactos",
        "/api/v1/usuarios",
        "/api/v1/plantillas",
    }
    # Rutas de ESCRITURA: su contrato lo gobierna el DTO del cuerpo, no la
    # query. `/clientes/empresas` no está aquí porque comparte ruta con su GET
    # de colección, que ya declara filtros.
    #
    # De estas se exige algo distinto y más estricto: que NO declaren ningún
    # parámetro de consulta. Un POST con query params mezclaría dos contratos y
    # necesitaría su propio modelo para no volver a ignorar lo desconocido.
    escrituras = {
        "/api/v1/clientes/contactos",
    }
    sin_parametros = {
        "/api/v1/catalogo/{public_id}",
        "/api/v1/categorias/{public_id}",
        "/api/v1/catalogo/{public_id}/acreditacion",
        "/api/v1/catalogo/{public_id}/componentes",
        "/api/v1/clientes/empresas/{public_id}",
        "/api/v1/clientes/personas/{public_id}",
        "/api/v1/clientes/contactos/{public_id}",
        "/api/v1/usuarios/{public_id}",
        "/api/v1/plantillas/{public_id}",
    }

    declaradas = colecciones_con_filtros | escrituras | sin_parametros
    rutas_v1 = {r for r in esquema["paths"] if r.startswith("/api/v1")}

    assert rutas_v1 == declaradas, (
        "hay rutas /api/v1 sin contrato de query declarado en este test: "
        f"{rutas_v1 - declaradas}"
    )

    # Las de detalle: ningún parámetro salvo el del path. `SinParametros` no
    # debe añadir nada al esquema.
    for ruta in sin_parametros:
        params = esquema["paths"][ruta]["get"].get("parameters", [])
        nombres = {p["name"] for p in params}
        assert nombres == {"public_id"}, f"{ruta} declara {nombres}"

    # Las de escritura: NINGÚN parámetro de consulta. Su contrato es el cuerpo.
    for ruta in escrituras:
        for metodo, operacion in esquema["paths"][ruta].items():
            nombres = {p["name"] for p in operacion.get("parameters", [])}
            assert not nombres, f"{metodo.upper()} {ruta} declara query: {nombres}"
