"""Fase 7H.1 — las barreras de H-02, probadas antes de que haya qué proteger.

Hay dos barreras y resuelven cosas distintas, así que se prueban por separado:

  1. `EntradaWrite` — lo que el cliente NO puede enviar. Es `extra="forbid"` y
     tres opciones más, y se prueba sin tocar la base.
  2. `resolver_public_id()` — lo que el cliente SÍ envía. Se prueba CONTRA
     PostgreSQL con RLS forzada, porque su garantía es que la política decide.

La segunda es la que importa: `extra="forbid"` no impide nada si el `public_id`
que el cliente manda se traduce sin pasar por RLS. Ese sería un IDOR con el DTO
perfecto.

Como todavía no existe ningún endpoint de escritura, la barrera se ejercita con
un endpoint de prueba montado SOLO aquí — igual que se hizo con
`require_permission()` en la fase 6B.
"""

import httpx
import pytest
from fastapi import Depends, FastAPI
from psycopg import AsyncConnection
from pydantic import ValidationError
from typing_extensions import Annotated

from sacgeo.api import errors
from sacgeo.api.deps import get_db_tx, require_permission
from sacgeo.api.dto_negocio import ComponentePaquete, CrearCotizacion, ItemCotizacion
from sacgeo.api.escritura import EntradaWrite, resolver_public_id, resolver_varios
from sacgeo.api.v1 import auth as auth_router
from sacgeo.config import settings
from sacgeo.main import ciclo_de_vida

PASSWORD_PRUEBA = "contraseña-de-prueba-larga"
INEXISTENTE = "00000000-0000-4000-8000-000000000000"


# ================================================ 1. EntradaWrite (sin BD) ==

class _Ejemplo(EntradaWrite):
    nombre: str
    cantidad: int = 1


def test_entrada_rechaza_campos_no_declarados():
    """Lo que no está en el contrato responde error, no se ignora.

    Los cinco campos que se prueban son los que un atacante intentaría primero,
    y los cinco son columnas REALES del esquema. Ninguno está declarado, así que
    ninguno entra.
    """
    for intruso in ("tenant_id", "id", "creado_por", "total", "estado"):
        with pytest.raises(ValidationError) as e:
            _Ejemplo(nombre="x", **{intruso: 1})
        assert "extra" in str(e.value).lower() or "permitted" in str(e.value).lower()


def test_entrada_es_inmutable():
    """`frozen=True`: nadie añade un campo DESPUÉS de validar.

    Sin esto la validación sería una sugerencia: una capa intermedia podría
    inyectar un valor ya validado el DTO y ese valor llegaría a la base.
    """
    e = _Ejemplo(nombre="x")
    with pytest.raises(ValidationError):
        e.nombre = "otro"
    with pytest.raises(ValidationError):
        e.cantidad = 99


def test_entrada_recorta_espacios():
    """`"  "` se vuelve `""` y choca con los CHECK, en vez de colarse."""
    assert _Ejemplo(nombre="  Suelos  ").nombre == "Suelos"
    assert _Ejemplo(nombre="   ").nombre == ""


def test_entrada_coerciona_pero_no_acepta_basura():
    """`strict=False` es deliberado: un formulario HTML manda cadenas."""
    assert _Ejemplo(nombre="x", cantidad="5").cantidad == 5
    with pytest.raises(ValidationError):
        _Ejemplo(nombre="x", cantidad="cinco")


def test_entrada_config_completa():
    """Las cuatro opciones están puestas. Si alguien quita una, se ve aquí."""
    c = EntradaWrite.model_config
    assert c["extra"] == "forbid"
    assert c["frozen"] is True
    assert c["str_strip_whitespace"] is True
    assert c["strict"] is False


@pytest.mark.parametrize("dto", [ItemCotizacion, ComponentePaquete, CrearCotizacion])
def test_todos_los_dto_heredan_la_base(dto):
    """Ningún DTO de negocio se escapa de la base."""
    assert issubclass(dto, EntradaWrite)
    assert dto.model_config["extra"] == "forbid"
    assert dto.model_config["frozen"] is True


# ============================================ 2. DTO de negocio (sin BD) ====

def test_item_no_acepta_precio_ni_snapshots():
    """Un cliente que fijara el precio se cotizaría un ensayo a cero."""
    for prohibido in ("precio_unitario", "subtotal", "codigo_snapshot",
                      "nombre_snapshot", "acreditado_snapshot",
                      "componentes_snapshot", "orden", "cotizacion_id"):
        with pytest.raises(ValidationError):
            ItemCotizacion(ensayo=INEXISTENTE, **{prohibido: 1})


def test_item_exige_public_id_no_entero():
    """Aceptar un entero reabriría el IDOR que la traducción centralizada cierra."""
    with pytest.raises(ValidationError):
        ItemCotizacion(ensayo=7)
    ok = ItemCotizacion(ensayo=INEXISTENTE, cantidad=3)
    assert str(ok.ensayo) == INEXISTENTE
    assert ok.acreditado_override is None


@pytest.mark.parametrize("cantidad", [0, -1, 1000, 99999])
def test_item_cantidad_fuera_de_rango(cantidad):
    """El rango es el del CHECK del esquema: BETWEEN 1 AND 999."""
    with pytest.raises(ValidationError):
        ItemCotizacion(ensayo=INEXISTENTE, cantidad=cantidad)


def test_componente_vinculado_o_descriptivo():
    """Impone los dos CHECK del esquema antes de llegar a PostgreSQL."""
    ItemCotizacion(ensayo=INEXISTENTE)                       # control
    ComponentePaquete(ensayo=INEXISTENTE)                    # vinculado
    ComponentePaquete(nombre="Ensayo descrito", norma="NTP") # descriptivo

    with pytest.raises(ValidationError, match="ninguno de los dos"):
        ComponentePaquete()

    with pytest.raises(ValidationError, match="no lleva `nombre`"):
        ComponentePaquete(ensayo=INEXISTENTE, nombre="Mezcla de los dos")

    with pytest.raises(ValidationError, match="no lleva `nombre`"):
        ComponentePaquete(ensayo=INEXISTENTE, norma="NTP 000")


def test_cotizacion_empresa_o_persona():
    """El esquema los modela como alternativas; el DTO también."""
    base = {"plantilla": INEXISTENTE, "proyecto_nombre": "Obra",
            "items": [{"ensayo": INEXISTENTE}]}

    CrearCotizacion(empresa=INEXISTENTE, contacto=INEXISTENTE, **base)
    CrearCotizacion(persona=INEXISTENTE, **base)

    with pytest.raises(ValidationError, match="no para las dos"):
        CrearCotizacion(persona=INEXISTENTE, empresa=INEXISTENTE, **base)

    with pytest.raises(ValidationError, match="falta el cliente"):
        CrearCotizacion(**base)

    with pytest.raises(ValidationError, match="falta el cliente"):
        CrearCotizacion(empresa=INEXISTENTE, **base)   # empresa sin contacto


def test_cotizacion_no_acepta_campos_calculados():
    """Los ocho campos que la BD calcula no existen en el DTO."""
    base = {"empresa": INEXISTENTE, "contacto": INEXISTENTE,
            "plantilla": INEXISTENTE, "proyecto_nombre": "Obra",
            "items": [{"ensayo": INEXISTENTE}]}
    for prohibido in ("numero", "estado", "fecha_emision", "subtotal", "igv",
                      "total", "descuento_monto", "igv_tasa", "moneda",
                      "tenant_id", "creado_por", "public_id"):
        with pytest.raises(ValidationError):
            CrearCotizacion(**base, **{prohibido: 1})


def test_cotizacion_emitir_por_omision_es_falso():
    """Crear un borrador es la operación menos privilegiada: es el defecto.

    Quien no pida emitir explícitamente no debería necesitar
    `cotizaciones.emit`. Si el defecto fuera `True`, cada alta exigiría el
    permiso mayor y el menor no serviría para nada.
    """
    c = CrearCotizacion(empresa=INEXISTENTE, contacto=INEXISTENTE,
                        plantilla=INEXISTENTE, proyecto_nombre="Obra",
                        items=[{"ensayo": INEXISTENTE}])
    assert c.emitir is False


def test_cotizacion_descuento_coherente():
    """Un valor sin tipo es ambiguo: 10 ¿soles o por ciento?"""
    base = {"empresa": INEXISTENTE, "contacto": INEXISTENTE,
            "plantilla": INEXISTENTE, "proyecto_nombre": "Obra",
            "items": [{"ensayo": INEXISTENTE}]}

    CrearCotizacion(**base, descuento_tipo="porcentaje", descuento_valor=10)
    CrearCotizacion(**base)   # sin descuento

    with pytest.raises(ValidationError, match="van juntos"):
        CrearCotizacion(**base, descuento_valor=10)
    with pytest.raises(ValidationError, match="van juntos"):
        CrearCotizacion(**base, descuento_tipo="monto")
    with pytest.raises(ValidationError, match="no pasa del 100"):
        CrearCotizacion(**base, descuento_tipo="porcentaje", descuento_valor=150)
    with pytest.raises(ValidationError):
        CrearCotizacion(**base, descuento_tipo="regalo", descuento_valor=1)


def test_cotizacion_exige_al_menos_un_item():
    base = {"empresa": INEXISTENTE, "contacto": INEXISTENTE,
            "plantilla": INEXISTENTE, "proyecto_nombre": "Obra"}
    with pytest.raises(ValidationError):
        CrearCotizacion(**base, items=[])
    with pytest.raises(ValidationError):
        CrearCotizacion(**base, items=[{"ensayo": INEXISTENTE}] * 201)


# ==================== 3. resolver_public_id() CONTRA PostgreSQL con RLS =====

def _construir_app() -> FastAPI:
    """App de prueba. NO forma parte del producto.

    La barrera se ejercita a través de la cadena real —JWT, sesión, tenant,
    `get_db_tx`, RBAC— porque su garantía depende de que la consulta corra con
    el contexto puesto. Probarla con una conexión fabricada probaría otra cosa.
    """
    app = FastAPI(lifespan=ciclo_de_vida)
    errors.registrar(app)
    app.include_router(auth_router.router)

    @app.get("/prueba/resolver/{recurso}/{public_id}",
             dependencies=[Depends(require_permission("catalogo.read"))])
    async def _resolver(
        recurso: str, public_id: str,
        conn: Annotated[AsyncConnection, Depends(get_db_tx)],
    ):
        from uuid import UUID as _U
        interno = await resolver_public_id(conn, recurso, _U(public_id))
        return {"resuelto": interno > 0}

    @app.post("/prueba/resolver-varios/{recurso}",
              dependencies=[Depends(require_permission("catalogo.read"))])
    async def _varios(
        recurso: str, ids: list[str],
        conn: Annotated[AsyncConnection, Depends(get_db_tx)],
    ):
        from uuid import UUID as _U
        mapa = await resolver_varios(conn, recurso, [_U(i) for i in ids])
        return {"total": len(mapa)}

    return app


@pytest.fixture
async def cliente(url_app, usuarios_rbac, clientes_tenant_1, clientes_tenant_2,
                  monkeypatch):
    from sacgeo.db import pool as pool_mod

    monkeypatch.setattr(settings, "database_url", url_app)
    monkeypatch.setattr(pool_mod, "_pool", None)
    monkeypatch.setattr(settings, "require_rls_safe_role", True)

    app = _construir_app()
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


async def test_resolver_recurso_propio(cliente, usuarios_rbac, clientes_tenant_1):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(
        f"/prueba/resolver/empresa/{clientes_tenant_1['empresa_1_public_id']}",
        headers=_cab(t))
    assert r.status_code == 200, r.text
    assert r.json()["resuelto"] is True


async def test_resolver_recurso_ajeno_da_404(cliente, usuarios_rbac,
                                             clientes_tenant_2):
    """EL TEST QUE IMPORTA: el `public_id` de otro laboratorio no se traduce.

    Si la traducción no pasara por RLS, este `public_id` resolvería a un id
    interno válido y la escritura siguiente escribiría contra la empresa de otro
    laboratorio. El DTO habría sido perfecto y la fila, ajena.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(
        f"/prueba/resolver/empresa/{clientes_tenant_2['empresa_public_id']}",
        headers=_cab(t))
    assert r.status_code == 404, r.text
    assert r.status_code != 403, "confirmó que el recurso existe en otro sitio"


async def test_resolver_el_dueno_si_lo_traduce(cliente, usuarios_rbac,
                                               clientes_tenant_2):
    """Prueba que el 404 anterior lo causa RLS y no un UUID muerto."""
    t = await _token(cliente, usuarios_rbac["ajeno_email"])
    r = await cliente.get(
        f"/prueba/resolver/empresa/{clientes_tenant_2['empresa_public_id']}",
        headers=_cab(t))
    assert r.status_code == 200, r.text


async def test_resolver_inexistente_y_ajeno_son_indistinguibles(
    cliente, usuarios_rbac, clientes_tenant_2
):
    t = await _token(cliente, usuarios_rbac["lector_email"])
    a = await cliente.get(f"/prueba/resolver/empresa/{INEXISTENTE}", headers=_cab(t))
    b = await cliente.get(
        f"/prueba/resolver/empresa/{clientes_tenant_2['empresa_public_id']}",
        headers=_cab(t))
    assert a.status_code == b.status_code == 404
    assert a.json() == b.json(), "los 404 no son idénticos: hay oráculo"


@pytest.mark.parametrize(
    "recurso", ["empresa", "contacto", "persona", "plantilla", "ensayo",
                "categoria", "subcategoria", "cotizacion", "usuario"])
async def test_resolver_los_nueve_recursos_responden_404_si_no_existe(
    cliente, usuarios_rbac, recurso
):
    """Los nueve recursos resolubles se comportan igual ante un UUID muerto."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.get(f"/prueba/resolver/{recurso}/{INEXISTENTE}", headers=_cab(t))
    assert r.status_code == 404, f"{recurso} devolvió {r.status_code}"


async def test_resolver_recurso_no_whitelisted_no_toca_sql(cliente, usuarios_rbac):
    """El nombre de la tabla no viene del cliente: no hay tabla que inyectar.

    `_SQL_RESOLVER` es un diccionario de consultas literales. Una clave
    desconocida falla al BUSCARLA, **antes de tocar PostgreSQL**, y el resolutor
    la convierte en `ValueError` para que el log diga qué pasó — un `KeyError`
    suelto saliendo de un endpoint no explica nada.

    Lo importante es lo que NO ocurre: no se compone ninguna sentencia con el
    valor recibido, así que no hay nada que inyectar.

    El `Recurso` de la firma real es un `Literal`, de modo que un llamador
    correcto no puede llegar aquí; el endpoint de prueba lo declara `str`
    justamente para poder intentarlo.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    for intento in ("usuarios; DROP TABLE empresas", "pg_shadow", "auditoria",
                    "empresas", "'; SELECT 1 --"):
        with pytest.raises(ValueError, match="no permitido"):
            await cliente.get(f"/prueba/resolver/{intento}/{INEXISTENTE}",
                              headers=_cab(t))


async def test_resolver_varios_en_una_consulta(cliente, usuarios_rbac,
                                               clientes_tenant_1):
    """Un lote resuelve en una consulta, y los duplicados no dan falso 404."""
    t = await _token(cliente, usuarios_rbac["lector_email"])
    e1 = clientes_tenant_1["empresa_1_public_id"]
    e2 = clientes_tenant_1["empresa_2_public_id"]

    r = await cliente.post("/prueba/resolver-varios/empresa",
                           headers=_cab(t), json=[e1, e2])
    assert r.status_code == 200, r.text
    assert r.json()["total"] == 2

    # Duplicados: el conjunto los colapsa, no son un error.
    r = await cliente.post("/prueba/resolver-varios/empresa",
                           headers=_cab(t), json=[e1, e1, e1])
    assert r.status_code == 200, r.text
    assert r.json()["total"] == 1

    vacio = await cliente.post("/prueba/resolver-varios/empresa",
                               headers=_cab(t), json=[])
    assert vacio.status_code == 200 and vacio.json()["total"] == 0


async def test_resolver_varios_falla_si_uno_es_ajeno(cliente, usuarios_rbac,
                                                     clientes_tenant_1,
                                                     clientes_tenant_2):
    """Un solo `public_id` ajeno en el lote invalida el lote entero.

    Y con el mismo 404 sin decir cuál: si dijera cuál, un atacante descubriría
    qué UUIDs existen enviándolos en lotes y viendo cuál se señala.
    """
    t = await _token(cliente, usuarios_rbac["lector_email"])
    r = await cliente.post(
        "/prueba/resolver-varios/empresa", headers=_cab(t),
        json=[clientes_tenant_1["empresa_1_public_id"],
              clientes_tenant_2["empresa_public_id"]])
    assert r.status_code == 404, r.text
    assert clientes_tenant_2["empresa_public_id"] not in r.text


async def test_resolver_sin_permiso_no_llega_a_la_barrera(cliente,
                                                          usuarios_catalogo):
    """RBAC va antes: quien no puede leer el catálogo no traduce nada."""
    t = await _token(cliente, usuarios_catalogo["sin_roles_email"])
    r = await cliente.get(f"/prueba/resolver/empresa/{INEXISTENTE}", headers=_cab(t))
    assert r.status_code == 403


async def test_resolver_sin_contexto_no_devuelve_404(cliente, usuarios_rbac,
                                                     clientes_tenant_1, monkeypatch):
    """Sin contexto de tenant NO responde 404: responde 500.

    Es la distinción que hace esta barrera segura. Un 404 diría «ese recurso no
    existe» cuando lo que pasa es que el backend no fijó el contexto — y un
    fallo de infraestructura se leería como un dato de negocio.
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
                        "SELECT set_config('app.usuario_id', %s, true)",
                        (str(usuario_id),))
                yield conn

    monkeypatch.setattr(deps, "transaccion", _sin_tenant)
    r = await cliente.get(
        f"/prueba/resolver/empresa/{clientes_tenant_1['empresa_1_public_id']}",
        headers=_cab(t))
    assert r.status_code == 500, f"respondió {r.status_code}: {r.text}"
    assert set(r.json()) == {"error", "ref"}


# ======================================= 4. la traducción es punto ÚNICO ====

def test_la_traduccion_vive_en_dos_sitios_y_los_dos_estan_justificados():
    """La traducción `public_id → id` aparece en DOS módulos, no en uno.

    La primera versión de este test exigía uno solo y falló. El segundo sitio es
    legítimo y no debe desaparecer, así que el test lo fija en vez de fingir que
    no está:

      · `escritura.py` — traducción de recursos de NEGOCIO, bajo RLS. Es el
        punto único para todo lo que resuelva un endpoint de escritura.
      · `autenticacion.py` — `fn_sesion_resolver_usuario(public_id)` traduce el
        `sub` del JWT al usuario. NO puede pasar por `escritura.py`: ocurre
        ANTES de que exista contexto de tenant —es lo que lo establece— y por eso
        usa una función `SECURITY DEFINER` acotada de `sacgeo_auth`. Es la
        excepción documentada en CLAUDE.md §5.

    Un TERCER módulo sí sería un problema: significaría que alguien resolvió un
    recurso de negocio por su cuenta, sin la garantía de RLS.
    """
    import re
    from pathlib import Path

    fuente = Path(__file__).resolve().parents[1] / "src" / "sacgeo"
    patron = re.compile(r"SELECT\s+(public_id\s*,\s*)?id\b[^;]*?public_id",
                        re.IGNORECASE | re.DOTALL)

    culpables = sorted(
        p.name for p in fuente.rglob("*.py")
        if "__pycache__" not in str(p) and patron.search(p.read_text("utf-8"))
    )

    assert culpables == ["autenticacion.py", "escritura.py"], (
        f"la traducción public_id → id aparece en {culpables}. Los dos sitios "
        "legítimos son escritura.py (negocio, bajo RLS) y autenticacion.py "
        "(sesión, SECURITY DEFINER acotada). Cualquier otro es un IDOR en "
        "potencia."
    )


def test_ningun_sql_del_resolutor_filtra_por_tenant_en_python():
    """Las 18 consultas del resolutor no llevan `WHERE tenant_id`.

    El aislamiento lo impone RLS. Un filtro aquí sugeriría que depende de esta
    línea y, sin contexto, convertiría un 42501 en un 404 plausible.
    """
    from sacgeo.api.escritura import _SQL_RESOLVER, _SQL_RESOLVER_VARIOS

    todas = list(_SQL_RESOLVER.values()) + list(_SQL_RESOLVER_VARIOS.values())
    assert len(todas) == 18
    for sql in todas:
        assert "tenant_id" not in sql, f"filtra por tenant en Python: {sql}"
        assert "%(public_id)s" in sql or "%(ids)s" in sql, f"sin parámetro: {sql}"
