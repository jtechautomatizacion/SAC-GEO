"""Refresh tokens — BLOQUEADO: falta persistencia en el esquema.

------------------------------------------------------------------------------
POR QUÉ ESTE MÓDULO NO EMITE NADA
------------------------------------------------------------------------------
La fase 5C exige rotación con invalidación del token anterior:

    refresh antiguo  →  inválido
    refresh nuevo    →  válido

Eso es, por definición, ESTADO: para invalidar algo hay que recordar que se
invalidó. Un JWT es sin estado; su firma sigue siendo válida hasta `exp`
hagamos lo que hagamos. No existe forma criptográfica de revocarlo.

Se auditaron las 21 tablas de `sacgeo_dev` y **ninguna** sirve para esto:

    auditoria, campos_sensibles, categorias_ensayo, contactos, correlativos,
    cotizacion_historial_estados, cotizacion_items, cotizaciones,
    documentos_externos, empresas, ensayo_acreditacion_historial,
    ensayos_catalogo, integraciones, paquete_componentes, personas,
    plantillas_cotizacion, roles, schema_migrations, subcategorias_ensayo,
    tenants, usuarios

No hay tabla de sesiones ni de tokens. La fase 5C prohíbe explícitamente
modificar el esquema.

Las tres salidas fáciles están descartadas, y conviene decir por qué:

  · Guardarlos en memoria del proceso — se pierden al reiniciar y no funcionan
    con más de una réplica. Un usuario quedaría fuera al reiniciar, y peor: un
    token "revocado" volvería a ser válido tras el reinicio.
  · Guardarlos en un archivo local — mismo problema, más una condición de
    carrera y un fichero con material de autenticación en disco.
  · Emitir refresh tokens SIN rotación — un token de 7 días imposible de
    revocar. Es estrictamente PEOR que no tener refresh: amplía la ventana de
    un token robado de 15 minutos a una semana.

Por eso el login de esta fase **devuelve únicamente access token**. La sesión
dura 15 minutos y se vuelve a autenticar. Es una limitación de usabilidad
consciente, no un descuido, y desaparece en cuanto exista la tabla.

Lo que sí vive aquí son las dos primitivas que NO dependen del esquema y que la
implementación futura usará tal cual: generar el valor y hashearlo para
guardarlo. Están probadas y no emiten nada por sí solas.
"""

from __future__ import annotations

import hashlib
import secrets

# 32 bytes de entropía criptográfica. Es un valor opaco, no un JWT: no hay
# nada que el cliente deba leer dentro.
BYTES_ENTROPIA = 32


class RefreshNoDisponible(RuntimeError):
    """Se intentó usar refresh sin la persistencia que lo hace seguro."""


def generar_valor_refresh() -> str:
    """Genera un refresh token opaco, seguro para URL."""
    return secrets.token_urlsafe(BYTES_ENTROPIA)


def hashear_refresh(valor: str) -> str:
    """Hash del refresh token, que es lo ÚNICO que debe almacenarse.

    Se usa SHA-256 y no Argon2 a propósito: el valor tiene 256 bits de entropía
    aleatoria, así que no es susceptible de ataque por diccionario y no hace
    falta un hash lento. Lo que se busca aquí es que una lectura de la tabla no
    entregue tokens utilizables.

    Nota para 0005/0006: la columna que lo guarde debe registrarse en
    `campos_sensibles`, igual que `usuarios.password_hash`, para que no acabe
    copiada en `auditoria`.
    """
    if not valor:
        raise ValueError("no se hashea un refresh vacío")
    return hashlib.sha256(valor.encode("utf-8")).hexdigest()


def emitir_refresh(*_args, **_kwargs):
    """No disponible hasta que exista la tabla de sesiones."""
    raise RefreshNoDisponible(
        "La rotación de refresh tokens exige persistencia. No hay tabla de "
        "sesiones en el esquema y la fase 5C no autoriza crearla. "
        "Ver el diseño propuesto en el reporte de 5C."
    )


def rotar_refresh(*_args, **_kwargs):
    """No disponible hasta que exista la tabla de sesiones."""
    raise RefreshNoDisponible(
        "Rotar exige invalidar el token anterior, y eso exige recordarlo."
    )
