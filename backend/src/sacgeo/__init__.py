"""SAC-GEO backend.

Ajuste obligatorio en Windows: psycopg en modo async NO funciona sobre el
ProactorEventLoop, que es el bucle por omisión de asyncio en Windows desde
Python 3.8. Lanza:

    Psycopg cannot use the 'ProactorEventLoop' to run in async mode.

Se fija aquí, al importar el paquete, para que valga igual en la aplicación y
en los tests sin que cada punto de entrada tenga que acordarse. En Linux —el
entorno de producción previsto— esta rama no se ejecuta.
"""

import asyncio
import sys

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
