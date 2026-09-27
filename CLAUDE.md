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
| 3 · Evaluación de motor e infraestructura | ⏳ Pendiente. No decidir por intuición |
| 4 · Multi-tenant en la BD (migración 0003) | 📝 Escrita y probada, **no aplicada** |
| 5 · Backend / API | ⏳ Pendiente |
| 6 · Autenticación y autorización | ⏳ Pendiente |
| 7 · Multi-tenant de aplicación + RLS | ⏳ Pendiente |
| 8 · Frontend conectado al backend | ⏳ Pendiente |

**Cada fase se apoya en la anterior. No saltar etapas.**

---

## 3. Mapa de la carpeta

```
CLAUDE.md                  ← este archivo
app/
  gtqc_sistema_unificado_v2.html   El mockup, última versión. NO SE MODIFICA
database/
  00_schema.sql            tablas, dominios, PK/FK/UNIQUE/CHECK
  01_functions.sql         contexto de sesión, correlativos, casos de uso, dashboard
  02_triggers.sql          autoría, auditoría, append-only, reglas del catálogo, estados
  03_indexes_views.sql     índices (uno por uno justificados) y 8 vistas
  04_seeds.sql             roles, usuario sistema, 4 categorías, 14 subcategorías, 3 plantillas
  05_seed_ensayos.sql      87 ensayos, 13 paquetes, 119 componentes (74 amarrados)
  98_pruebas.sql           71 pruebas funcionales
  99_verificacion.sql      37 controles de integridad
  full_dump.sql            todo junto, reproducible de cero (se regenera, no se edita)
  migrations/
    0001_baseline_v2.sql            el esquema anterior, para reproducir el punto de partida
    0002_v2_a_v3.sql                migración real, preserva los datos
    0003_multitenant_habilitar.sql  ⚠ ESCRITA, NO APLICADA
docs/
  AUDITORIA_BD_v3.md       el informe completo: hallazgos, decisiones, verificación
  ER_GTQC_v3.png/.pdf/.svg diagrama entidad-relación actualizado
  gen_er_v3.py             genera el SVG del diagrama
  render_er_v3.js          lo renderiza a PNG y PDF
  Guion_BD_GTQC.docx       guion para explicarle la BD al cliente
skills/
  multi-tenant/SKILL.md    la guía de arquitectura para cuando se implemente multi-tenant
insumos/                   PDFs reales de presupuestos del laboratorio (material fuente)
_archivo/                  iteraciones anteriores. Material histórico, no se usa
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
createdb gtqc_test
psql -d gtqc_test -v ON_ERROR_STOP=1 -f database/full_dump.sql
psql -d gtqc_test -f database/98_pruebas.sql      # 71 en verde, 0 FAIL
psql -d gtqc_test -f database/99_verificacion.sql # 35 de 37 controles en cero
```

Los dos controles que no dan cero son informativos y están explicados en `docs/AUDITORIA_BD_v3.md §9`. Cualquier otro que se encienda es un problema real.

Si se agrega una regla de negocio, se agrega su prueba en `98_pruebas.sql`. Si se agrega una forma nueva de que los datos queden inconsistentes, se agrega su control en `99_verificacion.sql`.

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
# levantar PostgreSQL (entorno de trabajo)
sudo service postgresql start

# base limpia desde cero + verificación
createdb gtqc && psql -d gtqc -v ON_ERROR_STOP=1 -f database/full_dump.sql
psql -d gtqc -f database/98_pruebas.sql
psql -d gtqc -f database/99_verificacion.sql

# regenerar el diagrama ER
python3 docs/gen_er_v3.py && node docs/render_er_v3.js
```

---

## 8. Skills del proyecto

**`/multi-tenant`** (`skills/multi-tenant/SKILL.md`) — guía de arquitectura y seguridad para la fase multi-tenant. Contiene la clasificación GLOBAL / TENANT-SCOPED de cada tabla, las reglas de aislamiento y un checklist obligatorio. **Se consulta antes de tocar cualquier tabla tenant-scoped, de crear una tabla nueva, de agregar una FK o de escribir un endpoint.**

Si más adelante hacen falta otros skills, los candidatos naturales son: uno de migraciones de BD (el procedimiento de §4.5), y uno de generación del PDF de cotización.

---

## 9. Contexto del cliente

GTQC es un laboratorio real con presupuestos reales; los PDFs de `insumos/` son suyos. Dos cosas importan al hablar con ellos:

Los usuarios son **ingenieros civiles**, no informáticos. La app navega como su propia lista de precios en Excel: categoría → subcategoría → ensayo. Cualquier explicación de la base de datos se hace en esos términos, y para eso está `docs/Guion_BD_GTQC.docx` y el diagrama.

La **acreditación ISO 17025** no es un adorno: es lo que les permite cobrar más y lo primero que les revisa un auditor. Por eso el historial de acreditación es append-only y las cotizaciones guardan el estado de acreditación del día en que se emitieron.
