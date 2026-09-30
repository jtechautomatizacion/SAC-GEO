"""Barreras de escritura. Existen ANTES de que haya nada que escribir.

H-02 —mass assignment— no es explotable hoy: no hay un solo endpoint de
escritura. Este módulo se adelanta a propósito, porque un mecanismo de
seguridad escrito junto al primer endpoint que lo necesita se escribe con prisa,
y porque así queda probado contra un endpoint de prueba antes de que exista uno
de verdad. Es lo que se hizo con `require_permission()` en la fase 6B.

Dos barreras, y resuelven problemas distintos:

  1. `EntradaWrite` — lo que el cliente NO puede enviar.
  2. `resolver_public_id()` — lo que el cliente SÍ envía, traducido una sola vez.

La segunda es la que más importa, y es la que `extra="forbid"` no cubre.

------------------------------------------------------------------------------
POR QUÉ LA TRADUCCIÓN public_id → id ES EL RIESGO PRINCIPAL
------------------------------------------------------------------------------
Las funciones de caso de uso reciben ids INTERNOS:

    fn_crear_cotizacion(p_empresa_id INTEGER, p_contacto_id INTEGER,
                        p_persona_id INTEGER, p_plantilla_id INTEGER, ...)
    fn_definir_componentes(p_paquete_id INTEGER, ...)
    fn_crear_ensayo(p_subcategoria_id INTEGER, ...)

Y la API recibe `public_id`. Alguien tiene que traducir, y ahí caben dos errores
que ninguna lista blanca de campos detecta:

  · traducir sin pasar por RLS —con una conexión sin contexto, o con una
    consulta que el motor no filtre— y aceptar el `public_id` de otro
    laboratorio. Es un IDOR completo: el DTO era perfecto y la fila era ajena;
  · traducir en cada endpoint. Nueve traducciones son nueve sitios donde
    equivocarse, y basta una.

Aquí hay UNA traducción, ocurre dentro de la transacción que `get_db_tx` ya
contextualizó, y lo que no es visible para esa sesión no existe: 404.

------------------------------------------------------------------------------
EL NOMBRE DE LA TABLA NO VIENE DEL CLIENTE. NUNCA.
------------------------------------------------------------------------------
Un resolutor genérico invita a `resolver(tabla=request.query["tipo"], ...)`, que
es inyección de SQL con un paso intermedio. Aquí el recurso es un `Literal`, y
ese valor validado es la CLAVE de un diccionario de consultas completas y
literales escritas en este archivo. En tiempo de petición no se compone SQL: se
elige una de N sentencias ya escritas. Es el mismo patrón que `query.componer()`
usa para la ordenación.
"""

from __future__ import annotations

import logging
from typing import Literal
from uuid import UUID

from fastapi import HTTPException, status
from psycopg import AsyncConnection
from pydantic import BaseModel, ConfigDict

log = logging.getLogger(__name__)


# ============================================================ 1. DTO BASE ===

class EntradaWrite(BaseModel):
    """Base de todo DTO de escritura de SAC-GEO.

    Cada opción cierra una vía concreta:

    `extra="forbid"`
        Un campo no declarado responde 422 en vez de ignorarse. Ignorarlo
        dejaría al cliente creyendo que fijó un `tenant_id` o un `total` que
        nunca llegó a ninguna parte — y escondería el intento. Es la misma
        decisión que ya gobierna los diez modelos de consulta.

    `frozen=True`
        El DTO validado no se puede mutar. Sin esto, una capa intermedia podría
        añadirle un atributo DESPUÉS de la validación y ese valor llegaría a la
        base sin haber pasado por el contrato. La validación deja de ser una
        puerta y pasa a ser una sugerencia.

    `str_strip_whitespace=True`
        `"  "` se convierte en `""`, y así choca con los CHECK del esquema
        —`btrim(nombre) <> ''`— en vez de colarse como un nombre invisible.

    `strict=False`
        Deliberado: `"5"` sigue valiendo como 5, porque un formulario HTML envía
        cadenas. Lo que no vale es `"cinco"`. Poner `strict=True` rompería
        clientes legítimos sin cerrar ninguna vía, porque la coerción de Pydantic
        no acepta basura.

    Y la propiedad que no es una opción de configuración: **ningún DTO declara
    jamás un campo de seguridad, de identidad, de autoría, de estado ni de
    importe.** No se filtran al escribir — no existen en el modelo. Es la
    diferencia entre una lista negra, que hay que recordar, y una blanca, donde
    no hay nada que recordar.
    """

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
        str_strip_whitespace=True,
        frozen=True,
    )


# =============================================== 2. public_id → id interno ===

Recurso = Literal[
    "empresa",
    "contacto",
    "persona",
    "plantilla",
    "ensayo",
    "categoria",
    "subcategoria",
    "cotizacion",
    "usuario",
]

# Una consulta COMPLETA y literal por recurso. El cliente elige la clave, nunca
# escribe la tabla.
#
# Ninguna lleva "WHERE tenant_id": lo impone RLS a partir del contexto de la
# transacción. Un filtro aquí sugeriría que el aislamiento depende de esta línea
# y, sin contexto, devolvería "no encontrado" en vez del 42501 que corresponde —
# convirtiendo un fallo de infraestructura en un 404 plausible.
_SQL_RESOLVER: dict[str, str] = {
    "empresa": "SELECT id FROM empresas WHERE public_id = %(public_id)s",
    "contacto": "SELECT id FROM contactos WHERE public_id = %(public_id)s",
    "persona": "SELECT id FROM personas WHERE public_id = %(public_id)s",
    "plantilla": "SELECT id FROM plantillas_cotizacion WHERE public_id = %(public_id)s",
    "ensayo": "SELECT id FROM ensayos_catalogo WHERE public_id = %(public_id)s",
    "categoria": "SELECT id FROM categorias_ensayo WHERE public_id = %(public_id)s",
    "subcategoria": "SELECT id FROM subcategorias_ensayo WHERE public_id = %(public_id)s",
    "cotizacion": "SELECT id FROM cotizaciones WHERE public_id = %(public_id)s",
    "usuario": "SELECT id FROM usuarios WHERE public_id = %(public_id)s",
}

# Variante por lotes. Existe para que resolver los 20 ítems de una cotización no
# sean 20 viajes a PostgreSQL — un N+1 escondido dentro de una barrera de
# seguridad es la clase de cosa que alguien "optimiza" más tarde saltándose la
# barrera.
_SQL_RESOLVER_VARIOS: dict[str, str] = {
    "empresa": "SELECT public_id, id FROM empresas WHERE public_id = ANY(%(ids)s)",
    "contacto": "SELECT public_id, id FROM contactos WHERE public_id = ANY(%(ids)s)",
    "persona": "SELECT public_id, id FROM personas WHERE public_id = ANY(%(ids)s)",
    "plantilla": "SELECT public_id, id FROM plantillas_cotizacion"
                 " WHERE public_id = ANY(%(ids)s)",
    "ensayo": "SELECT public_id, id FROM ensayos_catalogo WHERE public_id = ANY(%(ids)s)",
    "categoria": "SELECT public_id, id FROM categorias_ensayo"
                 " WHERE public_id = ANY(%(ids)s)",
    "subcategoria": "SELECT public_id, id FROM subcategorias_ensayo"
                    " WHERE public_id = ANY(%(ids)s)",
    "cotizacion": "SELECT public_id, id FROM cotizaciones WHERE public_id = ANY(%(ids)s)",
    "usuario": "SELECT public_id, id FROM usuarios WHERE public_id = ANY(%(ids)s)",
}

# Un 404 único y sin detalles. No dice QUÉ recurso faltaba ni CUÁL de una lista:
# esa información convertiría la escritura en un oráculo para enumerar el
# catálogo o la cartera de clientes de la competencia probando UUIDs. Es la misma
# regla que ya gobierna los GET de detalle.
_NO_ENCONTRADO = HTTPException(
    status_code=status.HTTP_404_NOT_FOUND,
    detail="no encontrado",
)


def _consulta(mapa: dict[str, str], recurso: str) -> str:
    """Busca la consulta del recurso, y falla EN CLARO si no está permitido.

    `Recurso` es un `Literal`, así que un llamador correcto no puede llegar
    aquí con algo raro: si llega, es un error de programación, no una petición
    inválida. Se lanza `ValueError` en vez de dejar escapar el `KeyError` del
    diccionario para que el log diga qué pasó — un KeyError suelto saliendo de
    un endpoint no explica nada.

    Lo que NO ocurre en ningún caso: componer SQL con el valor recibido. El
    nombre de la tabla no sale de aquí.
    """
    try:
        return mapa[recurso]
    except KeyError:
        log.error("recurso no permitido en el resolutor: %r", recurso)
        raise ValueError(
            "recurso no permitido para traducción de public_id: " + repr(recurso)
        ) from None


async def resolver_public_id(
    conn: AsyncConnection, recurso: Recurso, public_id: UUID
) -> int:
    """Traduce un `public_id` al `id` interno, BAJO RLS. Punto único.

    `conn` tiene que venir de `get_db_tx`: es lo que garantiza que la consulta
    se ejecute con el contexto de tenant puesto y que la política decida. Una
    conexión sin contexto no devuelve "no encontrado": lanza 42501, que
    `errors.py` traduce a 500 porque es un bug nuestro.

    Un `public_id` que exista en otro laboratorio responde 404 — para esta
    sesión la fila no existe, así que el 404 es la respuesta literal.
    """
    sql = _consulta(_SQL_RESOLVER, recurso)
    async with conn.cursor() as cur:
        await cur.execute(sql, {"public_id": str(public_id)}, prepare=False)
        fila = await cur.fetchone()

    if fila is None:
        # Se registra el recurso pedido, no el public_id: el log no es el sitio
        # para acumular identificadores que alguien probó.
        log.info("resolución fallida de %s", recurso)
        raise _NO_ENCONTRADO
    return fila[0]


async def resolver_varios(
    conn: AsyncConnection, recurso: Recurso, public_ids: list[UUID]
) -> dict[UUID, int]:
    """Traduce una lista de `public_id` en UNA consulta.

    Si alguno no es visible, lanza el MISMO 404 sin decir cuál. Decirlo
    permitiría descubrir qué UUIDs existen probándolos en lotes, que es
    exactamente lo que el 404 uniforme evita en los GET.

    Los duplicados se aceptan en la entrada —un cotizante puede repetir un
    ensayo— y el diccionario los colapsa. Comparar tamaños contra la lista
    original daría un falso 404, así que se compara contra el conjunto.
    """
    if not public_ids:
        return {}

    pedidos = {UUID(str(p)) for p in public_ids}
    sql = _consulta(_SQL_RESOLVER_VARIOS, recurso)
    async with conn.cursor() as cur:
        await cur.execute(sql, {"ids": [str(p) for p in pedidos]}, prepare=False)
        filas = await cur.fetchall()

    encontrados = {UUID(str(f[0])): f[1] for f in filas}
    if len(encontrados) != len(pedidos):
        log.info(
            "resolución por lotes incompleta de %s: %d de %d",
            recurso, len(encontrados), len(pedidos),
        )
        raise _NO_ENCONTRADO
    return encontrados
