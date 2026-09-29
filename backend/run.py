"""Punto de entrada para desarrollo local.

Existe por un motivo concreto de Windows, y conviene que esté explicado:

psycopg en modo async no funciona sobre el ProactorEventLoop, que es el bucle
por omisión de asyncio en Windows. Hay que cambiar la política a
WindowsSelectorEventLoopPolicy ANTES de que se cree el bucle.

Ponerlo en sacgeo/__init__.py no basta para el servidor: `uvicorn sacgeo.main:app`
crea el bucle ANTES de importar el módulo de la aplicación, así que para cuando
nuestro código se ejecuta ya es tarde. (Para pytest sí basta, porque allí el
paquete se importa primero.)

Por eso en Windows se arranca así:

    python run.py

y NO así:

    uvicorn sacgeo.main:app      # ← el pool no conectará

En Linux —el entorno de producción previsto— el problema no existe y el
Dockerfile invoca uvicorn directamente.
"""

import asyncio
import sys

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

import uvicorn  # noqa: E402  (debe importarse después de fijar la política)

if __name__ == "__main__":
    uvicorn.run(
        "sacgeo.main:app",
        host="127.0.0.1",
        port=8000,
        reload=True,
        log_level="info",
    )
