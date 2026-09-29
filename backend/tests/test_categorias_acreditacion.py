"""Fase 7C.1 — categorías y acreditación, contra PostgreSQL con RLS forzada.

Dos recursos con DOS permisos distintos, y ese es el punto de esta suite: hasta
ahora todos los endpoints de negocio exigían `catalogo.read`, así que un guard
mal escrito —el que copia el permiso del endpoint de al lado— habría pasado
inadvertido. Aquí `catalogo.read` NO abre la acreditación y `acreditacion.read`
NO abre las categorías, y hay usuarios que tienen exactamente uno de los dos
para demostrarlo.

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
CATEGORIAS = "/api/v1/categorias"
CATALOGO = "/api/v1/catalogo"


def ACREDITACION(public_id: str) -> str:
    return f"{CATALOGO}/{public_id}/acreditacion"


@pytest.fixture
async def cliente(url_app, usuarios_rbac, usuarios_permisos_separados,
                  catalogo_tenant_2, monkeypatch):
    """La app real, como `sacgeo_app`: sin superusuario y sin BYPASSRLS.

    Con `sacgeo_dev` estos tests pasarían igual sin que ninguna política se
    evaluara, es decir, probarían lo contrario de lo que dicen probar.
    """
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


def _cab(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _un_ensayo(cliente, token: str) -> str:
    """Un public_id real del catálogo del tenant 1."""
    r = await cliente.get(CATALOGO, headers=_cab(token), params={"limite": 1})
    assert r.status_code == 200, r.text
    return r.json()["items"][0]["public_id"]


# ================================================================= AUTH =====

@pytest.mark.parametrize("ruta", [CATEGORIAS, f"{CATEGORIAS}/x", CATALOGO])
async def test_auth_1_sin_bearer(cliente, ruta):
    r = await cliente.get(ruta)
    assert r.status_code == 401


async def test_auth_2_jwt_malformado(cliente):
    for ruta in (CATEGORIAS, ACREDITACION("00000000-0000-4000-8000-000000000000")):
        r = await cliente.get(ruta, headers=_cab("no-es-un-jwt"))
        assert r.status_code == 401, ruta


async def test_auth_3_jwt_con_permisos_inyectados(cliente, usuarios_rbac, url_super):
    """Token CORRECTAMENTE FIRMADO con un claim `permissions` añadido → 401.

    Es el ataque que hace inútil meter autorización en el JWT. La firma es
    buena y el `sub` es de un usuario real; lo único anómalo es el claim.
    """
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE email = %s",
                    (usuarios_rbac["lector_email"],))
        (public_id,) = cur.fetchone()

    ahora = datetime.now(UTC)
    token = pyjwt.encode(
        {"sub": str(public_id), "jti": "z",
         "iat": int(ahora.timestamp()),
         "exp": int((ahora + timedelta(minutes=15)).timestamp()),
         "permissions": ["catalogo.read", "acreditacion.read"]},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo,
    )
    r = await cliente.get(CATEGORIAS, headers=_cab(token))
    assert r.status_code == 401, "un claim de autorización en el token fue aceptado"


# ================================================================= RBAC =====

async def test_rbac_1_catalogo_read_abre_categorias(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(CATEGORIAS, headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["total"] > 0


async def test_rbac_2_sin_ningun_rol(cliente, usuarios_catalogo):
    """Autenticado, con tenant, sin una sola fila en usuario_roles: 403 en ambos."""
    t = await _token(cliente, usuarios_catalogo["sin_roles_email"])
    for ruta in (CATEGORIAS, ACREDITACION("00000000-0000-4000-8000-000000000000")):
        r = await cliente.get(ruta, headers=_cab(t))
        assert r.status_code == 403, f"{ruta} devolvió {r.status_code}"


async def test_rbac_3_rol_sin_el_permiso(cliente, usuarios_catalogo):
    """Rol real con `dashboard.read` y nada más: 403 en los dos recursos."""
    t = await _token(cliente, usuarios_catalogo["solo_dash_email"])
    for ruta in (CATEGORIAS, ACREDITACION("00000000-0000-4000-8000-000000000000")):
        r = await cliente.get(ruta, headers=_cab(t))
        assert r.status_code == 403, f"{ruta} devolvió {r.status_code}"


async def test_rbac_4_acreditacion_read_abre_acreditacion(cliente, usuarios_rbac,
                                                          usuarios_permisos_separados):
    """El usuario que SOLO tiene acreditacion.read entra a la acreditación."""
    t_cat = await _token(cliente, usuarios_rbac["lector_email"])
    ensayo = await _un_ensayo(cliente, t_cat)

    t = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    r = await cliente.get(ACREDITACION(ensayo), headers=_cab(t))
    assert r.status_code == 200, r.text


async def test_rbac_5_catalogo_read_NO_sustituye_a_acreditacion_read(
    cliente, usuarios_rbac, usuarios_permisos_separados
):
    """El usuario que SOLO tiene catalogo.read NO puede leer la acreditación.

    Es el test que atrapa el error más probable de esta fase: colgar la ruta
    del router de catálogo y heredar `catalogo.read` sin darse cuenta. Si eso
    ocurriera, este usuario recibiría 200 y el historial ISO 17025 quedaría
    abierto a cualquiera que pueda ver precios.
    """
    t_lector = await _token(cliente, usuarios_rbac["lector_email"])
    ensayo = await _un_ensayo(cliente, t_lector)

    t = await _token(cliente, usuarios_permisos_separados["solo_catalogo_email"])
    propio = await cliente.get(CATEGORIAS, headers=_cab(t))
    assert propio.status_code == 200, "catalogo.read debería abrir categorías"

    r = await cliente.get(ACREDITACION(ensayo), headers=_cab(t))
    assert r.status_code == 403, (
        "catalogo.read abrió la acreditación: el router hereda el permiso equivocado"
    )


async def test_rbac_6_acreditacion_read_NO_sustituye_a_catalogo_read(
    cliente, usuarios_permisos_separados
):
    """Y al revés: acreditacion.read no abre categorías ni catálogo."""
    t = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    for ruta in (CATEGORIAS, CATALOGO):
        r = await cliente.get(ruta, headers=_cab(t))
        assert r.status_code == 403, f"{ruta} devolvió {r.status_code}"


# =============================================================== TENANT =====

async def test_tenant_1_solo_las_propias(cliente, usuarios_rbac, url_super):
    """El total coincide con lo que tiene ESE laboratorio, calculado en la base."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(CATEGORIAS, headers=_cab(t), params={"solo_activas": False})
    assert r.status_code == 200, r.text

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM categorias_ensayo WHERE tenant_id = 1")
        (esperado,) = cur.fetchone()

    assert r.json()["total"] == esperado


async def test_tenant_2_la_categoria_ajena_no_aparece(cliente, usuarios_rbac,
                                                      catalogo_tenant_2):
    """La categoría sembrada en el tenant 2 no está en el listado del tenant 1."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(CATEGORIAS, headers=_cab(t), params={"solo_activas": False})
    nombres = {c["nombre"] for c in r.json()["items"]}
    ids = {c["public_id"] for c in r.json()["items"]}

    assert catalogo_tenant_2["categoria_nombre"] not in nombres
    assert catalogo_tenant_2["categoria_public_id"] not in ids


async def test_tenant_3_public_id_ajeno_da_404(cliente, usuarios_rbac,
                                               catalogo_tenant_2):
    """Categoría de otro laboratorio: 404, NUNCA 403."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(f"{CATEGORIAS}/{catalogo_tenant_2['categoria_public_id']}",
                          headers=_cab(t))
    assert r.status_code == 404, r.text
    assert r.status_code != 403


async def test_tenant_4_el_dueno_si_la_ve(cliente, usuarios_rbac, catalogo_tenant_2):
    """Prueba que el 404 anterior lo causa RLS y no un UUID muerto."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.get(f"{CATEGORIAS}/{catalogo_tenant_2['categoria_public_id']}",
                          headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == catalogo_tenant_2["categoria_nombre"]


async def test_tenant_5_acreditacion_ajena_da_404(cliente, usuarios_rbac,
                                                  usuarios_permisos_separados,
                                                  catalogo_tenant_2, asignar_rol):
    """El ensayo del tenant 2 no tiene acreditación visible para el tenant 1.

    El usuario de tenant 1 usado aquí tiene `acreditacion.read`, así que un 403
    no podría confundirse con falta de permiso: si respondiera algo distinto de
    404, sería una fuga.
    """
    t = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    r = await cliente.get(ACREDITACION(catalogo_tenant_2["public_id"]), headers=_cab(t))
    assert r.status_code == 404, r.text
    assert r.status_code != 403


# ================================================================== RLS =====

async def test_rls_1_sin_contexto_no_devuelve_lista_vacia(cliente, usuarios_rbac,
                                                          monkeypatch):
    """Sin contexto de tenant la petición MUERE. No responde 200 con [].

    Es el modo de fallo que este diseño evita: con un `WHERE tenant_id =
    <variable vacía>` en Python la respuesta sería `200 []`, indistinguible de
    "este laboratorio no tiene categorías". Con RLS, `fn_app_tenant()` lanza
    42501 y `errors.py` lo traduce a 500, porque llegar ahí es un bug nuestro.
    """
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
                        "SELECT set_config('app.usuario_id', %s, true)", (str(usuario_id),)
                    )
                yield conn

    monkeypatch.setattr(deps, "transaccion", _sin_tenant)
    r = await cliente.get(CATEGORIAS, headers=_cab(t))
    assert r.status_code == 500, f"sin contexto respondió {r.status_code}: {r.text}"
    assert r.json().get("items") is None, "devolvió una lista en vez de fallar"
    assert set(r.json()) == {"error", "ref"}


async def test_rls_2_categoria_inactiva_se_excluye(cliente, usuarios_rbac,
                                                   url_super, catalogo_tenant_2):
    """`solo_activas=true` (por defecto) excluye lo desactivado; false lo incluye.

    Se desactiva una categoría del tenant 2 —nunca una del 1, que es la que
    usan los demás tests— y se comprueba desde su propio laboratorio.
    """
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT set_config('app.tenant_id', %s, false)",
                    (str(catalogo_tenant_2["tenant_2"]),))
        cur.execute("SELECT set_config('app.usuario_id', '1', false)")
        cur.execute("UPDATE categorias_ensayo SET activo = FALSE WHERE id = %s",
                    (catalogo_tenant_2["categoria_id"],))
        conn.commit()

    try:
        t = await _token(cliente, usuarios_rbac["ajeno_email"])

        por_defecto = await cliente.get(CATEGORIAS, headers=_cab(t))
        assert catalogo_tenant_2["categoria_public_id"] not in {
            c["public_id"] for c in por_defecto.json()["items"]
        }, "una categoría desactivada apareció con solo_activas por defecto"

        todas = await cliente.get(CATEGORIAS, headers=_cab(t),
                                  params={"solo_activas": False})
        assert catalogo_tenant_2["categoria_public_id"] in {
            c["public_id"] for c in todas.json()["items"]
        }, "solo_activas=false no la trajo"
    finally:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT set_config('app.tenant_id', %s, false)",
                        (str(catalogo_tenant_2["tenant_2"]),))
            cur.execute("SELECT set_config('app.usuario_id', '1', false)")
            cur.execute("UPDATE categorias_ensayo SET activo = TRUE WHERE id = %s",
                        (catalogo_tenant_2["categoria_id"],))
            conn.commit()


async def test_rls_3_las_politicas_intervienen_de_verdad(url_app):
    """Sin contexto, consultar las tablas como `sacgeo_app` lanza 42501.

    No devuelve cero filas —que la API podría confundir con "no hay datos"—:
    la política llama a `fn_app_tenant()` y esa función falla ruidosamente.
    """
    conn = await psycopg.AsyncConnection.connect(url_app)
    try:
        for tabla in ("categorias_ensayo", "subcategorias_ensayo",
                      "ensayo_acreditacion_historial"):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                async with conn.cursor() as cur:
                    await cur.execute(f"SELECT count(*) FROM {tabla}")  # noqa: S608
            await conn.rollback()
    finally:
        await conn.close()


# =========================================================== VALIDACIÓN =====

@pytest.mark.parametrize(
    "params",
    [
        {"tenant_id": 2},          # campo desconocido: no se ignora
        {"limite": 10},            # no hay paginación en este recurso
        {"desplazamiento": 0},
        {"solo_activas": "quizas"},
        {"incluir_vacias": "tal vez"},
    ],
)
async def test_validacion_1_query_invalida(cliente, usuarios_rbac, params):
    """`extra="forbid"` rechaza lo que no está en el contrato.

    `limite` y `desplazamiento` NO forman parte de este contrato: las
    categorías de un laboratorio son cinco, y paginar un conjunto cerrado añade
    dos parámetros y dos modos de fallo a cambio de nada. Se comprueba que se
    rechazan, no que funcionen.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(CATEGORIAS, headers=_cab(t), params=params)
    assert r.status_code == 422, f"{params} devolvió {r.status_code}"


async def test_validacion_2_public_id_no_es_uuid(cliente, usuarios_rbac,
                                                 usuarios_permisos_separados):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(f"{CATEGORIAS}/no-es-un-uuid", headers=_cab(t))
    assert r.status_code == 422

    t2 = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    r2 = await cliente.get(ACREDITACION("tampoco-lo-es"), headers=_cab(t2))
    assert r2.status_code == 422


async def test_validacion_3_uuid_valido_inexistente(cliente, usuarios_rbac,
                                                    usuarios_permisos_separados):
    inexistente = "00000000-0000-4000-8000-000000000000"
    t = await _token(cliente, usuarios_rbac["lector_email"])
    assert (await cliente.get(f"{CATEGORIAS}/{inexistente}",
                              headers=_cab(t))).status_code == 404

    t2 = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    assert (await cliente.get(ACREDITACION(inexistente),
                              headers=_cab(t2))).status_code == 404


# ============================================================= CONTRATO =====

CLAVES_CATEGORIA = {
    "public_id", "slug", "nombre", "prefijo_codigo", "icono", "color_hex",
    "orden", "activo", "ensayos", "subcategorias",
}
CLAVES_SUBCATEGORIA = {"public_id", "nombre", "orden", "activo"}
CLAVES_ACREDITACION = {
    "public_id", "codigo", "nombre", "acreditado", "vigente_desde",
    "motivo", "coherente", "historial",
}
CLAVES_CAMBIO = {"acreditado", "motivo", "vigente_desde", "registrado_en"}


async def test_contrato_1_categorias(cliente, usuarios_rbac):
    """Claves exactas, subcategorías anidadas, y NADA de ids internos."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(CATEGORIAS, headers=_cab(t))
    assert r.status_code == 200, r.text
    cuerpo = r.json()

    assert set(cuerpo) == {"items", "total"}
    assert cuerpo["items"], "el tenant 1 tiene categorías sembradas"
    assert cuerpo["total"] == len(cuerpo["items"])

    for c in cuerpo["items"]:
        assert set(c) == CLAVES_CATEGORIA, f"claves inesperadas: {set(c) ^ CLAVES_CATEGORIA}"
        assert "id" not in c and "tenant_id" not in c
        for s in c["subcategorias"]:
            assert set(s) == CLAVES_SUBCATEGORIA
            assert "id" not in s and "tenant_id" not in s and "categoria_id" not in s

    # El orden es el de navegación: `orden` ascendente, como la lista de precios.
    ordenes = [c["orden"] for c in cuerpo["items"]]
    assert ordenes == sorted(ordenes)

    # Anidado real: al menos una categoría trae subcategorías.
    assert any(c["subcategorias"] for c in cuerpo["items"])


async def test_contrato_2_detalle_de_categoria(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    lista = await cliente.get(CATEGORIAS, headers=_cab(t))
    una = lista.json()["items"][0]

    r = await cliente.get(f"{CATEGORIAS}/{una['public_id']}", headers=_cab(t))
    assert r.status_code == 200, r.text
    assert set(r.json()) == CLAVES_CATEGORIA
    assert r.json()["public_id"] == una["public_id"]
    assert r.json()["subcategorias"] == una["subcategorias"]


async def test_contrato_3_acreditacion(cliente, usuarios_rbac,
                                       usuarios_permisos_separados):
    """Claves exactas y, sobre todo, sin `registrado_por` — es un usuarios.id."""
    t_cat = await _token(cliente, usuarios_rbac["lector_email"])
    ensayo = await _un_ensayo(cliente, t_cat)

    t = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    r = await cliente.get(ACREDITACION(ensayo), headers=_cab(t))
    assert r.status_code == 200, r.text
    cuerpo = r.json()

    assert set(cuerpo) == CLAVES_ACREDITACION
    assert "ensayo_id" not in cuerpo and "tenant_id" not in cuerpo
    assert cuerpo["public_id"] == ensayo
    assert isinstance(cuerpo["acreditado"], bool)

    for h in cuerpo["historial"]:
        assert set(h) == CLAVES_CAMBIO
        assert "registrado_por" not in h, "se filtró un id técnico de usuario"
        assert "id" not in h and "tenant_id" not in h


async def test_contrato_4_incluir_vacias(cliente, usuarios_rbac, catalogo_tenant_2):
    """`incluir_vacias=false` quita las categorías sin ensayos activos.

    Se prueba desde el tenant 2, que es donde vive la categoría vacía. En
    `sacgeo_dev` ese caso existe de forma natural —«Geotecnia», cero ensayos—,
    pero la base desechable se levanta desde el seed, con sus 4 categorías
    pobladas: había que crear el escenario o el test pasaría sin comprobar nada,
    que fue exactamente lo que ocurrió en la primera ejecución de esta suite.
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])

    todas = await cliente.get(CATEGORIAS, headers=_cab(t))
    assert todas.status_code == 200, todas.text
    con_ensayos = await cliente.get(CATEGORIAS, headers=_cab(t),
                                    params={"incluir_vacias": False})
    assert con_ensayos.status_code == 200, con_ensayos.text

    vacia = catalogo_tenant_2["categoria_vacia_public_id"]
    todas_ids = {c["public_id"] for c in todas.json()["items"]}
    devueltas = {c["public_id"] for c in con_ensayos.json()["items"]}

    assert vacia in todas_ids, "por defecto la categoría vacía debe aparecer"
    assert vacia not in devueltas, "incluir_vacias=false devolvió una categoría vacía"
    assert all(c["ensayos"] > 0 for c in con_ensayos.json()["items"])
    assert devueltas, "el filtro no puede vaciar el listado entero"

    # La cuenta de ensayos es real, no un cero por defecto.
    la_vacia = next(c for c in todas.json()["items"] if c["public_id"] == vacia)
    assert la_vacia["ensayos"] == 0
    assert la_vacia["subcategorias"], "fn_crear_categoria crea su «General» (R2)"


# ==================================================== COHERENCIA ISO ========

async def test_iso_1_estado_e_historial_son_coherentes(cliente, usuarios_rbac,
                                                       usuarios_permisos_separados):
    """`coherente` es cierto y el historial lo respalda.

    La acreditación es lo primero que revisa un auditor ISO 17025. Que el
    estado de la ficha y el último hecho del historial coincidan es la
    propiedad que el trigger de la base protege; aquí se comprueba que la API
    no la rompe al servirla.
    """
    t_cat = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(CATALOGO, headers=_cab(t_cat), params={"limite": 15})
    ensayos = [i["public_id"] for i in r.json()["items"]]

    t = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    revisados = 0
    for ensayo in ensayos:
        a = await cliente.get(ACREDITACION(ensayo), headers=_cab(t))
        assert a.status_code == 200, a.text
        cuerpo = a.json()
        assert cuerpo["coherente"] is True, f"{ensayo}: estado e historial divergen"
        if cuerpo["historial"]:
            assert cuerpo["historial"][0]["acreditado"] == cuerpo["acreditado"], (
                "el hecho más reciente no coincide con el estado vigente"
            )
        revisados += 1
    assert revisados >= 10


async def test_iso_2_el_historial_viene_ordenado(cliente, usuarios_rbac,
                                                 usuarios_permisos_separados):
    """Lo más reciente primero, que es como se lee un historial."""
    t_cat = await _token(cliente, usuarios_rbac["lector_email"])
    ensayo = await _un_ensayo(cliente, t_cat)

    t = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    cuerpo = (await cliente.get(ACREDITACION(ensayo), headers=_cab(t))).json()

    fechas = [h["vigente_desde"] for h in cuerpo["historial"]]
    assert fechas == sorted(fechas, reverse=True)
    assert cuerpo["historial"], "el seed tiene 90 hechos de acreditación"


# =========================================================== AUDITORÍA ======

async def test_auditoria_un_get_no_escribe(cliente, usuarios_rbac,
                                           usuarios_permisos_separados, url_super):
    """Leer categorías o acreditación no deja rastro en `auditoria`.

    La auditoría registra CAMBIOS. Escribir una fila por lectura la inundaría y
    haría inútil justo aquello para lo que existe.
    """
    def _contar() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM auditoria")
            return cur.fetchone()[0]

    t = await _token(cliente, usuarios_rbac["lector_email"])
    ensayo = await _un_ensayo(cliente, t)
    t_acr = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])

    antes = _contar()
    lista = await cliente.get(CATEGORIAS, headers=_cab(t))
    assert lista.status_code == 200
    detalle = await cliente.get(f"{CATEGORIAS}/{lista.json()['items'][0]['public_id']}",
                                headers=_cab(t))
    assert detalle.status_code == 200
    acr = await cliente.get(ACREDITACION(ensayo), headers=_cab(t_acr))
    assert acr.status_code == 200

    assert _contar() == antes, "un GET escribió auditoría"


# ======================================================= POOL / CONTEXTO ====

async def test_pool_1_ocho_peticiones_seguidas(cliente, usuarios_rbac,
                                               usuarios_permisos_separados):
    """Diez peticiones consecutivas sin SQLSTATE 26000 (defecto D-3).

    D-3 se cerró en 7B.1 desactivando la preparación automática en el pool.
    Estos endpoints son nuevos y repiten sus consultas igual que los demás:
    si alguien revirtiera aquella corrección, reventarían en la cuarta.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    t_acr = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    ensayo = await _un_ensayo(cliente, t)

    for vuelta in range(1, 11):
        r = await cliente.get(CATEGORIAS, headers=_cab(t))
        assert r.status_code == 200, f"categorías, vuelta {vuelta}: {r.text}"
        a = await cliente.get(ACREDITACION(ensayo), headers=_cab(t_acr))
        assert a.status_code == 200, f"acreditación, vuelta {vuelta}: {a.text}"


async def test_pool_2_el_contexto_no_sobrevive(cliente, usuarios_rbac):
    """Tras devolver la conexión al pool, el contexto no queda puesto.

    `set_config(..., true)` es LOCAL: PostgreSQL lo descarta al COMMIT. Con un
    SET de sesión, la siguiente petición —posiblemente de otro laboratorio— lo
    heredaría.
    """
    from sacgeo.db.pool import obtener_pool
    from sacgeo.db.tx import leer_contexto

    t = await _token(cliente, usuarios_rbac["lector_email"])
    assert (await cliente.get(CATEGORIAS, headers=_cab(t))).status_code == 200

    pool = obtener_pool()
    async with pool.connection() as conn:
        contexto = await leer_contexto(conn)

    assert contexto["tenant_id"] in (None, ""), contexto
    assert contexto["usuario_id"] in (None, ""), contexto
    assert contexto["ip_origen"] in (None, ""), contexto


# ============================================================== OPENAPI =====

async def test_openapi_documenta_los_tres_endpoints(cliente):
    r = await cliente.get("/openapi.json")
    assert r.status_code == 200
    rutas = r.json()["paths"]

    assert CATEGORIAS in rutas and "get" in rutas[CATEGORIAS]
    assert f"{CATEGORIAS}/{{public_id}}" in rutas
    assert f"{CATALOGO}/{{public_id}}/acreditacion" in rutas

    parametros = {p["name"] for p in rutas[CATEGORIAS]["get"]["parameters"]}
    assert parametros == {"solo_activas", "incluir_vacias"}
    assert "tenant_id" not in parametros

    # Esta fase es solo de lectura: ninguna ruta nueva expone escritura.
    for ruta, metodos in rutas.items():
        if ruta.startswith(CATEGORIAS) or ruta.endswith("/acreditacion"):
            assert set(metodos) == {"get"}, f"{ruta} expone {set(metodos)}"
