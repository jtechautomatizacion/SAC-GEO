# CLAUDE.md — Sistema de Cotizaciones GTQC

> Este archivo es el cerebro del proyecto. Cualquier sesión que trabaje aquí lo lee **primero**.
> Si algo de lo que vas a hacer contradice este archivo, para y pregunta.
> Cuando se tome una decisión nueva que valga para el futuro, se escribe aquí.

---

## 1. Qué es esto

Sistema de cotizaciones para **GTQC — Group Total Quality Control S.A.C.**, laboratorio de ensayos de materiales en Perú (suelos, concreto, asfalto, albañilería).

Flujo del negocio, de punta a punta:

```
EMPRESA (RUC) ──→ CONTACTO ──┐
                              ├──→ COTIZACIÓN #COT-2026-001 ──→ PLANTILLA
PERSONA NATURAL (DNI) ───────┘              │
                                            ├── ÍTEM 1 → ensayo individual
                                            ├── ÍTEM 2 → ensayo individual
                                            └── ÍTEM 3 → paquete → componentes A, B, C
                                            │
                          PRECIO FINAL → ESTADO → PDF → DOCUMENTO EN NUBE
```

Atraviesan todo el flujo: **usuarios y roles** (quién puede hacer qué), **auditoría** (quién cambió qué y cuándo), **acreditación ISO 17025** (qué ensayos estaban acreditados en la fecha del documento) e **integraciones** de nube.

---

## 2. Dónde estamos (actualizar al cerrar cada fase)

| Fase | Estado |
|---|---|
| 1 · Mockup / diseño de la app | ✅ **Terminado y congelado.** No se toca el diseño |
| 2 · Base de datos | ✅ **Terminada** (v3.0, 27-sep-2026) — ver `docs/AUDITORIA_BD_v3.md` |
| 3 · Evaluación de motor e infraestructura | ✅ **Terminada** (27-sep-2026) — ver `docs/03_AMBIENTES.md` |
| 4 · Multi-tenant en la BD | ✅ **Terminada** (29-sep-2026) — `0003`, `0004` y `0005` aplicadas y certificadas |
| 5 · Backend / API | 🔶 **En progreso.** 16 GET y 2 POST bajo `/api/v1`: catálogo (7B), categorías y acreditación (7C.1), componentes (7D.1), clientes (7F), usuarios y plantillas (7G), y las dos primeras escrituras (7I, 7I.1). Faltan cotizaciones, dashboard, auditoría y el resto de escrituras |
| 6 · Autenticación y autorización | 🔶 **En progreso.** 6A y 6B cerradas, y los guards ya protegen un endpoint real (7B): **H-01 cerrado**. Faltan las subfases `0008`–`0010` y el hardening |
| 7 · Multi-tenant de aplicación + RLS | ✅ **Terminada** (29-sep-2026) — RLS forzada, aislamiento certificado |
| 8 · Frontend conectado al backend | ⏳ Pendiente |

**Cada fase se apoya en la anterior. No saltar etapas.**

### Estado real de la base de trabajo

`sacgeo_dev`, en el contenedor `sac-geo-postgres-dev` (PostgreSQL 16.15):

- migraciones aplicadas: `0001, 0002, 0003, 0004, 0005, 0006, 0007`
- RLS: **18 tablas** con `ENABLE` **y** `FORCE`, **19 políticas**
- roles del clúster: `sacgeo_dev` (dueño, superusuario — **nunca** para la API),
  `sacgeo_app` (el rol de la API), `sacgeo_auth` (NOLOGIN, dueño de las dos
  funciones de login)
- auditoría: 355 filas, 11 de ellas globales (`tenant_id` NULL)
- RBAC: 31 permisos, 49 `rol_permisos`, 2 `usuario_roles`

### Superficie de la API publicada

Del código, no de la documentación (`app.routes`, 30-sep-2026):

```
LECTURA — 16 GET bajo /api/v1, más /auth/yo, /salud y /salud/rol
  /api/v1/catalogo · /{public_id} · /{public_id}/acreditacion · /{public_id}/componentes
  /api/v1/categorias · /{public_id}
  /api/v1/clientes/empresas · /{public_id} · /{public_id}/contactos
  /api/v1/clientes/personas · /{public_id}
  /api/v1/clientes/contactos/{public_id}
  /api/v1/usuarios · /{public_id}
  /api/v1/plantillas · /{public_id}

ESCRITURA — TRES en todo el sistema, y ni una más
  POST /auth/login                      (autenticación, no negocio)
  POST /api/v1/clientes/empresas        clientes.manage   (7I)
  POST /api/v1/clientes/contactos       clientes.manage   (7I.1)
```

**No existe ningún PUT, PATCH ni DELETE**, ni escrituras de personas, cotizaciones,
usuarios o catálogo. `test_ningun_endpoint_de_negocio_acepta_escritura` falla si
aparece una escritura que no esté en esa lista de tres.

Permiso por router: `catalogo.read` (catálogo y categorías) · `acreditacion.read` ·
`clientes.read` (lectura) · `clientes.manage` (escritura) · `usuarios.read` ·
`cotizaciones.read` (plantillas, ver §5).

### Estado de Git

```
HEAD         2df52dfbc9dd37198d2be283f329bbdc2511f1c1
             feat(security): establish secured client read and write surface
branch       main
working tree LIMPIO
origin/main  4a34c60   ← main va 1 commit POR DELANTE: el push está PENDIENTE
```

El commit de 7I.2 consolida las cinco fases 7F, 7G, 7H.1, 7I y 7I.1 en 20 archivos,
sin SQL, sin migraciones y sin cambios en RLS ni en RBAC.

### Qué falta para cerrar la fase 5 (backend)

- **Endpoints de negocio.** Hoy no existe ninguno, a propósito: cada fase los
  prohibió expresamente hasta cerrar la autorización. Hoy existen los de
  catálogo, categorías, acreditación, componentes, clientes, usuarios y
  plantillas; faltan cotizaciones, dashboard, auditoría, documentos e
  integraciones.
- **Escrituras**: solo dos, `POST /clientes/empresas` y `POST /clientes/contactos`.
  Faltan personas, y todos los `PATCH`/`DELETE` — que son un contrato distinto
  (campos parciales, `actualizado_por`, baja lógica) y merecen su propio diseño.
- Paginación y filtros: hechos en las colecciones publicadas. Falta el mapeo
  completo de errores de dominio.

### Qué falta para cerrar la fase 6 (autenticación y autorización)

La auditoría de seguridad previa a las APIs (`docs/AUDITORIA_SEGURIDAD_PRE_API.md`)
encontró **15 hallazgos** y concluyó que **hoy no se puede publicar un endpoint de
escritura sin crear una vulnerabilidad estructural**: RLS separa laboratorios, pero
dentro de un laboratorio no hay ninguna barrera entre lo que un usuario puede hacer
y lo que le corresponde.

El plan de migraciones, en orden:

| # | Contenido | Estado |
|---|---|---|
| **0006** | Autor de auditoría no falsificable (H-06) | ✅ **aplicada y certificada** (29-sep-2026) |
| **0007** | RBAC multi-rol: `permisos`, `rol_permisos`, `usuario_roles` + H-15 y H-13 | ✅ **aplicada y certificada** (29-sep-2026) |
| **0008** | Sesiones y refresh con rotación y detección de reuso | ⏳ diseño previo pendiente de revisar |
| **0009** | `eventos_seguridad` | ⏳ |
| **0010** | Flujo de aprobación (`docs/FLUJO_APROBACION.md`) | ⏳ |

Y en el backend, lo hecho y lo que falta:

| | Estado |
|---|---|
| `require_permission()`, `require_any_permission()`, `require_all_permissions()` | ✅ **fase 6B** (29-sep-2026), 16 pruebas |
| **Barreras** de H-02: `EntradaWrite` + `resolver_public_id()` + DTO tipados | ✅ **fase 7H.1**, 40 pruebas. ⚠ tenerlas NO cierra H-02: ver abajo |
| `SinParametros` en los endpoints sin parámetros de consulta | ✅ **fase 7F**, 25 pruebas |
| `/api/v1` para los recursos de negocio | ✅ desde 7B. `/auth` sigue sin versión (ver §5) |
| Mapeo de errores de dominio completo | 🔶 23503/23505/23514/23001/22P02/P0002 mapeados; faltan los de cotizaciones |
| `/docs` condicionado al entorno | ⏳ (G-4) |
| Límite de intentos en el login (H-08) | ⏳ |

### Gaps de seguridad abiertos

**H-01 — CERRADO en la fase 7B** (29-sep-2026). El mecanismo de autorización ya
no guarda el vacío: `GET /api/v1/catalogo` y `GET /api/v1/catalogo/{public_id}`
exigen `catalogo.read` mediante `require_permission()`, declarado en el **router**
y no endpoint por endpoint, de modo que un endpoint nuevo en ese archivo nace
protegido. Demostrado por sus contrarios, no solo por el caso feliz: usuario sin
ningún rol → 403; rol con otro permiso → 403; tenant A contra datos de B → 0 filas
y 404; sin contexto de tenant → 500, nunca `200 []`; JWT con `permissions`
inyectado y firma válida → 401.

⚠ **H-01 se reabre en cuanto alguien publique un endpoint de negocio sin su
`require_permission()`.** Lo que está cerrado es la ausencia de capa de
autorización, no la obligación de usarla en cada recurso nuevo.

**G-2 — `sacgeo_app` conserva INSERT y DELETE directos sobre `usuario_roles`.**
Un endpoint que escribiera la tabla a mano saltaría `fn_asignar_rol()` y la
comprobación de `usuarios.assign_role`. Se resuelve en la fase de administración
de usuarios/RBAC, no antes: retirar el GRANT ahora dejaría sin vía a la función
que lo necesita.

**G-4 — la API no tiene CORS, ni cabeceras de seguridad, ni límite de peticiones,
y `/docs` se publica sin condición.** Fase de hardening.

**H-02 — mass assignment. NO está cerrado globalmente.** Está cerrado, endpoint por
endpoint, solo donde se ha implementado y probado:

| Endpoint | Estado |
|---|---|
| `POST /api/v1/clientes/empresas` | ✅ cerrado (7I), 44 pruebas |
| `POST /api/v1/clientes/contactos` | ✅ cerrado (7I.1), 58 pruebas |
| Cualquier escritura futura | ⏳ **debe demostrarlo individualmente** |

Las barreras existen desde 7H.1 —`EntradaWrite`, `resolver_public_id()` y los DTO
tipados— pero tenerlas no cierra nada: **H-02 se cierra cuando un endpoint las usa y
sus pruebas lo demuestran.** Es la misma lección de H-01, que no se cerró al
implementar `require_permission()` sino al aplicarlo. Publicar una escritura sin
ellas reabre H-02 para ese recurso.

Y siguen abiertos de la auditoría pre-API: **H-08**
(sin límite de intentos en el login) y **H-12** (los PDF de `insumos/` versionados).

**H-11 — cerrado en la fase 6B.3.** La credencial histórica de desarrollo —la
contraseña funcional del rol `sacgeo_dev`— estaba versionada en `.env.example` y
`docker-compose.yml` de la raíz, y en el `.env.example` del backend. Se retiró de
los tres y del único commit local que la contenía, reescrito antes de publicarlo.
Hoy `docker-compose.yml` exige `POSTGRES_PASSWORD` sin valor por defecto y la
suite exige `PG_PASSWORD`: **ningún archivo versionado contiene una contraseña que
funcione**. La contraseña del clúster de desarrollo NO se cambió; sigue viva en
`.env`, que está ignorado. Rotarla es trabajo aparte y no bloquea nada.

Entitlements por plan (`docs/SAAS_ENTITLEMENTS.md`) quedan para después del primer
endpoint: no bloquean nada.

### Decisión de negocio todavía abierta

**M-07 — el descuento se aplica después del IGV.** Ver §5. Bloquea cualquier
trabajo sobre importes y sobre el PDF.

---

## 3. Mapa de la carpeta

```
CLAUDE.md                  ← este archivo
app/
  gtqc_sistema_unificado_v2.html   El mockup, última versión. NO SE MODIFICA
backend/                   API FastAPI. Fase 5-6. Ver backend/.env.example
  src/sacgeo/
    config.py              configuración por entorno; ningún secreto en el repo
    main.py                app + ciclo de vida (arranque fail-closed)
    db/pool.py             pool, DISCARD ALL, verificación del rol de conexión
    db/tx.py               PUNTO ÚNICO de transacción: set_config(..., true)
    api/deps.py            cadena JWT → sesión → transacción → identidad →
                           autorización (require_permission y variantes)
    api/v1/auth.py         /auth/login y /auth/yo. SIN prefijo /api/v1 (ver §5)
    api/v1/catalogo.py     GET /api/v1/catalogo, /{public_id} y
                           /{public_id}/componentes. Primer recurso de negocio.
                           El listado lee vw_catalogo_disponible; los componentes
                           leen las tablas, porque la vista pierde el public_id
                           del componente
    api/v1/categorias.py   GET /api/v1/categorias y /{public_id}, con las
                           subcategorías anidadas. Lee las TABLAS: no hay vista,
                           y vw_catalogo_disponible ocultaría las categorías vacías
    api/v1/acreditacion.py GET /api/v1/catalogo/{public_id}/acreditacion. Router
                           APARTE del de catálogo: exige acreditacion.read
    api/v1/clientes.py     6 GET: empresas, sus contactos y personas naturales.
                           clientes.read. Paginación y ordenación de lista blanca
    api/v1/clientes_escritura.py
                           POST /clientes/empresas (7I) y /clientes/contactos
                           (7I.1). Router APARTE: exige clientes.manage, NO
                           clientes.read
    api/v1/usuarios.py     GET /api/v1/usuarios y /{public_id}. usuarios.read.
                           Los roles salen de usuario_roles, no de rol_id
    api/v1/plantillas.py   GET /api/v1/plantillas y /{public_id}.
                           cotizaciones.read (ver §5). RLS híbrida: es_base
    api/query.py           SinParametros, Paginacion y `componer()`: las consultas
                           de ordenación se arman AL IMPORTAR, no por petición
    api/escritura.py       BARRERAS DE ESCRITURA: EntradaWrite y el punto ÚNICO
                           de traducción public_id → id, bajo RLS
    api/dto_negocio.py     DTO de escritura. Los tres que van delante de los
                           `jsonb`, más CrearEmpresa y CrearContacto
    security/              passwords (Argon2id), jwt, autenticacion, tenant
  tests/                   506 pruebas. Clúster APARTE, y PG_PASSWORD obligatoria:
                           sin valor por defecto
                           194 previas + 76 clientes + 68 usuarios/plantillas
                           + 25 SinParametros + 40 barreras + 44 empresas
                           + 58 contactos + 1 guarda de escritura
database/
  00_schema.sql            tablas, dominios, PK/FK/UNIQUE/CHECK
  01_functions.sql         contexto de sesión, correlativos, casos de uso, dashboard
  02_triggers.sql          autoría, auditoría, append-only, reglas del catálogo, estados
  03_indexes_views.sql     índices (uno por uno justificados) y 8 vistas
  04_seeds.sql             roles, usuario sistema, 4 categorías, 14 subcategorías, 3 plantillas
  05_seed_ensayos.sql      87 ensayos, 13 paquetes, 119 componentes (74 amarrados)
  97_aislamiento.sql       40 aserciones de aislamiento entre tenants
  98_pruebas.sql           71 pruebas funcionales
  99_verificacion.sql      37 controles de integridad
  full_dump.sql            línea base 0002. NO incluye 0003/0004/0005 (Opción C)
  migrations/
    0001_baseline_v2.sql            el esquema anterior, para reproducir el punto de partida
    0002_v2_a_v3.sql                migración real, preserva los datos
    0003_multitenant_habilitar.sql  ✅ aplicada — tenants, tenant_id, FK compuestas
    0004_rls_rol_aplicacion.sql     ✅ aplicada — RLS FORCE, sacgeo_app, sacgeo_auth
    0005_guarda_plantilla_y_sello_auditoria.sql  ✅ aplicada — corrige D-1 y D-2
    0006_auditoria_autor_no_falsificable.sql     ✅ aplicada — H-06, autor no falsificable
    0007_rbac_multirol.sql                       ✅ aplicada — RBAC multi-rol, H-15, H-13
docs/
  AUDITORIA_BD_v3.md       el informe completo: hallazgos, decisiones, verificación
  03_AMBIENTES.md          versiones verificadas del entorno (fase 3)
  AUDITORIA_SEGURIDAD_PRE_API.md  los 15 hallazgos previos a las APIs
  DISENO_RBAC_0007.md      RBAC multi-rol: 31 permisos y la matriz. ✅ 0007 APLICADA
  SEGURIDAD_RBAC.md        diseño previo de roles. ⚠ su §3.3 (un rol) está SUPERADO
  MODELO_AMENAZAS.md       amenazas y mitigaciones
  PLAN_PRUEBAS_SEGURIDAD.md
  FLUJO_APROBACION.md      aprobación interna de cotizaciones. NO implementado
  SAAS_ENTITLEMENTS.md     planes y límites. NO implementado
  ER_GTQC_v3.png/.pdf/.svg diagrama entidad-relación actualizado
  gen_er_v3.py             genera el SVG del diagrama
  render_er_v3.js          lo renderiza a PNG y PDF
  Guion_BD_GTQC.docx       guion para explicarle la BD al cliente
skills/
  multi-tenant/SKILL.md    clasificación GLOBAL/TENANT/HÍBRIDA y checklist de aislamiento
insumos/                   PDFs reales de presupuestos del laboratorio (material fuente)
_archivo/                  iteraciones anteriores. Material histórico, no se usa
_backups_sacgeo/           backups y logs de migración. IGNORADO POR GIT:
                           contiene password_hash y datos reales del laboratorio
```

---

## 4. Reglas de trabajo

### 4.1 La regla que más se rompe

**El SQL es la fuente de verdad, no la documentación.** Durante la auditoría v3 se encontró que el diagnóstico escrito describía tablas que no existían (`personas_naturales`, `auditoria_catalogo`, `sesiones`) y omitía una que sí (`cotizacion_historial_estados`). Antes de afirmar algo sobre la base, **leer el archivo SQL**.

### 4.2 No adelantarse de fase

No escribir API, endpoints, JWT, middleware ni frontend mientras la fase no esté abierta. Si una tarea parece necesitarlo, es señal de que falta cerrar algo de la fase anterior.

### 4.3 No aceptar una base porque "el SQL ejecutó sin errores"

Después de cualquier cambio en `database/`:

```bash
# Base desechable con el esquema COMPLETO. full_dump por sí solo ya no basta:
# es la línea base 0002 y no trae multi-tenant ni RLS.
docker exec CONT psql -U sacgeo_dev -d postgres -c 'CREATE DATABASE prueba'
for f in database/full_dump.sql \
         database/migrations/0003_multitenant_habilitar.sql \
         database/migrations/0004_rls_rol_aplicacion.sql \
         database/migrations/0005_guarda_plantilla_y_sello_auditoria.sql; do
  docker exec -i CONT psql -U sacgeo_dev -d prueba -v ON_ERROR_STOP=1 < "$f"
done

docker exec -i CONT psql -U sacgeo_dev -d prueba < database/98_pruebas.sql   # 71 PASS, 0 FAIL
docker exec -i CONT psql -U sacgeo_dev -d prueba < database/99_verificacion.sql # 35 de 37 en cero
```

Los dos controles que no dan cero son informativos y están explicados en `docs/AUDITORIA_BD_v3.md §9`. Cualquier otro que se encienda es un problema real.

**La suite 97 se certifica CON `sacgeo_app`, no con el dueño:**

```bash
docker exec -i -e PGPASSWORD=... CONT psql -U sacgeo_app -h localhost -d prueba \
  < database/97_aislamiento.sql      # 40 PASS, 0 FAIL, 0 SKIP
```

Ejecutarla como `sacgeo_dev` NO certifica nada: es dueño de las tablas y tiene
BYPASSRLS, así que las políticas no se le aplican. La propia suite lo detecta y
marca esas pruebas como SKIP. **Un SKIP es deuda declarada; un PASS falso es una
fuga que nadie va a volver a mirar.**

⚠ **`0004` solo puede aplicarse UNA VEZ POR CLÚSTER.** Su precondición exige que
`sacgeo_auth` no preexista, y los roles de PostgreSQL son del clúster, no de la
base: `DROP DATABASE` no se los lleva. Para una segunda base de prueba hay que
levantar otro contenedor.

Si se agrega una regla de negocio, se agrega su prueba en `98_pruebas.sql`. Si se agrega una forma nueva de que los datos queden inconsistentes, se agrega su control en `99_verificacion.sql`.

### 4.3 bis Un backup no está validado hasta que se restaura EN OTRO CLÚSTER

`pg_dump` NO vuelca los roles: son globales del clúster. Un dump de `sacgeo_dev`
restaurado en un clúster limpio **falla** en la primera política
(`role "sacgeo_app" does not exist`) y, con `--exit-on-error`, deja la base vacía.

Las validaciones de las fases 4B y 4D restauraron en el MISMO clúster, donde los roles
ya existían. Pasaron, y no probaban lo que decían probar. Corregido en 5B.

El respaldo completo son **dos archivos**:

```bash
docker exec CONT pg_dump    -U sacgeo_dev -d sacgeo_dev -Fc > base.dump
docker exec CONT pg_dumpall -U sacgeo_dev --globals-only --no-role-passwords > globals.sql
```

Y la restauración, en este orden: `globals.sql` primero, `pg_restore` después.
`--no-role-passwords` evita que el volcado lleve hashes de contraseña de los roles.

### 4.4 `full_dump.sql` se regenera, no se edita

```bash
cd database && cat 00_schema.sql 01_functions.sql 02_triggers.sql \
  03_indexes_views.sql 04_seeds.sql 05_seed_ensayos.sql >> full_dump.sql
```
(conservando la cabecera del archivo). Cualquier cambio va en el archivo numerado que corresponde.

### 4.5 Toda modificación del esquema es una migración

Nada de `ALTER TABLE` suelto. Archivo nuevo en `database/migrations/NNNN_descripcion.sql`, en una transacción, con su fila en `schema_migrations`, y con un paso previo que informe qué datos existentes no pasarían las restricciones nuevas y **aborte** si los hay.

### 4.6 Constraints con nombre propio, siempre

`CONSTRAINT uq_empresas_ruc UNIQUE (ruc)`, nunca `ruc VARCHAR UNIQUE`. Un constraint con nombre autogenerado no se puede sustituir de forma reproducible en una migración futura — esto bloqueó de hecho la migración multi-tenant hasta corregirlo.

### 4.7 Antes de crear una tabla nueva

Decidir y anotar si es **GLOBAL**, **TENANT-SCOPED** o **HÍBRIDA**, y dejarlo en su `COMMENT ON TABLE`. Después, pasar el checklist del skill `/multi-tenant`.

---

## 5. Decisiones tomadas (y por qué)

Estas ya están decididas. No volver a abrirlas sin una razón nueva.

**Tres tipos de identificador, separados.** `id` técnico (IDENTITY, interno, nunca sale a la API), `public_id` (UUID, es lo que viaja en URLs y en el QR del PDF), y código de negocio (`SU-01`, `COT-2026-001`, RUC, `slug` — dato del dominio, se muestra, no es clave de nada). Mezclarlos es lo que produce IDOR.

**Los correlativos los emite la BD, nunca el frontend.** Tabla `correlativos` + `fn_siguiente_correlativo()` sobre `INSERT … ON CONFLICT DO UPDATE`. Prohibido `MAX(...)+1`. Prohibido contar filas en el cliente. El número de cotización se consume **al emitir**, no al abrir el asistente. El código de ensayo **nunca** se reutiliza.

**Snapshot ≠ historial ≠ auditoría.** Son tres cosas distintas y no se mezclan:
- *Snapshot* — `cotizacion_items`: copia congelada de lo que se cotizó. No cambia nunca, aunque el catálogo cambie.
- *Historial* — `ensayo_acreditacion_historial`, `cotizacion_historial_estados`: hechos de negocio con fecha, append-only.
- *Auditoría* — `auditoria`: quién tocó qué fila y cómo estaba antes. Append-only, con purga controlada.

**Lo que tiene historia no se borra: se desactiva.** Una sola convención, `activo BOOLEAN`. Las cotizaciones no se eliminan, se cancelan. Los usuarios no se eliminan, se desactivan.

**El documento emitido se congela.** Borrador → se edita libre. Emitida → solo estado, notas y auditoría. Sus ítems dejan de ser tocables. El número no cambia jamás.

**La acreditación solo se cambia por `fn_cambiar_acreditacion()`.** Un `UPDATE` directo está bloqueado por trigger: el estado actual y el historial no pueden divergir, porque eso es lo que se le muestra a un auditor ISO 17025.

**Las fechas de negocio son `DATE` en hora de Lima**, vía `fn_hoy_lima()` y `cotizaciones.fecha_emision`. Nunca comparar `TIMESTAMPTZ` contra `DATE` directamente: el corte del día depende del *TimeZone* de la sesión.

**La pertenencia se declara con FK compuestas, no con disciplina.** `contactos` tiene `UNIQUE (empresa_id, id)` y `cotizaciones` referencia ese par. Así, que el contacto sea de esa empresa es imposible de violar, no una regla que alguien deba recordar. Este mismo patrón es el del aislamiento por tenant.

**El backend fija el contexto en cada transacción:**
```sql
SET LOCAL app.usuario_id = '<id>';
SET LOCAL app.ip_origen  = '<ip>';
-- y cuando llegue 0003:
SET LOCAL app.tenant_id  = '<id>';
```
Sin esto la auditoría culpa al usuario `sistema`.

**La BD no guarda secretos.** `integraciones.token_ref` es una referencia a un vault, nunca el token. `usuarios.password_hash` es solo un hash (Argon2id/bcrypt), nunca una contraseña.

**La atribución no se elige: se deriva del contexto.** Tres columnas lo aprendieron por
separado — `auditoria.usuario_id` (0006), `creado_por` vía `p_usuario` (0007, H-15) y
`usuario_roles.asignado_por` (0007). La regla general: **toda columna de autoría que el
que escribe pueda elegir es falsificable mientras el motor no la ate a
`fn_app_usuario()`**. Cualquier tabla nueva con una columna `*_por` debe llevar su guarda.

**RLS se habilita con `FORCE`, no solo con `ENABLE`.** Sin `FORCE`, el dueño de
la tabla ignora sus propias políticas: existirían en el catálogo, se verían en
`pg_policies`, y no protegerían nada. Es el modo de fallo más silencioso que
tiene RLS, porque no hay ninguna señal en tiempo de ejecución.

**La API NUNCA se conecta como `sacgeo_dev`.** Se conecta como `sacgeo_app`:
sin `SUPERUSER`, sin `BYPASSRLS`, sin poseer ninguna tabla, con GRANTs acotados
—sin `DELETE` sobre `usuarios`, sin nada sobre `schema_migrations`— y sin poder
ejecutar `fn_purgar_auditoria`.

**El arranque es fail-closed.** Con `REQUIRE_RLS_SAFE_ROLE=true` la API comprueba
antes de aceptar la primera petición que su rol no puede saltarse RLS —incluida
la herencia, vía `pg_has_role`, porque `pg_roles.rolsuper` solo mira el atributo
directo— y que se llama exactamente `ROL_APLICACION`. Si algo falla, **aborta**.
`DATABASE_URL` y `REQUIRE_RLS_SAFE_ROLE` se cambian en el MISMO despliegue.

**Login y sesión son la única excepción a RLS, y es acotada.** No es un problema
de orden sino de datos: el contexto de tenant no se puede fijar hasta saber el
tenant, y el tenant sale de la propia consulta. Lo resuelven dos funciones
`SECURITY DEFINER` propiedad de `sacgeo_auth` (NOLOGIN, sin `BYPASSRLS`), con
`search_path` fijo, sin SQL dinámico y con `EXECUTE` revocado a `PUBLIC`:
`fn_login_buscar(TEXT)` y `fn_sesion_resolver_usuario(UUID)`. La segunda devuelve
tres columnas y ninguna sensible. Todo lo demás se lee ya dentro de la
transacción, con el contexto puesto.

**La auditoría se sella con el tenant DE LA FILA auditada, no con el de la
sesión.** Un cambio sobre una entidad global (`roles`, `campos_sensibles`, una
plantilla base) produce `tenant_id` NULL, que es lo que significa: lo ven todos.
`b_auditoria_sello` impide lo contrario en las dos direcciones — que un rastro
tenant-scoped se marque como global, que sería a la vez una fuga y una forma de
sacarlo del historial que su dueño revisa.

**Una guarda que consulta otra tabla tiene que contar con RLS.** Lo aprendimos
con `fn_validar_plantilla_tenant`: comprobaba `IF v_tp IS NOT NULL AND v_tp <>
NEW.tenant_id`, y bajo RLS la fila ajena es invisible, así que `v_tp` salía NULL
y la guarda no disparaba. Se arregló preguntando primero **si la fila es
visible** —lo que la política ya contesta— y conservando después la comparación
de pertenencia, que es la que sirve para los roles no sujetos a RLS. Sin
`SECURITY DEFINER`, sin rol nuevo y sin privilegio nuevo.

**La atribución de autoría no la elige quien escribe.** `auditoria.usuario_id` debe
ser `fn_app_usuario()` — lo impone `b_auditoria_autor` (`0006`). El mismo criterio se
aplicará al parámetro `p_usuario` de las siete funciones de caso de uso que lo aceptan
(hallazgo H-15): hoy permiten escribir `creado_por` a nombre de otro.

**El multi-rol sustituye a los permisos implícitos del administrador.** `admin` NO
recibe `catalogo.manage`, `acreditacion.manage` ni ningún permiso de operación de
cotizaciones. Si un administrador necesita cotizar o gestionar acreditación, se le
añade el rol correspondiente — asignación visible y auditada, en vez de potestad
escondida dentro de la palabra «administrador». El efecto buscado es que
`if role == "admin"` **no funcione ni escribiéndolo**.

**La autorización se pregunta a PostgreSQL en cada petición** (fase 6B). Los guards
`require_permission()`, `require_any_permission()` y `require_all_permissions()` de
`api/deps.py` leen `fn_usuario_permisos()` dentro de la MISMA transacción que
`get_db_tx` ya contextualizó — de ahí sale el aislamiento entre laboratorios, que lo
impone RLS sobre `usuario_roles` y no el código de la API. Un permiso dentro del JWT
sería una foto del momento del login: retirar un rol no surtiría efecto hasta que el
token expirase. Sin caché entre peticiones, la revocación se nota en la siguiente.

**El primer recurso de negocio lee una VISTA, y sin ningún `WHERE tenant_id`.**
`/api/v1/catalogo` consulta `vw_catalogo_disponible`, que es `security_invoker` y
ya une ensayo → subcategoría → categoría por el par `(tenant_id, id)` filtrando
las tres por `activo`. El aislamiento lo impone el motor: contexto de sesión →
política `USING (tenant_id = fn_app_tenant())`. Añadir un filtro por tenant en
Python sugeriría que el aislamiento depende de esa línea, y **enmascararía un fallo
de contexto**: sin contexto, RLS lanza 42501 y la petición muere con 500, mientras
que un filtro con una variable vacía devolvería `200 []` — indistinguible de «este
laboratorio no tiene ensayos». Un recurso ajeno responde **404, nunca 403**: un 403
confirmaría que existe y convertiría el endpoint en un oráculo para enumerar el
catálogo de la competencia.

**El pool NO prepara sentencias** (`prepare_threshold = None`, hook `configure` de
`db/pool.py`). Defecto **D-3**, encontrado en la fase 7B y cerrado en la 7B.1:
psycopg3 prepara una consulta tras 5 ejecuciones sobre la misma conexión y guarda
su nombre en una caché *del cliente*; `DISCARD ALL` borra el statement *del
servidor* y no toca esa caché, así que la siguiente ejecución fallaba con
`SQLSTATE 26000`. La sentencia que primero alcanzaba el umbral era el `set_config`
de `tx.py` —dos o tres por petición—, de modo que reventaba en la **cuarta**
petición de cualquier endpoint autenticado. Estaba latente desde que existe el
pool. **No se quitó `DISCARD ALL`**: eso habría tapado el síntoma eliminando la red
que impide devolver una conexión con estado. No preparar cuesta cero aquí, porque
con `DISCARD ALL` un prepared statement no sobrevive a la petición que lo creó.

**Un permiso distinto exige un router distinto.** `/catalogo/{id}/acreditacion`
comparte prefijo con el catálogo pero exige **`acreditacion.read`**, no
`catalogo.read`, así que vive en `api/v1/acreditacion.py` con su propio
`APIRouter`. Colgar la ruta del router de catálogo —que declara `catalogo.read` a
nivel de router— le habría dado el permiso equivocado **en silencio**, y habría
bastado con poder ver precios para leer el historial ISO 17025. Dos tests
(`rbac_5` y `rbac_6`) fallan si eso vuelve a ocurrir, y para que puedan fallar hubo
que crear dos roles de prueba con UN permiso cada uno: los cinco roles del producto
llevan los dos, así que con ellos el error habría pasado inadvertido.

**El permiso se declara en el router, no endpoint por endpoint.** Así un endpoint
nuevo en ese archivo nace protegido: olvidarse de la dependencia deja de ser
posible, porque no hay nada que recordar.

**Un paquete NO es una entidad aparte: es un ensayo con `es_paquete = TRUE`.** Por
eso sus componentes son un subrecurso —`/catalogo/{public_id}/componentes`— y no un
`/paquetes` paralelo, que habría duplicado listado, paginación, filtros y contrato,
y creado dos sitios donde arreglar el mismo error. Un ensayo que existe pero **no**
es paquete responde **404**, no `componentes: []`: una lista vacía afirmaría dos
cosas falsas a la vez —que es un paquete y que está vacío— y confirmaría que el UUID
existe. Inexistente, ajeno, inactivo y no-paquete devuelven el MISMO 404.

**Un componente puede no tener ficha.** 45 de los 122 componentes reales son texto
libre (`ensayo_componente_id IS NULL`), y son el 37 %, no una excepción. En la API
salen con `public_id`, `codigo`, `precio_individual` y `activo` en **null** y
`vinculado: false`. `activo` va a null y no a `true`: la base no registra el estado
de un texto libre, y afirmarlo sería inventarlo. Y un componente puede venir de
**otra categoría** —regla P5, 8 casos reales—: eso es válido, el aislamiento es por
tenant, no por categoría.

**Un endpoint sin parámetros también declara que no los acepta.** `extra="forbid"`
solo actúa cuando hay un modelo Pydantic de query, así que un endpoint sin
parámetros ignoraba en silencio lo que le llegara: `?tenant_id=2` devolvía 200 y el
cliente podía creer que había consultado otro laboratorio mientras recibía el suyo.
`SinParametros` —modelo vacío con `extra="forbid"`, que no añade nada al esquema
OpenAPI— cierra esa puerta en `/catalogo/{public_id}/componentes`.

**La deuda de `SinParametros` se cerró en la fase 7F.** Eran **seis** endpoints, no
tres: los tres de detalle del catálogo, `/auth/yo` y los dos de `/salud`. Todos
declaran ya su contrato de query, y `test_ninguna_ruta_nueva_queda_sin_modelo_de_query`
compara el esquema OpenAPI contra tres categorías declaradas —colecciones con
filtros, escrituras y rutas sin parámetros—, así que **una ruta nueva sin contrato
falla en las pruebas y no en producción**.

**El cliente NUNCA controla un campo de seguridad, de identidad, de autoría, de
estado ni de importe.** La regla la impone `EntradaWrite` (`api/escritura.py`) y no
es una lista negra: los campos protegidos **no existen en el DTO**, así que
`extra="forbid"` los rechaza con 422 sin que nadie tenga que acordarse de filtrarlos.
Cuatro opciones, y cada una cierra algo distinto: `extra="forbid"` (un campo no
previsto no se ignora), `frozen=True` (nadie añade un atributo DESPUÉS de validar,
que convertiría la validación en una sugerencia), `str_strip_whitespace` (`"  "` pasa
a `""` y choca con los CHECK) y `strict=False` (un formulario HTML manda cadenas).

**La traducción `public_id → id` vive en UN solo punto**, `resolver_public_id()`, y
ocurre dentro de la transacción ya contextualizada. Es la barrera que
`extra="forbid"` no da: las funciones de caso de uso reciben ids **internos** y la
API recibe `public_id`, así que traducir sin pasar por RLS sería un IDOR con el DTO
perfecto. Lo que no es visible para la sesión no existe: **404**, el mismo que un
UUID inexistente. El nombre de la tabla nunca viene del cliente — el recurso es un
`Literal` que sirve de clave a un diccionario de consultas literales.

Hay **dos** sitios donde se traduce, y el segundo es legítimo: `autenticacion.py`
resuelve el `sub` del JWT con `fn_sesion_resolver_usuario()`, y **no puede pasar por
`escritura.py`** porque ocurre antes de que exista contexto de tenant — es lo que lo
establece. Un tercer sitio sí sería un problema, y un test lo vigila.

**Una escritura nombra en su INSERT solo las columnas de negocio.** `tenant_id`
(`DEFAULT fn_app_tenant()`), `creado_por` (`fn_tocar` con `fn_app_usuario()`),
`public_id`, `activo` y `creado_en` los pone el motor: no se nombran, así que no hay
nada que filtrar. Y si un bug los colara, la política `WITH CHECK (tenant_id =
fn_app_tenant())` rechazaría la fila — comprobado como `sacgeo_app`. La BD es la
última barrera, no la única.

**Un permiso distinto exige un router distinto, también para escribir.**
`clientes_escritura.py` comparte el prefijo `/clientes` con el de lectura pero exige
`clientes.manage`: compartir router le habría dado `clientes.read`, y **quien puede
consultar la cartera de clientes crearía empresas en ella**. Es el mismo patrón que
separó `acreditacion.py` de `catalogo.py`.

**Una referencia entre recursos viaja como `public_id`, nunca como id interno.**
`CrearContacto` declara `empresa_public_id`; aceptar `empresa_id` sería invitar a
recorrer enteros hasta dar con una empresa ajena. Y la pertenencia la respalda una
clave, no la disciplina: la FK de `contactos` es **compuesta**
`(tenant_id, empresa_id) → empresas (tenant_id, id)`, así que el par «mi tenant, su
empresa» no existe ni aunque alguien saltara el resolutor. Verificado contra el
motor.

### Decisión abierta, no técnica

**M-07 — el descuento se aplica después del IGV.** Se conservó el comportamiento del mockup, pero lo habitual en Perú es descontar sobre la base imponible. Es un cambio de una línea en `fn_recalcular_cotizacion()` que altera los importes de todo lo emitido: **lo decide contabilidad, no el desarrollo.**

---

## 6. Reglas del dominio (las exige la BD, no solo la app)

**Catálogo — R1 a R6**

- **R1** · Jerarquía estricta Categoría → Subcategoría → Ensayo. La categoría del ensayo sale de su subcategoría (FK compuesta).
- **R2** · Toda categoría activa tiene al menos una subcategoría activa. Al crear una categoría nace su "General".
- **R3** · Lo que tiene ensayos, cotizaciones o componentes no se borra: se desactiva.
- **R4** · `prefijo_codigo` arma el código (`SU-01`) y queda fijo en cuanto la categoría tiene ensayos.
- **R5** · Nombre de categoría único en todo el catálogo; de subcategoría, único dentro de su categoría (sin distinguir mayúsculas).
- **R6** · El número del código sale de `correlativos` y no se reutiliza nunca.

**Paquetes — P1 a P5**

- **P1** · Solo un ensayo con `es_paquete = TRUE` puede tener componentes.
- **P2** · Un componente vinculado es un ensayo individual. No se anidan paquetes.
- **P3** · El mismo ensayo no se repite dentro de un paquete: para eso está `cantidad`.
- **P4** · Un paquete creado desde la app lleva al menos **2 componentes vinculados al catálogo** (no vale texto libre).
- **P5** · Los componentes pueden venir de otra categoría (el paquete de cantera de Suelos incluye "Abrasión Los Ángeles" de Concreto).

**Cotización — máquina de estados**

```
borrador ──→ emitida ──→ aceptada
    │           ├──→ rechazada
    └───────────┴──→ cancelada
```
`aceptada`, `rechazada` y `cancelada` son terminales. Solo `borrador` admite ítems. El historial lo escribe la BD, no la aplicación.

---

## 7. Comandos que se usan seguido

```bash
# PostgreSQL vive en Docker, no en el sistema
docker start sac-geo-postgres-dev
docker exec sac-geo-postgres-dev psql -U sacgeo_dev -d sacgeo_dev -c '\dt'

# estado de la base de trabajo
docker exec sac-geo-postgres-dev psql -U sacgeo_dev -d sacgeo_dev -c \
  "SELECT version FROM schema_migrations ORDER BY version"

# backend (Windows: usar run.py, NO 'uvicorn' directo — fija la política de
# event loop antes de importar uvicorn, y psycopg async falla sin ella)
cd backend && ./.venv/Scripts/python.exe run.py

# pruebas del backend. PG_CONTENEDOR debe apuntar a un clúster DE VALIDACIÓN:
# el conftest crea y ELIMINA los roles sacgeo_app y sacgeo_auth, que en el
# clúster real son permanentes. Hay una guarda que lo impide, pero conviene
# saber por qué existe. POSTGRES_DB=postgres es obligatorio: sin él, Docker
# crea una base llamada sacgeo_dev y la guarda aborta la suite entera.
docker run -d --name sac-geo-postgres-val -e POSTGRES_USER=sacgeo_dev \
  -e POSTGRES_PASSWORD=<elegir> -e POSTGRES_DB=postgres -p 5433:5432 postgres:16

cd backend && PG_CONTENEDOR=sac-geo-postgres-val PG_PUERTO=5433 \
  PG_PASSWORD=<la misma> ./.venv/Scripts/python.exe -m pytest -q   # 506 en verde

# regenerar el diagrama ER
python3 docs/gen_er_v3.py && node docs/render_er_v3.js
```

---

## 8. Skills del proyecto

**`/multi-tenant`** (`skills/multi-tenant/SKILL.md`) — guía de arquitectura y seguridad del multi-tenant, YA IMPLEMENTADO (fases 4 y 7). Contiene la clasificación GLOBAL / TENANT-SCOPED de cada tabla, las reglas de aislamiento y un checklist obligatorio. **Se consulta antes de tocar cualquier tabla tenant-scoped, de crear una tabla nueva, de agregar una FK o de escribir un endpoint.**

Si más adelante hacen falta otros skills, los candidatos naturales son: uno de migraciones de BD (el procedimiento de §4.5, que ya se ha ejecutado tres veces con el mismo guion: precheck, backup validado por restauración, ejecución, certificación) y uno de generación del PDF de cotización.

---

## 9. Contexto del cliente

GTQC es un laboratorio real con presupuestos reales; los PDFs de `insumos/` son suyos. Dos cosas importan al hablar con ellos:

Los usuarios son **ingenieros civiles**, no informáticos. La app navega como su propia lista de precios en Excel: categoría → subcategoría → ensayo. Cualquier explicación de la base de datos se hace en esos términos, y para eso está `docs/Guion_BD_GTQC.docx` y el diagrama.

La **acreditación ISO 17025** no es un adorno: es lo que les permite cobrar más y lo primero que les revisa un auditor. Por eso el historial de acreditación es append-only y las cotizaciones guardan el estado de acreditación del día en que se emitieron.
