"""Contrato de los parámetros de consulta. Piezas compartidas por los routers.

Dos cosas viven aquí, y las dos existen para cerrar una categoría entera de
error en vez de un caso concreto.

------------------------------------------------------------------------------
1. SinParametros — un endpoint sin parámetros también lo declara
------------------------------------------------------------------------------
`extra="forbid"` solo actúa cuando hay un modelo Pydantic de query. Un endpoint
que no declara ninguno **ignora en silencio** lo que le llegue: `?tenant_id=2`
devolvía 200 y el cliente podía creer que había consultado otro laboratorio
mientras recibía el suyo. El tenant nunca salió del contexto —no era un fallo
de aislamiento— pero el silencio esconde el intento, y este proyecto no acepta
silencios.

Se detectó en la fase 7D.1 sobre un endpoint y se extiende aquí a los seis que
lo tenían: los tres de detalle del catálogo, `/auth/yo` y los dos de `/salud`.

------------------------------------------------------------------------------
2. Ordenación — sin una sola columna que venga del cliente
------------------------------------------------------------------------------
`ORDER BY {lo que pida el cliente}` es inyección de SQL con otro nombre, y
sanearlo a mano es la clase de defensa que falla el día que alguien añade un
campo. Aquí el cliente elige de un `Literal` —así que Pydantic rechaza con 422
cualquier valor que no esté en la lista— y ese valor es la CLAVE de un
diccionario cuyos valores son consultas **completas y literales**, armadas al
importar el módulo a partir de constantes del servidor.

Consecuencia: en tiempo de petición no se construye SQL. Se elige una de N
consultas ya escritas. No hay nada que sanear porque no hay nada que componer.

El desempate por `id` no es decorativo: sin un orden total, dos páginas
consecutivas pueden repetir u omitir filas cuando varias comparten el valor de
ordenación.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Direccion = Literal["asc", "desc"]


class SinParametros(BaseModel):
    """El endpoint no acepta ningún parámetro de consulta, y lo dice.

    Modelo vacío a propósito: no declara campos, así que no añade parámetros al
    esquema OpenAPI. Solo cierra la puerta a los que no existen.
    """

    model_config = ConfigDict(extra="forbid")


class Paginacion(BaseModel):
    """Límites de página. Una colección sin techo es una denegación de servicio.

    `le=200` no es un número redondo cualquiera: es el mismo techo que ya usa
    `/catalogo`, y por encima de él una respuesta deja de caber cómodamente en
    una pantalla y empieza a ser una descarga.
    """

    model_config = ConfigDict(extra="forbid")

    limite: int = Field(default=50, ge=1, le=200)
    desplazamiento: int = Field(default=0, ge=0)


def componer(base: str, ordenaciones: dict[str, str], cola: str) -> dict[str, str]:
    """Arma, AL IMPORTAR, una consulta completa por cada ordenación permitida.

    Se llama una vez por módulo, con `base`, `ordenaciones` y `cola` que son
    literales del código fuente. Ningún dato del cliente pasa por aquí: el
    cliente solo elige una clave del diccionario resultante.

    Devuelve {"<campo>:<direccion>": "<SQL completo>"}.
    """
    consultas: dict[str, str] = {}
    for campo, expresion in ordenaciones.items():
        for direccion, sql_dir in (("asc", "ASC"), ("desc", "DESC")):
            clave = campo + ":" + direccion
            consultas[clave] = (
                base + "\n ORDER BY " + expresion + " " + sql_dir + ", id " + sql_dir
                + "\n" + cola
            )
    return consultas
