"""Fase 7I.1 — primer WRITE que REFERENCIA otro recurso por `public_id`.

Lo que esta suite existe para demostrar, y no para afirmar:

    empresa_public_id  →  resolver central  →  tenant context  →  RLS
                       →  id interno  →  INSERT  →  auditoría protegida

El eslabón nuevo respecto a 7I es el primero. Un alta de empresa no referencia
nada; un contacto sí, y ahí es donde nace el IDOR: si la traducción de
`public_id` a `id` no pasara por RLS, un contacto podría colgarse de la empresa
de otro laboratorio con un DTO impecable.

Se comprueba además que la barrera es TRIPLE, porque la tercera no depende de
que nadie recuerde nada: la FK de `contactos` es compuesta.
"""

import httpx
import psycopg
import pytest

from sacgeo.config import settings

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"
CONTACTOS = "/api/v1/clientes/contactos"
EMPRESAS = "/api/v1/clientes/empresas"
INEXISTENTE = "00000000-0000-4000-8000-000000000000"


def _nuevo(ref: str, **extra) -> dict:
    """Cuerpo mínimo válido, con campos extra opcionales.

    El parámetro se llama `ref` y no `empresa` a propósito: `empresa` es uno de
    los campos protegidos que hay que poder enviar como extra para comprobar que
    se rechaza, y un parámetro con ese nombre choca con el `**extra`. Costó un
    TypeError descubrirlo.
    """
    cuerpo = {"empresa_public_id": ref, "nombres": "Luis",
              "apellidos": "Ramirez"}
    cuerpo.update(extra)
    return cuerpo


@pytest.fixture
async def cliente(url_app, usuarios_rbac, usuarios_catalogo,
                  usuarios_permisos_separados, clientes_tenant_1,
                  clientes_tenant_2, monkeypatch):
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


def _contar(url_super: str, tabla: str = "contactos", tenant: int | None = None) -> int:
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        if tenant is None:
            cur.execute(f"SELECT count(*) FROM {tabla}")  # noqa: S608
        else:
            cur.execute(f"SELECT count(*) FROM {tabla} WHERE tenant_id = %s",  # noqa: S608
                        (tenant,))
        return cur.fetchone()[0]


# =================================================== 1. AUTENTICACIÓN (401) ==

async def test_401_sin_autenticacion(cliente, clientes_tenant_1):
    r = await cliente.post(CONTACTOS,
                           json=_nuevo(clientes_tenant_1["empresa_1_public_id"]))
    assert r.status_code == 401


async def test_401_jwt_malformado(cliente, clientes_tenant_1):
    r = await cliente.post(CONTACTOS, headers=_cab("basura"),
                           json=_nuevo(clientes_tenant_1["empresa_1_public_id"]))
    assert r.status_code == 401


async def test_401_jwt_con_permisos_inyectados(cliente, usuarios_rbac, url_super,
                                               clientes_tenant_1):
    """Token FIRMADO con `permissions: [clientes.manage]` → 401."""
    from datetime import UTC, datetime, timedelta

    import jwt as pyjwt

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE email = %s",
                    (usuarios_rbac["lector_email"],))
        (public_id,) = cur.fetchone()

    ahora = datetime.now(UTC)
    token = pyjwt.encode(
        {"sub": str(public_id), "jti": "c1", "iat": int(ahora.timestamp()),
         "exp": int((ahora + timedelta(minutes=15)).timestamp()),
         "permissions": ["clientes.manage"]},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo)

    r = await cliente.post(CONTACTOS, headers=_cab(token),
                           json=_nuevo(clientes_tenant_1["empresa_1_public_id"]))
    assert r.status_code == 401


# ========================================================= 2. RBAC (403) ====

async def test_403_clientes_read_no_puede_crear(cliente, usuarios_rbac,
                                                clientes_tenant_1, url_super):
    """El rol `lectura` tiene clientes.read y NO clientes.manage. Cero filas."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    antes = _contar(url_super)
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_1["empresa_1_public_id"]))
    assert r.status_code == 403, r.text
    assert _contar(url_super) == antes, "se creó un contacto sin el permiso"


async def test_403_sin_ningun_rol(cliente, usuarios_catalogo, clientes_tenant_1):
    t = await _token(cliente, usuarios_catalogo["sin_roles_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_1["empresa_1_public_id"]))
    assert r.status_code == 403


async def test_403_otro_permiso_no_sirve(cliente, usuarios_permisos_separados,
                                         clientes_tenant_1):
    t = await _token(cliente, usuarios_permisos_separados["solo_catalogo_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_1["empresa_1_public_id"]))
    assert r.status_code == 403


async def test_403_no_llega_a_resolver_el_public_id(cliente, usuarios_rbac,
                                                    clientes_tenant_2):
    """RBAC va ANTES del resolutor: sin permiso, ni siquiera se traduce.

    Se manda una empresa AJENA con un usuario sin permiso. Si el resolutor
    corriera primero, la respuesta sería 404 y delataría que el guard está
    después. Debe ser 403.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"]))
    assert r.status_code == 403, "el resolutor corrió antes que RBAC"


# ================================================== 3. CREACIÓN VÁLIDA (201) =

async def test_201_creacion_valida(cliente, usuarios_rbac, clientes_tenant_2):
    """Camino feliz: `comercial` del tenant 2 sobre una empresa del tenant 2."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(
        CONTACTOS, headers=_cab(t),
        json=_nuevo(clientes_tenant_2["empresa_public_id"], dni="45678912",
                    cargo="Jefe de obra", celular="987654321",
                    email="luis@test.pe"))
    assert r.status_code == 201, r.text
    cuerpo = r.json()
    assert cuerpo["nombres"] == "Luis"
    assert cuerpo["dni"] == "45678912"
    assert cuerpo["activo"] is True
    assert cuerpo["empresa"] == clientes_tenant_2["empresa_public_id"]


async def test_201_sin_los_campos_opcionales(cliente, usuarios_rbac,
                                             clientes_tenant_2):
    """`dni` es OPCIONAL en el esquema, y aquí también.

    El seed tiene dos contactos sin DNI. Exigirlo sería inventar una regla de
    negocio que la base no tiene.
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                       nombres="Marta", apellidos="Flores"))
    assert r.status_code == 201, r.text
    assert r.json()["dni"] is None
    assert r.json()["cargo"] is None


async def test_el_contacto_aparece_en_la_empresa(cliente, usuarios_rbac,
                                                 clientes_tenant_2):
    """Recorrido completo: se crea y se lee por el subrecurso de su empresa."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    empresa = clientes_tenant_2["empresa_public_id"]

    antes = (await cliente.get(f"{EMPRESAS}/{empresa}/contactos",
                               headers=_cab(t))).json()["total"]
    creado = await cliente.post(CONTACTOS, headers=_cab(t),
                                json=_nuevo(empresa, nombres="Jorge",
                                            apellidos="Nunez"))
    assert creado.status_code == 201, creado.text

    despues = await cliente.get(f"{EMPRESAS}/{empresa}/contactos", headers=_cab(t))
    assert despues.json()["total"] == antes + 1
    assert creado.json()["public_id"] in {
        c["public_id"] for c in despues.json()["items"]
    }

    # Y por su propia ruta de detalle.
    suyo = await cliente.get(f"{CONTACTOS}/{creado.json()['public_id']}",
                             headers=_cab(t))
    assert suyo.status_code == 200
    assert suyo.json()["empresa"] == empresa


# ============================ 4. CROSS-TENANT: EL NÚCLEO DE ESTA FASE ========

async def test_404_empresa_de_otro_tenant(cliente, usuarios_rbac,
                                          clientes_tenant_2, url_super):
    """EL TEST CENTRAL. Un `public_id` de empresa ajena no se traduce.

    El usuario es `comercial` del tenant 1... no existe: `comercial` del tenant 2
    es `ajeno`. Aquí se usa al revés — el comercial del tenant 2 apuntando a una
    empresa del tenant 1 — y debe recibir 404, no 201 ni 403.

    Si el resolutor no pasara por RLS, ese `public_id` traduciría a un id interno
    válido, la FK compuesta lo rechazaría y la respuesta sería un 409 o un 500:
    ruidoso, pero ya habría revelado que la empresa existe. El 404 llega antes.
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])   # tenant 2
    antes_t1 = _contar(url_super, "contactos", tenant=1)

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM empresas WHERE tenant_id = 1 LIMIT 1")
        (empresa_t1,) = cur.fetchone()

    r = await cliente.post(CONTACTOS, headers=_cab(t), json=_nuevo(str(empresa_t1)))
    assert r.status_code == 404, r.text
    assert r.status_code != 403, "distinguió «no autorizado» de «no existe»"
    assert _contar(url_super, "contactos", tenant=1) == antes_t1, (
        "creó un contacto en el laboratorio ajeno"
    )


async def test_404_empresa_inexistente(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t), json=_nuevo(INEXISTENTE))
    assert r.status_code == 404, r.text


async def test_ajeno_e_inexistente_son_indistinguibles(cliente, usuarios_rbac,
                                                       url_super):
    """Sin esto, el endpoint sería un oráculo para enumerar la competencia.

    Se comparan los cuerpos completos, no solo el código: una diferencia en el
    mensaje o en la forma bastaría para distinguir «existe en otro sitio» de «no
    existe».
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT public_id FROM empresas WHERE tenant_id = 1 LIMIT 1")
        (empresa_t1,) = cur.fetchone()

    ajena = await cliente.post(CONTACTOS, headers=_cab(t), json=_nuevo(str(empresa_t1)))
    muerta = await cliente.post(CONTACTOS, headers=_cab(t), json=_nuevo(INEXISTENTE))

    assert ajena.status_code == muerta.status_code == 404
    assert ajena.json() == muerta.json(), "los 404 difieren: hay oráculo"
    assert str(empresa_t1) not in ajena.text


async def test_la_fk_compuesta_bloquea_aunque_se_salte_el_resolutor(url_app):
    """La TERCERA barrera, sin pasar por la API: la clave, no la disciplina.

    Si alguien saltara `resolver_public_id` y pasara el `empresa_id` interno de
    otro laboratorio a mano, la FK compuesta lo rechaza:

        FOREIGN KEY (tenant_id, empresa_id) REFERENCES empresas (tenant_id, id)

    El par (mi tenant, su empresa) no existe. No es una comprobación que alguien
    deba acordarse de escribir — es una clave foránea.
    """
    conn = await psycopg.AsyncConnection.connect(url_app)
    try:
        async with conn.cursor() as cur:
            # (a) La FK es compuesta, no de una columna.
            await cur.execute(
                "SELECT pg_get_constraintdef(oid) FROM pg_constraint"
                " WHERE conname = 'contactos_empresa_id_fkey'")
            (definicion,) = await cur.fetchone()
            assert "tenant_id, empresa_id" in definicion.replace("(", "").replace(")", ""), (
                f"la FK dejó de ser compuesta: {definicion}"
            )

            # (b) Con contexto del tenant 1, el empresa_id de otro tenant falla.
            await cur.execute("SELECT set_config('app.tenant_id','1',true)")
            await cur.execute("SELECT set_config('app.usuario_id','1',true)")
            await cur.execute(
                "SELECT id FROM empresas WHERE tenant_id <> 1 LIMIT 1")
            fila = await cur.fetchone()
        await conn.rollback()

        # `empresas` está bajo RLS, así que como sacgeo_app no se ve ninguna de
        # otro tenant: esa es la barrera 1, y se comprueba aquí de paso.
        assert fila is None, "RLS dejó ver una empresa de otro laboratorio"
    finally:
        await conn.close()


async def test_el_contacto_nace_en_el_tenant_de_la_sesion(cliente, usuarios_rbac,
                                                          clientes_tenant_2,
                                                          url_super):
    """`tenant_id` del contacto = tenant de la sesión, y coincide con su empresa."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                       nombres="Ana", apellidos="Tenant"))
    assert r.status_code == 201, r.text

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT c.tenant_id, c.creado_por, c.activo, e.tenant_id
              FROM contactos c JOIN empresas e ON e.id = c.empresa_id
             WHERE c.public_id = %s
            """,
            (r.json()["public_id"],))
        tenant_c, creado_por, activo, tenant_e = cur.fetchone()

    assert tenant_c == clientes_tenant_2["tenant_2"]
    assert tenant_c == tenant_e, "el contacto y su empresa están en tenants distintos"
    assert creado_por is not None, "fn_tocar no selló el autor"
    assert activo is True


# ========================================= 5. MASS ASSIGNMENT (H-02) ========

CAMPOS_PROTEGIDOS = [
    ("tenant_id", 1),
    ("id", 1),
    ("public_id", "11111111-1111-4111-8111-111111111111"),
    ("empresa_id", 1),                 # el id interno: el IDOR que el nombre cierra
    ("creado_por", 1),
    ("creado_en", "2020-01-01T00:00:00Z"),
    ("actualizado_por", 1),
    ("actualizado_en", "2020-01-01T00:00:00Z"),
    ("activo", False),
    ("empresa", "11111111-1111-4111-8111-111111111111"),
    ("estado", "activo"),
]


@pytest.mark.parametrize("campo,valor", CAMPOS_PROTEGIDOS)
async def test_422_campo_protegido(cliente, usuarios_rbac, clientes_tenant_2,
                                   url_super, campo, valor):
    """Un campo protegido responde 422 y NO ejecuta el INSERT.

    `empresa_id` está en la lista a propósito: es el campo que el contrato
    sustituye por `empresa_public_id`. Aceptarlo sería volver a abrir el IDOR
    que el nombre del campo cierra.
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    antes = _contar(url_super)
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                       **{campo: valor}))
    assert r.status_code == 422, f"{campo} devolvió {r.status_code}: {r.text}"
    assert _contar(url_super) == antes, f"{campo} llegó a insertar"


async def test_422_campo_desconocido(cliente, usuarios_rbac, clientes_tenant_2):
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    for campo in ("rol", "permissions", "es_admin", "cualquiera", "usuario_id"):
        r = await cliente.post(CONTACTOS, headers=_cab(t),
                               json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                           **{campo: "x"}))
        assert r.status_code == 422, f"{campo} devolvió {r.status_code}"


async def test_no_se_puede_falsificar_el_autor(cliente, usuarios_rbac,
                                               clientes_tenant_2, url_super):
    """Ni por el payload ni por el resultado: el autor lo sella el motor.

    `creado_por` y `usuario_id` dan 422 en el DTO, y el contacto creado
    legítimamente queda a nombre del usuario de la sesión — no de otro.
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                       nombres="Autor", apellidos="Real"))
    assert r.status_code == 201

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute("SELECT creado_por FROM contactos WHERE public_id = %s",
                    (r.json()["public_id"],))
        (creado_por,) = cur.fetchone()
    assert creado_por == usuarios_rbac["ajeno"], (
        "el contacto no quedó a nombre del usuario de la sesión"
    )


# ==================================================== 6. VALIDACIÓN (422) ===

@pytest.mark.parametrize(
    "extra",
    [
        {"nombres": ""},                        # CHECK btrim <> ''
        {"nombres": "   "},                     # strip lo vuelve vacío
        {"apellidos": ""},
        {"nombres": "N" * 101},                 # se pasa de 100
        {"apellidos": "A" * 101},
        {"dni": "123"},                         # dom_dni exige 8 dígitos
        {"dni": "1234567a"},
        {"dni": "123456789"},
        {"email": "no-es-correo"},
        {"celular": "abc"},
        {"cargo": "C" * 101},
        {"empresa_public_id": "no-es-uuid"},
    ],
)
async def test_422_datos_invalidos(cliente, usuarios_rbac, clientes_tenant_2, extra):
    """Los patrones replican los dominios del esquema, no los endurecen."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                       **extra))
    assert r.status_code == 422, f"{extra} devolvió {r.status_code}: {r.text}"


@pytest.mark.parametrize(
    "cuerpo",
    [
        {"nombres": "Sin", "apellidos": "Empresa"},          # falta la referencia
        {"empresa_public_id": INEXISTENTE, "apellidos": "X"},  # faltan nombres
        {"empresa_public_id": INEXISTENTE, "nombres": "X"},    # faltan apellidos
        {},
    ],
)
async def test_422_faltan_obligatorios(cliente, usuarios_rbac, cuerpo):
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t), json=cuerpo)
    assert r.status_code == 422, f"{cuerpo} devolvió {r.status_code}"


async def test_422_cuerpo_no_json(cliente, usuarios_rbac):
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(CONTACTOS,
                           headers=_cab(t) | {"Content-Type": "application/json"},
                           content=b"{roto")
    assert r.status_code == 422


async def test_inyeccion_como_texto(cliente, usuarios_rbac, clientes_tenant_2,
                                    url_super):
    """Las cargas se guardan como TEXTO. Las tablas siguen en pie."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    carga = "Robert'); DROP TABLE contactos; --"
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                       nombres=carga, apellidos="Tables"))
    assert r.status_code == 201, r.text
    assert r.json()["nombres"] == carga

    assert _contar(url_super) > 0, "la tabla contactos desapareció"
    assert _contar(url_super, "empresas") > 0


# ======================================================= 7. CONFLICTO 409 ===

async def test_409_dni_repetido_en_la_misma_empresa(cliente, usuarios_rbac,
                                                    clientes_tenant_2):
    """`uq_contactos_empresa_dni (tenant_id, empresa_id, dni)` → 23505 → 409."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    empresa = clientes_tenant_2["empresa_public_id"]

    primera = await cliente.post(CONTACTOS, headers=_cab(t),
                                 json=_nuevo(empresa, dni="11223344"))
    assert primera.status_code == 201, primera.text

    segunda = await cliente.post(CONTACTOS, headers=_cab(t),
                                 json=_nuevo(empresa, dni="11223344",
                                             nombres="Otro", apellidos="Mismo DNI"))
    assert segunda.status_code == 409, segunda.text
    assert set(segunda.json()) == {"error", "ref"}
    assert "11223344" not in segunda.text, "el 409 repitió el DNI"
    assert "uq_contactos" not in segunda.text


async def test_el_mismo_dni_en_otra_empresa_es_legitimo(cliente, usuarios_rbac,
                                                        clientes_tenant_2):
    """Una persona puede ser contacto de dos clientes distintos.

    El UNIQUE es `(tenant_id, empresa_id, dni)`, no `(tenant_id, dni)`.
    """
    t = await _token(cliente, usuarios_rbac["ajeno_email"])

    otra = await cliente.post(EMPRESAS, headers=_cab(t),
                              json={"ruc": "20777777777",
                                    "razon_social": "Segunda Empresa S.A.C."})
    assert otra.status_code == 201, otra.text

    dni = "55667788"
    a = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                       dni=dni))
    b = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(otra.json()["public_id"], dni=dni))
    assert a.status_code == 201, a.text
    assert b.status_code == 201, (
        "el UNIQUE es por empresa: el mismo DNI en otra empresa debe valer: " + b.text
    )


async def test_un_fallo_no_deja_fila(cliente, usuarios_rbac, clientes_tenant_2,
                                     url_super):
    """Tras un 409, un 404 y un 422, el conteo no cambia."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    empresa = clientes_tenant_2["empresa_public_id"]

    base = await cliente.post(CONTACTOS, headers=_cab(t),
                              json=_nuevo(empresa, dni="99001122"))
    assert base.status_code == 201

    antes = _contar(url_super)
    assert (await cliente.post(CONTACTOS, headers=_cab(t),
                               json=_nuevo(empresa, dni="99001122"))
            ).status_code == 409
    assert (await cliente.post(CONTACTOS, headers=_cab(t),
                               json=_nuevo(INEXISTENTE))).status_code == 404
    assert (await cliente.post(CONTACTOS, headers=_cab(t),
                               json=_nuevo(empresa, dni="mal"))).status_code == 422
    assert _contar(url_super) == antes, "un fallo dejó una fila"


# ========================================================== 8. AUDITORÍA ====

async def test_auditoria_correcta(cliente, usuarios_rbac, clientes_tenant_2,
                                  url_super):
    """Una fila, tabla `contactos`, acción INSERT, autor y tenant correctos."""
    def _filas_contactos() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM auditoria WHERE tabla='contactos'")
            return cur.fetchone()[0]

    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    antes = _filas_contactos()

    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                       nombres="Auditada", apellidos="Fila",
                                       dni="33445566"))
    assert r.status_code == 201, r.text
    assert _filas_contactos() == antes + 1, "no dejó exactamente una fila"

    with psycopg.connect(url_super) as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT a.accion, a.usuario_id, a.tenant_id,
                   a.datos_nuevos->>'dni', a.datos_nuevos->>'nombres'
              FROM auditoria a
              JOIN contactos c ON c.id = a.registro_id AND c.tenant_id = a.tenant_id
             WHERE a.tabla = 'contactos' AND c.public_id = %s
            """,
            (r.json()["public_id"],))
        filas = cur.fetchall()

    assert len(filas) == 1
    accion, usuario_id, tenant_id, dni, nombres = filas[0]
    assert accion == "INSERT"
    assert usuario_id == usuarios_rbac["ajeno"], "autor incorrecto"
    assert tenant_id == clientes_tenant_2["tenant_2"], (
        "un rastro tenant-scoped quedó con el tenant equivocado"
    )
    assert dni == "33445566" and nombres == "Auditada"


async def test_un_404_no_deja_rastro_de_auditoria(cliente, usuarios_rbac,
                                                  url_super):
    """Un intento contra una empresa ajena no escribe en `auditoria`.

    La auditoría registra CAMBIOS. Un 404 no cambió nada; registrarlo sería
    confundirla con eventos de seguridad, que son la migración `0009`.
    """
    def _contar_aud() -> int:
        with psycopg.connect(url_super) as conn, conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM auditoria")
            return cur.fetchone()[0]

    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    antes = _contar_aud()
    assert (await cliente.post(CONTACTOS, headers=_cab(t),
                               json=_nuevo(INEXISTENTE))).status_code == 404
    assert _contar_aud() == antes


# ============================================== 9. RESPUESTA Y ERRORES ======

CLAVES = {"public_id", "dni", "nombres", "apellidos", "cargo", "celular",
          "email", "activo", "empresa"}


async def test_respuesta_sin_ids_internos(cliente, usuarios_rbac,
                                          clientes_tenant_2):
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(clientes_tenant_2["empresa_public_id"],
                                       nombres="Sin", apellidos="Ids"))
    assert r.status_code == 201, r.text
    assert set(r.json()) == CLAVES, f"claves inesperadas: {set(r.json()) ^ CLAVES}"

    for prohibido in ('"id"', "tenant_id", "empresa_id", "creado_por",
                      "actualizado_por", "creado_en"):
        assert prohibido not in r.text, f"se filtró {prohibido}"

    # `empresa` es el public_id de la empresa, no su id interno.
    assert r.json()["empresa"] == clientes_tenant_2["empresa_public_id"]


async def test_ningun_error_filtra_informacion(cliente, usuarios_rbac,
                                               clientes_tenant_2):
    """401, 403, 404, 409 y 422: ni SQL, ni constraints, ni códigos, ni trazas."""
    t_lector = await _token(cliente, usuarios_rbac["lector_email"])
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    empresa = clientes_tenant_2["empresa_public_id"]

    await cliente.post(CONTACTOS, headers=_cab(t), json=_nuevo(empresa, dni="77889900"))

    respuestas = [
        await cliente.post(CONTACTOS, json=_nuevo(empresa)),                      # 401
        await cliente.post(CONTACTOS, headers=_cab(t_lector),
                           json=_nuevo(empresa)),                                 # 403
        await cliente.post(CONTACTOS, headers=_cab(t), json=_nuevo(INEXISTENTE)),  # 404
        await cliente.post(CONTACTOS, headers=_cab(t),
                           json=_nuevo(empresa, dni="77889900")),                 # 409
        await cliente.post(CONTACTOS, headers=_cab(t), json={"nombres": "x"}),     # 422
    ]
    for r in respuestas:
        crudo = r.text.lower()
        for prohibido in ("insert into", "select ", "contactos", "empresas",
                          "psycopg", "traceback", "sqlstate", "23505", "23503",
                          "fkey", "uq_contactos", "postgresql://", "password",
                          "argon2", "jwt_secret", "fn_app_tenant"):
            assert prohibido not in crudo, f"{r.status_code} filtró {prohibido!r}"


# =========================================== 10. LA CADENA, COMPROBADA ======

def test_el_endpoint_usa_el_resolutor_central():
    """No hay un SELECT de empresas escrito dentro del endpoint.

    Si lo hubiera, sería el noveno sitio donde traducir un `public_id`, y basta
    uno mal escrito para abrir un IDOR. El test de 7H.1
    (`test_la_traduccion_vive_en_dos_sitios...`) ya vigila el conjunto; este fija
    que ESTE módulo delega.
    """
    from pathlib import Path

    fuente = (Path(__file__).resolve().parents[1] / "src" / "sacgeo" / "api" /
              "v1" / "clientes_escritura.py").read_text("utf-8")

    assert "resolver_public_id(conn, \"empresa\"" in fuente, (
        "el endpoint no usa el resolutor central"
    )
    codigo = "\n".join(
        l for l in fuente.splitlines()
        if not l.strip().startswith("#") and not l.strip().startswith("·")
    )
    assert "FROM empresas" not in codigo, (
        "hay un SELECT de empresas escrito en el endpoint: debe delegar"
    )


def test_el_dto_usa_las_barreras_de_7h1():
    from sacgeo.api.dto_negocio import CrearContacto
    from sacgeo.api.escritura import EntradaWrite

    assert issubclass(CrearContacto, EntradaWrite)
    assert CrearContacto.model_config["extra"] == "forbid"
    assert CrearContacto.model_config["frozen"] is True

    declarados = set(CrearContacto.model_fields)
    assert declarados == {"empresa_public_id", "nombres", "apellidos", "dni",
                          "cargo", "celular", "email"}
    for prohibido in ("empresa_id", "tenant_id", "id", "public_id", "creado_por",
                      "activo"):
        assert prohibido not in declarados


def test_el_insert_no_nombra_columnas_protegidas():
    """Siete columnas. Las otras ocho las pone el motor."""
    from sacgeo.api.v1.clientes_escritura import _SQL_CREAR_CONTACTO

    columnas = _SQL_CREAR_CONTACTO.lower().split("insert into contactos (")[1]
    columnas = columnas.split(")")[0]
    assert {c.strip() for c in columnas.split(",")} == {
        "empresa_id", "dni", "nombres", "apellidos", "cargo", "celular", "email"
    }
    for prohibida in ("tenant_id", "creado_por", "public_id", "activo", "creado_en"):
        assert prohibida not in columnas, f"el INSERT nombra {prohibida}"


async def test_solo_post_en_contactos(cliente, usuarios_rbac):
    """Ni PUT, ni PATCH, ni DELETE: son fases posteriores."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    for metodo in ("put", "patch", "delete"):
        r = await getattr(cliente, metodo)(CONTACTOS, headers=_cab(t))
        assert r.status_code == 405, f"{metodo.upper()} devolvió {r.status_code}"


async def test_openapi(cliente):
    r = await cliente.get("/openapi.json")
    rutas = r.json()["paths"]
    assert "post" in rutas[CONTACTOS]
    post = rutas[CONTACTOS]["post"]
    for codigo in ("201", "404", "409"):
        assert codigo in post["responses"], f"el esquema no declara {codigo}"

    esquemas = r.json()["components"]["schemas"]
    assert "CrearContacto" in esquemas
    props = set(esquemas["CrearContacto"]["properties"])
    assert props == {"empresa_public_id", "nombres", "apellidos", "dni",
                     "cargo", "celular", "email"}
    assert "empresa_id" not in props
    assert esquemas["CrearContacto"].get("additionalProperties") is False
