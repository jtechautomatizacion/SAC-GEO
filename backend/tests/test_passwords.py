"""Tests 1-4 de la fase 5C: contraseñas."""

import logging

import pytest

from sacgeo.security import passwords


def test_1_password_correcto():
    h = passwords.hashear("contraseña-de-prueba-larga")
    assert passwords.verificar("contraseña-de-prueba-larga", h) is True


def test_2_password_incorrecto():
    h = passwords.hashear("contraseña-de-prueba-larga")
    assert passwords.verificar("contraseña-equivocada", h) is False


def test_3_hash_corrupto_falla_controladamente():
    """Un hash inválido devuelve False; NO propaga una excepción.

    Si lanzara, un `except` demasiado amplio en el endpoint podría convertir el
    error en un camino inesperado.
    """
    assert passwords.verificar("cualquiera", "esto-no-es-un-hash") is False
    assert passwords.verificar("cualquiera", "$argon2id$roto") is False
    assert passwords.verificar("cualquiera", "") is False


def test_3b_hash_nulo_devuelve_false():
    """Caso del usuario `sistema`: password_hash IS NULL."""
    assert passwords.verificar("cualquiera", None) is False


def test_password_vacio_rechazado():
    with pytest.raises(passwords.PasswordInvalida):
        passwords.hashear("")
    assert passwords.verificar("", passwords.hashear("otra-contraseña-larga")) is False


def test_password_corto_rechazado():
    with pytest.raises(passwords.PasswordInvalida):
        passwords.hashear("corta")


def test_hashes_distintos_para_la_misma_password():
    """Salt aleatorio: dos hashes de la misma contraseña deben diferir."""
    a = passwords.hashear("misma-contraseña-larga")
    b = passwords.hashear("misma-contraseña-larga")
    assert a != b
    assert passwords.verificar("misma-contraseña-larga", a)
    assert passwords.verificar("misma-contraseña-larga", b)


def test_es_argon2id():
    assert passwords.hashear("contraseña-de-prueba-larga").startswith("$argon2id$")


def test_4_password_no_aparece_en_logs(caplog):
    """La contraseña no debe filtrarse a los logs por ningún camino."""
    secreto = "ESTA-CONTRASENA-NO-DEBE-APARECER"
    with caplog.at_level(logging.DEBUG):
        h = passwords.hashear(secreto)
        passwords.verificar(secreto, h)
        passwords.verificar("otra", h)
        passwords.verificar(secreto, "hash-roto")
    texto = caplog.text
    assert secreto not in texto
    assert h not in texto
