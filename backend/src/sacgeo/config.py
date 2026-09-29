"""Configuración leída del entorno. Ningún secreto vive en el repositorio."""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- PostgreSQL ---------------------------------------------------------
    # Hoy apunta al rol de desarrollo. A partir de 0004 debe apuntar a
    # sacgeo_app: sin BYPASSRLS y sin ser propietario de las tablas.
    database_url: str = "postgresql://sacgeo_dev@localhost:5432/sacgeo_dev"

    # --- Pool ---------------------------------------------------------------
    pool_min_size: int = 2
    pool_max_size: int = 10
    pool_timeout: float = 10.0
    pool_max_lifetime: float = 1800.0   # 30 min: recicla y evita fugas de memoria
    pool_max_idle: float = 300.0        # 5 min: devuelve recursos en horas valle

    # Red de seguridad, no sustituto de set_config(..., true). Ver db/pool.py.
    pool_discard_all: bool = True

    # --- Seguridad ----------------------------------------------------------
    # Ponerlo en true al aplicar 0004: a partir de entonces, arrancar con un rol
    # capaz de saltarse RLS impide el arranque, no solo lo advierte.
    #
    # El valor por omisión es false porque hoy 0004 NO esta aplicado en ninguna
    # base y el unico rol existente es sacgeo_dev, que es superusuario. Poner
    # true aqui dejaria el backend sin arrancar en el entorno de trabajo
    # actual. Deja de ser un valor aceptable en el momento en que 0004 entra.
    require_rls_safe_role: bool = False

    # Nombre del rol con el que la API DEBE conectarse en modo seguro.
    #
    # Comprobar solo los privilegios no basta: un rol sin SUPERUSER ni
    # BYPASSRLS puede aun asi tener GRANTs que no le corresponden. Fijar el
    # nombre convierte "conectarse con el rol equivocado" en un fallo de
    # arranque en vez de en un permiso de mas que nadie nota.
    rol_aplicacion: str = "sacgeo_app"

    entorno: str = "desarrollo"

    # --- Autenticación ------------------------------------------------------
    # Sin valor por omisión a propósito: si falta JWT_SECRET en el entorno, la
    # aplicación no arranca. Un secreto de ejemplo que funcione en desarrollo
    # es un secreto de ejemplo que acaba en producción.
    jwt_secret: str
    jwt_algoritmo: str = "HS256"

    access_token_minutos: int = 15      # decisión D-4
    refresh_token_dias: int = 7         # decisión D-4, pendiente de persistencia

    @property
    def es_desarrollo(self) -> bool:
        return self.entorno == "desarrollo"


settings = Settings()
