"""Tests 5-13 de la fase 5C: access tokens."""

from datetime import UTC, datetime, timedelta

import jwt as pyjwt
import pytest

from sacgeo.config import settings
from sacgeo.security import jwt as jwt_mod

SUB = "0f8b1c2d-3e4f-5a6b-7c8d-9e0f1a2b3c4d"


def test_5_token_valido():
    token, jti, expira = jwt_mod.emitir_access_token(SUB)
    payload = jwt_mod.validar_access_token(token)
    assert payload["sub"] == SUB
    assert payload["jti"] == jti
    assert expira == settings.access_token_minutos * 60


def test_6_token_expirado():
    pasado = datetime.now(UTC) - timedelta(hours=1)
    token = pyjwt.encode(
        {"sub": SUB, "jti": "x", "iat": int(pasado.timestamp()),
         "exp": int((pasado + timedelta(minutes=1)).timestamp())},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo,
    )
    with pytest.raises(jwt_mod.TokenInvalido):
        jwt_mod.validar_access_token(token)


def test_7_firma_invalida():
    token = pyjwt.encode(
        {"sub": SUB, "jti": "x",
         "iat": int(datetime.now(UTC).timestamp()),
         "exp": int((datetime.now(UTC) + timedelta(minutes=15)).timestamp())},
        "clave-del-atacante", algorithm="HS256",
    )
    with pytest.raises(jwt_mod.TokenInvalido):
        jwt_mod.validar_access_token(token)


def test_8_algoritmo_none_rechazado():
    """alg=none: el ataque clásico de JWT. Un token sin firma no se acepta."""
    token = pyjwt.encode(
        {"sub": SUB, "jti": "x",
         "iat": int(datetime.now(UTC).timestamp()),
         "exp": int((datetime.now(UTC) + timedelta(minutes=15)).timestamp())},
        key="", algorithm="none",
    )
    with pytest.raises(jwt_mod.TokenInvalido):
        jwt_mod.validar_access_token(token)


def test_8b_otro_algoritmo_rechazado():
    """Un algoritmo distinto del configurado no se acepta aunque firme bien."""
    token = pyjwt.encode(
        {"sub": SUB, "jti": "x",
         "iat": int(datetime.now(UTC).timestamp()),
         "exp": int((datetime.now(UTC) + timedelta(minutes=15)).timestamp())},
        settings.jwt_secret, algorithm="HS512",
    )
    with pytest.raises(jwt_mod.TokenInvalido):
        jwt_mod.validar_access_token(token)


def test_9_token_sin_sub():
    token = pyjwt.encode(
        {"jti": "x", "iat": int(datetime.now(UTC).timestamp()),
         "exp": int((datetime.now(UTC) + timedelta(minutes=15)).timestamp())},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo,
    )
    with pytest.raises(jwt_mod.TokenInvalido):
        jwt_mod.validar_access_token(token)


def test_10_token_sin_exp():
    token = pyjwt.encode(
        {"sub": SUB, "jti": "x", "iat": int(datetime.now(UTC).timestamp())},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo,
    )
    with pytest.raises(jwt_mod.TokenInvalido):
        jwt_mod.validar_access_token(token)


def test_token_vacio():
    with pytest.raises(jwt_mod.TokenInvalido):
        jwt_mod.validar_access_token("")


# --- Los tres que verifican la decisión D-4 ---------------------------------

def _claims_emitidos() -> set[str]:
    token, _, _ = jwt_mod.emitir_access_token(SUB)
    return set(pyjwt.decode(
        token, settings.jwt_secret, algorithms=[settings.jwt_algoritmo]
    ).keys())


def test_11_jwt_no_contiene_tenant_id():
    claims = _claims_emitidos()
    assert "tenant_id" not in claims
    assert "tenant" not in claims


def test_12_jwt_no_contiene_rol():
    claims = _claims_emitidos()
    assert "rol" not in claims and "role" not in claims and "roles" not in claims


def test_13_jwt_no_contiene_permisos():
    claims = _claims_emitidos()
    assert "permissions" not in claims
    assert "permisos" not in claims
    assert "scope" not in claims
    assert "plan" not in claims


def test_claims_exactos():
    """Los claims emitidos son EXACTAMENTE los aprobados. Ni uno más."""
    assert _claims_emitidos() == {"sub", "jti", "iat", "exp"}


def test_token_ajeno_con_tenant_id_es_rechazado():
    """Un token bien firmado pero con claims de autorización NO se acepta.

    Defensa contra un emisor futuro que intente meter autorización en el token:
    aunque la firma sea válida, el contrato dice que ahí no va.
    """
    token = pyjwt.encode(
        {"sub": SUB, "jti": "x", "tenant_id": 2,
         "iat": int(datetime.now(UTC).timestamp()),
         "exp": int((datetime.now(UTC) + timedelta(minutes=15)).timestamp())},
        settings.jwt_secret, algorithm=settings.jwt_algoritmo,
    )
    with pytest.raises(jwt_mod.TokenInvalido, match="claims de autorización"):
        jwt_mod.validar_access_token(token)


def test_jti_unico_por_token():
    _, jti1, _ = jwt_mod.emitir_access_token(SUB)
    _, jti2, _ = jwt_mod.emitir_access_token(SUB)
    assert jti1 != jti2
