"""Fase 7D.1 — componentes de un paquete, contra PostgreSQL con RLS forzada.

Un paquete no es una entidad aparte: es un ensayo con `es_paquete = TRUE`. Lo
que aquí se prueba es su subrecurso —de qué se compone— y, sobre todo, tres
cosas que un diseño escrito solo desde el caso feliz habría pasado por alto:

  · un ensayo que EXISTE pero no es paquete debe dar 404, no `componentes: []`.
    Una lista vacía afirmaría dos cosas falsas a la vez —que es un paquete y
    que está vacío— y confirmaría que el UUID existe;
  · 45 de los 122 componentes reales son texto libre, sin ficha detrás. No son
    un caso excepcional: son el 37 %, y sus cuatro campos nulos forman parte
    del contrato;
  · 8 componentes reales vienen de OTRA categoría (regla P5). Eso es válido y
    ningún test debe prohibirlo.
"""

from datetime import UTC, datetime, timedelta

import httpx
import jwt as pyjwt
import psycopg
import pytest

from sacgeo.config import settings

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"
CATALOGO = "/api/v1/catalogo"
INEXISTENTE = "00000000-0000-4000-8000-000000000000"


def COMPONENTES(public_id: str) -> str:
    return f"{CATALOGO}/{public_id}/componentes"


@pytest.fixture
async def cliente(url_app, usuarios_rbac, usuarios_catalogo,
                  usuarios_permisos_separados, catalogo_tenant_2, monkeypatch):
    """La app real, como `sacgeo_app`: sin superusuario y sin BYPASSRLS."""
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


# ================================================================= AUTH =====

async def test_pkg_01_sin_jwt(cliente, paquete_mixto):
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]))
    assert r.status_code == 401


async def test_pkg_02_jwt_malformado(cliente, paquete_mixto):
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]),
                          headers=_cab("no-es-un-jwt"))
    assert r.status_code == 401


async def test_pkg_03_jwt_con_permisos_inyectados(cliente, usuarios_rbac,
                                                  paquete_mixto, url_super):
    """Token bien FIRMADO con un claim `permissions` añadido → 401.

    La firma es buena y el `sub` es de un usuario real; lo único anómalo es el
    claim. Es el ataque que hace inútil meter autorización en el JWT.
    """
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE email = %s",
                    (usuarios_rbac["lector_email"],))
        (public_id,) = cur.fetchone()

    ahora = datetime.now(UTC)
    token = pyjwt.encode(
        {"sub": str(public_id), "jti": "pkg",
         "iat": int(ahora.timestamp()),
         "exp": int((ahora + timedelta(minutes=15)).timestamp()),
         "permissions": ["catalogo.read"]},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo,
    )
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(token))
    assert r.status_code == 401, "un claim de autorización en el token fue aceptado"


# ================================================================= RBAC =====

async def test_pkg_04_con_catalogo_read(cliente, usuarios_rbac, paquete_mixto):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["componentes"]


async def test_pkg_05_usuario_sin_ningun_rol(cliente, usuarios_catalogo, paquete_mixto):
    t = await _token(cliente, usuarios_catalogo["sin_roles_email"])
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
    assert r.status_code == 403, r.text


async def test_pkg_06_rol_con_otro_permiso(cliente, usuarios_catalogo, paquete_mixto):
    """Rol real con `dashboard.read` y nada más."""
    t = await _token(cliente, usuarios_catalogo["solo_dash_email"])
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
    assert r.status_code == 403, r.text


async def test_pkg_07_acreditacion_read_no_abre_componentes(
    cliente, usuarios_permisos_separados, paquete_mixto
):
    """`acreditacion.read` NO sirve aquí: este endpoint exige `catalogo.read`.

    Repite la lección de 7C.1 sobre el endpoint nuevo: los permisos no se
    heredan del vecino. El usuario tiene un permiso real del sistema, y aun así
    no entra.
    """
    t = await _token(cliente, usuarios_permisos_separados["solo_acreditacion_email"])
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
    assert r.status_code == 403, "acreditacion.read abrió los componentes"


async def test_pkg_07b_solo_catalogo_read_basta(cliente, usuarios_permisos_separados,
                                                paquete_mixto):
    """Y el que SOLO tiene catalogo.read sí entra: el permiso es el correcto."""
    t = await _token(cliente, usuarios_permisos_separados["solo_catalogo_email"])
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
    assert r.status_code == 200, r.text


# =============================================================== TENANT =====

async def test_pkg_08_paquete_propio(cliente, usuarios_rbac, paquete_mixto):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["codigo"] == paquete_mixto["codigo"]


async def test_pkg_09_paquete_de_otro_tenant(cliente, usuarios_rbac, catalogo_tenant_2):
    """Paquete del tenant 2 pedido desde el tenant 1: 404, NUNCA 403."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(COMPONENTES(catalogo_tenant_2["paquete_public_id"]),
                          headers=_cab(t))
    assert r.status_code == 404, r.text
    assert r.status_code != 403, "confirmó la existencia de un recurso ajeno"


async def test_pkg_10_el_dueno_si_lo_ve(cliente, usuarios_rbac, catalogo_tenant_2):
    """Prueba que el 404 anterior lo causa RLS y no un UUID muerto."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.get(COMPONENTES(catalogo_tenant_2["paquete_public_id"]),
                          headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["codigo"] == catalogo_tenant_2["paquete_codigo"]
    assert len(r.json()["componentes"]) == 3


async def test_pkg_11_tenant_id_en_query(cliente, usuarios_rbac, paquete_mixto):
    """`?tenant_id=2` no se ignora: se rechaza."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]),
                          headers=_cab(t), params={"tenant_id": 2})
    assert r.status_code == 422, r.text


# ================================================================== RLS =====

async def test_pkg_12_sin_contexto_no_devuelve_lista_vacia(cliente, usuarios_rbac,
                                                           paquete_mixto, monkeypatch):
    """Sin contexto de tenant la petición MUERE. No responde 200 con [].

    Con un `WHERE tenant_id = <variable vacía>` en Python la respuesta sería
    `200 []`, indistinguible de "este paquete no tiene componentes". Con RLS,
    `fn_app_tenant()` lanza 42501 y `errors.py` lo traduce a 500.
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
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
    assert r.status_code == 500, f"sin contexto respondió {r.status_code}: {r.text}"
    assert r.json().get("componentes") is None, "devolvió una lista en vez de fallar"
    assert set(r.json()) == {"error", "ref"}


async def test_pkg_13_acceso_directo_sin_contexto(url_app):
    """`paquete_componentes` sin contexto lanza 42501, no devuelve cero filas."""
    conn = await psycopg.AsyncConnection.connect(url_app)
    try:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            async with conn.cursor() as cur:
                await cur.execute("SELECT count(*) FROM paquete_componentes")
        await conn.rollback()
    finally:
        await conn.close()


# =========================================================== VALIDACIÓN =====

async def test_pkg_14_uuid_invalido(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(COMPONENTES("no-es-un-uuid"), headers=_cab(t))
    assert r.status_code == 422


async def test_pkg_15_uuid_inexistente(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(COMPONENTES(INEXISTENTE), headers=_cab(t))
    assert r.status_code == 404


async def test_pkg_16_parametro_desconocido(cliente, usuarios_rbac, paquete_mixto):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]),
                          headers=_cab(t), params={"incluir_inactivos": True})
    assert r.status_code == 422


async def test_pkg_17_ensayo_que_no_es_paquete(cliente, usuarios_rbac,
                                               ensayo_no_paquete):
    """Un ensayo que EXISTE y es visible, pero no es paquete: 404.

    Es el test que separa "vacío" de "no existe". Devolver `componentes: []`
    afirmaría que ese ensayo es un paquete sin componentes —falso— y de paso
    confirmaría que el UUID corresponde a algo real.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])

    # El ensayo existe de verdad: la ficha responde 200.
    ficha = await cliente.get(f"{CATALOGO}/{ensayo_no_paquete['public_id']}",
                              headers=_cab(t))
    assert ficha.status_code == 200, ficha.text
    assert ficha.json()["es_paquete"] is False

    r = await cliente.get(COMPONENTES(ensayo_no_paquete["public_id"]), headers=_cab(t))
    assert r.status_code == 404, f"un ensayo normal devolvió {r.status_code}"
    assert "componentes" not in r.json()


async def test_pkg_17b_los_tres_404_son_indistinguibles(cliente, usuarios_rbac,
                                                        ensayo_no_paquete,
                                                        catalogo_tenant_2):
    """Inexistente, ajeno y no-paquete responden EXACTAMENTE lo mismo.

    Si alguno se distinguiera del resto —por el cuerpo, por una cabecera—, el
    endpoint sería un oráculo para enumerar el catálogo de la competencia.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    respuestas = []
    for uuid in (INEXISTENTE,
                 catalogo_tenant_2["paquete_public_id"],
                 ensayo_no_paquete["public_id"]):
        r = await cliente.get(COMPONENTES(uuid), headers=_cab(t))
        respuestas.append((r.status_code, r.json()))

    assert all(c == 404 for c, _ in respuestas)
    assert len({str(cuerpo) for _, cuerpo in respuestas}) == 1, (
        f"los 404 no son idénticos: {respuestas}"
    )


async def test_pkg_17c_paquete_inactivo(cliente, usuarios_rbac, catalogo_tenant_2,
                                        url_super):
    """Un paquete desactivado también da 404.

    Se desactiva en el tenant 2 —nunca en el 1, que usan los demás tests— y se
    comprueba desde su propio laboratorio, donde sí sería visible si estuviera
    activo.
    """
    def _activo(valor: bool) -> None:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT set_config('app.tenant_id', %s, false)",
                        (str(catalogo_tenant_2["tenant_2"]),))
            cur.execute("SELECT set_config('app.usuario_id', '1', false)")
            cur.execute(
                "UPDATE ensayos_catalogo SET activo = %s WHERE codigo = %s AND tenant_id = %s",
                (valor, catalogo_tenant_2["paquete_codigo"], catalogo_tenant_2["tenant_2"]),
            )
            conn.commit()

    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    assert (await cliente.get(COMPONENTES(catalogo_tenant_2["paquete_public_id"]),
                              headers=_cab(t))).status_code == 200

    _activo(False)
    try:
        r = await cliente.get(COMPONENTES(catalogo_tenant_2["paquete_public_id"]),
                              headers=_cab(t))
        assert r.status_code == 404, "un paquete desactivado siguió siendo visible"
    finally:
        _activo(True)


# ============================================================= CONTRATO =====

CLAVES_RESPUESTA = {"public_id", "codigo", "nombre", "componentes"}
CLAVES_COMPONENTE = {
    "orden", "nombre", "norma", "cantidad", "vinculado",
    "public_id", "codigo", "precio_individual", "activo",
}


async def test_pkg_18_claves_exactas(cliente, usuarios_rbac, paquete_mixto):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    cuerpo = (await cliente.get(COMPONENTES(paquete_mixto["public_id"]),
                                headers=_cab(t))).json()

    assert set(cuerpo) == CLAVES_RESPUESTA
    assert cuerpo["public_id"] == paquete_mixto["public_id"]
    for c in cuerpo["componentes"]:
        assert set(c) == CLAVES_COMPONENTE, f"claves inesperadas: {set(c) ^ CLAVES_COMPONENTE}"


async def test_pkg_19_sin_ids_internos(cliente, usuarios_rbac, paquete_mixto):
    """Ni `id`, ni `tenant_id`, ni `paquete_id`, ni `ensayo_componente_id`."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
    crudo = r.text

    for prohibido in ("tenant_id", "paquete_id", "ensayo_componente_id", "ensayo_id"):
        assert prohibido not in crudo, f"se filtró {prohibido}"

    cuerpo = r.json()
    assert "id" not in cuerpo
    for c in cuerpo["componentes"]:
        assert "id" not in c


async def test_pkg_20_componente_vinculado(cliente, usuarios_rbac, paquete_mixto):
    """Un componente vinculado trae ficha, código y precio."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    cuerpo = (await cliente.get(COMPONENTES(paquete_mixto["public_id"]),
                                headers=_cab(t))).json()

    vinculados = [c for c in cuerpo["componentes"] if c["vinculado"]]
    assert len(vinculados) == paquete_mixto["vinculados"]

    for c in vinculados:
        assert c["public_id"] is not None
        assert c["codigo"] is not None
        assert c["precio_individual"] is not None
        assert c["activo"] is not None
        assert c["nombre"]


async def test_pkg_21_componente_descriptivo(cliente, usuarios_rbac, paquete_mixto):
    """Un componente descriptivo trae los cuatro campos en null. Es válido.

    Son el 37 % de los componentes reales. `activo` también va a null y no a
    `true`: la base no registra el estado de un texto libre, y devolver `true`
    afirmaría algo que nadie ha declarado.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    cuerpo = (await cliente.get(COMPONENTES(paquete_mixto["public_id"]),
                                headers=_cab(t))).json()

    descriptivos = [c for c in cuerpo["componentes"] if not c["vinculado"]]
    assert len(descriptivos) == paquete_mixto["descriptivos"]
    assert descriptivos, "este paquete se eligió porque tiene componentes descriptivos"

    for c in descriptivos:
        assert c["public_id"] is None
        assert c["codigo"] is None
        assert c["precio_individual"] is None
        assert c["activo"] is None
        assert c["nombre"], "un componente descriptivo SÍ tiene nombre propio"


async def test_pkg_22_orden_ascendente(cliente, usuarios_rbac, paquete_mixto):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    cuerpo = (await cliente.get(COMPONENTES(paquete_mixto["public_id"]),
                                headers=_cab(t))).json()

    ordenes = [c["orden"] for c in cuerpo["componentes"]]
    assert ordenes == sorted(ordenes)
    assert len(ordenes) == len(set(ordenes)), "uq_paquete_componente_orden lo impide"


# =========================================================== SEGURIDAD ======

async def test_pkg_23_ningun_componente_es_cross_tenant(cliente, usuarios_rbac,
                                                        url_super):
    """Ningún componente devuelto pertenece a otro laboratorio.

    Se recorren TODOS los paquetes del tenant 1 y se comprueba que cada
    `public_id` de componente existe en `ensayos_catalogo` con `tenant_id = 1`.
    La garantía es doble: RLS lo oculta, y las FK COMPUESTAS de
    `paquete_componentes` —(tenant_id, ensayo_componente_id)— lo hacen
    imposible de insertar en primer lugar.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    catalogo = await cliente.get(CATALOGO, headers=_cab(t), params={"limite": 200})
    paquetes = [i["public_id"] for i in catalogo.json()["items"] if i["es_paquete"]]
    assert paquetes, "el seed tiene paquetes"

    ajenos = []
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        for paquete in paquetes:
            cuerpo = (await cliente.get(COMPONENTES(paquete), headers=_cab(t))).json()
            for c in cuerpo["componentes"]:
                if c["public_id"] is None:
                    continue
                cur.execute(
                    "SELECT tenant_id FROM ensayos_catalogo WHERE public_id = %s",
                    (c["public_id"],),
                )
                (tenant,) = cur.fetchone()
                if tenant != 1:
                    ajenos.append((paquete, c["public_id"], tenant))

    assert not ajenos, f"componentes de otro laboratorio: {ajenos}"


async def test_pkg_24_componente_de_otra_categoria_es_valido(cliente, usuarios_rbac,
                                                             url_super):
    """La regla P5 permite componentes de otra categoría, y los hay de verdad.

    El paquete de cantera de Suelos incluye «Abrasión Los Ángeles», que es de
    Concreto. NO es un fallo de aislamiento: el aislamiento es por TENANT, no
    por categoría. Este test existe para que nadie «arregle» eso más adelante.
    """
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT p.public_id, count(*)
              FROM paquete_componentes pc
              JOIN ensayos_catalogo p ON p.id = pc.ensayo_id AND p.tenant_id = pc.tenant_id
              JOIN ensayos_catalogo c ON c.id = pc.ensayo_componente_id
                                     AND c.tenant_id = pc.tenant_id
             WHERE c.categoria_id <> p.categoria_id AND p.tenant_id = 1 AND p.activo
             GROUP BY p.public_id
             ORDER BY 2 DESC LIMIT 1
            """
        )
        fila = cur.fetchone()

    assert fila is not None, "el seed tiene componentes de otra categoría"
    paquete_public_id, esperados = fila

    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(COMPONENTES(str(paquete_public_id)), headers=_cab(t))
    assert r.status_code == 200, r.text
    assert len([c for c in r.json()["componentes"] if c["vinculado"]]) >= esperados


async def test_pkg_25_el_public_id_del_componente_resuelve(cliente, usuarios_rbac,
                                                           paquete_mixto):
    """El `public_id` de un componente sirve para pedir su ficha.

    Es la razón de no usar `vw_paquete_detalle`: la vista solo conserva el
    código del componente, así que con ella este recorrido sería imposible.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    cuerpo = (await cliente.get(COMPONENTES(paquete_mixto["public_id"]),
                                headers=_cab(t))).json()

    vinculados = [c for c in cuerpo["componentes"] if c["vinculado"]]
    assert vinculados

    for c in vinculados[:3]:
        ficha = await cliente.get(f"{CATALOGO}/{c['public_id']}", headers=_cab(t))
        assert ficha.status_code == 200, ficha.text
        assert ficha.json()["codigo"] == c["codigo"]
        assert ficha.json()["nombre"] == c["nombre"]


# =========================================================== AUDITORÍA ======

async def test_pkg_26_un_get_no_escribe_auditoria(cliente, usuarios_rbac,
                                                  paquete_mixto, url_super):
    def _contar() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM auditoria")
            return cur.fetchone()[0]

    t = await _token(cliente, usuarios_rbac["lector_email"])
    antes = _contar()
    r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
    assert r.status_code == 200
    assert _contar() == antes, "un GET escribió auditoría"


# ======================================================= POOL / CONTEXTO ====

async def test_pkg_27_peticiones_consecutivas(cliente, usuarios_rbac, paquete_mixto):
    """Doce peticiones seguidas sin SQLSTATE 26000 (defecto D-3, cerrado en 7B.1)."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    for vuelta in range(1, 13):
        r = await cliente.get(COMPONENTES(paquete_mixto["public_id"]), headers=_cab(t))
        assert r.status_code == 200, f"vuelta {vuelta}: {r.text}"


async def test_pkg_28_contexto_limpio(cliente, usuarios_rbac, paquete_mixto):
    from sacgeo.db.pool import obtener_pool
    from sacgeo.db.tx import leer_contexto

    t = await _token(cliente, usuarios_rbac["lector_email"])
    assert (await cliente.get(COMPONENTES(paquete_mixto["public_id"]),
                              headers=_cab(t))).status_code == 200

    pool = obtener_pool()
    async with pool.connection() as conn:
        contexto = await leer_contexto(conn)

    assert contexto["tenant_id"] in (None, ""), contexto
    assert contexto["usuario_id"] in (None, ""), contexto
    assert contexto["ip_origen"] in (None, ""), contexto


# ============================================================== OPENAPI =====

async def test_pkg_29_ruta_registrada(cliente):
    r = await cliente.get("/openapi.json")
    assert r.status_code == 200
    rutas = r.json()["paths"]

    ruta = f"{CATALOGO}/{{public_id}}/componentes"
    assert ruta in rutas
    assert set(rutas[ruta]) == {"get"}, "esta fase es solo de lectura"
    assert "tenant_id" not in {
        p["name"] for p in rutas[ruta]["get"].get("parameters", [])
    }


async def test_pkg_30_response_model(cliente):
    """El esquema declara el contrato, incluidos los campos que admiten null."""
    esquema = (await cliente.get("/openapi.json")).json()
    componentes = esquema["components"]["schemas"]

    assert "ComponentesResponse" in componentes
    assert "Componente" in componentes

    props = componentes["ComponentesResponse"]["properties"]
    assert set(props) == CLAVES_RESPUESTA

    props_c = componentes["Componente"]["properties"]
    assert set(props_c) == CLAVES_COMPONENTE
    # Los cuatro campos del componente descriptivo deben admitir null.
    for opcional in ("public_id", "codigo", "precio_individual", "activo"):
        assert "anyOf" in props_c[opcional] or props_c[opcional].get("nullable"), (
            f"{opcional} no admite null en el esquema"
        )
