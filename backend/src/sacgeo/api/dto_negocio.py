"""DTO de escritura del dominio. TODAVÍA SIN ENDPOINT QUE LOS USE.

Existen antes que sus endpoints a propósito: son el contrato tipado que tiene
que ir delante de los tres `jsonb` de las funciones de caso de uso, y escribirlo
junto al endpoint que lo necesita es escribirlo con prisa.

------------------------------------------------------------------------------
QUÉ PROBLEMA RESUELVEN EXACTAMENTE
------------------------------------------------------------------------------
Tres funciones reciben `jsonb` y leen sus claves con `->>`:

    fn_crear_cotizacion(p_items jsonb)         lee ensayo_id, cantidad, acreditado
    fn_definir_componentes(p_componentes jsonb) lee ensayo_id, cantidad, nombre, norma
    fn_crear_paquete(p_componentes jsonb)       ídem

`->>` **ignora en silencio** cualquier clave que no lea. Hoy
`{"ensayo_id": 1, "precio_unitario": 0}` descartaría el precio — pero por
accidente de cómo está escrita la función, no porque nadie lo haya decidido. Y
un accidente deja de protegerte el día que alguien añade una clave a la función.

Estos DTO convierten ese accidente en un contrato: lo que no está declarado
responde 422.

------------------------------------------------------------------------------
LOS DTO HABLAN public_id; LAS FUNCIONES HABLAN id
------------------------------------------------------------------------------
Aquí `ensayo`, `empresa`, `contacto`, `persona` y `plantilla` son UUID. La
traducción a id interno la hace `escritura.resolver_public_id()` dentro de la
transacción y bajo RLS. Ningún DTO acepta un entero: aceptar uno reabriría el
IDOR que la traducción centralizada cierra.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from sacgeo.api.escritura import EntradaWrite


class ItemCotizacion(EntradaWrite):
    """Un ensayo cotizado.

    NO declara `precio_unitario`, `subtotal`, `codigo_snapshot` ni ninguno de los
    ocho `*_snapshot`: los calcula y congela `fn_crear_cotizacion` copiando el
    catálogo del momento. Un cliente que pudiera fijar el precio de un ítem
    podría cotizarse a sí mismo un ensayo a cero.

    `acreditado_override` SÍ es entrada del cliente, y se llama así y no
    `acreditado` a propósito: sobreescribe el estado del catálogo para esta
    cotización, y el nombre tiene que decir que es una excepción deliberada —
    queda en `cotizacion_items.acreditado_override` y en la auditoría.
    """

    ensayo: UUID = Field(description="public_id del ensayo del catálogo.")
    cantidad: int = Field(default=1, ge=1, le=999)
    acreditado_override: bool | None = Field(
        default=None,
        description="Cotiza el ensayo con un estado de acreditación distinto "
                    "al del catálogo. Null = se usa el del catálogo.",
    )


class ComponentePaquete(EntradaWrite):
    """Un componente de paquete: o un ensayo del catálogo, o texto libre.

    Los dos CHECK del esquema exigen exactamente esta disyuntiva:

        ck_componente_vinculado_o_descrito   ensayo IS NOT NULL OR nombre <> ''
        ck_componente_sin_texto_duplicado    ensayo IS NULL OR (nombre IS NULL
                                                            AND norma IS NULL)

    El validador de abajo la impone ANTES de llegar a PostgreSQL. No sustituye a
    los CHECK —la BD sigue siendo la última barrera— pero convierte un 23514
    genérico en un 422 que dice qué está mal, y así el cliente puede corregirlo.
    """

    ensayo: UUID | None = Field(
        default=None, description="public_id del ensayo. Null si es descriptivo."
    )
    cantidad: int = Field(default=1, ge=1, le=999)
    nombre: str | None = Field(default=None, min_length=1, max_length=200)
    norma: str | None = Field(default=None, min_length=1, max_length=120)

    @model_validator(mode="after")
    def _vinculado_o_descriptivo(self) -> ComponentePaquete:
        if self.ensayo is None and not self.nombre:
            raise ValueError(
                "un componente lleva `ensayo` (vinculado al catálogo) o `nombre` "
                "(descriptivo). No puede no llevar ninguno de los dos."
            )
        if self.ensayo is not None and (self.nombre or self.norma):
            raise ValueError(
                "un componente vinculado no lleva `nombre` ni `norma` propios: "
                "salen del ensayo, que es la única fuente de verdad."
            )
        return self


class CrearCotizacion(EntradaWrite):
    """Alta de una cotización.

    Lo que NO declara, y por qué cada cosa:

      · `numero` — lo emite `fn_siguiente_correlativo()` **al emitir**, no al
        abrir el asistente, y no se reutiliza jamás;
      · `estado` — lo gobierna la máquina de estados. Ver `emitir`;
      · `fecha_emision` — `fn_hoy_lima()`;
      · `subtotal`, `igv`, `total`, `descuento_monto` — los calcula
        `fn_recalcular_cotizacion()`;
      · `igv_tasa` — es una tasa legal, no una preferencia del cliente. Queda
        con su `DEFAULT 0.1800` hasta que se decida de dónde leerla (abierto,
        junto a M-07);
      · `moneda` — `DEFAULT 'PEN'`. Cambiarla afecta a los importes y merece su
        propia decisión;
      · `tenant_id`, `creado_por` — contexto de sesión, impuesto por el motor.
    """

    empresa: UUID | None = Field(default=None, description="public_id de la empresa.")
    contacto: UUID | None = Field(
        default=None, description="public_id del contacto. Debe ser de la empresa."
    )
    persona: UUID | None = Field(
        default=None, description="public_id de la persona natural."
    )
    plantilla: UUID = Field(description="public_id de la plantilla.")

    proyecto_nombre: str = Field(min_length=1, max_length=200)
    validez_dias: int | None = Field(default=None, ge=1, le=365)
    notas: str | None = Field(default=None, max_length=5000)

    descuento_tipo: Literal["porcentaje", "monto"] | None = None
    descuento_valor: Decimal | None = Field(default=None, ge=0)
    descuento_razon: str | None = Field(default=None, min_length=1, max_length=200)

    items: list[ItemCotizacion] = Field(min_length=1, max_length=200)

    emitir: bool = Field(
        default=False,
        description="Emite la cotización al crearla. EXIGE cotizaciones.emit, "
                    "además de cotizaciones.create.",
    )

    @model_validator(mode="after")
    def _empresa_o_persona(self) -> CrearCotizacion:
        """Empresa+contacto O persona natural. Nunca las dos, nunca ninguna.

        El esquema lo modela como alternativas y `cotizaciones` las referencia
        con FK distintas — incluida la de tres columnas
        `(tenant_id, empresa_id, contacto_id)`, que hace imposible que el
        contacto sea de otra empresa.

        `emitir` con `default=False` no es un detalle: crear un borrador es la
        operación menos privilegiada, y quien no pida emitir explícitamente no
        debería necesitar `cotizaciones.emit`.
        """
        if self.persona is not None:
            if self.empresa is not None or self.contacto is not None:
                raise ValueError(
                    "una cotización es para una empresa (con su contacto) o para "
                    "una persona natural, no para las dos."
                )
            return self

        if self.empresa is None or self.contacto is None:
            raise ValueError(
                "falta el cliente: se necesita `empresa` + `contacto`, o `persona`."
            )
        return self

    @model_validator(mode="after")
    def _descuento_coherente(self) -> CrearCotizacion:
        """Un descuento se declara entero o no se declara.

        `descuento_monto` lo calcula la BD, pero el TIPO y el VALOR son decisión
        comercial, y un valor sin tipo no se puede interpretar: 10 ¿son diez
        soles o el diez por ciento? `fn_recalcular_cotizacion` lo resolvería por
        su CASE sin avisar, y la cotización saldría con un importe que nadie
        pidió.
        """
        declarados = [self.descuento_tipo is not None, self.descuento_valor is not None]
        if any(declarados) and not all(declarados):
            raise ValueError(
                "`descuento_tipo` y `descuento_valor` van juntos: un valor sin "
                "tipo es ambiguo."
            )
        if self.descuento_tipo == "porcentaje" and self.descuento_valor is not None:
            if self.descuento_valor > 100:
                raise ValueError("un descuento porcentual no pasa del 100.")
        return self


class CrearEmpresa(EntradaWrite):
    """Alta de una empresa cliente. Primer DTO de escritura en producción.

    ------------------------------------------------------------------------
    LOS CINCO CAMPOS SON TODO LO QUE EL CLIENTE ENVÍA
    ------------------------------------------------------------------------
    La tabla tiene trece columnas. Ocho las pone el motor, y se comprobó una
    por una sobre el esquema real antes de escribir esto:

        id             GENERATED BY DEFAULT AS IDENTITY
        public_id      DEFAULT gen_random_uuid()
        tenant_id      DEFAULT fn_app_tenant()        ← del contexto, no del cliente
        creado_por     lo fija `fn_tocar` con fn_app_usuario() si el INSERT
                       no lo trae
        creado_en      DEFAULT now()
        activo         DEFAULT true
        actualizado_por / actualizado_en   solo en UPDATE

    Ninguna está declarada aquí, así que `extra="forbid"` responde 422 a quien
    lo intente. Y si algún día un bug del backend colara un `tenant_id`, la
    política de `empresas` lo rechazaría igualmente:

        WITH CHECK (tenant_id = fn_app_tenant())

    Verificado como `sacgeo_app`: «new row violates row-level security policy».
    La BD es la última barrera, no la única.

    ------------------------------------------------------------------------
    LOS PATRONES REPLICAN LOS DOMINIOS, NO LOS ENDURECEN
    ------------------------------------------------------------------------
    `ruc` y `email` llevan exactamente la expresión de `dom_ruc` y `dom_email`.
    Es deliberado y hay precedente: en `auth.py` se documentó por qué NO se usa
    `pydantic.EmailStr` —rechaza los TLD reservados que la base sí acepta— y el
    efecto de una API más estricta que su esquema es que unos datos den 422 y
    otros 500 sin motivo aparente para quien los envía.

    Un RUC peruano empieza por 10, 15, 16, 17 o 20. No se valida el dígito
    verificador: el esquema no lo hace, y añadirlo aquí volvería a separar las
    dos reglas.
    """

    ruc: str = Field(
        pattern=r"^(10|15|16|17|20)[0-9]{9}$",
        description="RUC de 11 dígitos. Igual que el dominio dom_ruc.",
    )
    razon_social: str = Field(min_length=1, max_length=200)
    direccion: str | None = Field(default=None, min_length=1, max_length=250)
    telefono: str | None = Field(
        default=None, pattern=r"^[-0-9+() ]{6,25}$",
        description="Igual que el dominio dom_telefono.",
    )
    email: str | None = Field(
        default=None, max_length=150,
        pattern=r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$",
        description="Igual que el dominio dom_email.",
    )


class CrearContacto(EntradaWrite):
    """Alta de un contacto de empresa. Primer DTO que REFERENCIA otro recurso.

    ------------------------------------------------------------------------
    `empresa_public_id`, NUNCA `empresa_id`
    ------------------------------------------------------------------------
    El campo se llama así a propósito. Aceptar `empresa_id` —un entero
    secuencial— sería invitar a recorrerlo: pedir el contacto sobre la empresa
    1, la 2, la 3… hasta dar con una que no es del laboratorio. Ese es el IDOR
    clásico, y el nombre del campo es la primera línea que lo cierra.

    La traducción a id interno la hace `escritura.resolver_public_id()` dentro
    de la transacción y bajo RLS. Un `public_id` de otra empresa responde 404,
    igual que uno inexistente.

    ------------------------------------------------------------------------
    NUEVE COLUMNAS QUE EL CLIENTE NO ENVÍA
    ------------------------------------------------------------------------
    `contactos` tiene quince columnas. El cliente controla siete —seis de datos
    más la referencia— y las otras nueve las pone el motor:

        id, public_id, creado_en, activo   DEFAULT
        tenant_id                          DEFAULT fn_app_tenant()
        creado_por                         fn_tocar() con fn_app_usuario()
        actualizado_por / actualizado_en   solo en UPDATE
        empresa_id                         lo resuelve el backend, no el cliente

    `empresa_id` es el caso interesante: SÍ va en el INSERT, pero no viene del
    cliente. Viene de resolver `empresa_public_id`.

    ------------------------------------------------------------------------
    LOS PATRONES REPLICAN LOS DOMINIOS
    ------------------------------------------------------------------------
    `dni` → `dom_dni` (`^[0-9]{8}$`), `celular` → `dom_telefono`,
    `email` → `dom_email`. Exactamente los mismos, por el motivo que ya se
    documentó en `auth.py`: una API más estricta que su esquema hace que unos
    datos den 422 y otros 500 sin razón aparente para quien los envía.

    `dni` es OPCIONAL en el esquema, y aquí también: el seed tiene dos contactos
    sin DNI. Exigirlo sería inventar una regla de negocio que la base no tiene.
    """

    empresa_public_id: UUID = Field(
        description="public_id de la empresa a la que pertenece el contacto."
    )
    nombres: str = Field(min_length=1, max_length=100)
    apellidos: str = Field(min_length=1, max_length=100)
    dni: str | None = Field(
        default=None, pattern=r"^[0-9]{8}$",
        description="8 dígitos. Igual que el dominio dom_dni.",
    )
    cargo: str | None = Field(default=None, min_length=1, max_length=100)
    celular: str | None = Field(
        default=None, pattern=r"^[-0-9+() ]{6,25}$",
        description="Igual que el dominio dom_telefono.",
    )
    email: str | None = Field(
        default=None, max_length=150,
        pattern=r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$",
        description="Igual que el dominio dom_email.",
    )
