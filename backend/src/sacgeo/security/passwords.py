"""Hash y verificación de contraseñas con Argon2id.

Se elige Argon2id sobre bcrypt por dos motivos concretos:

  · resistencia a GPU/ASIC — el coste en memoria es el que encarece el ataque
    masivo, y bcrypt apenas lo tiene;
  · bcrypt trunca silenciosamente a 72 bytes; una contraseña larga se recorta
    sin avisar.

El hash resultante ocupa ~97 caracteres y cabe holgadamente en
`usuarios.password_hash VARCHAR(255)`.

NUNCA se registra en logs: ni la contraseña, ni el hash, ni un fragmento de
ninguno de los dos. La migración 0003 ya impide además que el hash llegue a la
tabla `auditoria`, que es append-only (ver `campos_sensibles`).
"""

from __future__ import annotations

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

# Parámetros de partida. Calibrar en el servidor real para ~250 ms por hash:
# más bajo abarata el ataque offline, más alto convierte el login en un vector
# de denegación de servicio.
_hasher = PasswordHasher(
    time_cost=3,
    memory_cost=65536,   # 64 MiB
    parallelism=4,
    hash_len=32,
    salt_len=16,
)

LONGITUD_MINIMA = 12


class PasswordInvalida(ValueError):
    """La contraseña no cumple los requisitos mínimos."""


def hashear(password: str) -> str:
    """Devuelve el hash Argon2id de una contraseña.

    Rechaza la cadena vacía y las contraseñas demasiado cortas aquí, y no en el
    endpoint: así la regla no depende de que cada punto de entrada se acuerde.
    """
    if not password:
        raise PasswordInvalida("la contraseña no puede estar vacía")
    if len(password) < LONGITUD_MINIMA:
        raise PasswordInvalida(
            f"la contraseña debe tener al menos {LONGITUD_MINIMA} caracteres"
        )
    return _hasher.hash(password)


def verificar(password: str | None, hash_almacenado: str | None) -> bool:
    """Comprueba una contraseña contra su hash. Nunca lanza por datos malos.

    Devuelve False —jamás una excepción que se propague— ante:
      · hash NULL, que es el caso del usuario `sistema` y de cualquier cuenta
        sin credencial asignada;
      · hash corrupto o con formato desconocido;
      · contraseña vacía.

    Que un hash NULL devuelva False de forma explícita importa: algunas
    librerías lanzan excepción ante None, y un `except` demasiado amplio en el
    endpoint podría convertir ese error en un camino inesperado. Aquí el caso
    se trata de frente.
    """
    if not password or not hash_almacenado:
        return False
    try:
        _hasher.verify(hash_almacenado, password)
        return True
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def necesita_rehash(hash_almacenado: str) -> bool:
    """Indica si el hash se generó con parámetros ya obsoletos.

    Permite endurecer los parámetros con el tiempo y re-hashear de forma
    transparente en el siguiente login correcto, sin pedir nada al usuario.
    """
    try:
        return _hasher.check_needs_rehash(hash_almacenado)
    except InvalidHashError:
        return False
