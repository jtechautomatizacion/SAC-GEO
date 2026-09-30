"""Endpoints de autenticación. Lo mínimo para iniciar sesión.

No hay endpoints de negocio aquí ni en ninguna otra parte todavía.
"""

from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict, Field

from sacgeo.api.deps import get_current_user
from sacgeo.api.query import SinParametros
from sacgeo.db.pool import obtener_pool
from sacgeo.security import jwt as jwt_mod
from sacgeo.security.autenticacion import (
    CredencialesInvalidas,
    UsuarioAutenticado,
    autenticar,
)

log = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])

# Un solo error para todos los fallos de login. Distinguir "no existe" de
# "contraseña incorrecta" de "desactivado" permite enumerar cuentas.
_CREDENCIALES = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="credenciales inválidas",
    headers={"WWW-Authenticate": "Bearer"},
)


# Misma regla que el dominio `dom_email` de PostgreSQL:
#     ^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z]{2,}$
#
# NO se usa pydantic.EmailStr, y el motivo es concreto: EmailStr rechaza los
# TLD de uso reservado (.local, .test, .internal), y `usuarios` ya contiene
# `sistema@gtqc.local`. Un laboratorio con dominio interno tendría usuarios que
# la base acepta y el backend rechaza — una incoherencia que aparecería como
# "no puedo entrar" sin explicación.
#
# Además, validar el formato aquí con una regla MÁS estricta que la de la base
# haría que el login devolviera 422 para unos correos y 401 para otros,
# dando una señal distinta según el input.
PATRON_EMAIL = r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"


class LoginRequest(BaseModel):
    # extra="forbid": un campo no previsto no se ignora, se rechaza con 422.
    # Ignorarlo en silencio escondería el intento; rechazarlo lo hace visible.
    model_config = ConfigDict(extra="forbid")

    email: str = Field(min_length=3, max_length=150, pattern=PATRON_EMAIL)
    password: str = Field(min_length=1, max_length=256)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int

    # NO se devuelve refresh_token: la rotación segura exige persistencia que el
    # esquema todavía no tiene. Ver security/refresh.py y el reporte de 5C.
    # NO se devuelven rol, permisos ni password_hash.


class UsuarioResponse(BaseModel):
    public_id: str
    email: str
    # tenant_id se incluye porque el frontend necesita saber en qué laboratorio
    # está operando para mostrarlo. NO es un dato que el cliente pueda usar para
    # elegir: el backend lo resuelve de nuevo en cada petición.
    tenant_id: int


@router.post("/login", response_model=TokenResponse)
async def login(datos: LoginRequest) -> TokenResponse:
    """Verifica credenciales y emite un access token."""
    pool = obtener_pool()
    try:
        async with pool.connection() as conn:
            usuario = await autenticar(conn, datos.email, datos.password)
    except CredencialesInvalidas:
        # El email NO se registra: un log de intentos fallidos con correos
        # acaba siendo una lista de cuentas válidas para quien lea los logs.
        log.info("login fallido")
        raise _CREDENCIALES from None

    token, jti, expira_en = jwt_mod.emitir_access_token(usuario.public_id)
    log.info("login correcto usuario_id=%s jti=%s", usuario.id, jti)
    return TokenResponse(access_token=token, expires_in=expira_en)


@router.get("/yo", response_model=UsuarioResponse)
async def yo(
    _: Annotated[SinParametros, Query()],
    usuario: UsuarioAutenticado = Depends(get_current_user),
) -> UsuarioResponse:
    """Devuelve la identidad de la sesión actual.

    Sirve para que el frontend sepa quién es sin decodificar el token — y para
    verificar que la cadena de dependencias funciona de extremo a extremo.
    """
    return UsuarioResponse(
        public_id=usuario.public_id,
        email=usuario.email,
        tenant_id=usuario.tenant_id,
    )
