"""Fase 7B — el primer recurso de negocio, contra PostgreSQL con RLS forzada.

Estos tests no comprueban que el catálogo "funcione". Comprueban que NO
funciona cuando no debe: sin token, sin permiso, desde otro laboratorio, sin
contexto de tenant, o con un token al que alguien le metió permisos.

El caso feliz ocupa dos tests. Los otros veinte son el motivo de que este
archivo exista.
"""

from datetime import UTC, datetime, timedelta

import httpx
import jwt as pyjwt
import psycopg
import pytest

from sacgeo.config import settings

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"
RUTA = "/api/v1/catalogo"


@pytest.fixture
async def cliente(url_app, usuarios_rbac, catalogo_tenant_2, monkeypatch):
    """La app real, apuntando a la base desechable, conectada como sacgeo_app.

    `sacgeo_app` no es superusuario, no tiene BYPASSRLS y no posee las tablas:
    las políticas se evalúan de verdad. Con `sacgeo_dev` estos tests pasarían
    igual sin que RLS interviniera, es decir, probarían lo contrario de lo que
    dicen probar.
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


# ======================================================== AUTENTICACIÓN =====

async def test_1_sin_bearer(cliente):
    r = await cliente.get(RUTA)
    assert r.status_code == 401


async def test_2_jwt_malformado(cliente):
    r = await cliente.get(RUTA, headers=_cab("esto-no-es-un-jwt"))
    assert r.status_code == 401


async def test_3_jwt_expirado(cliente, usuarios_rbac):
    """Un token bien firmado pero caducado no sirve."""
    pasado = datetime.now(UTC) - timedelta(hours=2)
    token = pyjwt.encode(
        {"sub": "00000000-0000-0000-0000-000000000001", "jti": "x",
         "iat": int(pasado.timestamp()),
         "exp": int((pasado + timedelta(minutes=1)).timestamp())},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo,
    )
    r = await cliente.get(RUTA, headers=_cab(token))
    assert r.status_code == 401


async def test_4_jwt_con_permisos_inyectados(cliente, usuarios_rbac, url_super):
    """Un token CORRECTAMENTE FIRMADO al que se le añade `permissions` se rechaza.

    Es el ataque que hace inútil meter autorización en el JWT: quien consiga
    firmar —o quien escriba el emisor con prisa— se otorga lo que quiera. Aquí
    el token lleva la firma buena y el `sub` de un usuario real; lo único
    anómalo es el claim. Debe dar 401, no 200.
    """
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE email = %s",
                    (usuarios_rbac["lector_email"],))
        (public_id,) = cur.fetchone()

    ahora = datetime.now(UTC)
    token = pyjwt.encode(
        {"sub": str(public_id), "jti": "y",
         "iat": int(ahora.timestamp()),
         "exp": int((ahora + timedelta(minutes=15)).timestamp()),
         "permissions": ["catalogo.read", "cotizaciones.create"]},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo,
    )
    r = await cliente.get(RUTA, headers=_cab(token))
    assert r.status_code == 401, "un claim de autorización en el token fue aceptado"


async def test_5_usuario_desactivado(cliente, usuarios_prueba, url_super):
    """El estado se consulta en CADA petición, no se lee del token.

    El usuario se desactiva DESPUÉS de emitir un token válido: si el backend
    confiara en el token, seguiría entrando hasta que expirase.
    """
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE id = %s",
                    (usuarios_prueba["inactivo"],))
        (public_id,) = cur.fetchone()

    from sacgeo.security import jwt as jwt_mod
    token, _, _ = jwt_mod.emitir_access_token(str(public_id))

    r = await cliente.get(RUTA, headers=_cab(token))
    assert r.status_code == 401


# ================================================================ RBAC ======

async def test_6_con_permiso(cliente, usuarios_rbac):
    """El rol `lectura` tiene catalogo.read. Caso feliz."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(RUTA, headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["total"] > 0


async def test_7_usuario_sin_ningun_rol(cliente, usuarios_catalogo):
    """Autenticado, con tenant, y sin una sola fila en `usuario_roles`: 403.

    Es el estado de una cuenta recién creada, y el que demuestra que el
    conjunto vacío de permisos DENIEGA. Si el guard estuviera escrito al revés
    —"si no tiene permisos, déjalo pasar"— este sería el único test que lo
    atraparía.
    """
    t = await _token(cliente, usuarios_catalogo["sin_roles_email"])
    r = await cliente.get(RUTA, headers=_cab(t))
    assert r.status_code == 403, r.text
    assert r.status_code not in (401, 404), "403 confundido con otro error"


async def test_8_rol_sin_ese_permiso(cliente, usuarios_catalogo):
    """Un rol REAL, con permisos, pero sin `catalogo.read`: 403.

    Distinto del test 7: aquí el usuario sí tiene rol y sí tiene un permiso
    (`dashboard.read`). Lo que se comprueba es que el guard mira el código
    concreto y no se conforma con "tiene algún permiso".
    """
    t = await _token(cliente, usuarios_catalogo["solo_dash_email"])
    r = await cliente.get(RUTA, headers=_cab(t))
    assert r.status_code == 403, "un rol sin catalogo.read entró al catálogo"


# ========================================================= MULTITENANT ======

async def test_9_tenant_ve_solo_lo_suyo(cliente, usuarios_rbac, url_super):
    """El total que devuelve la API coincide con lo que tiene ESE laboratorio.

    El esperado se calcula en la base, no se escribe a mano: una constante aquí
    dejaría de ser cierta en cuanto cambie el seed, y el test seguiría verde
    mintiendo.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(RUTA, headers=_cab(t), params={"limite": 200})
    assert r.status_code == 200, r.text

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM vw_catalogo_disponible WHERE tenant_id = 1")
        (esperado,) = cur.fetchone()

    assert r.json()["total"] == esperado


async def test_10_no_ve_el_ensayo_del_otro_laboratorio(cliente, usuarios_rbac,
                                                       catalogo_tenant_2):
    """El ensayo sembrado en el tenant 2 no aparece para un usuario del tenant 1.

    Se busca por su nombre exacto, así que un fallo de aislamiento no podría
    esconderse detrás de la paginación.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(RUTA, headers=_cab(t),
                          params={"q": catalogo_tenant_2["nombre"], "limite": 200})
    assert r.status_code == 200, r.text
    cuerpo = r.json()
    assert cuerpo["total"] == 0, "se filtró el catálogo del otro laboratorio"
    assert cuerpo["items"] == []

    # Y al revés: desde el tenant 2 sí se ve. Si no, el test anterior pasaría
    # porque el ensayo no existe, no porque RLS lo oculte.
    t2 = await _token(cliente, usuarios_rbac["ajeno_email"])
    r2 = await cliente.get(RUTA, headers=_cab(t2),
                           params={"q": catalogo_tenant_2["nombre"]})
    assert r2.status_code == 200, r2.text
    assert r2.json()["total"] == 1, "el dueño del ensayo tampoco lo ve"


async def test_11_public_id_ajeno_da_404(cliente, usuarios_rbac, catalogo_tenant_2):
    """Pedir por UUID un ensayo de otro laboratorio: 404, NUNCA 403.

    Un 403 confirmaría que ese UUID corresponde a algo real y convertiría el
    endpoint en un oráculo para enumerar el catálogo de la competencia. Con RLS
    el 404 además es literalmente cierto: la fila no existe para esta sesión.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(f"{RUTA}/{catalogo_tenant_2['public_id']}", headers=_cab(t))
    assert r.status_code == 404, r.text
    assert r.status_code != 403, "el endpoint confirmó la existencia de un recurso ajeno"

    # El dueño sí lo obtiene: prueba que el 404 lo causa RLS y no un UUID muerto.
    t2 = await _token(cliente, usuarios_rbac["ajeno_email"])
    r2 = await cliente.get(f"{RUTA}/{catalogo_tenant_2['public_id']}", headers=_cab(t2))
    assert r2.status_code == 200, r2.text
    assert r2.json()["codigo"] == catalogo_tenant_2["codigo"]


async def test_12_identidad_sin_tenant(cliente, url_super):
    """Una identidad sin laboratorio no obtiene sesión.

    El diseño de 7A esperaba 403 desde `get_current_tenant`. La realidad es
    401, y una capa antes: `fn_sesion_resolver_usuario` filtra
    `tenant_id IS NOT NULL`, así que el usuario `sistema` no llega siquiera a
    la resolución de tenant. Es una garantía MÁS fuerte, no más débil, y se
    comprueba tal como es.
    """
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE tenant_id IS NULL")
        (public_id,) = cur.fetchone()

    from sacgeo.security import jwt as jwt_mod
    token, _, _ = jwt_mod.emitir_access_token(str(public_id))

    r = await cliente.get(RUTA, headers=_cab(token))
    assert r.status_code == 401


def test_12b_get_current_tenant_rechaza_tenant_nulo():
    """La segunda línea de defensa existe y devuelve 403.

    Aunque hoy sea inalcanzable por HTTP, el día que el Super Admin de
    plataforma pueda iniciar sesión, ésta es la barrera que queda.
    """
    from fastapi import HTTPException

    from sacgeo.security.tenant import Sesion, TenantNoAutorizado, resolver_tenant_activo

    with pytest.raises(TenantNoAutorizado):
        resolver_tenant_activo(Sesion("00000000-0000-0000-0000-000000000000", 1, None))

    assert HTTPException  # el 403 lo produce get_current_tenant al capturarla


# ================================================================= RLS ======

async def test_13_sin_contexto_no_devuelve_lista_vacia(cliente, usuarios_rbac,
                                                       monkeypatch):
    """Sin contexto de tenant la petición MUERE. No devuelve 200 con [].

    Es el modo de fallo que este diseño evita a propósito: con un filtro
    `WHERE tenant_id = <variable vacía>` en Python, la respuesta sería
    `200 []`, indistinguible de "este laboratorio no tiene ensayos". Con RLS,
    `fn_app_tenant()` lanza 42501, `errors.py` lo traduce a 500 —porque llegar
    ahí es un bug nuestro, no una denegación al cliente— y el fallo es ruidoso.
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
                    # Se fija el usuario y NO el tenant: el escenario exacto de
                    # un get_db_tx incompleto.
                    await cur.execute(
                        "SELECT set_config('app.usuario_id', %s, true)", (str(usuario_id),)
                    )
                yield conn

    monkeypatch.setattr(deps, "transaccion", _sin_tenant)
    r = await cliente.get(RUTA, headers=_cab(t))
    assert r.status_code == 500, f"sin contexto respondió {r.status_code}: {r.text}"
    assert r.json().get("items") is None, "devolvió una lista en vez de fallar"
    assert set(r.json()) == {"error", "ref"}


async def test_14_la_vista_es_security_invoker(url_super):
    """Sin `security_invoker`, la vista se evaluaría con los privilegios de su
    DUEÑO y las políticas de las tablas subyacentes no se aplicarían.

    Sería el modo de fallo más silencioso posible: las políticas seguirían en
    el catálogo, `pg_policies` las mostraría, y no protegerían nada.
    """
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT c.reloptions FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public' AND c.relname = 'vw_catalogo_disponible'
            """
        )
        (opciones,) = cur.fetchone()
    assert opciones and "security_invoker=true" in opciones


# ========================================================== VALIDACIÓN ======

@pytest.mark.parametrize(
    "params",
    [
        {"limite": 0},                 # 15
        {"limite": 500},               # 16
        {"desplazamiento": -1},        # 17
        {"tenant_id": 2},              # 18 — campo desconocido
        {"q": "x" * 101},              # q > 100
        {"categoria_id": 0},           # categoria_id <= 0
        {"categoria_id": -5},
        {"limite": "muchos"},
    ],
)
async def test_15a20_query_invalida(cliente, usuarios_rbac, params):
    """Todo parámetro fuera de contrato da 422.

    `tenant_id` merece una nota: con `extra="forbid"` se rechaza en vez de
    ignorarse. Ignorarlo devolvería el catálogo del laboratorio propio y el
    cliente creería haber consultado otro — un silencio que esconde el intento.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(RUTA, headers=_cab(t), params=params)
    assert r.status_code == 422, f"{params} devolvió {r.status_code}"


async def test_19_public_id_no_es_uuid(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(f"{RUTA}/no-es-un-uuid", headers=_cab(t))
    assert r.status_code == 422


async def test_20_uuid_valido_inexistente(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(f"{RUTA}/00000000-0000-4000-8000-000000000000", headers=_cab(t))
    assert r.status_code == 404


# ============================================================ CONTRATO ======

CAMPOS_ITEM = {
    "public_id", "codigo", "nombre", "norma", "unidad",
    "precio_base", "es_paquete", "acreditado", "categoria", "subcategoria",
}


async def test_21_contrato_de_la_respuesta(cliente, usuarios_rbac):
    """La respuesta lleva exactamente lo acordado, y NADA de lo prohibido.

    `ensayo_id` y `tenant_id` están en la vista y no deben salir: el id técnico
    no sale nunca de la base —publicar un entero secuencial invita a
    recorrerlo, que es como se produce un IDOR— y el tenant no es un dato que
    el cliente deba manejar.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(RUTA, headers=_cab(t), params={"limite": 3})
    assert r.status_code == 200, r.text
    cuerpo = r.json()

    assert set(cuerpo) == {"items", "total", "limite", "desplazamiento"}
    assert cuerpo["limite"] == 3 and cuerpo["desplazamiento"] == 0
    assert cuerpo["items"], "el catálogo del tenant 1 no puede estar vacío"

    for item in cuerpo["items"]:
        assert set(item) == CAMPOS_ITEM, f"claves inesperadas: {set(item) ^ CAMPOS_ITEM}"
        assert "ensayo_id" not in item
        assert "tenant_id" not in item
        assert set(item["categoria"]) == {"id", "slug", "nombre", "icono", "color_hex"}
        assert set(item["subcategoria"]) == {"id", "nombre"}
        assert "tenant_id" not in item["categoria"]

    # El detalle usa el MISMO modelo: un campo prohibido no puede colarse por
    # la otra ruta.
    r2 = await cliente.get(f"{RUTA}/{cuerpo['items'][0]['public_id']}", headers=_cab(t))
    assert r2.status_code == 200, r2.text
    assert set(r2.json()) == CAMPOS_ITEM


async def test_21b_filtros_y_paginacion(cliente, usuarios_rbac):
    """Los filtros filtran y la paginación no pierde ni repite filas."""
    t = await _token(cliente, usuarios_rbac["lector_email"])

    r = await cliente.get(RUTA, headers=_cab(t),
                          params={"solo_acreditados": True, "limite": 200})
    assert r.status_code == 200
    assert all(i["acreditado"] for i in r.json()["items"])

    completo = await cliente.get(RUTA, headers=_cab(t), params={"limite": 200})
    codigos = [i["codigo"] for i in completo.json()["items"]]

    p1 = await cliente.get(RUTA, headers=_cab(t), params={"limite": 5})
    p2 = await cliente.get(RUTA, headers=_cab(t),
                           params={"limite": 5, "desplazamiento": 5})
    assert [i["codigo"] for i in p1.json()["items"]] == codigos[:5]
    assert [i["codigo"] for i in p2.json()["items"]] == codigos[5:10]
    # El total NO depende de la página: es lo que la función de ventana habría
    # perdido en la última página.
    assert p2.json()["total"] == completo.json()["total"]

    lejos = await cliente.get(RUTA, headers=_cab(t),
                              params={"limite": 5, "desplazamiento": 10_000})
    assert lejos.json()["items"] == []
    assert lejos.json()["total"] == completo.json()["total"], (
        "una página vacía informó total=0"
    )


async def test_21c_el_comodin_de_like_no_se_interpreta(cliente, usuarios_rbac):
    """`q=%` busca el carácter `%`, no "todo".

    Sin escapar, el filtro diría una cosa y haría otra: devolvería el catálogo
    entero mientras el usuario cree haber buscado algo.

    El seed real da la prueba perfecta sin inventar datos: el ensayo AG-11 se
    llama «% de caras fracturadas». Así que la búsqueda correcta devuelve
    EXACTAMENTE ese, y el fallo se distingue del acierto por 1 contra 89 — no
    por 0 contra 89, que también pasaría si el filtro se rompiera del otro lado
    y no devolviera nunca nada.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    completo = await cliente.get(RUTA, headers=_cab(t), params={"limite": 200})
    total_catalogo = completo.json()["total"]

    r = await cliente.get(RUTA, headers=_cab(t), params={"q": "%", "limite": 200})
    assert r.status_code == 200, r.text
    cuerpo = r.json()
    assert cuerpo["total"] < total_catalogo, "el comodín se interpretó: devolvió todo"
    assert cuerpo["total"] == 1
    assert cuerpo["items"][0]["codigo"] == "AG-11"
    assert "%" in cuerpo["items"][0]["nombre"]

    # `_` es el otro comodín, y ningún ensayo lo lleva en el nombre.
    r2 = await cliente.get(RUTA, headers=_cab(t), params={"q": "_", "limite": 200})
    assert r2.json()["total"] == 0, "el comodín _ se interpretó como una letra"


# =========================================================== AUDITORÍA ======

async def test_22_un_get_no_escribe_auditoria(cliente, usuarios_rbac, url_super):
    """Leer el catálogo no deja rastro en `auditoria`.

    La auditoría registra CAMBIOS. Escribir una fila por cada lectura la
    inundaría y haría inútil justo aquello para lo que existe: que un auditor
    ISO 17025 pueda ver quién tocó qué.
    """
    def _contar() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM auditoria")
            return cur.fetchone()[0]

    antes = _contar()
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(RUTA, headers=_cab(t))
    assert r.status_code == 200
    r = await cliente.get(f"{RUTA}/{r.json()['items'][0]['public_id']}", headers=_cab(t))
    assert r.status_code == 200
    assert _contar() == antes, "un GET del catálogo escribió auditoría"


# ====================================================== POOL / CONTEXTO =====

async def test_23_el_contexto_no_sobrevive_a_la_peticion(cliente, usuarios_rbac):
    """Tras devolver la conexión al pool, el contexto no queda puesto.

    `set_config(..., true)` es LOCAL: PostgreSQL lo descarta al COMMIT. Con un
    SET de sesión, la conexión volvería al pool con el tenant todavía puesto y
    la siguiente petición —posiblemente de OTRO laboratorio— lo heredaría. Una
    fuga entre clientes causada por una palabra.
    """
    from sacgeo.db.pool import obtener_pool
    from sacgeo.db.tx import leer_contexto

    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(RUTA, headers=_cab(t))
    assert r.status_code == 200

    pool = obtener_pool()
    async with pool.connection() as conn:
        contexto = await leer_contexto(conn)

    assert contexto["tenant_id"] in (None, ""), contexto
    assert contexto["usuario_id"] in (None, ""), contexto
    assert contexto["ip_origen"] in (None, ""), contexto


# ============================================================== OPENAPI =====

async def test_24_openapi_documenta_los_dos_endpoints(cliente):
    """Ambas rutas aparecen en el esquema, y ninguna que no exista todavía."""
    r = await cliente.get("/openapi.json")
    assert r.status_code == 200
    rutas = r.json()["paths"]

    assert RUTA in rutas and "get" in rutas[RUTA]
    assert f"{RUTA}/{{public_id}}" in rutas

    parametros = {p["name"] for p in rutas[RUTA]["get"]["parameters"]}
    assert {"categoria_id", "solo_acreditados", "q", "limite", "desplazamiento"} <= parametros
    assert "tenant_id" not in parametros

    # Nada de escritura sobre el catálogo: esta fase es solo de lectura.
    for ruta, metodos in rutas.items():
        if ruta.startswith("/api/v1/catalogo"):
            assert set(metodos) == {"get"}, f"{ruta} expone {set(metodos)}"
