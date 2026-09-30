"""Fase 7I — el PRIMER WRITE de negocio, y la cerradura real de H-02.

Las barreras de 7H.1 existían sin nada que proteger. Esta suite las pone a
prueba sobre una escritura de verdad, y por eso está organizada por los 13
criterios de la fase en lugar de por endpoint.

Lo que se demuestra, en orden de importancia:

  · un campo protegido enviado por el cliente **no se ignora**: responde 422;
  · un `tenant_id` forjado no llega a ninguna parte, y si llegara la política
    `WITH CHECK (tenant_id = fn_app_tenant())` lo rechazaría — hay un test que
    lo comprueba contra PostgreSQL directamente;
  · `clientes.read` a solas NO puede crear;
  · la fila creada queda auditada, con autor sellado y no falsificable;
  · nada de esto se escribe en `sacgeo_dev`: todo va a la base desechable.
"""

import httpx
import psycopg
import pytest

from sacgeo.config import settings

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"
EMPRESAS = "/api/v1/clientes/empresas"


def _nueva(ruc: str, **extra) -> dict:
    cuerpo = {"ruc": ruc, "razon_social": "Constructora " + ruc[-4:] + " S.A.C."}
    cuerpo.update(extra)
    return cuerpo


@pytest.fixture
async def cliente(url_app, usuarios_rbac, usuarios_catalogo,
                  usuarios_permisos_separados, clientes_tenant_1,
                  clientes_tenant_2, monkeypatch):
    """La app real como `sacgeo_app`: sin superusuario, sin BYPASSRLS."""
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


# =================================================== 1. AUTENTICACIÓN (401) ==

async def test_sin_jwt(cliente):
    r = await cliente.post(EMPRESAS, json=_nueva("20500000001"))
    assert r.status_code == 401


async def test_jwt_malformado(cliente):
    r = await cliente.post(EMPRESAS, headers=_cab("basura"), json=_nueva("20500000002"))
    assert r.status_code == 401


async def test_jwt_con_permisos_inyectados(cliente, usuarios_rbac, url_super):
    """Un token FIRMADO con `permissions: [clientes.manage]` → 401.

    Es el ataque que hace inútil meter autorización en el JWT: la firma es buena
    y el `sub` es de un usuario real; lo único anómalo es el claim.
    """
    from datetime import UTC, datetime, timedelta

    import jwt as pyjwt

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE email = %s",
                    (usuarios_rbac["lector_email"],))
        (public_id,) = cur.fetchone()

    ahora = datetime.now(UTC)
    token = pyjwt.encode(
        {"sub": str(public_id), "jti": "w", "iat": int(ahora.timestamp()),
         "exp": int((ahora + timedelta(minutes=15)).timestamp()),
         "permissions": ["clientes.manage"]},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo)

    r = await cliente.post(EMPRESAS, headers=_cab(token), json=_nueva("20500000003"))
    assert r.status_code == 401, "un claim de autorización en el token fue aceptado"


async def test_usuario_desactivado(cliente, usuarios_prueba, url_super):
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE id = %s",
                    (usuarios_prueba["inactivo"],))
        (public_id,) = cur.fetchone()

    from sacgeo.security import jwt as jwt_mod
    token, _, _ = jwt_mod.emitir_access_token(str(public_id))
    r = await cliente.post(EMPRESAS, headers=_cab(token), json=_nueva("20500000004"))
    assert r.status_code == 401


# ========================================================= 2. RBAC (403) ====

async def test_clientes_read_NO_puede_crear(cliente, usuarios_rbac, url_super):
    """EL TEST CENTRAL DEL PERMISO: leer la cartera no autoriza a escribir en ella.

    El rol `lectura` tiene `clientes.read` y NO `clientes.manage`. Si el POST
    colgara del router de lectura heredaría el permiso equivocado y este usuario
    crearía empresas. Se comprueba además que NO quedó ninguna fila.
    """
    def _contar() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM empresas")
            return cur.fetchone()[0]

    t = await _token(cliente, usuarios_rbac["lector_email"])
    antes = _contar()
    r = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500000005"))
    assert r.status_code == 403, r.text
    assert _contar() == antes, "se creó una empresa sin el permiso"


async def test_comercial_si_puede_crear(cliente, usuarios_rbac):
    """`comercial` tiene clientes.manage: el camino feliz, y devuelve 201."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500001001"))
    assert r.status_code == 201, r.text
    assert r.json()["ruc"] == "20500001001"


async def test_sin_ningun_rol(cliente, usuarios_catalogo):
    t = await _token(cliente, usuarios_catalogo["sin_roles_email"])
    r = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500000006"))
    assert r.status_code == 403


async def test_otro_permiso_no_sirve(cliente, usuarios_permisos_separados):
    """`catalogo.read` no abre la escritura de clientes."""
    t = await _token(cliente, usuarios_permisos_separados["solo_catalogo_email"])
    r = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500000007"))
    assert r.status_code == 403


# ============================================ 3. MASS ASSIGNMENT (H-02) =====

CAMPOS_PROTEGIDOS = [
    ("tenant_id", 1),
    ("id", 1),
    ("public_id", "11111111-1111-4111-8111-111111111111"),
    ("creado_por", 1),
    ("creado_en", "2020-01-01T00:00:00Z"),
    ("actualizado_por", 1),
    ("activo", False),
    ("contactos", 99),
]


@pytest.mark.parametrize("campo,valor", CAMPOS_PROTEGIDOS)
async def test_campo_protegido_se_rechaza(cliente, usuarios_rbac, campo, valor):
    """Un campo protegido **no se ignora**: responde 422.

    Es la diferencia entre `extra="forbid"` y el comportamiento por omisión de
    Pydantic. Ignorarlo dejaría al cliente creyendo que fijó un `tenant_id` o un
    `creado_por` que nunca llegó a ninguna parte — y escondería el intento.

    Los ocho campos son columnas REALES de `empresas` (o de su respuesta).
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(EMPRESAS, headers=_cab(t),
                           json=_nueva("20500000008", **{campo: valor}))
    assert r.status_code == 422, f"{campo} devolvió {r.status_code}: {r.text}"


async def test_tenant_id_forjado_no_crea_nada(cliente, usuarios_rbac, url_super,
                                              clientes_tenant_2):
    """Enviar `tenant_id` del otro laboratorio: 422 y CERO filas allí.

    El 422 lo da el DTO. Lo que este test añade es la comprobación de que no
    quedó rastro en el tenant ajeno, que es lo que de verdad importaría.
    """
    def _contar_t2() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM empresas WHERE tenant_id = %s",
                        (clientes_tenant_2["tenant_2"],))
            return cur.fetchone()[0]

    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    antes = _contar_t2()
    r = await cliente.post(
        EMPRESAS, headers=_cab(t),
        json=_nueva("20500000009", tenant_id=clientes_tenant_2["tenant_2"]))
    assert r.status_code == 422
    assert _contar_t2() == antes


async def test_la_bd_rechazaria_un_tenant_forjado_aunque_el_dto_fallara(url_app):
    """La última barrera, comprobada SIN pasar por la API.

    Si un bug del backend colara un `tenant_id` ajeno en el INSERT, la política
    lo rechazaría igual:

        WITH CHECK (tenant_id = fn_app_tenant())

    Es la propiedad que hace que H-02 no dependa solo de Pydantic. Se ejecuta
    como `sacgeo_app`, en transacción, y se deshace.
    """
    conn = await psycopg.AsyncConnection.connect(url_app)
    try:
        async with conn.cursor() as cur:
            await cur.execute("SELECT set_config('app.tenant_id','1',true)")
            await cur.execute("SELECT set_config('app.usuario_id','1',true)")
            # (a) La política tiene WITH CHECK, no solo USING.
            await cur.execute(
                "SELECT with_check FROM pg_policies"
                " WHERE tablename='empresas' AND policyname='p_tenant'")
            (with_check,) = await cur.fetchone()
            assert with_check and "fn_app_tenant()" in with_check

            # (b) Un INSERT con tenant ajeno es rechazado por el motor.
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                await cur.execute(
                    "INSERT INTO empresas (ruc, razon_social, tenant_id)"
                    " VALUES ('20599999999','Intrusa',%s)",
                    (2,))
        await conn.rollback()
    finally:
        await conn.close()


# =================================================== 4. VALIDACIÓN (422) ====

@pytest.mark.parametrize(
    "cuerpo",
    [
        {"ruc": "123", "razon_social": "Corta"},                    # RUC corto
        {"ruc": "30123456789", "razon_social": "Prefijo malo"},      # no 10/15/16/17/20
        {"ruc": "2012345678a", "razon_social": "Con letra"},
        {"ruc": "20500000010"},                                      # sin razón social
        {"razon_social": "Sin RUC"},
        {"ruc": "20500000011", "razon_social": ""},                  # vacía
        {"ruc": "20500000012", "razon_social": "   "},               # solo espacios
        {"ruc": "20500000013", "razon_social": "X" * 201},           # se pasa de 200
        {"ruc": "20500000014", "razon_social": "Ok", "email": "no-es-correo"},
        {"ruc": "20500000015", "razon_social": "Ok", "telefono": "abc"},
        {"ruc": "20500000016", "razon_social": "Ok", "direccion": "D" * 251},
    ],
)
async def test_datos_invalidos(cliente, usuarios_rbac, cuerpo):
    """Los patrones replican los dominios del esquema, no los endurecen.

    `razon_social: "   "` merece una nota: `str_strip_whitespace` lo convierte en
    `""` y entonces choca con `min_length=1`, así que da 422 y no un 23514 desde
    PostgreSQL. La regla es la misma; la que responde es la API.
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(EMPRESAS, headers=_cab(t), json=cuerpo)
    assert r.status_code == 422, f"{cuerpo} devolvió {r.status_code}: {r.text}"


async def test_cuerpo_no_es_json_valido(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(EMPRESAS, headers=_cab(t) | {"Content-Type": "application/json"},
                           content=b"{no es json")
    assert r.status_code == 422


async def test_inyeccion_en_los_campos_de_texto(cliente, usuarios_rbac, url_super):
    """Cargas de inyección se guardan como TEXTO. La tabla sigue en pie."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    carga = "Robert'); DROP TABLE empresas; --"
    r = await cliente.post(EMPRESAS, headers=_cab(t),
                           json=_nueva("20500002001", razon_social=carga))
    assert r.status_code == 201, r.text
    assert r.json()["razon_social"] == carga

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM empresas")
        assert cur.fetchone()[0] > 0, "la tabla desapareció"


# ======================================================= 5. CONFLICTO 409 ===

async def test_ruc_repetido_en_el_mismo_laboratorio(cliente, usuarios_rbac):
    """`uq_empresas_ruc (tenant_id, ruc)` → 23505 → 409."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    primera = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500003001"))
    assert primera.status_code == 201, primera.text

    segunda = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500003001"))
    assert segunda.status_code == 409, segunda.text
    assert set(segunda.json()) == {"error", "ref"}


async def test_el_mismo_ruc_en_otro_laboratorio_no_colisiona_ni_delata(
    cliente, usuarios_rbac, clientes_tenant_1
):
    """Dos laboratorios pueden facturar al MISMO cliente, y el 409 no lo delata.

    `uq_empresas_ruc` es `(tenant_id, ruc)`, así que un RUC que ya existe en el
    tenant 1 se crea sin problema desde el tenant 2.

    Y eso es exactamente lo que evita un oráculo: si el UNIQUE fuera global, un
    409 revelaría que ese RUC está registrado en ALGÚN laboratorio, y bastaría
    probar RUCs para descubrir la cartera de clientes de la competencia.

    (Este test reemplaza a dos que comprobaban lo mismo por separado. Ambos
    creaban el mismo RUC en el tenant 2, así que el segundo colisionaba consigo
    mismo según el orden de ejecución — un falso positivo de fuga que costó
    verificar. Uno solo, sin dependencia de orden.)
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])   # comercial del tenant 2
    ruc_del_otro_lab = clientes_tenant_1["empresa_1_ruc"]

    r = await cliente.post(EMPRESAS, headers=_cab(t),
                           json=_nueva(ruc_del_otro_lab,
                                       razon_social="Homónima legítima"))
    assert r.status_code == 201, (
        "el UNIQUE por tenant debería permitir el mismo RUC en otro laboratorio: "
        + r.text
    )

    # Repetirlo DENTRO del mismo laboratorio sí es un conflicto real.
    repetido = await cliente.post(EMPRESAS, headers=_cab(t),
                                  json=_nueva(ruc_del_otro_lab))
    assert repetido.status_code == 409, repetido.text
    assert "uq_empresas_ruc" not in repetido.text
    assert ruc_del_otro_lab not in repetido.text, "el 409 repitió el RUC"


# ============================================= 6. TENANT / RLS / CONTRATO ===

async def test_la_empresa_nace_en_el_tenant_de_la_sesion(cliente, usuarios_rbac,
                                                         url_super,
                                                         clientes_tenant_2):
    """El `tenant_id` sale del contexto, no del cliente. Verificado en la fila."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500004001"))
    assert r.status_code == 201, r.text

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT tenant_id, creado_por, activo FROM empresas WHERE public_id = %s",
            (r.json()["public_id"],))
        tenant_id, creado_por, activo = cur.fetchone()

    assert tenant_id == clientes_tenant_2["tenant_2"], "nació en el tenant equivocado"
    assert creado_por is not None, "fn_tocar no selló el autor"
    assert activo is True


async def test_la_empresa_creada_no_es_visible_desde_el_otro_tenant(
    cliente, usuarios_rbac
):
    """Creada en el tenant 2, invisible desde el tenant 1: 404 por su public_id."""
    t2 = await _token(cliente, usuarios_rbac["ajeno_email"])
    creada = await cliente.post(EMPRESAS, headers=_cab(t2), json=_nueva("20500004002"))
    assert creada.status_code == 201
    public_id = creada.json()["public_id"]

    t1 = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(f"{EMPRESAS}/{public_id}", headers=_cab(t1))
    assert r.status_code == 404, "la empresa creada se filtró al otro laboratorio"

    propia = await cliente.get(f"{EMPRESAS}/{public_id}", headers=_cab(t2))
    assert propia.status_code == 200, "su dueño sí debe verla"


CLAVES = {"public_id", "ruc", "razon_social", "direccion", "telefono",
          "email", "activo", "contactos"}


async def test_contrato_de_la_respuesta(cliente, usuarios_rbac):
    """201 con el recurso, sin un solo id interno."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(
        EMPRESAS, headers=_cab(t),
        json=_nueva("20500005001", direccion="Av. Test 123",
                    telefono="987654321", email="obras@test.pe"))
    assert r.status_code == 201, r.text
    cuerpo = r.json()

    assert set(cuerpo) == CLAVES, f"claves inesperadas: {set(cuerpo) ^ CLAVES}"
    for prohibido in ('"id"', "tenant_id", "creado_por", "actualizado_por",
                      "creado_en"):
        assert prohibido not in r.text, f"se filtró {prohibido}"

    assert cuerpo["activo"] is True
    assert cuerpo["contactos"] == 0, "una empresa nueva no tiene contactos"
    assert cuerpo["direccion"] == "Av. Test 123"

    # El recurso creado se puede leer por su public_id: el identificador sirve.
    leida = await cliente.get(f"{EMPRESAS}/{cuerpo['public_id']}", headers=_cab(t))
    assert leida.status_code == 200
    assert leida.json() == cuerpo


async def test_sin_contexto_no_crea_nada(cliente, usuarios_rbac, monkeypatch,
                                         url_super):
    """Sin contexto de tenant la escritura MUERE con 500, y no inserta.

    Con un `tenant_id` puesto a mano en Python, un contexto vacío habría creado
    la fila en el tenant equivocado o con NULL. Aquí el `DEFAULT
    fn_app_tenant()` lanza 42501 y la transacción hace ROLLBACK.
    """
    def _contar() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM empresas")
            return cur.fetchone()[0]

    t = await _token(cliente, usuarios_rbac["ajeno_email"])

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

    antes = _contar()
    monkeypatch.setattr(deps, "transaccion", _sin_tenant)
    r = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500006001"))
    assert r.status_code == 500, f"respondió {r.status_code}: {r.text}"
    assert set(r.json()) == {"error", "ref"}
    assert _contar() == antes, "insertó sin contexto de tenant"


# ========================================================== 7. AUDITORÍA ====

async def test_la_creacion_queda_auditada_con_autor_no_falsificable(
    cliente, usuarios_rbac, url_super
):
    """`trg_auditar` deja UNA fila, y su autor lo sella `fn_app_usuario()`.

    Desde `0006` (H-06) ese autor no se puede falsificar: `b_auditoria_autor`
    exige que `usuario_id` sea `fn_app_usuario()`. Aquí se comprueba que la
    escritura nueva se apoya en esa garantía, no solo que existe.
    """
    def _auditoria(public_id=None):
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            if public_id is None:
                cur.execute("SELECT count(*) FROM auditoria WHERE tabla='empresas'")
                return cur.fetchone()[0]
            cur.execute(
                """
                SELECT a.accion, a.usuario_id, a.tenant_id, a.datos_nuevos->>'ruc'
                  FROM auditoria a
                  JOIN empresas e ON e.id = a.registro_id AND e.tenant_id = a.tenant_id
                 WHERE a.tabla = 'empresas' AND e.public_id = %s
                """,
                (public_id,))
            return cur.fetchall()

    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    antes = _auditoria()

    r = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500007001"))
    assert r.status_code == 201, r.text

    assert _auditoria() == antes + 1, "la creación no dejó exactamente una fila"

    filas = _auditoria(r.json()["public_id"])
    assert len(filas) == 1
    accion, usuario_id, tenant_id, ruc = filas[0]
    assert accion == "INSERT"
    assert ruc == "20500007001"
    assert usuario_id == usuarios_rbac["ajeno"], (
        "la auditoría no se atribuyó al usuario de la sesión"
    )
    assert tenant_id is not None, "un rastro tenant-scoped quedó marcado como global"


async def test_un_403_no_deja_rastro_de_auditoria(cliente, usuarios_rbac,
                                                  url_super):
    """Un intento rechazado por RBAC no escribe en `auditoria`.

    La auditoría registra CAMBIOS. Un 403 no cambió nada, y registrarlo sería
    confundir auditoría con eventos de seguridad — que son la migración `0009`,
    todavía sin escribir.
    """
    def _contar() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM auditoria")
            return cur.fetchone()[0]

    t = await _token(cliente, usuarios_rbac["lector_email"])
    antes = _contar()
    r = await cliente.post(EMPRESAS, headers=_cab(t), json=_nueva("20500008001"))
    assert r.status_code == 403
    assert _contar() == antes


# ================================================ 8. ERRORES SIN FUGAS ======

async def test_ningun_error_filtra_informacion(cliente, usuarios_rbac):
    """401, 403, 409, 422 y 500: ninguno devuelve SQL, traza ni secretos."""
    t_lector = await _token(cliente, usuarios_rbac["lector_email"])
    t_com = await _token(cliente, usuarios_rbac["ajeno_email"])

    await cliente.post(EMPRESAS, headers=_cab(t_com), json=_nueva("20500009001"))

    respuestas = [
        await cliente.post(EMPRESAS, json=_nueva("20500009002")),                # 401
        await cliente.post(EMPRESAS, headers=_cab(t_lector),
                           json=_nueva("20500009003")),                          # 403
        await cliente.post(EMPRESAS, headers=_cab(t_com),
                           json=_nueva("20500009001")),                          # 409
        await cliente.post(EMPRESAS, headers=_cab(t_com), json={"ruc": "x"}),    # 422
    ]
    for r in respuestas:
        crudo = r.text.lower()
        for prohibido in ("insert into", "select ", "empresas", "psycopg",
                          "traceback", "sqlstate", "23505", "postgresql://",
                          "password", "argon2", "jwt_secret", "uq_empresas_ruc"):
            assert prohibido not in crudo, f"{r.status_code} filtró {prohibido!r}"


# ============================================== 9. BARRERAS DE 7H.1 EN USO ==

def test_el_dto_hereda_entradawrite():
    """El endpoint usa el DTO de 7H.1, no un modelo suelto."""
    from sacgeo.api.dto_negocio import CrearEmpresa
    from sacgeo.api.escritura import EntradaWrite

    assert issubclass(CrearEmpresa, EntradaWrite)
    assert CrearEmpresa.model_config["extra"] == "forbid"
    assert CrearEmpresa.model_config["frozen"] is True
    assert CrearEmpresa.model_config["str_strip_whitespace"] is True

    declarados = set(CrearEmpresa.model_fields)
    assert declarados == {"ruc", "razon_social", "direccion", "telefono", "email"}
    for prohibido in ("tenant_id", "id", "public_id", "creado_por", "activo"):
        assert prohibido not in declarados


def test_el_insert_no_nombra_columnas_protegidas():
    """El SQL del endpoint nombra CINCO columnas. Las otras ocho las pone el motor.

    Si alguien añadiera `tenant_id` o `creado_por` al INSERT, la política y
    `fn_tocar` seguirían defendiendo — pero el endpoint dejaría de ser la
    referencia limpia que las fases siguientes van a copiar.
    """
    from sacgeo.api.v1.clientes_escritura import _SQL_CREAR_EMPRESA

    sql = _SQL_CREAR_EMPRESA.lower()
    columnas = sql.split("insert into empresas (")[1].split(")")[0]
    assert {c.strip() for c in columnas.split(",")} == {
        "ruc", "razon_social", "direccion", "telefono", "email"
    }
    for prohibida in ("tenant_id", "creado_por", "public_id", "activo", "creado_en"):
        assert prohibida not in columnas, f"el INSERT nombra {prohibida}"


async def test_el_post_no_acepta_otros_metodos(cliente, usuarios_rbac):
    """Solo POST. Ni PUT, ni PATCH, ni DELETE: son fases posteriores."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    for metodo in ("put", "patch", "delete"):
        r = await getattr(cliente, metodo)(EMPRESAS, headers=_cab(t))
        assert r.status_code == 405, f"{metodo.upper()} devolvió {r.status_code}"


async def test_openapi_declara_el_201_y_el_dto(cliente):
    r = await cliente.get("/openapi.json")
    rutas = r.json()["paths"]
    assert "post" in rutas[EMPRESAS]
    post = rutas[EMPRESAS]["post"]
    assert "201" in post["responses"]
    assert "409" in post["responses"]

    esquemas = r.json()["components"]["schemas"]
    assert "CrearEmpresa" in esquemas
    props = set(esquemas["CrearEmpresa"]["properties"])
    assert props == {"ruc", "razon_social", "direccion", "telefono", "email"}
    assert esquemas["CrearEmpresa"].get("additionalProperties") is False, (
        "el esquema no declara que prohíbe campos extra"
    )
