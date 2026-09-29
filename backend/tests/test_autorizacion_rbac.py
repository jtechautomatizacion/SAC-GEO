"""Fase 6B — la capa de autorización, contra PostgreSQL con RLS forzada.

Hasta esta fase el backend respondía "quién eres" y "en qué laboratorio
operas", y ahí se detenía: cualquier usuario autenticado habría podido ejecutar
cualquier endpoint de negocio el día que existiera uno. Eso era H-01.

Los endpoints de más abajo NO forman parte del producto. Viven aquí porque no
hay ningún endpoint de negocio todavía y un guard sin nada que guardar no se
puede probar. Se montan sobre una app propia, con el mismo ciclo de vida, el
mismo manejador de errores y el mismo router de autenticación que la real, para
que lo que se prueba sea la cadena de dependencias de verdad y no una maqueta.
"""

import re
from pathlib import Path

import httpx
import psycopg
import pytest
from fastapi import Depends, FastAPI

from sacgeo.api import deps, errors
from sacgeo.api.deps import (
    get_permisos,
    require_all_permissions,
    require_any_permission,
    require_permission,
)
from sacgeo.api.v1 import auth as auth_router
from sacgeo.main import ciclo_de_vida

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"
FUENTE = Path(__file__).resolve().parents[1] / "src" / "sacgeo"

# Endpoints que llegaron a ejecutarse. Un 403 y un 500 se distinguen mirando el
# código de estado; que el CUERPO del endpoint no corriera, no: hay que
# anotarlo desde dentro.
EJECUTADOS: list[str] = []

# Los códigos que usa la app de prueba son reales salvo uno. Ese está puesto a
# propósito y es el sujeto del test 5.
#
# El endpoint lo escribe como literal y no usa esta constante, aunque se
# repita: el detector del test 10 busca literales, que es lo único que puede
# revisar sin ejecutar el código. Pasarlo como variable lo haría invisible
# —pasó en la primera versión de este archivo— y el test habría quedado en
# verde comprobando la nada.
CODIGO_INEXISTENTE = "permiso.inexistente"


def construir_app() -> FastAPI:
    app = FastAPI(lifespan=ciclo_de_vida)
    errors.registrar(app)
    app.include_router(auth_router.router)

    @app.get("/rbac/lectura",
             dependencies=[Depends(require_permission("catalogo.read"))])
    async def _lectura():
        EJECUTADOS.append("lectura")
        return {"ok": True}

    @app.get("/rbac/crear",
             dependencies=[Depends(require_permission("cotizaciones.create"))])
    async def _crear():
        EJECUTADOS.append("crear")
        return {"ok": True}

    @app.get("/rbac/inexistente",
             dependencies=[Depends(require_permission("permiso.inexistente"))])
    async def _inexistente():
        EJECUTADOS.append("inexistente")
        return {"ok": True}

    @app.get("/rbac/cualquiera",
             dependencies=[Depends(require_any_permission(
                 "cotizaciones.approve", "cotizaciones.create"))])
    async def _cualquiera():
        EJECUTADOS.append("cualquiera")
        return {"ok": True}

    @app.get("/rbac/todos",
             dependencies=[Depends(require_all_permissions(
                 "catalogo.read", "cotizaciones.approve"))])
    async def _todos():
        EJECUTADOS.append("todos")
        return {"ok": True}

    # Tres guards sobre la misma petición: el escenario del N+1.
    @app.get("/rbac/tres",
             dependencies=[
                 Depends(require_permission("catalogo.read")),
                 Depends(require_permission("clientes.read")),
                 Depends(require_permission("cotizaciones.read")),
             ])
    async def _tres():
        EJECUTADOS.append("tres")
        return {"ok": True}

    @app.get("/rbac/mis-permisos",
             dependencies=[Depends(require_permission("catalogo.read"))])
    async def _mis_permisos(permisos: frozenset[str] = Depends(get_permisos)):
        return {"permisos": sorted(permisos)}

    return app


@pytest.fixture
async def cliente(url_app, usuarios_rbac, monkeypatch):
    from sacgeo.config import settings
    from sacgeo.db import pool as pool_mod

    monkeypatch.setattr(settings, "database_url", url_app)
    monkeypatch.setattr(pool_mod, "_pool", None)
    monkeypatch.setattr(settings, "require_rls_safe_role", True)

    app = construir_app()
    EJECUTADOS.clear()
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


# ---------------------------------------------------------------- 1 --------

async def test_1_sin_autenticacion(cliente):
    """Un endpoint protegido sin Bearer responde 401, no 403.

    El orden importa: si el guard de permisos corriera antes que la
    autenticación, un anónimo recibiría 403 y el sistema estaría afirmando que
    existe alguien sin permiso donde no hay nadie.
    """
    r = await cliente.get("/rbac/lectura")
    assert r.status_code == 401
    assert "lectura" not in EJECUTADOS


# ---------------------------------------------------------------- 2 --------

async def test_2_con_permiso(cliente, usuarios_rbac):
    """El rol `lectura` tiene catalogo.read: pasa."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get("/rbac/lectura", headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json() == {"ok": True}


# ---------------------------------------------------------------- 3 --------

async def test_3_sin_permiso(cliente, usuarios_rbac):
    """El mismo usuario, autenticado y con sesión válida, NO puede crear.

    Es la demostración de que H-01 queda cerrado: el 403 no viene de que el
    token sea malo ni de que el recurso no exista, viene de que el rol no
    alcanza. Antes de esta fase esta petición habría devuelto 200.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get("/rbac/crear", headers=_cab(t))
    assert r.status_code == 403, r.text
    assert "crear" not in EJECUTADOS


# ---------------------------------------------------------------- 4 --------

async def test_4_aislamiento_multitenant(cliente, usuarios_rbac, url_app):
    """Los permisos de un laboratorio no se prestan al otro.

    `ajeno` es comercial en el tenant 2 y sí puede crear allí. El lector del
    tenant 1 no. Y la comprobación que de verdad importa se hace un nivel más
    abajo: preguntar desde el contexto del tenant 1 por los permisos del
    usuario del tenant 2 devuelve el conjunto VACÍO, porque RLS oculta sus
    filas de `usuario_roles`. No hay código de la API que lo impida — lo impide
    el motor.
    """
    t_ajeno = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.get("/rbac/crear", headers=_cab(t_ajeno))
    assert r.status_code == 200, r.text

    t_lector = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get("/rbac/crear", headers=_cab(t_lector))
    assert r.status_code == 403

    conn = await psycopg.AsyncConnection.connect(url_app)
    try:
        async with conn.cursor() as cur:
            await cur.execute("SELECT set_config('app.tenant_id', '1', false)")
            await cur.execute("SELECT count(*) FROM fn_usuario_permisos(%s)",
                              (usuarios_rbac["ajeno"],))
            (desde_tenant_1,) = await cur.fetchone()
            await cur.execute("SELECT count(*) FROM fn_usuario_permisos(%s)",
                              (usuarios_rbac["lector"],))
            (propios,) = await cur.fetchone()
        await conn.rollback()
    finally:
        await conn.close()
    assert desde_tenant_1 == 0, "RLS no ocultó los roles del otro laboratorio"
    assert propios > 0, "el contexto correcto tiene que ver sus propios permisos"


# ---------------------------------------------------------------- 5 --------

async def test_5_codigo_inexistente(cliente, usuarios_rbac):
    """Un código que no existe en `permisos` deniega. No concede por descuido.

    Es la rama que un guard escrito al revés —"si el permiso no existe, pasa"—
    dejaría abierta, y que nadie notaría hasta que alguien la usara.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get("/rbac/inexistente", headers=_cab(t))
    assert r.status_code == 403
    assert "inexistente" not in EJECUTADOS


# ---------------------------------------------------------------- 6 --------

async def test_6_sin_contexto_falla_cerrado(url_app):
    """Sin contexto de tenant la consulta de permisos ni siquiera se ejecuta.

    No devuelve cero filas —que la API podría confundir con "no tiene
    permisos"—: `fn_app_tenant()` lanza 42501 desde la política de
    `usuario_roles` y la transacción muere. La API traduce ese 42501 a 500,
    porque llegar aquí significaría que `get_db_tx` no fijó el contexto, y eso
    es un bug nuestro, no una denegación al cliente.
    """
    conn = await psycopg.AsyncConnection.connect(url_app)
    try:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            async with conn.cursor() as cur:
                await cur.execute("SELECT count(*) FROM fn_usuario_permisos(1)")
        await conn.rollback()
    finally:
        await conn.close()


# ---------------------------------------------------------------- 7 --------

async def test_7_fallo_de_base_no_concede(cliente, usuarios_rbac, monkeypatch):
    """Si la consulta de permisos falla, el endpoint NO se ejecuta.

    El modo de fallo peligroso sería capturar la excepción y seguir con un
    conjunto vacío —que denegaría— o, peor, tratarla como "no se pudo
    comprobar, dejemos pasar". Aquí la excepción sube, el manejador responde
    500 y la transacción hace ROLLBACK.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])

    async def _explota(conn, usuario_id):
        raise psycopg.OperationalError("conexión perdida durante la prueba")

    monkeypatch.setattr(deps, "_consultar_permisos", _explota)
    r = await cliente.get("/rbac/lectura", headers=_cab(t))
    assert r.status_code == 500
    assert "lectura" not in EJECUTADOS
    # El formato de error es el que ya existía: nada de PostgreSQL sale fuera.
    assert set(r.json()) == {"error", "ref"}


# ---------------------------------------------------------------- 8 --------

async def test_8_multirol_es_la_union(cliente, usuarios_rbac, url_super):
    """Dos roles dan la unión de sus permisos, sin duplicados.

    El esperado no se escribe a mano: se calcula desde la base. Una lista
    copiada aquí dejaría de ser cierta el día que alguien cambie la matriz de
    `rol_permisos`, y el test seguiría en verde mientras miente.
    """
    t = await _token(cliente, usuarios_rbac["multirol_email"])
    r = await cliente.get("/rbac/mis-permisos", headers=_cab(t))
    assert r.status_code == 200, r.text
    obtenidos = r.json()["permisos"]

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT DISTINCT p.codigo
              FROM roles r
              JOIN rol_permisos rp ON rp.rol_id = r.id
              JOIN permisos p ON p.id = rp.permiso_id
             WHERE r.codigo IN ('lectura', 'aprobador')
             ORDER BY 1
            """
        )
        esperados = [f[0] for f in cur.fetchall()]

    assert obtenidos == esperados
    assert len(obtenidos) == len(set(obtenidos)), "la unión trajo duplicados"
    # La unión es estrictamente mayor que cualquiera de las partes: si fuera
    # igual, el test pasaría sin que el segundo rol aportara nada.
    assert "cotizaciones.approve" in obtenidos   # sólo de `aprobador`
    assert "dashboard.read" in obtenidos         # sólo de `lectura`


# ---------------------------------------------------------------- 9 --------

async def test_9_revocacion_surte_efecto(cliente, usuarios_rbac, retirar_rol):
    """Retirar un rol se nota en la petición siguiente, con el MISMO token.

    Es la consecuencia de no guardar los permisos en el JWT ni cachearlos entre
    peticiones. Con permisos en el token, este test sólo pasaría después de que
    el access token expirase.
    """
    t = await _token(cliente, usuarios_rbac["revocable_email"])
    r = await cliente.get("/rbac/lectura", headers=_cab(t))
    assert r.status_code == 200, r.text

    retirar_rol(1, usuarios_rbac["revocable"], "lectura")

    r = await cliente.get("/rbac/lectura", headers=_cab(t))
    assert r.status_code == 403, "el permiso sobrevivió a la revocación"


# --------------------------------------------------------------- 10 --------

_PATRON_GUARD = re.compile(
    r"require_(?:permission|any_permission|all_permissions)\s*\(([^)]*)\)",
    re.DOTALL,
)
_PATRON_LITERAL = re.compile(r"""["']([^"']+)["']""")


def _codigos_exigidos(texto: str) -> set[str]:
    """Extrae los códigos literales que exige cualquier guard de un archivo."""
    encontrados: set[str] = set()
    for m in _PATRON_GUARD.finditer(texto):
        encontrados.update(_PATRON_LITERAL.findall(m.group(1)))
    return encontrados


def _permisos_reales(url: str) -> set[str]:
    with psycopg.connect(url) as conn, conn.cursor() as cur:
        cur.execute("SELECT codigo FROM permisos")
        return {f[0] for f in cur.fetchall()}


def test_10_sin_codigos_huerfanos(url_super):
    """Ningún guard exige un permiso que no exista en `permisos`.

    Un código mal escrito no rompe nada visible: produce un 403 permanente,
    idéntico al de "no le corresponde". El endpoint queda inalcanzable y no se
    nota hasta que alguien lo reclama.

    Se revisa el código DE PRODUCTO. Hoy no hay ningún endpoint de negocio, así
    que ese conjunto está vacío y la comprobación sola no demostraría nada —por
    eso se verifica también que el detector encuentra un huérfano cuando lo
    hay, sobre la app de prueba de este mismo archivo.
    """
    reales = _permisos_reales(url_super)
    assert len(reales) == 31, f"se esperaban 31 permisos, hay {len(reales)}"

    del_producto: set[str] = set()
    for p in FUENTE.rglob("*.py"):
        if "__pycache__" in str(p):
            continue
        del_producto |= _codigos_exigidos(p.read_text("utf-8"))
    assert not (del_producto - reales), (
        f"guards del producto con permisos inexistentes: {del_producto - reales}"
    )

    # El detector funciona: sobre esta app de prueba encuentra exactamente el
    # único código falso que se puso a propósito, y ni uno más.
    de_la_prueba = _codigos_exigidos(Path(__file__).read_text("utf-8"))
    assert de_la_prueba - reales == {CODIGO_INEXISTENTE}


# --------------------------------------------------------------- 11 --------

async def test_11_una_consulta_por_peticion(cliente, usuarios_rbac, monkeypatch):
    """Tres guards en la misma petición, UNA sola consulta de permisos.

    Sin la dependencia intermedia cacheada, cada guard preguntaría por su
    cuenta: tres viajes a PostgreSQL para responder una pregunta, y creciendo
    con cada permiso que se añada a un endpoint.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])

    original = deps._consultar_permisos
    llamadas = []

    async def _contada(conn, usuario_id):
        llamadas.append(usuario_id)
        return await original(conn, usuario_id)

    monkeypatch.setattr(deps, "_consultar_permisos", _contada)
    r = await cliente.get("/rbac/tres", headers=_cab(t))
    assert r.status_code == 200, r.text
    assert len(llamadas) == 1, f"N+1: {len(llamadas)} consultas de permisos"


# ------------------------------------------------------- extras de forma ----

async def test_any_permission_con_uno_basta(cliente, usuarios_rbac):
    """`aprobador` tiene cotizaciones.approve pero no cotizaciones.create."""
    t = await _token(cliente, usuarios_rbac["multirol_email"])
    r = await cliente.get("/rbac/cualquiera", headers=_cab(t))
    assert r.status_code == 200, r.text


async def test_any_permission_sin_ninguno(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get("/rbac/cualquiera", headers=_cab(t))
    assert r.status_code == 403


async def test_all_permissions_completo(cliente, usuarios_rbac):
    """multirol tiene catalogo.read (lectura) y cotizaciones.approve (aprobador)."""
    t = await _token(cliente, usuarios_rbac["multirol_email"])
    r = await cliente.get("/rbac/todos", headers=_cab(t))
    assert r.status_code == 200, r.text


async def test_all_permissions_le_falta_uno(cliente, usuarios_rbac):
    """El lector tiene catalogo.read pero no cotizaciones.approve: falta uno."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get("/rbac/todos", headers=_cab(t))
    assert r.status_code == 403


def test_guard_sin_codigos_es_un_error_al_importar():
    """Un guard vacío se rechaza al construirse, no en producción.

    `require_all_permissions()` sin códigos sería el peor de los dos: el
    conjunto vacío está contenido en cualquier otro, así que dejaría pasar a
    todo el mundo.
    """
    with pytest.raises(ValueError):
        require_all_permissions()
    with pytest.raises(ValueError):
        require_any_permission()
    with pytest.raises(ValueError):
        require_permission("")
