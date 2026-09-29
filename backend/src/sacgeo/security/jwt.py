"""Emisión y validación de access tokens.

------------------------------------------------------------------------------
QUÉ LLEVA EL TOKEN, Y POR QUÉ TAN POCO
------------------------------------------------------------------------------
Claims: sub, jti, iat, exp. Nada más.

NO lleva tenant_id, ni rol, ni permisos, ni plan, ni capacidades. La decisión
está tomada (D-4) y el motivo es operativo: un claim firmado es inmutable hasta
que expira, así que un cambio de rol —o la retirada del acceso a un tenant—
tardaría hasta 15 minutos en surtir efecto. Peor: un claim firmado invita a
confiar en él sin revalidar, y esa costumbre es la que acaba aceptando un
tenant_id NO firmado el día que alguien añade un endpoint con prisa.

El token dice QUIÉN es el usuario. PostgreSQL dice QUÉ puede hacer.

------------------------------------------------------------------------------
ALGORITMO
------------------------------------------------------------------------------
Se fija en configuración y se pasa a jwt.decode como lista blanca de UN
elemento. Esto cierra dos ataques clásicos:

  · alg=none — el token se acepta sin firma;
  · confusión HS/RS — un token firmado con HMAC usando la clave pública RSA
    como secreto se valida como si fuera RSA.

PyJWT no acepta "none" si no está en la lista, pero además aquí se rechaza de
forma explícita antes de decodificar: defensa en profundidad sobre una
categoría de fallo que históricamente ha comprometido muchos sistemas.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import jwt

from sacgeo.config import settings

ALGORITMOS_PROHIBIDOS = {"none", "None", "NONE", ""}

# Claims permitidos. Cualquier otro en un token emitido por nosotros es un bug.
CLAIMS_PERMITIDOS = frozenset({"sub", "jti", "iat", "exp"})

# Claims cuya presencia indicaría que alguien intentó meter autorización en el
# token. Se rechazan al validar, aunque la firma sea correcta.
CLAIMS_PROHIBIDOS = frozenset(
    {"tenant_id", "tenant", "rol", "role", "roles", "permissions", "permisos",
     "plan", "capacidades", "scope", "scopes"}
)


class TokenInvalido(Exception):
    """El token no es utilizable. Nunca explica por qué al cliente."""


def emitir_access_token(public_id_usuario: str) -> tuple[str, str, int]:
    """Devuelve (token, jti, segundos_de_vida).

    `sub` es el public_id (UUID) del usuario, nunca el id técnico: ese no sale
    a la API.
    """
    ahora = datetime.now(UTC)
    expira = ahora + timedelta(minutes=settings.access_token_minutos)
    jti = uuid.uuid4().hex

    payload = {
        "sub": str(public_id_usuario),
        "jti": jti,
        "iat": int(ahora.timestamp()),
        "exp": int(expira.timestamp()),
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algoritmo)
    return token, jti, settings.access_token_minutos * 60


def validar_access_token(token: str) -> dict:
    """Valida firma, expiración y forma. Devuelve el payload.

    Lanza TokenInvalido en cualquier caso de fallo, sin distinguir el motivo
    hacia fuera: el endpoint traduce todo a 401 con un mensaje genérico.
    """
    if not token:
        raise TokenInvalido("token ausente")

    if settings.jwt_algoritmo in ALGORITMOS_PROHIBIDOS:
        raise TokenInvalido("algoritmo del servidor mal configurado")

    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algoritmo],   # lista blanca de UNO
            options={"require": ["sub", "exp", "iat", "jti"]},
        )
    except jwt.ExpiredSignatureError as e:
        raise TokenInvalido("token expirado") from e
    except jwt.InvalidTokenError as e:
        raise TokenInvalido("token inválido") from e

    # Un token con claims de autorización no es nuestro, o alguien cambió el
    # emisor sin revisar este contrato. En ambos casos: no se usa.
    intrusos = CLAIMS_PROHIBIDOS & payload.keys()
    if intrusos:
        raise TokenInvalido(f"el token trae claims de autorización: {sorted(intrusos)}")

    if not payload.get("sub"):
        raise TokenInvalido("token sin sujeto")

    return payload
