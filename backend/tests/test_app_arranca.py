"""La aplicación se importa y monta sus rutas.

Existe por un fallo real: `EmailStr` exige `email-validator`, que faltaba en las
dependencias. Los tests unitarios pasaban porque ninguno importaba el router, y
el fallo solo apareció al arrancar el servidor. Este test cierra ese hueco: si
falta una dependencia de importación, se ve aquí y no en el despliegue.
"""


def test_la_app_se_importa_y_monta_las_rutas():
    from sacgeo.main import app

    rutas = {r.path for r in app.routes}
    assert "/salud" in rutas
    assert "/auth/login" in rutas
    assert "/auth/yo" in rutas


def test_no_hay_endpoints_de_negocio():
    """La fase 5C solo autoriza autenticación."""
    from sacgeo.main import app

    prohibidas = ("cotizacion", "empresa", "ensayo", "auditoria", "cliente")
    for r in app.routes:
        for p in prohibidas:
            assert p not in r.path.lower(), f"endpoint de negocio no autorizado: {r.path}"
