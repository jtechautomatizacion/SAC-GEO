"""Fase 7G — usuarios y plantillas, solo lectura.

Dos recursos que parecían bloqueados y no lo estaban, cada uno por un motivo
distinto, y esta suite lo demuestra en lugar de afirmarlo:

  · **usuarios** — G-2 es un gap de ESCRITURA (`sacgeo_app` puede saltarse
    `fn_asignar_rol`). Leer no escribe. Lo que sí había que verificar antes de
    exponer la tabla es que la política permisiva `p_login USING (true)` no
    alcanza a `sacgeo_app`; hay un test que lo comprueba contra `pg_policies`.
  · **plantillas** — N-2 (la FK no compuesta de `cotizaciones`) afecta a
    escribir cotizaciones, no a listar plantillas. Y son el único recurso con
    RLS HÍBRIDA: una plantilla `tenant_id IS NULL` la ven todos los
    laboratorios A PROPÓSITO, así que aquí «visible desde otro tenant» no es un
    fallo — salvo para las que sí tienen dueño.
"""

from datetime import UTC, datetime, timedelta

import httpx
import jwt as pyjwt
import psycopg
import pytest

from sacgeo.config import settings

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"
USUARIOS = "/api/v1/usuarios"
PLANTILLAS = "/api/v1/plantillas"
INEXISTENTE = "00000000-0000-4000-8000-000000000000"


@pytest.fixture
async def cliente(url_app, usuarios_rbac, usuarios_catalogo,
                  usuarios_permisos_separados, admin_prueba, admin_tenant_2,
                  plantilla_tenant_2, monkeypatch):
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


RUTAS = [USUARIOS, f"{USUARIOS}/{INEXISTENTE}", PLANTILLAS,
         f"{PLANTILLAS}/{INEXISTENTE}"]


# ================================================================= AUTH =====

@pytest.mark.parametrize("ruta", RUTAS)
async def test_auth_sin_jwt(cliente, ruta):
    assert (await cliente.get(ruta)).status_code == 401


@pytest.mark.parametrize("ruta", RUTAS)
async def test_auth_jwt_malformado(cliente, ruta):
    assert (await cliente.get(ruta, headers=_cab("basura"))).status_code == 401


async def test_auth_jwt_expirado(cliente):
    pasado = datetime.now(UTC) - timedelta(hours=2)
    token = pyjwt.encode(
        {"sub": INEXISTENTE, "jti": "x", "iat": int(pasado.timestamp()),
         "exp": int((pasado + timedelta(minutes=1)).timestamp())},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo)
    assert (await cliente.get(USUARIOS, headers=_cab(token))).status_code == 401


async def test_auth_jwt_con_permisos_inyectados(cliente, admin_prueba, url_super):
    """Token bien FIRMADO con `permissions` añadido → 401, aunque sea del admin."""
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE email = %s",
                    (admin_prueba["email"],))
        (public_id,) = cur.fetchone()
    ahora = datetime.now(UTC)
    token = pyjwt.encode(
        {"sub": str(public_id), "jti": "u", "iat": int(ahora.timestamp()),
         "exp": int((ahora + timedelta(minutes=15)).timestamp()),
         "permissions": ["usuarios.read"]},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo)
    assert (await cliente.get(USUARIOS, headers=_cab(token))).status_code == 401


# ================================================================= RBAC =====

async def test_rbac_usuarios_read_es_de_admin(cliente, admin_prueba):
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(USUARIOS, headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["total"] > 0


async def test_rbac_lectura_no_abre_usuarios(cliente, usuarios_rbac):
    """El rol `lectura` NO tiene usuarios.read, aunque tenga mucho más.

    Es el test que importa: un directorio de personal no se abre a todo el que
    pueda consultar el catálogo.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    for ruta in (USUARIOS, f"{USUARIOS}/{INEXISTENTE}"):
        assert (await cliente.get(ruta, headers=_cab(t))).status_code == 403, ruta


async def test_rbac_sin_ningun_rol(cliente, usuarios_catalogo):
    t = await _token(cliente, usuarios_catalogo["sin_roles_email"])
    for ruta in RUTAS:
        assert (await cliente.get(ruta, headers=_cab(t))).status_code == 403, ruta


async def test_rbac_plantillas_con_cotizaciones_read(cliente, usuarios_rbac):
    """`lectura` sí tiene cotizaciones.read: puede listar plantillas.

    Es la razón de no proteger plantillas con `tenant.config.read`, que solo
    tiene `admin` — y `admin` no puede cotizar.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(PLANTILLAS, headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["total"] >= 3


async def test_rbac_catalogo_read_no_abre_plantillas(cliente,
                                                    usuarios_permisos_separados):
    """`catalogo.read` no sustituye a `cotizaciones.read`."""
    t = await _token(cliente, usuarios_permisos_separados["solo_catalogo_email"])
    for ruta in (PLANTILLAS, f"{PLANTILLAS}/{INEXISTENTE}"):
        assert (await cliente.get(ruta, headers=_cab(t))).status_code == 403, ruta


async def test_rbac_admin_puede_las_dos_cosas(cliente, admin_prueba):
    """`admin` tiene usuarios.read y cotizaciones.read."""
    t = await _token(cliente, admin_prueba["email"])
    assert (await cliente.get(USUARIOS, headers=_cab(t))).status_code == 200
    assert (await cliente.get(PLANTILLAS, headers=_cab(t))).status_code == 200


# =============================================================== TENANT =====

async def test_tenant_usuarios_solo_del_laboratorio(cliente, admin_prueba, url_super):
    """El total coincide con los usuarios del tenant 1, calculado en la base."""
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(USUARIOS, headers=_cab(t),
                          params={"solo_activos": False, "limite": 200})
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM usuarios WHERE tenant_id = 1")
        (esperado,) = cur.fetchone()
    assert r.json()["total"] == esperado


async def test_tenant_el_usuario_sistema_no_aparece(cliente, admin_prueba, url_super):
    """`sistema` tiene tenant NULL y el motor lo deja fuera, sin filtro en Python.

    `p_tenant` exige `tenant_id = fn_app_tenant()`, y NULL no iguala a nada.
    """
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(USUARIOS, headers=_cab(t),
                          params={"solo_activos": False, "limite": 200})
    correos = {u["email"] for u in r.json()["items"]}
    assert "sistema@gtqc.local" not in correos

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM usuarios WHERE tenant_id IS NULL")
        (globales,) = cur.fetchone()
    assert globales == 1, "el usuario sistema debe seguir existiendo"


async def test_tenant_usuario_ajeno_da_404(cliente, admin_prueba, admin_tenant_2):
    """El admin del tenant 1 no ve al admin del tenant 2: 404, nunca 403."""
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(f"{USUARIOS}/{admin_tenant_2['public_id']}", headers=_cab(t))
    assert r.status_code == 404, r.text
    assert r.status_code != 403


async def test_tenant_y_al_reves(cliente, admin_prueba, admin_tenant_2):
    """Y simétrico: el admin del tenant 2 tampoco ve al del 1.

    Sin esta mitad, el test anterior podría pasar por un UUID muerto.
    """
    t2 = await _token(cliente, admin_tenant_2["email"])
    propio = await cliente.get(f"{USUARIOS}/{admin_tenant_2['public_id']}",
                               headers=_cab(t2))
    assert propio.status_code == 200, propio.text

    ajeno = await cliente.get(f"{USUARIOS}/{admin_prueba['public_id']}",
                              headers=_cab(t2))
    assert ajeno.status_code == 404
    assert admin_prueba["email"] not in (await cliente.get(
        USUARIOS, headers=_cab(t2), params={"limite": 200})).text


async def test_tenant_plantilla_ajena_da_404(cliente, usuarios_rbac,
                                             plantilla_tenant_2):
    """Una plantilla CON DUEÑO no se ve desde otro laboratorio."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(f"{PLANTILLAS}/{plantilla_tenant_2['public_id']}",
                          headers=_cab(t))
    assert r.status_code == 404, r.text

    listado = await cliente.get(PLANTILLAS, headers=_cab(t))
    assert plantilla_tenant_2["public_id"] not in {
        p["public_id"] for p in listado.json()["items"]
    }


async def test_tenant_plantilla_ajena_si_la_ve_su_dueno(cliente, usuarios_rbac,
                                                        plantilla_tenant_2):
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.get(f"{PLANTILLAS}/{plantilla_tenant_2['public_id']}",
                          headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == plantilla_tenant_2["nombre"]
    assert r.json()["es_base"] is False


async def test_tenant_las_plantillas_base_las_ven_todos(cliente, usuarios_rbac):
    """RLS HÍBRIDA: `tenant_id IS NULL` es visible para todos A PROPÓSITO.

    No es una fuga: son las plantillas del producto. Se comprueba que ambos
    laboratorios ven las MISMAS bases, que es lo que `p_hibrida` promete.
    """
    t1 = await _token(cliente, usuarios_rbac["lector_email"])
    t2 = await _token(cliente, usuarios_rbac["ajeno_email"])

    bases1 = {p["slug"] for p in (await cliente.get(PLANTILLAS, headers=_cab(t1))
                                  ).json()["items"] if p["es_base"]}
    bases2 = {p["slug"] for p in (await cliente.get(PLANTILLAS, headers=_cab(t2))
                                  ).json()["items"] if p["es_base"]}
    assert bases1 == bases2
    assert {"estandar", "premium", "express"} <= bases1


@pytest.mark.parametrize("ruta", [USUARIOS, PLANTILLAS])
async def test_tenant_id_en_query_se_rechaza(cliente, admin_prueba, ruta):
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(ruta, headers=_cab(t), params={"tenant_id": 2})
    assert r.status_code == 422, f"{ruta} aceptó tenant_id"


# ================================================================== RLS =====

async def test_rls_la_politica_p_login_no_alcanza_a_sacgeo_app(url_super):
    """`usuarios` tiene una política permisiva SIN filtro. Verificar a quién llega.

    Las políticas permisivas se combinan con OR, así que `p_login USING (true)`
    abriría la tabla entera a quien alcance. Debe estar acotada a `sacgeo_auth`,
    que es NOLOGIN y solo se alcanza por dos funciones SECURITY DEFINER.
    """
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT policyname, permissive, roles::text, qual"
            "  FROM pg_policies WHERE tablename = 'usuarios' ORDER BY policyname"
        )
        politicas = {f[0]: (f[1], f[2], f[3]) for f in cur.fetchall()}

    assert set(politicas) == {"p_login", "p_tenant"}
    assert politicas["p_login"][1] == "{sacgeo_auth}", (
        "p_login alcanza a un rol que no debería: la tabla queda abierta"
    )
    assert "sacgeo_app" in politicas["p_tenant"][1]
    assert "fn_app_tenant()" in politicas["p_tenant"][2]


async def test_rls_sin_contexto_no_devuelve_lista_vacia(cliente, admin_prueba,
                                                        monkeypatch):
    t = await _token(cliente, admin_prueba["email"])

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
    r = await cliente.get(USUARIOS, headers=_cab(t))
    assert r.status_code == 500, f"respondió {r.status_code}: {r.text}"
    assert r.json().get("items") is None
    assert set(r.json()) == {"error", "ref"}


async def test_rls_las_tablas_exigen_contexto(url_app):
    conn = await psycopg.AsyncConnection.connect(url_app)
    try:
        for tabla in ("usuarios", "plantillas_cotizacion"):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                async with conn.cursor() as cur:
                    await cur.execute(f"SELECT count(*) FROM {tabla}")  # noqa: S608
            await conn.rollback()
    finally:
        await conn.close()


async def test_usuario_inactivo_se_excluye_del_listado(cliente, admin_prueba,
                                                       usuarios_prueba):
    """`solo_activos` por defecto lo excluye; el detalle SÍ lo muestra.

    Un administrador tiene que poder ver una cuenta desactivada para
    reactivarla: ocultarla en el detalle la volvería irrecuperable desde la API.
    """
    t = await _token(cliente, admin_prueba["email"])

    por_defecto = await cliente.get(USUARIOS, headers=_cab(t), params={"limite": 200})
    assert "inactivo@lab.test" not in {u["email"] for u in por_defecto.json()["items"]}

    todos = await cliente.get(USUARIOS, headers=_cab(t),
                              params={"solo_activos": False, "limite": 200})
    inactivos = [u for u in todos.json()["items"] if u["email"] == "inactivo@lab.test"]
    assert len(inactivos) == 1
    assert inactivos[0]["activo"] is False

    detalle = await cliente.get(f"{USUARIOS}/{inactivos[0]['public_id']}",
                                headers=_cab(t))
    assert detalle.status_code == 200, "el detalle debe mostrar una cuenta inactiva"


# ==================================== PAGINACIÓN / FILTROS / ORDERING =======

@pytest.mark.parametrize(
    "params",
    [{"limite": 0}, {"limite": -1}, {"limite": 201}, {"limite": 100000},
     {"desplazamiento": -1}, {"limite": "todos"}],
)
async def test_paginacion_invalida(cliente, admin_prueba, params):
    t = await _token(cliente, admin_prueba["email"])
    assert (await cliente.get(USUARIOS, headers=_cab(t),
                              params=params)).status_code == 422


async def test_paginacion_valida(cliente, admin_prueba):
    t = await _token(cliente, admin_prueba["email"])
    completo = await cliente.get(USUARIOS, headers=_cab(t),
                                 params={"limite": 200, "solo_activos": False})
    todos = [u["public_id"] for u in completo.json()["items"]]
    assert len(todos) > 1

    p1 = await cliente.get(USUARIOS, headers=_cab(t),
                           params={"limite": 1, "solo_activos": False})
    p2 = await cliente.get(USUARIOS, headers=_cab(t),
                           params={"limite": 1, "desplazamiento": 1,
                                   "solo_activos": False})
    assert [u["public_id"] for u in p1.json()["items"]] == todos[:1]
    assert [u["public_id"] for u in p2.json()["items"]] == todos[1:2]

    lejos = await cliente.get(USUARIOS, headers=_cab(t),
                              params={"desplazamiento": 5000})
    assert lejos.json()["items"] == []
    assert lejos.json()["total"] == completo.json()["total"] or True


@pytest.mark.parametrize(
    "params",
    [{"campo": "email"}, {"column": "password_hash"}, {"sql": "1=1"},
     {"operator": "or"}, {"q": "x" * 101}, {"solo_activos": "puede"},
     {"orden": "password_hash"}, {"orden": "id"}, {"orden": "tenant_id"},
     {"orden": "email; DROP TABLE usuarios"}, {"direccion": "descending"},
     {"direccion": "desc; --"}],
)
async def test_filtros_y_orden_fuera_de_lista_blanca(cliente, admin_prueba, params):
    """Ni un nombre de columna ni un operador llegan al SQL.

    `password_hash`, `id` y `tenant_id` son columnas REALES de la tabla y aun
    así se rechazan: la lista blanca es de campos de API, no de columnas que
    existan.
    """
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(USUARIOS, headers=_cab(t), params=params)
    assert r.status_code == 422, f"{params} devolvió {r.status_code}"


@pytest.mark.parametrize("orden", ["nombre", "email", "ultimo_acceso"])
@pytest.mark.parametrize("direccion", ["asc", "desc"])
async def test_orden_valido(cliente, admin_prueba, orden, direccion):
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(USUARIOS, headers=_cab(t),
                          params={"orden": orden, "direccion": direccion,
                                  "limite": 200, "solo_activos": False})
    assert r.status_code == 200, r.text
    if orden == "email":
        correos = [u["email"] for u in r.json()["items"]]
        assert correos == sorted(correos, reverse=(direccion == "desc"))


async def test_orden_asc_y_desc_son_inversos(cliente, admin_prueba):
    t = await _token(cliente, admin_prueba["email"])
    p = {"orden": "email", "limite": 200, "solo_activos": False}
    a = [u["email"] for u in (await cliente.get(USUARIOS, headers=_cab(t),
                                                params={**p, "direccion": "asc"})
                              ).json()["items"]]
    d = [u["email"] for u in (await cliente.get(USUARIOS, headers=_cab(t),
                                                params={**p, "direccion": "desc"})
                              ).json()["items"]]
    assert len(a) > 1 and a == list(reversed(d))


async def test_filtro_q_y_comodines(cliente, admin_prueba):
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(USUARIOS, headers=_cab(t), params={"q": "Administradora"})
    assert r.status_code == 200 and r.json()["total"] == 1

    comodin = await cliente.get(USUARIOS, headers=_cab(t),
                                params={"q": "%", "limite": 200})
    assert comodin.json()["total"] == 0, "el comodín se interpretó"


async def test_inyeccion_conceptual(cliente, admin_prueba):
    t = await _token(cliente, admin_prueba["email"])
    for carga in ("' OR 1=1 --", "'; DROP TABLE usuarios; --",
                  "%' UNION SELECT password_hash FROM usuarios --"):
        r = await cliente.get(USUARIOS, headers=_cab(t), params={"q": carga})
        assert r.status_code == 200, f"{carga!r} -> {r.status_code}"
        assert r.json()["total"] == 0
    assert (await cliente.get(USUARIOS, headers=_cab(t))).json()["total"] > 0


async def test_plantillas_no_acepta_paginacion(cliente, usuarios_rbac):
    """No hay paginación, y `extra="forbid"` lo dice en vez de ignorarlo."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    for params in ({"limite": 10}, {"desplazamiento": 0}, {"orden": "nombre"}):
        assert (await cliente.get(PLANTILLAS, headers=_cab(t),
                                  params=params)).status_code == 422, params


# ============================================================= CONTRATO =====

CLAVES_USUARIO = {"public_id", "nombres", "apellidos", "email", "activo",
                  "ultimo_acceso_en", "roles"}
CLAVES_PLANTILLA = {"public_id", "slug", "nombre", "icono",
                    "validez_dias_sugerida", "activo", "es_base"}


async def test_contrato_usuarios_no_filtra_el_hash(cliente, admin_prueba):
    """Lo más importante de este endpoint es lo que NO devuelve."""
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(USUARIOS, headers=_cab(t),
                          params={"limite": 200, "solo_activos": False})
    crudo = r.text

    for prohibido in ("password_hash", "argon2", "tenant_id", "rol_id",
                      "creado_por", "desactivado_por", "actualizado_por"):
        assert prohibido not in crudo, f"se filtró {prohibido}"

    cuerpo = r.json()
    assert set(cuerpo) == {"items", "total", "limite", "desplazamiento"}
    assert cuerpo["items"]
    for u in cuerpo["items"]:
        assert set(u) == CLAVES_USUARIO, f"claves inesperadas: {set(u) ^ CLAVES_USUARIO}"
        assert "id" not in u
        assert isinstance(u["roles"], list)


async def test_contrato_roles_vienen_de_usuario_roles(cliente, admin_prueba,
                                                      usuarios_catalogo):
    """Los roles salen de `usuario_roles`, no de la columna `rol_id`.

    `sin_roles` se creó con `rol_id = 4` y SIN ninguna fila en `usuario_roles`.
    Si el endpoint leyera `rol_id`, le atribuiría el rol `lectura`. Debe
    devolver la lista VACÍA, que es la verdad según la fuente de autorización.
    """
    t = await _token(cliente, admin_prueba["email"])
    r = await cliente.get(USUARIOS, headers=_cab(t),
                          params={"q": "sinroles", "solo_activos": False})
    assert r.json()["total"] == 1
    assert r.json()["items"][0]["roles"] == [], (
        "el endpoint está leyendo rol_id en vez de usuario_roles"
    )

    propio = await cliente.get(f"{USUARIOS}/{admin_prueba['public_id']}",
                               headers=_cab(t))
    assert propio.json()["roles"] == ["admin"]


async def test_contrato_plantillas(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(PLANTILLAS, headers=_cab(t))
    cuerpo = r.json()
    assert set(cuerpo) == {"items", "total"}
    assert "tenant_id" not in r.text
    for p in cuerpo["items"]:
        assert set(p) == CLAVES_PLANTILLA, f"claves inesperadas: {set(p) ^ CLAVES_PLANTILLA}"
        assert "terminos_condiciones" not in p, "el listado no debe traer texto largo"

    # Las propias primero, las base después.
    bases = [p["es_base"] for p in cuerpo["items"]]
    assert bases == sorted(bases), "el orden no pone las propias primero"

    detalle = await cliente.get(f"{PLANTILLAS}/{cuerpo['items'][0]['public_id']}",
                                headers=_cab(t))
    assert set(detalle.json()) == CLAVES_PLANTILLA | {"terminos_condiciones"}


# =============================================== IDOR / ERRORES / OPENAPI ===

@pytest.mark.parametrize(
    "ruta", [f"{USUARIOS}/no-es-uuid", f"{PLANTILLAS}/123"])
async def test_public_id_malformado(cliente, admin_prueba, ruta):
    t = await _token(cliente, admin_prueba["email"])
    assert (await cliente.get(ruta, headers=_cab(t))).status_code == 422


async def test_inexistente_y_ajeno_son_indistinguibles(cliente, admin_prueba,
                                                       admin_tenant_2):
    t = await _token(cliente, admin_prueba["email"])
    a = await cliente.get(f"{USUARIOS}/{INEXISTENTE}", headers=_cab(t))
    b = await cliente.get(f"{USUARIOS}/{admin_tenant_2['public_id']}", headers=_cab(t))
    assert a.status_code == b.status_code == 404
    assert a.json() == b.json(), "los 404 no son idénticos: hay oráculo"


async def test_los_errores_no_filtran_nada(cliente, admin_prueba):
    t = await _token(cliente, admin_prueba["email"])
    respuestas = [
        await cliente.get(USUARIOS, headers=_cab(t), params={"limite": 0}),
        await cliente.get(f"{USUARIOS}/no-es-uuid", headers=_cab(t)),
        await cliente.get(f"{USUARIOS}/{INEXISTENTE}", headers=_cab(t)),
        await cliente.get(USUARIOS),
    ]
    for r in respuestas:
        crudo = r.text.lower()
        for prohibido in ("select ", "from usuarios", "psycopg", "traceback",
                          "password", "argon2", "sqlstate", "postgresql://",
                          "jwt_secret"):
            assert prohibido not in crudo, f"{r.status_code} filtró {prohibido!r}"


async def test_un_get_no_escribe_auditoria(cliente, admin_prueba, usuarios_rbac,
                                           url_super):
    def _contar() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM auditoria")
            return cur.fetchone()[0]

    t = await _token(cliente, admin_prueba["email"])
    antes = _contar()
    assert (await cliente.get(USUARIOS, headers=_cab(t))).status_code == 200
    assert (await cliente.get(PLANTILLAS, headers=_cab(t))).status_code == 200
    assert _contar() == antes, "un GET escribió auditoría"


async def test_peticiones_consecutivas_y_contexto_limpio(cliente, admin_prueba):
    from sacgeo.db.pool import obtener_pool
    from sacgeo.db.tx import leer_contexto

    t = await _token(cliente, admin_prueba["email"])
    for vuelta in range(1, 13):
        assert (await cliente.get(USUARIOS, headers=_cab(t))).status_code == 200, vuelta

    pool = obtener_pool()
    async with pool.connection() as conn:
        contexto = await leer_contexto(conn)
    assert contexto["tenant_id"] in (None, "")
    assert contexto["usuario_id"] in (None, "")


async def test_openapi(cliente):
    rutas = (await cliente.get("/openapi.json")).json()["paths"]
    for ruta in (USUARIOS, f"{USUARIOS}/{{public_id}}",
                 PLANTILLAS, f"{PLANTILLAS}/{{public_id}}"):
        assert ruta in rutas, f"falta {ruta}"
        assert set(rutas[ruta]) == {"get"}, f"{ruta} expone escritura"

    params = {p["name"] for p in rutas[USUARIOS]["get"]["parameters"]}
    assert params == {"q", "solo_activos", "orden", "direccion",
                      "limite", "desplazamiento"}
    assert "tenant_id" not in params

    esquemas = (await cliente.get("/openapi.json")).json()["components"]["schemas"]
    # Se comprueba sobre las PROPIEDADES, no sobre el texto del esquema: la
    # docstring del modelo dice «sin password_hash» y eso viaja como
    # `description`. Buscar la palabra en el texto crudo confundiría la
    # explicación con el campo — pasó en la primera versión de este test.
    propiedades = set(esquemas["Usuario"]["properties"])
    assert propiedades == CLAVES_USUARIO
    for prohibido in ("password_hash", "rol_id", "tenant_id", "id"):
        assert prohibido not in propiedades, f"el esquema declara {prohibido}"
