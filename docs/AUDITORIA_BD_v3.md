# Auditoría y reconstrucción de la base de datos GTQC
### De la v2 a la v3 · 27 de septiembre de 2026

Este documento es el informe de la fase de base de datos. No toca backend, API ni frontend: esa separación es deliberada y se explica al final, en **Pendientes**.

---

## 1. Estado anterior

La v2 era un esquema PostgreSQL de **17 tablas** repartidas en cinco áreas —clientes, catálogo, cotizaciones, nube y auditoría— con nueve funciones, once triggers y cinco vistas. Estaba bastante mejor de lo que suele estar un esquema a esta altura de un proyecto: ya separaba empresa, contacto y persona natural; ya guardaba un snapshot del ensayo en el ítem de cotización; ya tenía una tabla de historial de acreditación pensando en ISO 17025; y ya protegía el catálogo contra borrados que rompieran el historial.

Lo que no estaba resuelto era casi todo lo que aparece cuando el sistema deja de tener un solo usuario: la emisión de números correlativos, la atribución real de los cambios, la aritmética del documento, y la posibilidad de que dos laboratorios convivan en la misma base.

### 1.1 Lo que decía la documentación frente a lo que decía el SQL

Antes de auditar nada hay que saber qué es verdad. El diagnóstico previo que había en el proyecto describía una base que no coincidía con el archivo `base_datos_cotizador_v2.sql`. Las divergencias encontradas:

| La documentación decía | El SQL real decía |
|---|---|
| Tabla `personas_naturales` | La tabla se llama `personas` |
| Dos tablas `auditoria_catalogo` y `auditoria_cotizaciones` | Existe **una** tabla, `auditoria` |
| Tabla `documentos_cotizacion` | La tabla es `documentos_externos` y cuelga de `integraciones` |
| PK de texto (`cat_suelos`, `sub_suelos_paquetes`) | Las PK son `SERIAL`; el texto estable es la columna `slug` |
| `plantillas_cotizacion.items JSONB` con los ensayos de la plantilla | La tabla guarda validez y términos, no ítems |
| Tabla `sesiones` para control de acceso | No existe |
| `cotizaciones` tenía trigger de auditoría | No lo tenía: solo lo tenían 4 tablas del catálogo |
| (no mencionada) | Existe `cotizacion_historial_estados`, que alimenta la vista Historial |

**Lección que se lleva a `CLAUDE.md`:** el SQL es la fuente de verdad. Ningún informe sobre esta base vale si no se contrastó contra el archivo.

---

## 2. Problemas encontrados

Veintiocho hallazgos. La severidad mide el daño si el problema ocurre, no lo difícil que sea de arreglar.

### CRÍTICO — pérdida de datos, fuga entre clientes o documento legalmente inválido

| # | Hallazgo | Por qué es crítico |
|---|---|---|
| C-01 | El número de cotización lo generaba el frontend contando registros en `localStorage`. La BD solo tenía un `UNIQUE`. | Dos comerciales cotizando a la vez generan el mismo `COT-2026-014`. Uno de los dos recibe un error al guardar y pierde el trabajo; si el frontend no lo maneja, se emiten dos documentos con el mismo número. |
| C-02 | `fn_siguiente_codigo_ensayo()` calculaba `MAX(split_part(codigo,'-',2)) + 1`. | Además de la carrera entre usuarios, si se elimina el último ensayo el número **se reutiliza**: dos servicios distintos con el mismo código en la historia del laboratorio. |
| C-03 | `contacto_id` y `empresa_id` eran FK independientes. | Una cotización de la Empresa A podía referenciar al contacto de la Empresa B. Es el mismo defecto que, con varios laboratorios, se llama fuga de datos entre tenants. |
| C-04 | `estado` era `VARCHAR(20)` libre, sin máquina de estados, y el historial lo escribía la aplicación. | Una cotización rechazada podía volver a "emitida" con un `UPDATE`; el timeline que ve el usuario podía contradecir el estado real del documento. |
| C-05 | Ningún `CHECK` verificaba que `total = subtotal + IGV − descuento`, ni que el subtotal del ítem fuera `cantidad × precio`, ni que el subtotal de la cotización fuera la suma de sus ítems. | Un error de redondeo o un bug del frontend produce un PDF cuya suma no cuadra. Eso lo ve el cliente del laboratorio. |
| C-06 | Sin validación de formato: RUC, DNI, email, precios y cantidades admitían cualquier cosa, incluidos precios negativos. | Basta una importación de Excel o un script de soporte para llenar la cartera de clientes de basura. |
| C-07 | `ensayos_catalogo.acreditado` se podía cambiar con un `UPDATE` directo sin escribir en `ensayo_acreditacion_historial`. | El estado actual y el historial cuentan cosas distintas. Ante una auditoría INACAL/ISO 17025 no se puede probar desde cuándo un ensayo está acreditado, que es justamente para lo que existe esa tabla. |
| C-08 | La tabla `auditoria` admitía `UPDATE` y `DELETE`. | Una auditoría que se puede reescribir no es una auditoría. |
| C-09 | `fn_auditar_generico()` tomaba el usuario de la columna `actualizado_por` **de la propia fila**. Un `UPDATE` que no la fijara atribuía el cambio a `creado_por`. | La auditoría culpaba a la persona equivocada. Es peor que no tener auditoría, porque se le cree. |
| C-10 | `documentos_externos.integracion_id` era `NOT NULL` y toda integración exigía una empresa cliente. | El PDF generado localmente no se podía registrar, y una cotización de persona natural no podía tener documento. El flujo "PDF → documento en la nube" que pidió el cliente estaba roto en el modelo. |
| C-11 | `ruc`, `dni`, `codigo`, `numero`, `slug` y `prefijo_codigo` eran únicos **globales**. | Con dos laboratorios: el segundo no puede registrar a un cliente que el primero ya tiene, no puede tener su propio `SU-01`, y su primera cotización sería la `COT-2026-203`. |
| C-12 | Todos los identificadores eran `SERIAL` y serían los que viajaran en la URL. | `/cotizaciones/8` invita a probar `/cotizaciones/9`. Es el vector de IDOR/BOLA más común y el más barato de cerrar. |

### ALTO — el sistema miente, o pierde historia

| # | Hallazgo |
|---|---|
| A-01 | Solo 4 de 17 tablas tenían auditoría. Sin auditar: cotizaciones, ítems, clientes, contactos, usuarios, plantillas, integraciones y documentos. Un cambio de rol o de precio de una cotización no dejaba rastro. |
| A-02 | Las funciones del dashboard comparaban `creado_en` (`TIMESTAMPTZ`) contra un `DATE`. El corte del día dependía del *TimeZone* de la sesión: una cotización de las 20:00 en Lima caía al día siguiente con el servidor en UTC. El reporte por rango de fechas no cuadraba. |
| A-03 | Las vistas del dashboard hacían `INNER JOIN` contra `ensayos_catalogo` por `ensayo_id`, que es anulable. Cualquier ítem cuyo ensayo desapareciera dejaba de sumar: el dashboard reportaba **menos dinero del realmente cotizado**. |
| A-04 | Una cotización emitida se podía modificar entera: importes, cliente, proyecto, ítems. |
| A-05 | Una cotización se podía eliminar, y con ella se iban en cascada sus ítems y su historial de estados. |
| A-06 | `ensayo_acreditacion_historial` no tenía unicidad por ensayo y fecha. Dos filas el mismo día hacen ambigua la reconstrucción histórica. |
| A-07 | Dos convenciones de baja lógica conviviendo: `activo BOOLEAN` en el catálogo y `estado VARCHAR` en empresas. `contactos` y `personas` no tenían ninguna: un contacto obsoleto no se podía ocultar, y borrarlo estaba bloqueado por sus cotizaciones. |
| A-08 | No existía tabla de versiones de esquema. Imposible saber qué versión está desplegada en un servidor. |
| A-09 | Dos funciones de auditoría haciendo lo mismo (`fn_auditar_generico` y `fn_auditar_ensayos_catalogo`), con criterios distintos para el usuario. |
| A-10 | Ninguna tabla registraba **desde cuándo** algo está desactivado. Para un ensayo es una pregunta de auditoría ISO real. |
| A-11 | `contactos.empresa_id` tenía `ON DELETE CASCADE`: borrar una empresa se llevaba en silencio a sus contactos y con ellos la trazabilidad de quién pidió qué. |
| A-12 | El ítem de cotización no tenía orden explícito (dependía del `id`) ni congelaba la categoría del ensayo, que es lo que rompía A-03. |

### MEDIO — costo, corrección incompleta o deuda que crece

| # | Hallazgo |
|---|---|
| M-01 | Índices redundantes: `idx_empresas_ruc`, `idx_personas_dni` e `idx_ensayos_codigo` duplicaban el índice que ya crea su `UNIQUE`; `idx_ensayos_acreditado` indexaba un booleano de dos valores que el planificador nunca usa. Solo encarecían cada escritura. |
| M-02 | Varias FK de navegación sin índice: PostgreSQL no las indexa solo, y sin índice cada verificación recorre la tabla hija. |
| M-03 | `fn_definir_componentes()` exigía 2 componentes, pero admitía que los dos fueran texto libre: un "paquete" sin ningún ensayo real, sin precio individual con el que comparar. |
| M-04 | Nada comprobaba que el precio del paquete fuera menor que la suma de sus partes. Un paquete más caro que sus componentes es un paquete sin sentido comercial. |
| M-05 | `roles.nombre` hacía de código técnico (`'admin'`) y de etiqueta de interfaz a la vez. Renombrar el rol en pantalla rompía el código. |
| M-06 | `usuarios` no tenía campos de actualización ni nada preparado para autenticación; el modelo obligaba a migrar la tabla el día del login. |
| M-07 | **Hallazgo fiscal.** El descuento se aplica *después* del IGV (`total = subtotal + IGV − descuento`), de modo que el IGV se calcula sobre la base sin descontar. Lo habitual en Perú es descontar sobre la base imponible y calcular el IGV después. **Se conservó el comportamiento actual** para no alterar los importes existentes, y queda explícito en `fn_recalcular_cotizacion()`. Es una decisión de negocio, no técnica: debe confirmarla contabilidad. |
| M-08 | El código de ensayo se formateaba con `lpad(...,2)` y se validaba con `[0-9]{2,3}`: a partir del ensayo 1000 de una categoría el código dejaba de validar. |

### BAJO

| # | Hallazgo |
|---|---|
| B-01 | `auditoria.ip_origen` existía y nunca se llenaba. |
| B-02 | Sin `COMMENT ON`: el ámbito y el propósito de cada tabla vivían solo en comentarios de un archivo. |
| B-03 | Constraints con nombre autogenerado (`empresas_ruc_key`), imposibles de sustituir de forma reproducible en una migración futura. Esto bloqueó de hecho la migración multi-tenant hasta corregirlo. |
| B-04 | La documentación describía tablas inexistentes (sección 1.1). |

---

## 3. Correcciones

Los 28 hallazgos están corregidos, salvo M-07, que es una decisión de negocio y se deja documentada en vez de cambiarla por cuenta propia.

Lo que cambió, agrupado por idea:

**La base es ahora la primera línea de defensa, no un almacén.** Los estados, unidades, monedas y proveedores dejaron de ser texto libre y pasaron a `DOMAIN` con `CHECK`. El RUC valida el formato peruano real (11 dígitos empezando en 10/15/16/17/20), el DNI ocho dígitos, el email un formato razonable, y el dinero no puede ser negativo. La aritmética del documento —IGV según su propia tasa, total según subtotal y descuento, subtotal del ítem según cantidad y precio— es un `CHECK`, no una promesa de la aplicación.

**Los tres tipos de identificador se separaron.** El `id` técnico es interno y nunca sale a la API. El `public_id` (UUID) es lo que viaja en la URL y en el QR del PDF. El código de negocio (`SU-01`, `COT-2026-001`, el RUC, el `slug`) es dato del dominio, se muestra al usuario y no es clave de nada. Los tres existían mezclados; ahora cada uno hace un solo trabajo.

**Los correlativos salieron del frontend.** Una tabla `correlativos` y una función `fn_siguiente_correlativo()` construida sobre `INSERT … ON CONFLICT DO UPDATE`, que es atómica: si dos transacciones piden el mismo contador, la segunda espera y recibe el siguiente valor. Sin `MAX()`, sin ventana de carrera, y sin huecos —el número queda reservado dentro de la misma transacción que lo usa, y si esa transacción falla el contador vuelve atrás. El número de cotización se consume **al emitir**, no al abrir el asistente, para que un borrador abandonado no deje un hueco en la serie oficial. El código de ensayo ya no se reutiliza jamás: si se elimina `SU-29`, el siguiente ensayo es `SU-30`.

**El documento emitido se congeló.** Una cotización en borrador se edita libremente; una vez emitida, solo pueden moverse su estado, sus notas internas y los campos de auditoría. Sus ítems dejan de ser tocables. No se puede eliminar: se cancela. El número, una vez emitido, no cambia nunca.

**La historia dejó de poder reescribirse.** `auditoria`, `ensayo_acreditacion_historial` y `cotizacion_historial_estados` son append-only por trigger. La auditoría admite una purga de registros de más de un año, pero solo por la función `fn_purgar_auditoria()`, que deja su propia constancia de qué rango se purgó y quién lo pidió.

**La acreditación y su historia no pueden divergir.** Cambiar `acreditado` con un `UPDATE` directo ahora está bloqueado; hay que pasar por `fn_cambiar_acreditacion()`, que mueve el estado y escribe la fila de historial en la misma transacción. `fn_acreditado_en_fecha(ensayo, fecha)` responde la pregunta que hace un auditor: *¿estaba este ensayo acreditado cuando se emitió este informe?*

**El dashboard dejó de perder dinero.** El ítem congela también su categoría y subcategoría, y las vistas agrupan por esa categoría congelada en lugar de hacer `INNER JOIN` contra el catálogo vivo. Y las fechas de negocio salen de `fecha_emision`, un `DATE` calculado en hora de Lima, no de una comparación entre `TIMESTAMPTZ` y `DATE` que dependía del *TimeZone* del servidor.

**La pertenencia se volvió estructural.** `contactos` declara `UNIQUE (empresa_id, id)` y `cotizaciones` referencia ese par: que el contacto sea de esa empresa ya no es una regla que el backend deba recordar, es una imposibilidad en el motor. Lo mismo entre ensayo, subcategoría y categoría. Este patrón es exactamente el que usará el aislamiento por tenant, y por eso la migración 0003 es mecánica.

---

## 4. Estrategia de identificadores

| Concepto | Qué es | Dónde vive | Quién lo ve |
|---|---|---|---|
| **ID técnico** | `INTEGER`/`BIGINT` `GENERATED BY DEFAULT AS IDENTITY` | PK de todas las tablas | Nadie fuera de la BD |
| **ID público** | `UUID` (`public_id`), único | Entidades que la API expondrá | URLs, QR del PDF, enlaces compartidos |
| **Código de negocio** | Texto con significado: `SU-01`, `COT-2026-001`, RUC, DNI, `slug` | Columna propia con `UNIQUE` | El usuario, el PDF, el cliente final |

`SERIAL` se reemplazó por `IDENTITY` —el estándar SQL, con la secuencia atada a la columna en vez de suelta como objeto aparte— **conservando todos los números existentes**: la migración solo reposiciona el contador.

`public_id` se agregó a las once entidades que una API expondría (usuarios, empresas, contactos, personas, categorías, subcategorías, ensayos, plantillas, cotizaciones, integraciones, documentos). **No** se agregó a tablas hijas como `cotizacion_items`, `paquete_componentes`, los historiales o `auditoria`: solo son alcanzables a través de su padre, y un UUID por fila ahí sería peso sin uso.

---

## 5. Correlativos

```
correlativos(ambito, clave, periodo) → ultimo
```

| Serie | ambito | clave | periodo | Resultado |
|---|---|---|---|---|
| Cotizaciones | `cotizacion` | `GLOBAL` | año (`2026`) | `COT-2026-001` |
| Códigos de ensayo | `ensayo` | prefijo (`SU`) | `-` | `SU-29` |

La serie de cotizaciones se reinicia cada año porque el periodo es parte de la clave. Los códigos de ensayo no se reinician nunca.

**Verificado bajo concurrencia real:** ocho sesiones simultáneas emitiendo 25 cotizaciones cada una → 200 cotizaciones, **0 números duplicados y 0 huecos en la serie**.

El día que entre el multi-tenant, `tenant_id` entra en la PK del contador y cada laboratorio tiene su propio `COT-2026-001`. La columna `clave` ya se diseñó como texto libre para que ese cambio no obligue a rediseñar nada.

---

## 6. Auditoría

Una sola tabla, `auditoria`, alimentada por un solo trigger genérico presente ahora en **las 14 tablas de negocio**. Cada fila responde: qué tabla, qué registro (por id técnico *y* por id público), qué operación, **qué campos exactamente cambiaron**, cómo estaba antes, cómo quedó, quién lo hizo, desde qué IP y cuándo.

El usuario sale de `fn_app_usuario()`, que lee `app.usuario_id` del contexto de la sesión. El backend debe abrir cada transacción con:

```sql
SET LOCAL app.usuario_id = '7';
SET LOCAL app.ip_origen  = '190.12.x.x';
```

Si no lo fija, el cambio queda a nombre del usuario 1 (`sistema`). Eso **no** es una puerta trasera: es un valor identificable, y una fila de auditoría con `usuario_id = 1` y una acción de negocio significa "el backend no fijó el contexto", que es un bug a corregir. El control `I2` de `99_verificacion.sql` lo cuenta explícitamente.

Un `UPDATE` que solo movió `actualizado_en`/`actualizado_por` no genera fila: el ruido también es un problema de auditoría.

---

## 7. Multi-tenant

### 7.1 Clasificación tabla por tabla

| Tabla | Ámbito | Por qué |
|---|---|---|
| `schema_migrations` | **GLOBAL** | Versión del esquema de la instalación, no de un cliente |
| `tenants` (futura) | **GLOBAL** | Es el registro de los propios tenants |
| `roles` | **GLOBAL** | Los 4 roles son del producto. Si un laboratorio necesitara roles propios, se agrega `roles_tenant`, no se duplican los básicos por cada cliente |
| `usuarios` | **TENANT-SCOPED** (`NULL` = global) | Cada laboratorio tiene su gente. Excepción: el usuario `sistema` (id 1) es global, porque es el autor de los seeds y el fallback de auditoría de todos |
| `plantillas_cotizacion` | **HÍBRIDA** | `tenant_id NULL` = las 3 plantillas base del producto, visibles para todos; `tenant_id = N` = las que cree ese laboratorio |
| `empresas`, `contactos`, `personas` | **TENANT-SCOPED** | La cartera de clientes es el activo del laboratorio. Dos laboratorios pueden tener al mismo cliente y no deben saberlo |
| `categorias_ensayo`, `subcategorias_ensayo`, `ensayos_catalogo` | **TENANT-SCOPED** | Cada laboratorio define su catálogo y su tarifa. Son su lista de precios |
| `ensayo_acreditacion_historial` | **TENANT-SCOPED** | La acreditación es del alcance de ese laboratorio |
| `paquete_componentes` | **TENANT-SCOPED** | Cuelga del catálogo |
| `correlativos` | **TENANT-SCOPED** | Cada laboratorio numera su propia serie desde 001 |
| `cotizaciones`, `cotizacion_items`, `cotizacion_historial_estados` | **TENANT-SCOPED** | Es el documento comercial. El dato más sensible del sistema |
| `integraciones`, `documentos_externos` | **TENANT-SCOPED** | Credenciales y archivos de ese laboratorio y de sus clientes |
| `auditoria` | **TENANT-SCOPED** | El rastro de un laboratorio no se muestra a otro |

Las tablas hijas (`cotizacion_items`, `paquete_componentes`, los historiales) llevan `tenant_id` **aunque solo sean alcanzables por su padre**. Razón: sin la columna, la política RLS de la hija tendría que consultar al padre en cada fila leída, y un `JOIN` mal escrito en un reporte se salta el aislamiento. Con la columna y la FK compuesta, es imposible que una hija pertenezca a otro tenant que su padre.

### 7.2 Qué queda preparado y qué no se hizo

**Preparado en la v3, ya aplicado:**

Todos los `UNIQUE` que deberán cambiar de ámbito tienen nombre propio (`uq_empresas_ruc`, `uq_ensayos_codigo`, …), lo que hace que sustituirlos sea una línea y no una arqueología de nombres autogenerados. El patrón de FK compuesta ya está en uso y probado con `(empresa_id, contacto_id)` y `(categoria_id, subcategoria_id)`. La tabla `correlativos` ya tiene la forma que admite el tenant en la PK. Y el contexto de sesión (`app.usuario_id`, `app.ip_origen`) ya existe, así que agregar `app.tenant_id` es un tercer valor, no un mecanismo nuevo.

**Escrito pero deliberadamente NO aplicado:** `migrations/0003_multitenant_habilitar.sql`.

Agrega la tabla `tenants`, la columna `tenant_id` donde corresponde, cambia todos los `UNIQUE` a su ámbito por tenant, convierte las FK en compuestas `(tenant_id, …)`, reordena los índices para que el tenant vaya al frente, y hace que `fn_app_tenant()` **falle** si no hay tenant en el contexto (al contrario de `fn_app_usuario()`, que tiene fallback: un cambio sin autor es un bug molesto, una consulta sin tenant es una fuga).

Esa migración está **verificada de extremo a extremo sobre una copia desechable**: se aplica sin error, los datos existentes quedan en el tenant 1, y con dos laboratorios cargados se comprobó que

- el mismo RUC, el mismo prefijo `SU` y el mismo código `SU-01` conviven en ambos;
- el laboratorio 2 arranca su serie en `COT-2026-001` mientras el 1 va por la 202;
- una cotización del tenant 2 que apunte a una empresa del tenant 1 es **rechazada por la FK compuesta**;
- una cotización del tenant 2 con un contacto del tenant 1 es **rechazada**;
- una consulta sin `app.tenant_id` es **rechazada**.

**No se hizo, y es correcto que no se haya hecho:** RLS (queda escrito como bloque no ejecutable al final de 0003, con la advertencia de que activarlo sin un backend que fije `app.tenant_id` deja la aplicación ciega), autenticación, autorización por rol, resolución del tenant desde la sesión, y aislamiento en caché, colas, logs y almacenamiento de archivos. La base es la última línea de defensa, no la única.

---

## 8. Datos

**Ninguna fila se perdió.** La migración probada sobre una base v2 real con catálogo y cotizaciones cargadas:

| | Antes (v2) | Después (v3) |
|---|---|---|
| Ensayos | 87 | 87 |
| Paquetes | 13 | 13 |
| Componentes de paquete (amarrados) | 119 (74) | 119 (74) |
| Cotizaciones / ítems | 2 / 3 | 2 / 3 |
| Empresas / contactos / personas | 1 / 1 / 1 | 1 / 1 / 1 |
| Documentos | 1 | 1 |

Dos datos se **reconstruyeron**, y conviene que quede dicho con claridad porque son derivados, no históricos verificados:

La **categoría y subcategoría congeladas** de los ítems de v2 se tomaron del catálogo actual, porque es la única fuente que existe. De aquí en adelante se congelan al emitir.

La **composición de los paquetes ya cotizados** que v2 guardó sin `componentes_snapshot` se reconstruyó desde la composición actual del paquete y **cada componente reconstruido lleva la marca `"reconstruido": true`** en el JSON, para que nadie lo confunda con un dato original. Si un paquete no tenía componentes registrados, el ítem se pasó a ensayo simple: es preferible un ítem honesto a un paquete que declara incluir nada.

La migración **se detiene antes de tocar nada** si los datos existentes no cumplen el modelo nuevo. El paso 0 informa exactamente qué filas fallan (RUC mal formado, importes que no cuadran, contacto ajeno a su empresa, …) y aborta. Primero se corrigen los datos, después se migra. Todo va en una transacción: si cualquier paso falla, la base queda como estaba.

---

## 9. Verificación

No se aceptó la base porque el SQL ejecutara sin errores.

**`99_verificacion.sql`** — 37 controles de integridad sobre los datos, agrupados en duplicados, huérfanos, aritmética, snapshots, acreditación, correlativos, catálogo y paquetes, máquina de estados, cobertura de auditoría y seguridad. Resultado en las tres bases probadas (v3 limpia, v3 migrada desde v2, y v3 con 0003 aplicada): **35 de 37 en cero**.

Los dos que no están en cero son informativos y correctos:

`G7` — 45 de los 119 componentes de paquete siguen siendo descriptivos (texto libre, sin ensayo equivalente vendible en el catálogo). Es una decisión del laboratorio pendiente, no un defecto.

`I2` — todas las filas de auditoría están a nombre del usuario `sistema`, porque las escribió la carga inicial. En cuanto haya backend con contexto, este número debe tender a cero; si no lo hace, hay un bug.

**`98_pruebas.sql`** — 71 pruebas funcionales sobre datos reales, **71 en verde**: emisión de cotizaciones, aritmética, congelado del documento emitido, máquina de estados, aislamiento empresa/contacto, acreditación con reconstrucción histórica, protección de borrados, no reutilización de códigos, reglas P1–P5 de paquetes, atribución correcta de la auditoría, reglas R2–R5 del catálogo, dashboard por periodo y registro de documentos locales y en nube.

**Concurrencia** — 8 sesiones en paralelo, 200 cotizaciones, 0 duplicados, 0 huecos.

---

## 10. Dónde está cada cosa

```
database/
  00_schema.sql            tablas, dominios, PK/FK/UNIQUE/CHECK
  01_functions.sql         contexto de sesión, correlativos, casos de uso, dashboard
  02_triggers.sql          autoría, auditoría, append-only, reglas R/P, estados
  03_indexes_views.sql     índices justificados uno por uno + 8 vistas
  04_seeds.sql             roles, usuario sistema, 4 categorías, 14 subcategorías, 3 plantillas
  05_seed_ensayos.sql      87 ensayos, 13 paquetes, 119 componentes (74 amarrados)
  98_pruebas.sql           71 pruebas funcionales
  99_verificacion.sql      37 controles de integridad
  full_dump.sql            todo lo anterior en un archivo, reproducible de cero
  migrations/
    0001_baseline_v2.sql            el punto de partida, para reproducirlo
    0002_v2_a_v3.sql                la migración real, preservando datos
    0003_multitenant_habilitar.sql  ESCRITA, NO APLICADA
docs/
  AUDITORIA_BD_v3.md   este documento
  ER_GTQC_v3.png/.pdf/.svg   diagrama actualizado
  gen_er_v3.py / render_er_v3.js  cómo se regenera el diagrama
```

Instalación desde cero:

```bash
createdb gtqc
psql -d gtqc -v ON_ERROR_STOP=1 -f database/full_dump.sql
psql -d gtqc -f database/99_verificacion.sql    # y leer el informe
```

Migración de una base v2 existente:

```bash
psql -d gtqc -v ON_ERROR_STOP=1 -f database/migrations/0002_v2_a_v3.sql
psql -d gtqc -f database/01_functions.sql
psql -d gtqc -f database/02_triggers.sql
psql -d gtqc -f database/03_indexes_views.sql
psql -d gtqc -c "SELECT fn_sincronizar_correlativos_ensayo();"
psql -d gtqc -f database/99_verificacion.sql
```

---

## 11. Diagrama

`docs/ER_GTQC_v3.png` (y `.pdf` para imprimir, `.svg` para editar). Muestra las 18 tablas en sus cinco áreas, y cada una lleva un badge que dice si será **G**lobal, **T**enant-scoped o **H**íbrida. Los iconos distinguen id técnico, id público y código de negocio; 📌 marca los snapshots y 🔒 las tablas append-only.

Se regenera con `python3 docs/gen_er_v3.py && node docs/render_er_v3.js`.

---

## 12. Pendientes

**BASE DE DATOS — terminada.** Modelo revisado, relaciones coherentes, identificadores definidos y separados de los códigos, correlativos seguros bajo concurrencia, FK y constraints auditados, índices justificados, auditoría completa, snapshots e históricos protegidos, datos preservados, estructura preparada para multi-tenant, documentación actualizada, exportación reproducible, diagrama al día.

**MOTOR DE BD — pendiente de decisión.** No se cambió de motor ni se evaluó la infraestructura, como correspondía a esta fase. La evaluación (PostgreSQL vs. alternativas sobre 2 vCore / 4 GB / 60 GB NVMe, considerando concurrencia, multi-tenant, RLS, respaldos y costo de administración) es una fase propia, y ahora tiene algo concreto que evaluar: un modelo que usa dominios, índices parciales, `JSONB`, FK compuestas y RLS futura. Conviene saber que ese conjunto pesa fuerte a favor de PostgreSQL, pero la decisión es una fase aparte.

**MULTI-TENANT DE APLICACIÓN — pendiente.** La estructura está lista y probada; falta aplicarla (0003) cuando existan las precondiciones, activar RLS y resolver el aislamiento fuera de la base: caché, colas, logs y almacenamiento de archivos.

**BACKEND / API — pendiente.** Debe fijar `app.usuario_id`, `app.ip_origen` y (cuando llegue 0003) `app.tenant_id` en cada transacción, y llamar a las funciones de caso de uso en vez de escribir tablas directamente.

**AUTENTICACIÓN Y AUTORIZACIÓN — pendiente.** El modelo está listo (`usuarios.password_hash`, `roles`, `es_sistema`), no hay una línea implementada, y así debía ser en esta fase.

**FRONTEND — sin tocar.** El mockup queda en la última versión funcional, sin ningún cambio de diseño.

---

## 13. Lo que hay que mirar antes de la siguiente fase

Tres cosas quedan sobre la mesa y no son técnicas:

**M-07, el descuento y el IGV.** Confirmar con contabilidad si el descuento va antes o después de la base imponible. Es un cambio de una línea en `fn_recalcular_cotizacion()`, pero altera los importes de todo lo emitido, así que debe decidirlo quien firma.

**Los 45 componentes sin amarrar.** El laboratorio tiene que decidir cuáles se convierten en ensayos vendibles del catálogo y cuáles se quedan como texto descriptivo. Mientras no se decida, esos paquetes no pueden mostrar su ahorro real.

**El usuario `sistema`.** Todo lo que hay hoy en la auditoría está a su nombre porque lo escribió la carga inicial. En cuanto haya login, ese número debe dejar de crecer.
