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


def test_solo_los_recursos_autorizados_estan_montados():
    """Ningún recurso de negocio se publica antes de que su fase lo autorice.

    ---------------------------------------------------------------------------
    POR QUÉ ESTE TEST CAMBIÓ EN LA FASE 7F
    ---------------------------------------------------------------------------
    Nació en 5C como `test_no_hay_endpoints_de_negocio`, cuando el backend solo
    tenía autenticación, y prohibía cualquier ruta que contuviera «cotizacion»,
    «empresa», «ensayo», «auditoria» o «cliente». Esa premisa la han levantado
    las fases posteriores, una por una y con autorización explícita: catálogo en
    7B, categorías y acreditación en 7C.1, componentes en 7D.1 y clientes en 7F.

    Con la lista original, `/api/v1/clientes/empresas` lo hacía fallar — y el
    test tenía razón según su premisa de 5C, no según la autorización de 7F.

    NO se ha debilitado: se ha ajustado a los recursos que SIGUEN sin autorizar,
    y se le ha añadido lo que antes no comprobaba —que ninguna ruta de negocio
    exponga escritura—, que es hoy el bloqueo real (H-02, mass assignment).
    """
    from sacgeo.main import app

    # Recursos cuya fase NO está abierta. Cotizaciones espera M-07, usuarios
    # espera G-2, aprobaciones esperan la migración 0010, y el resto su diseño.
    # `usuario` y `plantilla` salieron de la lista en 7G, que autorizó su
    # lectura. La escritura la sigue impidiendo el test de más abajo, que es
    # una guarda más fuerte que una palabra en una ruta.
    prohibidos = (
        "cotizacion", "auditoria", "dashboard",
        "documento", "integracion", "aprobacion",
    )
    for r in app.routes:
        ruta = r.path.lower()
        for p in prohibidos:
            assert p not in ruta, f"recurso de negocio no autorizado: {r.path}"


def test_ningun_endpoint_de_negocio_acepta_escritura():
    """Solo las escrituras explícitamente autorizadas existen.

    Nació en 7F prohibiéndolas todas, cuando H-02 estaba abierto de par en par.
    La fase 7I abrió la primera —`POST /clientes/empresas`— usando las barreras
    de 7H.1, así que la lista pasa de estar vacía a tener una entrada.

    NO se ha debilitado: sigue fallando ante cualquier escritura que nadie haya
    autorizado, que es exactamente para lo que existe. Lo que cambia es que
    ahora la autorización se declara aquí, en una lista corta y legible, en vez
    de ser «ninguna».
    """
    from sacgeo.main import app

    escrituras = {"POST", "PUT", "PATCH", "DELETE"}
    # Las escrituras autorizadas, una por una y con la fase que las abrió.
    # Añadir una ruta aquí es una decisión explícita, no un efecto secundario.
    permitidas = {
        "/auth/login",                    # autenticación, no negocio
        "/api/v1/clientes/empresas",      # POST — fase 7I, primer WRITE real
        "/api/v1/clientes/contactos",     # POST — fase 7I.1, primer WRITE con referencia
    }

    infractoras = [
        (r.path, sorted(set(r.methods) & escrituras))
        for r in app.routes
        if getattr(r, "methods", None)
        and set(r.methods) & escrituras
        and r.path not in permitidas
    ]
    assert not infractoras, f"endpoints de escritura no autorizados: {infractoras}"
