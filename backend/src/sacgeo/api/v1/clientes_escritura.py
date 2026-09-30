"""Escritura de clientes. EL PRIMER WRITE DE NEGOCIO DE SAC-GEO.

Un solo endpoint: `POST /api/v1/clientes/empresas`.

------------------------------------------------------------------------------
POR QUÉ ESTO ES UN ROUTER APARTE DE clientes.py
------------------------------------------------------------------------------
`clientes.py` declara `require_permission("clientes.read")` **a nivel de
router**, que es lo que hace que sus seis endpoints de lectura nazcan
protegidos. Colgar el POST de ese mismo router le daría `clientes.read`: **quien
pudiera consultar la cartera de clientes podría crear empresas en ella.**

Es el mismo razonamiento que separó `acreditacion.py` de `catalogo.py` en la
fase 7C.1, y allí dos tests (`rbac_5`, `rbac_6`) quedaron vigilándolo. Aquí
también: `clientes.read` a solas responde 403 a este POST.

Router propio, mismo prefijo, permiso distinto:

    lectura    clientes.py             clientes.read    admin, comercial, aprobador, lectura
    escritura  clientes_escritura.py   clientes.manage  comercial

`clientes.py` no se ha tocado.

------------------------------------------------------------------------------
POR QUÉ HAY UN INSERT EN PYTHON, Y QUÉ SIGNIFICA
------------------------------------------------------------------------------
Es el primer INSERT del proyecto que no pasa por una función de caso de uso, y
no es una desviación: **no existe `fn_crear_empresa`**. El dominio de clientes
nunca tuvo funciones —se comprobó en las fases 7E y 7G— a diferencia del
catálogo y de las cotizaciones, que sí las tienen y que por eso NO deben
escribirse así.

La regla que queda para las fases siguientes: **si existe una función de caso de
uso, la API la llama; si no existe, la API escribe la tabla.** Reescribir en
Python lo que `fn_crear_cotizacion()` hace —correlativo, snapshot, recálculo,
historial— sería saltarse cuatro garantías a la vez.

------------------------------------------------------------------------------
EL INSERT NOMBRA CINCO COLUMNAS. LAS OTRAS OCHO LAS PONE EL MOTOR
------------------------------------------------------------------------------
    id            IDENTITY
    public_id     DEFAULT gen_random_uuid()
    tenant_id     DEFAULT fn_app_tenant()     ← del contexto de la transacción
    creado_por    fn_tocar() con fn_app_usuario()
    creado_en     DEFAULT now()
    activo        DEFAULT true
    actualizado_* solo en UPDATE

No se nombran. No hay nada que filtrar porque no hay nada que enviar, y el DTO
tampoco las declara. Comprobado sobre el esquema real: un INSERT con solo los
cinco campos de negocio sale con `tenant_id`, `creado_por`, `activo`,
`public_id` y `creado_en` correctos.
"""

from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, status
from psycopg import AsyncConnection
from psycopg.rows import dict_row

from sacgeo.api.deps import get_db_tx, require_permission
from sacgeo.api.dto_negocio import CrearContacto, CrearEmpresa
from sacgeo.api.escritura import resolver_public_id
from sacgeo.api.v1.clientes import ContactoConEmpresa, Empresa

log = logging.getLogger(__name__)

router = APIRouter(
    prefix="/clientes",
    tags=["clientes"],
    # `clientes.manage`, NO `clientes.read`. Ver la cabecera.
    dependencies=[Depends(require_permission("clientes.manage"))],
    responses={
        401: {"description": "no autenticado"},
        403: {"description": "sin el permiso clientes.manage"},
    },
)

# Cinco columnas, cinco parámetros ligados. Ni `tenant_id`, ni `creado_por`, ni
# `public_id`, ni `activo`: el motor los pone, y la política `WITH CHECK
# (tenant_id = fn_app_tenant())` rechazaría un tenant impuesto aunque llegara.
#
# RETURNING trae la fila ya construida por el motor, así que la respuesta refleja
# lo que quedó guardado y no lo que el backend creía que iba a guardar.
_SQL_CREAR_EMPRESA = """
    INSERT INTO empresas (ruc, razon_social, direccion, telefono, email)
    VALUES (%(ruc)s, %(razon_social)s, %(direccion)s, %(telefono)s, %(email)s)
    RETURNING public_id, ruc, razon_social, direccion, telefono, email, activo, 0 AS contactos
"""


@router.post(
    "/empresas",
    response_model=Empresa,
    status_code=status.HTTP_201_CREATED,
    summary="Crear una empresa cliente",
    responses={
        409: {"description": "ya existe una empresa con ese RUC en este laboratorio"},
        422: {"description": "datos inválidos o campo no permitido"},
    },
)
async def crear_empresa(
    datos: CrearEmpresa,
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> Empresa:
    """Crea una empresa cliente en el laboratorio de la sesión.

    Devuelve **201** con el recurso tal como quedó en la base, incluido su
    `public_id`. `contactos` sale 0 porque una empresa recién creada no tiene
    ninguno todavía; el alta de contactos es otra fase.

    Un RUC repetido DENTRO del laboratorio responde **409**: lo impone
    `uq_empresas_ruc (tenant_id, ruc)`, y `errors.py` ya traduce el `23505`. El
    mismo RUC en otro laboratorio es legítimo y no colisiona — es lo que el
    UNIQUE por tenant permite a propósito, porque dos laboratorios pueden
    facturar al mismo cliente.

    No hay COMMIT aquí: lo hace `get_db_tx` al salir, y ante cualquier excepción
    hace ROLLBACK. Si el endpoint pudiera confirmar por su cuenta, algún día
    alguno confirmaría a medias.
    """
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(
            _SQL_CREAR_EMPRESA,
            {
                "ruc": datos.ruc,
                "razon_social": datos.razon_social,
                "direccion": datos.direccion,
                "telefono": datos.telefono,
                "email": datos.email,
            },
            prepare=False,
        )
        fila = await cur.fetchone()

    # No se registra el RUC ni la razón social: el log no es el sitio para
    # acumular datos de clientes. `trg_auditar` ya guarda la fila entera, con su
    # autor sellado por fn_app_usuario() y sin posibilidad de falsificarlo.
    log.info("empresa creada public_id=%s", fila["public_id"])

    return Empresa(
        public_id=fila["public_id"],
        ruc=fila["ruc"],
        razon_social=fila["razon_social"],
        direccion=fila["direccion"],
        telefono=fila["telefono"],
        email=fila["email"],
        activo=fila["activo"],
        contactos=fila["contactos"],
    )


# ============================================================================
# CONTACTOS — fase 7I.1. Primer WRITE que REFERENCIA otro recurso.
# ============================================================================
# La cadena que esta fase existe para demostrar:
#
#   empresa_public_id (del cliente)
#        ↓  resolver_public_id(), punto único, dentro de la transacción
#   RLS decide si esa empresa es visible para esta sesión
#        ↓  si no lo es: 404, el mismo que un UUID inexistente
#   empresa_id interno
#        ↓  INSERT que NO nombra tenant_id ni creado_por
#   FK COMPUESTA (tenant_id, empresa_id) → empresas (tenant_id, id)
#        ↓
#   trg_auditar con autor sellado por fn_app_usuario() (0006)
#
# ----------------------------------------------------------------------------
# TRES BARRERAS PARA LO MISMO, Y LA TERCERA ES ESTRUCTURAL
# ----------------------------------------------------------------------------
# Un contacto sobre la empresa de otro laboratorio está impedido tres veces:
#
#   1. `resolver_public_id` no lo traduce — para esta sesión la empresa no
#      existe. Responde 404.
#   2. Si alguien saltara el resolutor y pasara el id interno ajeno a mano, la
#      **FK compuesta** lo rechaza: el par (tenant_id propio, empresa_id ajeno)
#      no existe en `empresas`. Comprobado como `sacgeo_app`:
#      «violates foreign key constraint "contactos_empresa_id_fkey"».
#   3. La política `WITH CHECK (tenant_id = fn_app_tenant())` gobierna el
#      tenant_id de la fila nueva.
#
# La (2) es la que importa: no es una comprobación que alguien deba recordar
# escribir, es una clave. Es el patrón que CLAUDE.md §5 llama «la pertenencia se
# declara con FK compuestas, no con disciplina».

_SQL_CREAR_CONTACTO = """
    INSERT INTO contactos (empresa_id, dni, nombres, apellidos, cargo,
                           celular, email)
    VALUES (%(empresa_id)s, %(dni)s, %(nombres)s, %(apellidos)s, %(cargo)s,
            %(celular)s, %(email)s)
    RETURNING public_id, dni, nombres, apellidos, cargo, celular, email, activo
"""


@router.post(
    "/contactos",
    response_model=ContactoConEmpresa,
    status_code=status.HTTP_201_CREATED,
    summary="Crear un contacto de empresa",
    responses={
        404: {"description": "la empresa no existe o no es de este laboratorio"},
        409: {"description": "esa empresa ya tiene un contacto con ese DNI"},
        422: {"description": "datos inválidos o campo no permitido"},
    },
)
async def crear_contacto(
    datos: CrearContacto,
    conn: Annotated[AsyncConnection, Depends(get_db_tx)],
) -> ContactoConEmpresa:
    """Crea un contacto sobre una empresa del laboratorio de la sesión.

    La empresa se identifica por su `public_id`. Si no es visible para esta
    sesión —porque no existe o porque es de otro laboratorio— la respuesta es
    **404**, la misma en los dos casos: distinguirlos convertiría el endpoint en
    un oráculo para descubrir qué empresas tiene la competencia probando UUIDs.

    Un DNI repetido DENTRO de la misma empresa responde **409**, por
    `uq_contactos_empresa_dni (tenant_id, empresa_id, dni)`. El mismo DNI en
    otra empresa es legítimo: una persona puede ser contacto de dos clientes.

    Las dos sentencias van en la MISMA transacción, así que la resolución y el
    INSERT ven la misma instantánea y comparten el ROLLBACK: si el INSERT falla,
    no queda nada.
    """
    # Punto ÚNICO de traducción. No hay un SELECT de empresas escrito aquí: si
    # lo hubiera, sería el noveno sitio donde equivocarse, y basta uno.
    empresa_id = await resolver_public_id(conn, "empresa", datos.empresa_public_id)

    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(
            _SQL_CREAR_CONTACTO,
            {
                "empresa_id": empresa_id,
                "dni": datos.dni,
                "nombres": datos.nombres,
                "apellidos": datos.apellidos,
                "cargo": datos.cargo,
                "celular": datos.celular,
                "email": datos.email,
            },
            prepare=False,
        )
        fila = await cur.fetchone()

    # Ni el DNI ni el nombre van al log: no es el sitio para acumular datos
    # personales. `trg_auditar` ya guarda la fila con su autor sellado.
    log.info("contacto creado public_id=%s", fila["public_id"])

    return ContactoConEmpresa(
        public_id=fila["public_id"],
        dni=fila["dni"],
        nombres=fila["nombres"],
        apellidos=fila["apellidos"],
        cargo=fila["cargo"],
        celular=fila["celular"],
        email=fila["email"],
        activo=fila["activo"],
        empresa=datos.empresa_public_id,
    )
