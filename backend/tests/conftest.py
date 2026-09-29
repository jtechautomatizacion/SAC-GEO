import os
import secrets
import subprocess
from pathlib import Path

import psycopg
import pytest

from sacgeo.db import pool as pool_mod

RAIZ = Path(__file__).resolve().parents[2]
CONTENEDOR = os.environ.get("PG_CONTENEDOR", "sac-geo-postgres-dev")
USUARIO_PG = os.environ.get("PG_USUARIO", "sacgeo_dev")
# SIN valor por defecto, a proposito. El que había era la credencial histórica de
# desarrollo: la contraseña real y funcional del rol `sacgeo_dev` del clúster de
# trabajo, versionada en este archivo.
# Un valor por defecto que funciona deja de ser un ejemplo:
# se convierte en la contraseña que todo el mundo usa, y entonces publicarla es
# publicar una credencial. La suite corre contra un clúster DESECHABLE cuya
# contraseña elige quien lo levanta, así que no hay nada razonable que poner.
PASS_PG = os.environ.get("PG_PASSWORD")
HOST_PG = os.environ.get("PG_HOST", "localhost")
PUERTO_PG = os.environ.get("PG_PUERTO", "5432")

def _guarda_cluster_de_produccion() -> None:
    """Se niega a correr contra el clúster que contiene la base real.

    Desde que 0004 está aplicada, `sacgeo_app` y `sacgeo_auth` son roles
    PERMANENTES de ese clúster y son dueños de funciones de `sacgeo_dev`. Este
    conftest los crea y los borra: apuntarlo por descuido al clúster real
    destruiría la instalación, y lo haría en el teardown, cuando ya nadie está
    mirando la salida.

    Los roles son del clúster, no de la base, así que aislar la base desechable
    NO basta. La única señal fiable de que estamos en el sitio equivocado es la
    presencia de la base `sacgeo_dev`.
    """
    if not PASS_PG:
        raise RuntimeError(
            "Falta PG_PASSWORD. La suite se conecta a un clúster DESECHABLE cuya "
            "contraseña elige quien lo levanta; este archivo no trae ninguna por "
            "defecto para no versionar una credencial que funcione. Ejemplo:\n\n"
            "  docker run -d --name sac-geo-postgres-val -e POSTGRES_USER=sacgeo_dev \\\n"
            "    -e POSTGRES_PASSWORD=<elegir> -e POSTGRES_DB=postgres \\\n"
            "    -p 5433:5432 postgres:16\n\n"
            "  PG_CONTENEDOR=sac-geo-postgres-val PG_PUERTO=5433 "
            "PG_PASSWORD=<la misma> pytest -q"
        )

    r = subprocess.run(
        ["docker", "exec", CONTENEDOR, "psql", "-U", USUARIO_PG, "-d", "postgres",
         "-tAc", "SELECT 1 FROM pg_database WHERE datname='sacgeo_dev'"],
        capture_output=True, text=True,
    )
    if r.stdout.strip() == "1":
        raise RuntimeError(
            f"El contenedor '{CONTENEDOR}' contiene la base sacgeo_dev. Estos tests "
            "crean y ELIMINAN los roles sacgeo_app y sacgeo_auth, que en ese clúster "
            "son permanentes y sostienen la instalación real. Apunte PG_CONTENEDOR y "
            "PG_PUERTO al clúster de validación."
        )


# Bases DESECHABLES. Nunca sacgeo_dev.
BD_POOL = "sacgeo_pooltest"     # vacía: los tests de pool solo usan set_config
BD_AUTH = "sacgeo_authtest"     # full_dump + 0003..0006: el esquema real

# Rol de aplicación que crea 0004. Los tests de autenticación se conectan con
# ÉL, no con USUARIO_PG: `sacgeo_dev` es superusuario y BYPASSRLS, así que
# conectarse con él haría pasar los tests sin que ninguna política se evaluara.
# Es decir: probarían lo contrario de lo que dicen probar.
ROL_APP = "sacgeo_app"

# Contraseña efímera, distinta en cada ejecución, sólo para la base desechable.
# No se guarda en ningún archivo y el rol se elimina al terminar la sesión.
PASS_APP = secrets.token_urlsafe(24)


def _url(bd: str) -> str:
    return f"postgresql://{USUARIO_PG}:{PASS_PG}@{HOST_PG}:{PUERTO_PG}/{bd}"


def _url_app(bd: str) -> str:
    return f"postgresql://{ROL_APP}:{PASS_APP}@{HOST_PG}:{PUERTO_PG}/{bd}"


def _psql(bd: str, sql: str) -> None:
    subprocess.run(
        ["docker", "exec", "-i", CONTENEDOR, "psql", "-U", USUARIO_PG, "-d", bd,
         "-v", "ON_ERROR_STOP=1", "-q", "-c", sql],
        check=True, capture_output=True,
    )


def _psql_archivo(bd: str, ruta: Path) -> None:
    with open(ruta, "rb") as f:
        subprocess.run(
            ["docker", "exec", "-i", CONTENEDOR, "psql", "-U", USUARIO_PG, "-d", bd,
             "-v", "ON_ERROR_STOP=1", "-q"],
            check=True, stdin=f, capture_output=True,
        )


def _crear_bd(nombre: str) -> None:
    _psql("postgres", f'DROP DATABASE IF EXISTS "{nombre}"')
    _psql("postgres", f'CREATE DATABASE "{nombre}"')


def _borrar_bd(nombre: str) -> None:
    # WITH (FORCE) expulsa las sesiones que sigan abiertas. Sin él, un pool que
    # tarde un instante de más en cerrarse hace fallar el teardown de forma
    # intermitente, que es la peor manera de fallar: parece un test inestable.
    _psql("postgres", f'DROP DATABASE IF EXISTS "{nombre}" WITH (FORCE)')


def _borrar_roles() -> None:
    """Los roles son del CLÚSTER, no de la base: DROP DATABASE no los borra.

    Se eliminan explícitamente al terminar para no dejar roles permanentes,
    y también ANTES de crear la base, porque la sección 0 de 0004 aborta si
    `sacgeo_auth` ya existe.
    """
    for rol in ("sacgeo_app", "sacgeo_auth", *ROLES_MODO_SEGURO):
        _psql("postgres", f"DROP ROLE IF EXISTS {rol}")


# ---------------------------------------------------------------- pool -----

@pytest.fixture(scope="session", autouse=True)
def bd_pool_desechable():
    _guarda_cluster_de_produccion()
    _crear_bd(BD_POOL)
    yield
    _borrar_bd(BD_POOL)


@pytest.fixture
async def pool_de_una_conexion(monkeypatch):
    """Pool con max_size=1: hace determinista la contaminación entre peticiones."""
    from sacgeo.config import settings

    monkeypatch.setattr(settings, "database_url", _url(BD_POOL))
    monkeypatch.setattr(settings, "pool_min_size", 1)
    monkeypatch.setattr(settings, "pool_max_size", 1)
    monkeypatch.setattr(pool_mod, "_pool", None)

    p = await pool_mod.abrir_pool()
    yield p
    await pool_mod.cerrar_pool()


@pytest.fixture
async def pool_sin_discard(monkeypatch):
    """Igual, con DISCARD ALL desactivado: prueba que el aislamiento no depende de él."""
    from sacgeo.config import settings

    monkeypatch.setattr(settings, "database_url", _url(BD_POOL))
    monkeypatch.setattr(settings, "pool_min_size", 1)
    monkeypatch.setattr(settings, "pool_max_size", 1)
    monkeypatch.setattr(settings, "pool_discard_all", False)
    monkeypatch.setattr(pool_mod, "_pool", None)

    p = await pool_mod.abrir_pool()
    yield p
    await pool_mod.cerrar_pool()


# ------------------------------------------------------ autenticación -----

@pytest.fixture(scope="session")
def bd_auth_desechable():
    """Base desechable con el esquema real: full_dump.sql + 0003 + 0004.

    Se usa el MISMO 0003 que está aplicado en sacgeo_dev y el 0004 que todavía
    NO está aplicado en ninguna base real, para que los tests corran contra el
    esquema con RLS y no contra una aproximación sin políticas.

    sacgeo_dev NO se toca en ningún momento.
    """
    _guarda_cluster_de_produccion()
    _borrar_bd(BD_AUTH)
    _borrar_roles()
    _crear_bd(BD_AUTH)
    _psql_archivo(BD_AUTH, RAIZ / "database" / "full_dump.sql")
    _psql_archivo(BD_AUTH, RAIZ / "database" / "migrations" / "0003_multitenant_habilitar.sql")
    _psql_archivo(BD_AUTH, RAIZ / "database" / "migrations" / "0004_rls_rol_aplicacion.sql")
    # 0005 también, y no por simetría: añade b_auditoria_sello, un trigger que
    # dispara en CADA fila de auditoría. El backend escribe auditoría en todas
    # sus transacciones, así que sin 0005 estos tests correrían contra un
    # esquema en el que ese trigger no existe y no detectarían una escritura
    # que lo violara. La base de prueba tiene que parecerse a sacgeo_dev.
    _psql_archivo(BD_AUTH, RAIZ / "database" / "migrations" / "0005_guarda_plantilla_y_sello_auditoria.sql")
    # 0006 por el mismo motivo: b_auditoria_autor dispara en CADA fila de
    # auditoría, y el backend escribe auditoría en todas sus transacciones.
    # Sin ella, estos tests correrían contra un esquema donde la guarda no
    # existe y no detectarían una escritura que la violara.
    _psql_archivo(BD_AUTH, RAIZ / "database" / "migrations" / "0006_auditoria_autor_no_falsificable.sql")
    # 0007 trae el RBAC entero: permisos, rol_permisos, usuario_roles con RLS
    # FORCE y fn_usuario_permisos(). Sin ella no existe nada que autorizar, y
    # los tests de la fase 6B probarían una función que no está.
    #
    # Su semilla de usuario_roles se puebla desde los usuarios que existan EN
    # ESE MOMENTO, que aquí es solo `sistema` (tenant NULL, no recibe fila).
    # Los usuarios de prueba se crean después, así que nacen SIN ningún rol
    # —el punto de partida correcto: cada test declara los roles que necesita.
    _psql_archivo(BD_AUTH, RAIZ / "database" / "migrations" / "0007_rbac_multirol.sql")
    # 0004 crea el rol sin contraseña a propósito. Se le pone una aquí, efímera.
    _psql("postgres", f"ALTER ROLE {ROL_APP} PASSWORD '{PASS_APP}'")
    yield BD_AUTH
    _borrar_bd(BD_AUTH)
    _borrar_roles()


@pytest.fixture(scope="session")
def usuarios_prueba(bd_auth_desechable):
    """Crea los usuarios de prueba en la BASE DESECHABLE. Nunca en sacgeo_dev.

    Se siembra con USUARIO_PG (superusuario) a propósito: sembrar es
    preparación, no es lo que se está probando. Los tests se conectan después
    como `sacgeo_app`, que sí está sujeto a las políticas.

    Hay DOS tenants. Con uno solo no se puede probar aislamiento: sólo se
    probaría que sin contexto falla, que es una propiedad distinta y mucho más
    débil.

    El usuario `sistema` (id 1) se deja EXACTAMENTE como está: password_hash
    NULL y tenant_id NULL. No se le asigna contraseña bajo ningún concepto.
    """
    from sacgeo.security import passwords

    h = passwords.hashear(PASSWORD_PRUEBA)
    with psycopg.connect(_url(BD_AUTH)) as conn, conn.cursor() as cur:
        cur.execute("SET app.tenant_id = '1'")
        cur.execute("SET app.usuario_id = '1'")
        cur.execute(
            """
            INSERT INTO tenants (slug, razon_social, ruc)
            VALUES ('otro-lab', 'Otro Laboratorio S.A.C.', '20111111111')
            RETURNING id
            """
        )
        (id_tenant_2,) = cur.fetchone()
        cur.execute(
            """
            INSERT INTO usuarios (nombres, apellidos, email, rol_id, password_hash, creado_por)
            VALUES ('Activo','Prueba','activo@lab.test', 2, %s, 1) RETURNING id
            """,
            (h,),
        )
        (id_activo,) = cur.fetchone()
        cur.execute(
            """
            INSERT INTO usuarios (nombres, apellidos, email, rol_id, password_hash,
                                  activo, desactivado_en, creado_por)
            VALUES ('Inactivo','Prueba','inactivo@lab.test', 2, %s, FALSE, now(), 1)
            RETURNING id
            """,
            (h,),
        )
        (id_inactivo,) = cur.fetchone()
        cur.execute("SET app.tenant_id = '%s'" % id_tenant_2)
        cur.execute(
            """
            INSERT INTO usuarios (nombres, apellidos, email, rol_id, password_hash,
                                  tenant_id, creado_por)
            VALUES ('Ajeno','Prueba','ajeno@otro.test', 2, %s, %s, 1) RETURNING id
            """,
            (h, id_tenant_2),
        )
        (id_ajeno,) = cur.fetchone()
        conn.commit()
    return {
        "activo": id_activo,
        "inactivo": id_inactivo,
        "ajeno": id_ajeno,
        "tenant_2": id_tenant_2,
    }


# ------------------------------------------------------------- RBAC -------

def _asignar_rol(id_tenant: int, id_usuario: int, codigo_rol: str) -> None:
    """Otorga un rol en la BASE DESECHABLE. Preparación, no es lo que se prueba.

    Se escribe directo sobre `usuario_roles` en vez de por `fn_asignar_rol`
    porque esa función resuelve el usuario y el tenant del CONTEXTO de la
    sesión, y aquí hace falta sembrar a terceros —incluido un usuario del otro
    laboratorio— desde una sola conexión.

    `asignado_por` va a 1 y `app.usuario_id` también: el trigger
    a_validar_otorgante exige que coincidan, y quien siembra es literalmente el
    usuario `sistema`.
    """
    with psycopg.connect(_url(BD_AUTH)) as conn, conn.cursor() as cur:
        cur.execute("SELECT set_config('app.tenant_id', %s, false)", (str(id_tenant),))
        cur.execute("SELECT set_config('app.usuario_id', '1', false)")
        cur.execute(
            """
            INSERT INTO usuario_roles (tenant_id, usuario_id, rol_id, asignado_por)
            SELECT %s, %s, r.id, 1 FROM roles r WHERE r.codigo = %s
            ON CONFLICT (tenant_id, usuario_id, rol_id) DO NOTHING
            """,
            (id_tenant, id_usuario, codigo_rol),
        )
        conn.commit()


def _retirar_rol(id_tenant: int, id_usuario: int, codigo_rol: str) -> None:
    """Retira un rol en la BASE DESECHABLE. Para el test de revocación."""
    with psycopg.connect(_url(BD_AUTH)) as conn, conn.cursor() as cur:
        cur.execute("SELECT set_config('app.tenant_id', %s, false)", (str(id_tenant),))
        cur.execute("SELECT set_config('app.usuario_id', '1', false)")
        cur.execute(
            """
            DELETE FROM usuario_roles
             WHERE tenant_id = %s AND usuario_id = %s
               AND rol_id = (SELECT id FROM roles WHERE codigo = %s)
            """,
            (id_tenant, id_usuario, codigo_rol),
        )
        conn.commit()


@pytest.fixture(scope="session")
def asignar_rol(bd_auth_desechable):
    return _asignar_rol


@pytest.fixture(scope="session")
def retirar_rol(bd_auth_desechable):
    return _retirar_rol


@pytest.fixture(scope="session")
def usuarios_rbac(usuarios_prueba):
    """Reparto de roles para los tests de autorización.

    Cada usuario existe para probar UNA cosa. Compartir uno entre dos tests que
    necesitan repartos distintos haría que el orden de ejecución cambiara el
    resultado, que es la peor forma de tener tests verdes.

      · lector   — rol `lectura`: tiene catalogo.read, NO cotizaciones.create.
                   Es el caso que demuestra H-01: autenticado no es autorizado.
      · ajeno    — rol `comercial` en el OTRO laboratorio. Tiene
                   cotizaciones.create allí, y eso no debe servirle de nada a
                   nadie del tenant 1.
      · multirol — `lectura` + `aprobador`: la unión, sin duplicados.
      · revocable— `lectura`, que un test retira en mitad de su ejecución.
    """
    from sacgeo.security import passwords

    h = passwords.hashear(PASSWORD_PRUEBA)
    creados = {}
    with psycopg.connect(_url(BD_AUTH)) as conn, conn.cursor() as cur:
        cur.execute("SELECT set_config('app.tenant_id', '1', false)")
        cur.execute("SELECT set_config('app.usuario_id', '1', false)")
        for nombre, email in (
            ("multirol", "multirol@lab.test"),
            ("revocable", "revocable@lab.test"),
        ):
            cur.execute(
                """
                INSERT INTO usuarios (nombres, apellidos, email, rol_id,
                                      password_hash, creado_por)
                VALUES (%s, 'Prueba', %s, 4, %s, 1) RETURNING id
                """,
                (nombre, email, h),
            )
            (creados[nombre],) = cur.fetchone()
        conn.commit()

    _asignar_rol(1, usuarios_prueba["activo"], "lectura")
    _asignar_rol(usuarios_prueba["tenant_2"], usuarios_prueba["ajeno"], "comercial")
    _asignar_rol(1, creados["multirol"], "lectura")
    _asignar_rol(1, creados["multirol"], "aprobador")
    _asignar_rol(1, creados["revocable"], "lectura")

    return {
        "lector": usuarios_prueba["activo"],
        "lector_email": "activo@lab.test",
        "ajeno": usuarios_prueba["ajeno"],
        "ajeno_email": "ajeno@otro.test",
        "tenant_2": usuarios_prueba["tenant_2"],
        "multirol": creados["multirol"],
        "multirol_email": "multirol@lab.test",
        "revocable": creados["revocable"],
        "revocable_email": "revocable@lab.test",
    }


@pytest.fixture
async def conn_prueba(bd_auth_desechable):
    """Conexión async como `sacgeo_app`: con RLS forzada, igual que el backend."""
    conn = await psycopg.AsyncConnection.connect(_url_app(BD_AUTH))
    try:
        yield conn
    finally:
        await conn.close()


PASSWORD_PRUEBA = "contraseña-de-prueba-larga"


@pytest.fixture(scope="session")
def url_super(bd_auth_desechable):
    """URL de superusuario a la base desechable.

    Sólo para PREPARAR o LEER datos que la política oculta a propósito — por
    ejemplo el public_id del usuario `sistema`, que ninguna sesión puede ver.
    Nunca para ejecutar lo que se está probando: eso iría como `sacgeo_app`.
    """
    return _url(BD_AUTH)


@pytest.fixture(scope="session")
def url_app(bd_auth_desechable):
    """URL de `sacgeo_app` a la base desechable: el rol con el que corre la API."""
    return _url_app(BD_AUTH)


# ------------------------------------------------- modo RLS seguro ---------

# Roles DESECHABLES para probar el fail-closed. Cada uno encarna exactamente
# un defecto, porque un rol que falle por dos motivos no demuestra cuál de los
# dos controles funciona.
ROLES_MODO_SEGURO = ("sacgeo_t_super", "sacgeo_t_bypass", "sacgeo_t_otro")


@pytest.fixture(scope="session")
def roles_modo_seguro(bd_auth_desechable):
    """Crea los roles con defecto y devuelve sus URLs. Se eliminan al terminar.

    Se crean de verdad en el clúster —no se simulan— porque lo que se prueba es
    precisamente cómo PostgreSQL responde a `pg_has_role` sobre ellos. Un doble
    probaría el doble, no el motor.
    """
    claves = {rol: secrets.token_urlsafe(24) for rol in ROLES_MODO_SEGURO}
    _psql("postgres",
          f"CREATE ROLE sacgeo_t_super LOGIN SUPERUSER PASSWORD '{claves['sacgeo_t_super']}'")
    _psql("postgres",
          "CREATE ROLE sacgeo_t_bypass LOGIN NOSUPERUSER BYPASSRLS "
          f"PASSWORD '{claves['sacgeo_t_bypass']}'")
    # Sano en privilegios, pero NO es el rol previsto: aísla el control de nombre.
    _psql("postgres",
          "CREATE ROLE sacgeo_t_otro LOGIN NOSUPERUSER NOBYPASSRLS "
          f"PASSWORD '{claves['sacgeo_t_otro']}'")
    for rol in ROLES_MODO_SEGURO:
        _psql(BD_AUTH, f'GRANT CONNECT ON DATABASE "{BD_AUTH}" TO {rol}')

    yield {
        rol: f"postgresql://{rol}:{claves[rol]}@{HOST_PG}:{PUERTO_PG}/{BD_AUTH}"
        for rol in ROLES_MODO_SEGURO
    }

    for rol in ROLES_MODO_SEGURO:
        # DROP ROLE no se lleva por delante los GRANT que el rol tenga: hay que
        # soltarlos antes o PostgreSQL responde que hay objetos que dependen de
        # él. DROP OWNED los revoca todos dentro de esta base.
        _psql(BD_AUTH, f"DROP OWNED BY {rol}")
        _psql("postgres", f"DROP ROLE IF EXISTS {rol}")
