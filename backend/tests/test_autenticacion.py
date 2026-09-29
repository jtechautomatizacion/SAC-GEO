"""Tests 14-27 de la fase 5C, actualizados a RLS (fase 4A-SEXIES).

Los que tocan PostgreSQL usan una base DESECHABLE construida desde
full_dump.sql + 0003 + 0004, y se conectan como `sacgeo_app`. NUNCA se conectan
a sacgeo_dev, ni con un rol que bypasee RLS: hacerlo dejaría estos tests en
verde sin que ninguna política llegara a evaluarse.
"""

import logging

import psycopg
import pytest

from sacgeo.security import refresh
from sacgeo.security.autenticacion import (
    CredencialesInvalidas,
    autenticar,
    completar_usuario,
    resolver_sesion,
)
from sacgeo.security.tenant import Sesion, TenantNoAutorizado, resolver_tenant_activo

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"


async def _fijar_contexto(conn, tenant_id):
    """Fija el contexto igual que db.tx: set_config LOCAL y parametrizado."""
    async with conn.cursor() as cur:
        await cur.execute(
            "SELECT set_config(%s, %s, true)", ("app.tenant_id", str(tenant_id))
        )
        await cur.execute("SELECT set_config(%s, %s, true)", ("app.usuario_id", "1"))


# --- 14-17 · Usuario --------------------------------------------------------

async def test_14_usuario_activo(conn_prueba, usuarios_prueba):
    u = await autenticar(conn_prueba, "activo@lab.test", PASSWORD_PRUEBA)
    assert u.id == usuarios_prueba["activo"]
    assert u.tenant_id == 1


async def test_15_usuario_inexistente(conn_prueba, usuarios_prueba):
    with pytest.raises(CredencialesInvalidas):
        await autenticar(conn_prueba, "no-existe@lab.test", PASSWORD_PRUEBA)


async def test_16_usuario_deshabilitado(conn_prueba, usuarios_prueba):
    with pytest.raises(CredencialesInvalidas):
        await autenticar(conn_prueba, "inactivo@lab.test", PASSWORD_PRUEBA)


async def test_17_usuario_sistema_rechazado(conn_prueba, usuarios_prueba):
    """El usuario `sistema` NO puede autenticarse.

    Tres barreras independientes: fn_login_buscar lo excluye por construcción,
    su password_hash es NULL y su tenant_id es NULL — que significa "no
    pertenece a ningún laboratorio", nunca "acceso a todos".
    """
    with pytest.raises(CredencialesInvalidas):
        await autenticar(conn_prueba, "sistema@gtqc.local", PASSWORD_PRUEBA)
    with pytest.raises(CredencialesInvalidas):
        await autenticar(conn_prueba, "sistema@gtqc.local", "")


async def test_password_incorrecto_mismo_error(conn_prueba, usuarios_prueba):
    """Contraseña mala y usuario inexistente dan el MISMO error."""
    with pytest.raises(CredencialesInvalidas):
        await autenticar(conn_prueba, "activo@lab.test", "contraseña-equivocada")


async def test_email_no_aparece_en_logs(conn_prueba, usuarios_prueba, caplog):
    with caplog.at_level(logging.DEBUG):
        with pytest.raises(CredencialesInvalidas):
            await autenticar(conn_prueba, "activo@lab.test", "mala")
    assert PASSWORD_PRUEBA not in caplog.text
    assert "mala" not in caplog.text


# --- Resolución de sesión bajo RLS ------------------------------------------

async def test_login_no_consulta_usuarios_directamente(conn_prueba, usuarios_prueba):
    """El SELECT directo sobre `usuarios` sin contexto es 42501.

    Este test es el cimiento de todos los demás: si fallara —si la tabla fuera
    legible sin contexto— el resto de este archivo no probaría nada.
    """
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        async with conn_prueba.transaction():
            async with conn_prueba.cursor() as cur:
                await cur.execute("SELECT email FROM usuarios LIMIT 1")


async def test_resolver_sesion_sin_contexto(conn_prueba, usuarios_prueba):
    """La resolución de sesión funciona SIN contexto de tenant.

    Es su razón de ser: el contexto no puede fijarse hasta conocer el tenant, y
    el tenant sale justo de aquí. No es un problema de orden sino una
    dependencia de datos, y fn_sesion_resolver_usuario es lo que la rompe.
    """
    u = await autenticar(conn_prueba, "activo@lab.test", PASSWORD_PRUEBA)
    usuario_id, tenant_id = await resolver_sesion(conn_prueba, u.public_id)
    assert usuario_id == u.id
    assert tenant_id == 1


async def test_completar_usuario_dentro_del_contexto(conn_prueba, usuarios_prueba):
    """El email se lee después, ya bajo la política de `usuarios`."""
    u = await autenticar(conn_prueba, "activo@lab.test", PASSWORD_PRUEBA)
    usuario_id, tenant_id = await resolver_sesion(conn_prueba, u.public_id)
    async with conn_prueba.transaction():
        await _fijar_contexto(conn_prueba, tenant_id)
        completo = await completar_usuario(
            conn_prueba, usuario_id, u.public_id, tenant_id
        )
    assert completo.id == u.id
    assert completo.email == "activo@lab.test"
    assert completo.tenant_id == 1


async def test_completar_usuario_sin_contexto_falla(conn_prueba, usuarios_prueba):
    """Sin contexto, completar la identidad es 42501. Nunca una fila."""
    u = await autenticar(conn_prueba, "activo@lab.test", PASSWORD_PRUEBA)
    usuario_id, _ = await resolver_sesion(conn_prueba, u.public_id)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        async with conn_prueba.transaction():
            await completar_usuario(conn_prueba, usuario_id, u.public_id, 1)


async def test_usuario_de_otro_tenant_no_es_visible(conn_prueba, usuarios_prueba):
    """Con el contexto del tenant 1, el usuario del tenant 2 no existe.

    Aislamiento de verdad: no es que falte contexto, es que hay contexto y es
    el equivocado. Sin un segundo tenant esto no podría comprobarse.
    """
    ajeno = usuarios_prueba["ajeno"]
    async with conn_prueba.transaction():
        await _fijar_contexto(conn_prueba, 1)
        with pytest.raises(CredencialesInvalidas):
            await completar_usuario(conn_prueba, ajeno, "no-importa", 1)


async def test_sesion_del_usuario_sistema_imposible(conn_prueba, usuarios_prueba, url_super):
    """El usuario `sistema` no obtiene sesión ni con un token bien firmado.

    fn_sesion_resolver_usuario filtra tenant_id IS NOT NULL, así que una
    identidad global no puede convertirse en sesión de usuario. Su public_id se
    lee con el superusuario porque ninguna sesión puede verlo.
    """
    with psycopg.connect(url_super) as c, c.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE email = 'sistema@gtqc.local'")
        (pid,) = cur.fetchone()
    with pytest.raises(CredencialesInvalidas):
        await resolver_sesion(conn_prueba, str(pid))


async def test_usuario_desactivado_no_resuelve_desde_token(conn_prueba, usuarios_prueba, url_super):
    """Un usuario desactivado no pasa get_current_user aunque su token valga.

    Es lo que hace que desactivar surta efecto de inmediato en vez de esperar a
    que expire el access token.
    """
    with psycopg.connect(url_super) as c, c.cursor() as cur:
        cur.execute("SELECT public_id FROM usuarios WHERE email = 'inactivo@lab.test'")
        (pid,) = cur.fetchone()
    with pytest.raises(CredencialesInvalidas):
        await resolver_sesion(conn_prueba, str(pid))


async def test_resolver_sesion_no_expone_password_hash(conn_prueba, usuarios_prueba):
    """fn_sesion_resolver_usuario devuelve TRES columnas y ninguna sensible.

    Aquí no hay contraseña que verificar —el token ya viene firmado—, así que
    pedir el hash sería superficie regalada en el camino más caliente de la API.
    """
    async with conn_prueba.cursor() as cur:
        await cur.execute(
            "SELECT * FROM fn_sesion_resolver_usuario(%s)",
            ("00000000-0000-0000-0000-000000000000",),
        )
        columnas = [d.name for d in cur.description]
    assert columnas == ["id", "tenant_id", "activo"]


# --- 18-22 · Refresh --------------------------------------------------------

def test_18_a_22_refresh_bloqueado_por_falta_de_persistencia():
    """Los tests 18-22 NO pueden ejecutarse: falta la tabla de sesiones.

    La rotación exige invalidar el token anterior, y eso exige recordarlo. No
    hay tabla de sesiones en el esquema y la fase 5C prohíbe crearla.

    Lo que SÍ se comprueba aquí es que el código se niega a emitir refresh
    tokens en vez de emitir unos que no pueden revocarse — que sería peor que
    no tenerlos: ampliaría la ventana de un token robado de 15 minutos a
    7 días.
    """
    with pytest.raises(refresh.RefreshNoDisponible):
        refresh.emitir_refresh()
    with pytest.raises(refresh.RefreshNoDisponible):
        refresh.rotar_refresh()


def test_primitivas_de_refresh_sin_persistencia():
    """Las partes que NO dependen del esquema sí están implementadas y probadas."""
    a = refresh.generar_valor_refresh()
    b = refresh.generar_valor_refresh()
    assert a != b
    assert len(a) >= 40

    h = refresh.hashear_refresh(a)
    assert h == refresh.hashear_refresh(a)     # determinista
    assert h != refresh.hashear_refresh(b)
    assert a not in h                          # el valor no se deduce del hash
    with pytest.raises(ValueError):
        refresh.hashear_refresh("")


# --- 23-24 · Tenant ---------------------------------------------------------

def _sesion(tenant_id):
    return Sesion(
        public_id="11111111-1111-1111-1111-111111111111",
        usuario_id=10,
        tenant_id=tenant_id,
    )


def test_23_tenant_no_viene_del_jwt():
    """El tenant sale de PostgreSQL, no del token.

    El token sólo lleva `sub`; el tenant llega a `resolver_tenant_activo` dentro
    de la Sesion que produjo fn_sesion_resolver_usuario.
    """
    assert resolver_tenant_activo(_sesion(1)) == 1


def test_24_tenant_no_elegible_por_el_cliente():
    """Proponer otro tenant se RECHAZA, no se ignora en silencio.

    Un rechazo deja rastro en el log; un silencio no.
    """
    s = _sesion(1)
    with pytest.raises(TenantNoAutorizado):
        resolver_tenant_activo(s, tenant_propuesto=2)
    # Proponer el propio es inofensivo.
    assert resolver_tenant_activo(s, tenant_propuesto=1) == 1


def test_usuario_sin_tenant_no_obtiene_sesion():
    """tenant_id NULL no es acceso global: es ausencia de laboratorio."""
    with pytest.raises(TenantNoAutorizado):
        resolver_tenant_activo(_sesion(None))
