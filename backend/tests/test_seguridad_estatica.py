"""Test 28: patrones peligrosos en el código fuente.

Es un test barato que atrapa una categoría entera de errores en revisión, no en
producción. Si alguien escribe una f-string con SQL, o hardcodea un tenant, o
mete un secreto, esto lo detiene antes del commit.
"""

import re
from pathlib import Path

FUENTE = Path(__file__).resolve().parents[1] / "src" / "sacgeo"


def _archivos_py():
    return [p for p in FUENTE.rglob("*.py") if "__pycache__" not in str(p)]


def _codigo_sin_comentarios(texto: str) -> str:
    """Quita comentarios y docstrings para no dar falsos positivos.

    Los módulos de este backend explican en prosa los patrones que evitan
    (f-strings con SQL, SET de sesión…), así que buscar sobre el texto crudo
    detectaría las explicaciones, no el código.
    """
    sin_docstrings = re.sub(r'"""(?:.|\n)*?"""', "", texto)
    sin_docstrings = re.sub(r"'''(?:.|\n)*?'''", "", sin_docstrings)
    return "\n".join(
        linea for linea in sin_docstrings.splitlines()
        if not linea.strip().startswith("#")
    )


def test_28a_sin_sql_por_f_string():
    """Ninguna sentencia SQL se construye con f-string o concatenación."""
    patron = re.compile(
        r'f["\'].*\b(SELECT|INSERT|UPDATE|DELETE|SET\s+LOCAL|set_config)\b',
        re.IGNORECASE,
    )
    hallazgos = []
    for p in _archivos_py():
        for n, linea in enumerate(_codigo_sin_comentarios(p.read_text("utf-8")).splitlines(), 1):
            if patron.search(linea):
                hallazgos.append(f"{p.name}:{n}: {linea.strip()}")
    assert not hallazgos, "SQL construido con f-string:\n" + "\n".join(hallazgos)


def test_28b_sin_set_de_sesion():
    """El contexto se fija con set_config(..., true), nunca con SET de sesión.

    Un SET de sesión sobrevive al COMMIT y contamina la siguiente petición del
    pool — posiblemente de otro laboratorio.
    """
    hallazgos = []
    for p in _archivos_py():
        codigo = _codigo_sin_comentarios(p.read_text("utf-8"))
        for n, linea in enumerate(codigo.splitlines(), 1):
            if re.search(r'["\']\s*SET\s+app\.', linea, re.IGNORECASE):
                hallazgos.append(f"{p.name}:{n}: {linea.strip()}")
    assert not hallazgos, "SET de sesión en vez de set_config:\n" + "\n".join(hallazgos)


def test_28c_set_config_siempre_local():
    """Toda llamada a set_config del código lleva el tercer argumento true."""
    for p in _archivos_py():
        codigo = _codigo_sin_comentarios(p.read_text("utf-8"))
        for m in re.finditer(r"set_config\([^)]*\)", codigo, re.IGNORECASE):
            frag = m.group(0)
            # El SQL parametrizado usa %s como tercer argumento sólo si es literal.
            assert "true" in frag.lower() or "%s, true" in frag.lower(), (
                f"{p.name}: set_config sin LOCAL → {frag}"
            )


def test_28d_sin_tenant_hardcodeado():
    """Ningún tenant_id literal fuera de tests."""
    patron = re.compile(r"tenant_id\s*=\s*[0-9]+")
    hallazgos = []
    for p in _archivos_py():
        for n, linea in enumerate(_codigo_sin_comentarios(p.read_text("utf-8")).splitlines(), 1):
            if patron.search(linea):
                hallazgos.append(f"{p.name}:{n}: {linea.strip()}")
    assert not hallazgos, "tenant_id hardcodeado:\n" + "\n".join(hallazgos)


def test_28e_sin_secretos_hardcodeados():
    """Ninguna clave, secreto o contraseña literal en el código."""
    patron = re.compile(
        r'(jwt_secret|secret_key|api_key|password|passwd|token)\s*=\s*["\'][^"\']{8,}["\']',
        re.IGNORECASE,
    )
    hallazgos = []
    for p in _archivos_py():
        for n, linea in enumerate(_codigo_sin_comentarios(p.read_text("utf-8")).splitlines(), 1):
            if patron.search(linea):
                hallazgos.append(f"{p.name}:{n}: {linea.strip()}")
    assert not hallazgos, "posible secreto hardcodeado:\n" + "\n".join(hallazgos)


def test_28f_jwt_no_emite_tenant_ni_rol():
    """El emisor de tokens no incluye claims de autorización."""
    codigo = _codigo_sin_comentarios(
        (FUENTE / "security" / "jwt.py").read_text("utf-8")
    )
    emisor = codigo.split("def emitir_access_token")[1].split("def ")[0]
    for prohibido in ("tenant_id", "rol", "role", "permis", "plan", "scope"):
        assert f'"{prohibido}"' not in emisor, (
            f"el emisor de JWT incluye el claim prohibido {prohibido!r}"
        )


def test_28g_sin_password_en_logs():
    """Ninguna llamada a log.* recibe la contraseña o el hash."""
    patron = re.compile(
        r"log(?:ger)?\.\w+\([^)]*\b(password|contrase|hash_almacenado|password_hash)\b",
        re.IGNORECASE,
    )
    hallazgos = []
    for p in _archivos_py():
        codigo = _codigo_sin_comentarios(p.read_text("utf-8"))
        for n, linea in enumerate(codigo.splitlines(), 1):
            if patron.search(linea):
                hallazgos.append(f"{p.name}:{n}: {linea.strip()}")
    assert not hallazgos, "posible contraseña en logs:\n" + "\n".join(hallazgos)
