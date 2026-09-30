"""Fase 7F — clientes (empresas, contactos, personas), solo lectura.

Primer dominio con tres entidades relacionadas, y primero con **ordenación
elegida por el cliente**. Esas dos cosas son las que esta suite vigila de cerca:

  · que un contacto no pueda aparecer bajo la empresa de otro laboratorio;
  · que `orden` y `direccion` no lleguen nunca al SQL, ni saneados. Llegan como
    clave de un diccionario de consultas ya escritas, y cualquier otro valor
    muere en Pydantic con 422.

El caso feliz ocupa unos pocos tests. El resto comprueba que no funciona cuando
no debe.
"""

from datetime import UTC, datetime, timedelta

import httpx
import jwt as pyjwt
import psycopg
import pytest

from sacgeo.config import settings

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"
EMPRESAS = "/api/v1/clientes/empresas"
PERSONAS = "/api/v1/clientes/personas"
CONTACTOS = "/api/v1/clientes/contactos"
INEXISTENTE = "00000000-0000-4000-8000-000000000000"


@pytest.fixture
async def cliente(url_app, usuarios_rbac, usuarios_catalogo,
                  usuarios_permisos_separados, clientes_tenant_1,
                  clientes_tenant_2, monkeypatch):
    """La app real como `sacgeo_app`: sin superusuario y sin BYPASSRLS."""
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


def _cab(t: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {t}"}


RUTAS = [EMPRESAS, PERSONAS, f"{EMPRESAS}/{INEXISTENTE}",
         f"{PERSONAS}/{INEXISTENTE}", f"{CONTACTOS}/{INEXISTENTE}",
         f"{EMPRESAS}/{INEXISTENTE}/contactos"]


# ================================================================= AUTH =====

@pytest.mark.parametrize("ruta", RUTAS)
async def test_auth_sin_jwt(cliente, ruta):
    assert (await cliente.get(ruta)).status_code == 401


async def test_auth_jwt_malformado(cliente):
    assert (await cliente.get(EMPRESAS, headers=_cab("basura"))).status_code == 401


async def test_auth_jwt_expirado(cliente):
    pasado = datetime.now(UTC) - timedelta(hours=2)
    token = pyjwt.encode(
        {"sub": INEXISTENTE, "jti": "x", "iat": int(pasado.timestamp()),
         "exp": int((pasado + timedelta(minutes=1)).timestamp())},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo)
    assert (await cliente.get(EMPRESAS, headers=_cab(token))).status_code == 401


async def test_auth_usuario_desactivado(cliente, usuarios_prueba, url_super):
    """El estado se consulta en CADA petición, no se lee del token."""
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE id = %s",
                    (usuarios_prueba["inactivo"],))
        (public_id,) = cur.fetchone()

    from sacgeo.security import jwt as jwt_mod
    token, _, _ = jwt_mod.emitir_access_token(str(public_id))
    assert (await cliente.get(EMPRESAS, headers=_cab(token))).status_code == 401


async def test_auth_jwt_con_permisos_inyectados(cliente, usuarios_rbac, url_super):
    """Token bien FIRMADO con un claim `permissions` añadido → 401."""
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE email = %s",
                    (usuarios_rbac["lector_email"],))
        (public_id,) = cur.fetchone()

    ahora = datetime.now(UTC)
    token = pyjwt.encode(
        {"sub": str(public_id), "jti": "c", "iat": int(ahora.timestamp()),
         "exp": int((ahora + timedelta(minutes=15)).timestamp()),
         "permissions": ["clientes.read"]},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo)
    assert (await cliente.get(EMPRESAS, headers=_cab(token))).status_code == 401


# ================================================================= RBAC =====

async def test_rbac_con_clientes_read(cliente, usuarios_rbac):
    """El rol `lectura` tiene clientes.read."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(EMPRESAS, headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["total"] > 0


async def test_rbac_sin_ningun_rol(cliente, usuarios_catalogo):
    t = await _token(cliente, usuarios_catalogo["sin_roles_email"])
    for ruta in RUTAS:
        assert (await cliente.get(ruta, headers=_cab(t))).status_code == 403, ruta


async def test_rbac_rol_con_otro_permiso(cliente, usuarios_catalogo):
    """`dashboard.read` no abre clientes."""
    t = await _token(cliente, usuarios_catalogo["solo_dash_email"])
    assert (await cliente.get(EMPRESAS, headers=_cab(t))).status_code == 403


async def test_rbac_catalogo_read_no_abre_clientes(cliente, usuarios_permisos_separados):
    """`catalogo.read` NO sustituye a `clientes.read`: son permisos distintos.

    Es el test que atrapa el error de copiar el router de al lado. El usuario
    tiene un permiso real del sistema y aun así no entra.
    """
    t = await _token(cliente, usuarios_permisos_separados["solo_catalogo_email"])
    for ruta in RUTAS:
        assert (await cliente.get(ruta, headers=_cab(t))).status_code == 403, ruta


async def test_rbac_acreditacion_read_no_abre_clientes(cliente,
                                                       usuarios_permisos_separados):
    t = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    assert (await cliente.get(EMPRESAS, headers=_cab(t))).status_code == 403


# =============================================================== TENANT =====

async def test_tenant_solo_lo_propio(cliente, usuarios_rbac, url_super):
    """El total coincide con lo del laboratorio, calculado en la base."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(EMPRESAS, headers=_cab(t),
                          params={"solo_activas": False, "limite": 200})
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM empresas WHERE tenant_id = 1")
        (esperado,) = cur.fetchone()
    assert r.json()["total"] == esperado


async def test_tenant_la_empresa_ajena_no_aparece(cliente, usuarios_rbac,
                                                  clientes_tenant_2):
    """Ni por listado ni buscándola por su RUC exacto."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(EMPRESAS, headers=_cab(t),
                          params={"solo_activas": False, "limite": 200})
    ids = {e["public_id"] for e in r.json()["items"]}
    assert clientes_tenant_2["empresa_public_id"] not in ids

    buscada = await cliente.get(EMPRESAS, headers=_cab(t),
                                params={"q": clientes_tenant_2["empresa_ruc"]})
    assert buscada.json()["total"] == 0, "se filtró la cartera del otro laboratorio"


@pytest.mark.parametrize("recurso", ["empresa", "contacto", "persona"])
async def test_tenant_public_id_ajeno_da_404(cliente, usuarios_rbac,
                                             clientes_tenant_2, recurso):
    """Recurso de otro laboratorio: 404, NUNCA 403."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    rutas = {
        "empresa": f"{EMPRESAS}/{clientes_tenant_2['empresa_public_id']}",
        "contacto": f"{CONTACTOS}/{clientes_tenant_2['contacto_public_id']}",
        "persona": f"{PERSONAS}/{clientes_tenant_2['persona_public_id']}",
    }
    r = await cliente.get(rutas[recurso], headers=_cab(t))
    assert r.status_code == 404, r.text
    assert r.status_code != 403, "confirmó la existencia de un recurso ajeno"


async def test_tenant_el_dueno_si_lo_ve(cliente, usuarios_rbac, clientes_tenant_2,
                                        asignar_rol):
    """Prueba que los 404 anteriores los causa RLS y no un UUID muerto.

    `ajeno` es `comercial` en el tenant 2, y `comercial` tiene `clientes.read`.
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.get(f"{EMPRESAS}/{clientes_tenant_2['empresa_public_id']}",
                          headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["ruc"] == clientes_tenant_2["empresa_ruc"]

    c = await cliente.get(f"{CONTACTOS}/{clientes_tenant_2['contacto_public_id']}",
                          headers=_cab(t))
    assert c.status_code == 200, c.text
    assert c.json()["empresa"] == clientes_tenant_2["empresa_public_id"]


async def test_tenant_contactos_de_empresa_ajena_da_404(cliente, usuarios_rbac,
                                                        clientes_tenant_2):
    """No devuelve lista vacía: eso la distinguiría del 404 de su ficha.

    Una lista vacía sería cierta —no ve ninguno— pero diferente del 404 que da
    `/empresas/{id}` para el mismo UUID, y esa diferencia es un oráculo.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(f"{EMPRESAS}/{clientes_tenant_2['empresa_public_id']}/contactos",
                          headers=_cab(t))
    assert r.status_code == 404, r.text
    assert "items" not in r.json()


async def test_tenant_id_en_query_se_rechaza(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    for ruta in (EMPRESAS, PERSONAS):
        r = await cliente.get(ruta, headers=_cab(t), params={"tenant_id": 2})
        assert r.status_code == 422, f"{ruta} aceptó tenant_id"


# ================================================================== RLS =====

async def test_rls_sin_contexto_no_devuelve_lista_vacia(cliente, usuarios_rbac,
                                                        monkeypatch):
    """Sin contexto la petición MUERE con 500. No responde 200 con []."""
    t = await _token(cliente, usuarios_rbac["lector_email"])

    from contextlib import asynccontextmanager

    from sacgeo.api import deps
    from sacgeo.db.pool import obtener_pool

    @asynccontextmanager
    async def _sin_tenant(tenant_id, usuario_id, ip_origen=None):
        pool = obtener_pool()
        async with pool.connection() as conn:
            async with conn.transaction():
                async with conn.cursor() as cur:
                    await cur.execute(
                        "SELECT set_config('app.usuario_id', %s, true)",
                        (str(usuario_id),))
                yield conn

    monkeypatch.setattr(deps, "transaccion", _sin_tenant)
    r = await cliente.get(EMPRESAS, headers=_cab(t))
    assert r.status_code == 500, f"respondió {r.status_code}: {r.text}"
    assert r.json().get("items") is None
    assert set(r.json()) == {"error", "ref"}


async def test_rls_las_tres_tablas_exigen_contexto(url_app):
    """`empresas`, `contactos` y `personas` lanzan 42501 sin contexto."""
    conn = await psycopg.AsyncConnection.connect(url_app)
    try:
        for tabla in ("empresas", "contactos", "personas"):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                async with conn.cursor() as cur:
                    await cur.execute(f"SELECT count(*) FROM {tabla}")  # noqa: S608
            await conn.rollback()
    finally:
        await conn.close()


async def test_rls_empresa_inactiva_se_excluye(cliente, usuarios_rbac,
                                               clientes_tenant_2):
    """`solo_activas` por defecto excluye; en false, incluye."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    inactiva = clientes_tenant_2["inactiva_public_id"]

    por_defecto = await cliente.get(EMPRESAS, headers=_cab(t))
    assert inactiva not in {e["public_id"] for e in por_defecto.json()["items"]}

    todas = await cliente.get(EMPRESAS, headers=_cab(t), params={"solo_activas": False})
    assert inactiva in {e["public_id"] for e in todas.json()["items"]}


# ============================================================ PAGINACIÓN ====

@pytest.mark.parametrize(
    "params",
    [{"limite": 0}, {"limite": -1}, {"limite": 201}, {"limite": 99999},
     {"desplazamiento": -1}, {"limite": "muchos"}, {"desplazamiento": "x"}],
)
async def test_paginacion_invalida(cliente, usuarios_rbac, params):
    """Una colección sin techo es una denegación de servicio."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(EMPRESAS, headers=_cab(t), params=params)
    assert r.status_code == 422, f"{params} devolvió {r.status_code}"


async def test_paginacion_valida_y_sin_solapamiento(cliente, usuarios_rbac):
    """Dos páginas consecutivas no repiten ni omiten filas.

    Es lo que garantiza el desempate por `id` del ORDER BY: sin un orden total,
    dos empresas con la misma razón social podrían salir en cualquier orden y
    aparecer en las dos páginas.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    completo = await cliente.get(EMPRESAS, headers=_cab(t),
                                 params={"limite": 200, "solo_activas": False})
    todos = [e["public_id"] for e in completo.json()["items"]]

    p1 = await cliente.get(EMPRESAS, headers=_cab(t),
                           params={"limite": 1, "solo_activas": False})
    p2 = await cliente.get(EMPRESAS, headers=_cab(t),
                           params={"limite": 1, "desplazamiento": 1,
                                   "solo_activas": False})
    assert [e["public_id"] for e in p1.json()["items"]] == todos[:1]
    assert [e["public_id"] for e in p2.json()["items"]] == todos[1:2]
    assert p1.json()["total"] == p2.json()["total"] == completo.json()["total"]

    lejos = await cliente.get(EMPRESAS, headers=_cab(t),
                              params={"limite": 5, "desplazamiento": 10000})
    assert lejos.json()["items"] == []
    assert lejos.json()["total"] == completo.json()["total"], (
        "una página vacía informó total=0"
    )


async def test_limite_maximo_se_acepta(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    assert (await cliente.get(EMPRESAS, headers=_cab(t),
                              params={"limite": 200})).status_code == 200


# =============================================================== FILTROS ====

@pytest.mark.parametrize(
    "params",
    [{"q": "x" * 101}, {"campo": "ruc"}, {"column": "id"}, {"sql": "1=1"},
     {"operator": "or"}, {"solo_activas": "quizas"}, {"field": "email"}],
)
async def test_filtros_fuera_de_contrato(cliente, usuarios_rbac, params):
    """Solo lista blanca. Un nombre de campo o un operador nunca entran."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(EMPRESAS, headers=_cab(t), params=params)
    assert r.status_code == 422, f"{params} devolvió {r.status_code}"


async def test_filtro_q_busca_y_escapa_comodines(cliente, usuarios_rbac):
    """`q` filtra de verdad, y `%` busca el carácter, no «todo»."""
    t = await _token(cliente, usuarios_rbac["lector_email"])

    r = await cliente.get(EMPRESAS, headers=_cab(t), params={"q": "ALDEM"})
    assert r.status_code == 200, r.text
    assert r.json()["total"] == 1
    assert "ALDEM" in r.json()["items"][0]["razon_social"]

    por_ruc = await cliente.get(EMPRESAS, headers=_cab(t), params={"q": "20123456789"})
    assert por_ruc.json()["total"] == 1

    completo = await cliente.get(EMPRESAS, headers=_cab(t), params={"limite": 200})
    comodin = await cliente.get(EMPRESAS, headers=_cab(t),
                                params={"q": "%", "limite": 200})
    assert comodin.json()["total"] == 0, "el comodín se interpretó: devolvió todo"
    assert completo.json()["total"] > 0

    guion = await cliente.get(EMPRESAS, headers=_cab(t), params={"q": "_"})
    assert guion.json()["total"] == 0, "el comodín _ se interpretó como una letra"


async def test_inyeccion_conceptual_en_filtros(cliente, usuarios_rbac):
    """Cargas de inyección en `q` se tratan como texto, sin error de servidor."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    for carga in ("' OR 1=1 --", "'; DROP TABLE empresas; --",
                  "%' UNION SELECT NULL --", "1' AND SLEEP(5)--"):
        r = await cliente.get(EMPRESAS, headers=_cab(t), params={"q": carga})
        assert r.status_code == 200, f"{carga!r} -> {r.status_code}: {r.text}"
        assert r.json()["total"] == 0, f"{carga!r} devolvió filas"

    # La tabla sigue ahí.
    assert (await cliente.get(EMPRESAS, headers=_cab(t))).json()["total"] > 0


# ============================================================== ORDERING ====

@pytest.mark.parametrize(
    "params",
    [{"orden": "id"}, {"orden": "tenant_id"}, {"orden": "ruc; DROP TABLE empresas"},
     {"orden": "creado_en DESC"}, {"direccion": "ascending"},
     {"direccion": "asc; --"}, {"orden": ""}, {"orden": "1"}],
)
async def test_ordering_fuera_de_la_lista_blanca(cliente, usuarios_rbac, params):
    """`ORDER BY {cliente}` es inyección con otro nombre. Aquí no llega al SQL.

    `orden` y `direccion` son `Literal`, así que Pydantic los rechaza antes de
    que nadie los mire. Incluye a propósito `id` y `tenant_id`: son columnas
    REALES, y aun así no son ordenaciones permitidas — la lista blanca es de
    campos de API, no de columnas existentes.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(EMPRESAS, headers=_cab(t), params=params)
    assert r.status_code == 422, f"{params} devolvió {r.status_code}"


@pytest.mark.parametrize("orden", ["nombre", "ruc", "creado_en"])
@pytest.mark.parametrize("direccion", ["asc", "desc"])
async def test_ordering_valido(cliente, usuarios_rbac, orden, direccion):
    """Las 6 combinaciones permitidas funcionan y ordenan de verdad."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(EMPRESAS, headers=_cab(t),
                          params={"orden": orden, "direccion": direccion,
                                  "limite": 200, "solo_activas": False})
    assert r.status_code == 200, r.text
    items = r.json()["items"]

    if orden == "nombre":
        valores = [e["razon_social"] for e in items]
    elif orden == "ruc":
        valores = [e["ruc"] for e in items]
    else:
        return  # creado_en no se expone; basta con que la consulta sea válida

    assert valores == sorted(valores, reverse=(direccion == "desc")), (
        f"orden={orden} direccion={direccion} no ordenó: {valores}"
    )


async def test_ordering_asc_y_desc_son_inversos(cliente, usuarios_rbac):
    """Si `direccion` se ignorara, ambas listas serían idénticas."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    p = {"orden": "ruc", "limite": 200, "solo_activas": False}
    asc = await cliente.get(EMPRESAS, headers=_cab(t), params={**p, "direccion": "asc"})
    desc = await cliente.get(EMPRESAS, headers=_cab(t), params={**p, "direccion": "desc"})
    a = [e["ruc"] for e in asc.json()["items"]]
    d = [e["ruc"] for e in desc.json()["items"]]
    assert len(a) > 1
    assert a == list(reversed(d))


async def test_ordering_en_personas(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    for orden in ("nombre", "dni", "creado_en"):
        r = await cliente.get(PERSONAS, headers=_cab(t), params={"orden": orden})
        assert r.status_code == 200, r.text
    assert (await cliente.get(PERSONAS, headers=_cab(t),
                              params={"orden": "ruc"})).status_code == 422


# ============================================================= CONTRATO =====

CLAVES_EMPRESA = {"public_id", "ruc", "razon_social", "direccion", "telefono",
                  "email", "activo", "contactos"}
CLAVES_CONTACTO = {"public_id", "dni", "nombres", "apellidos", "cargo",
                   "celular", "email", "activo"}
CLAVES_PERSONA = {"public_id", "dni", "nombres", "apellidos", "celular",
                  "email", "empresa_asociada", "activo"}


async def test_contrato_empresas(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(EMPRESAS, headers=_cab(t))
    cuerpo = r.json()
    assert set(cuerpo) == {"items", "total", "limite", "desplazamiento"}
    assert cuerpo["items"], "el tenant 1 tiene empresas sembradas"
    for e in cuerpo["items"]:
        assert set(e) == CLAVES_EMPRESA, f"claves inesperadas: {set(e) ^ CLAVES_EMPRESA}"

    detalle = await cliente.get(f"{EMPRESAS}/{cuerpo['items'][0]['public_id']}",
                                headers=_cab(t))
    assert set(detalle.json()) == CLAVES_EMPRESA


async def test_contrato_contactos_y_personas(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    empresas = (await cliente.get(EMPRESAS, headers=_cab(t))).json()["items"]
    candidatas = [e for e in empresas if e["contactos"] > 0]
    assert candidatas, "el tenant 1 debe tener una empresa con contactos"
    con_contactos = candidatas[0]

    c = await cliente.get(f"{EMPRESAS}/{con_contactos['public_id']}/contactos",
                          headers=_cab(t))
    assert c.status_code == 200, c.text
    cuerpo = c.json()
    assert set(cuerpo) == {"empresa", "items", "total"}
    assert cuerpo["empresa"] == con_contactos["public_id"]
    assert cuerpo["total"] == len(cuerpo["items"]) == con_contactos["contactos"]
    for x in cuerpo["items"]:
        assert set(x) == CLAVES_CONTACTO

    uno = await cliente.get(f"{CONTACTOS}/{cuerpo['items'][0]['public_id']}",
                            headers=_cab(t))
    assert set(uno.json()) == CLAVES_CONTACTO | {"empresa"}
    assert uno.json()["empresa"] == con_contactos["public_id"]

    p = await cliente.get(PERSONAS, headers=_cab(t))
    for x in p.json()["items"]:
        assert set(x) == CLAVES_PERSONA


async def test_contrato_sin_ids_internos(cliente, usuarios_rbac):
    """Ni `id` ni `tenant_id` en ninguna de las seis respuestas."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    empresas = (await cliente.get(EMPRESAS, headers=_cab(t))).json()["items"]
    candidatas = [e for e in empresas if e["contactos"] > 0]
    assert candidatas, "el tenant 1 debe tener una empresa con contactos"
    una = candidatas[0]
    contactos = (await cliente.get(f"{EMPRESAS}/{una['public_id']}/contactos",
                                   headers=_cab(t))).json()["items"]

    rutas = [EMPRESAS, PERSONAS, f"{EMPRESAS}/{una['public_id']}",
             f"{EMPRESAS}/{una['public_id']}/contactos",
             f"{CONTACTOS}/{contactos[0]['public_id']}"]
    for ruta in rutas:
        crudo = (await cliente.get(ruta, headers=_cab(t))).text
        for prohibido in ('"id"', "tenant_id", "empresa_id", "creado_por",
                          "actualizado_por"):
            assert prohibido not in crudo, f"{ruta} filtró {prohibido}"


# ======================================================= IDOR / ERRORES =====

@pytest.mark.parametrize(
    "ruta", [f"{EMPRESAS}/no-es-uuid", f"{PERSONAS}/123",
             f"{CONTACTOS}/abc-def", f"{EMPRESAS}/xx/contactos"])
async def test_public_id_malformado(cliente, usuarios_rbac, ruta):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    assert (await cliente.get(ruta, headers=_cab(t))).status_code == 422


@pytest.mark.parametrize(
    "ruta", [f"{EMPRESAS}/{INEXISTENTE}", f"{PERSONAS}/{INEXISTENTE}",
             f"{CONTACTOS}/{INEXISTENTE}", f"{EMPRESAS}/{INEXISTENTE}/contactos"])
async def test_public_id_inexistente(cliente, usuarios_rbac, ruta):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    assert (await cliente.get(ruta, headers=_cab(t))).status_code == 404


async def test_inexistente_y_ajeno_son_indistinguibles(cliente, usuarios_rbac,
                                                       clientes_tenant_2):
    """El 404 del inexistente y el del ajeno son idénticos."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    a = await cliente.get(f"{EMPRESAS}/{INEXISTENTE}", headers=_cab(t))
    b = await cliente.get(f"{EMPRESAS}/{clientes_tenant_2['empresa_public_id']}",
                          headers=_cab(t))
    assert a.status_code == b.status_code == 404
    assert a.json() == b.json(), "los 404 no son idénticos: hay oráculo"


async def test_los_errores_no_filtran_nada(cliente, usuarios_rbac):
    """Ningún error devuelve SQL, traza, secretos ni nombres de tabla."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    respuestas = [
        await cliente.get(EMPRESAS, headers=_cab(t), params={"limite": 0}),
        await cliente.get(f"{EMPRESAS}/no-es-uuid", headers=_cab(t)),
        await cliente.get(f"{EMPRESAS}/{INEXISTENTE}", headers=_cab(t)),
        await cliente.get(EMPRESAS),
    ]
    for r in respuestas:
        crudo = r.text.lower()
        for prohibido in ("select ", "from empresas", "psycopg", "traceback",
                          "password", "argon2", "sqlstate", "postgresql://",
                          "database_url", "jwt_secret"):
            assert prohibido not in crudo, f"{r.status_code} filtró {prohibido!r}"


# =============================================== AUDITORÍA / POOL / API =====

async def test_un_get_no_escribe_auditoria(cliente, usuarios_rbac, url_super):
    def _contar() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM auditoria")
            return cur.fetchone()[0]

    t = await _token(cliente, usuarios_rbac["lector_email"])
    antes = _contar()
    for ruta in (EMPRESAS, PERSONAS):
        assert (await cliente.get(ruta, headers=_cab(t))).status_code == 200
    assert _contar() == antes, "un GET escribió auditoría"


async def test_peticiones_consecutivas_y_contexto_limpio(cliente, usuarios_rbac):
    """12 vueltas sin SQLSTATE 26000 (D-3) y contexto limpio al final."""
    from sacgeo.db.pool import obtener_pool
    from sacgeo.db.tx import leer_contexto

    t = await _token(cliente, usuarios_rbac["lector_email"])
    for vuelta in range(1, 13):
        r = await cliente.get(EMPRESAS, headers=_cab(t))
        assert r.status_code == 200, f"vuelta {vuelta}: {r.text}"

    pool = obtener_pool()
    async with pool.connection() as conn:
        contexto = await leer_contexto(conn)
    assert contexto["tenant_id"] in (None, ""), contexto
    assert contexto["usuario_id"] in (None, ""), contexto


async def test_openapi_documenta_los_seis(cliente):
    r = await cliente.get("/openapi.json")
    rutas = r.json()["paths"]
    esperadas = [
        "/api/v1/clientes/empresas",
        "/api/v1/clientes/empresas/{public_id}",
        "/api/v1/clientes/empresas/{public_id}/contactos",
        "/api/v1/clientes/personas",
        "/api/v1/clientes/personas/{public_id}",
        "/api/v1/clientes/contactos/{public_id}",
    ]
    # `/empresas` es la ÚNICA que además expone POST, autorizado en la fase 7I
    # (primer WRITE real). Las otras cinco siguen siendo de solo lectura, y este
    # test es lo que lo mantiene: si un PATCH o un DELETE apareciera en
    # cualquiera de ellas —o un segundo POST sin autorizar— fallaría aquí.
    metodos_esperados = {
        "/api/v1/clientes/empresas": {"get", "post"},
    }
    for ruta in esperadas:
        assert ruta in rutas, f"falta {ruta}"
        assert set(rutas[ruta]) == metodos_esperados.get(ruta, {"get"}), (
            f"{ruta} expone {set(rutas[ruta])}, no lo autorizado"
        )

    params = {p["name"] for p in rutas[EMPRESAS]["get"]["parameters"]}
    assert params == {"q", "solo_activas", "orden", "direccion",
                      "limite", "desplazamiento"}
    assert "tenant_id" not in params

    # La lista blanca de ordenación queda declarada en el esquema.
    orden = next(p for p in rutas[EMPRESAS]["get"]["parameters"] if p["name"] == "orden")
    assert "nombre" in str(orden), "el esquema no declara los valores de `orden`"
