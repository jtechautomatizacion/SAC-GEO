---
name: multi-tenant
description: Guía de arquitectura y seguridad multi-tenant para el sistema GTQC. Úsala antes de crear o modificar una tabla, una FK, una migración o un endpoint, y antes de aplicar la migración 0003 o activar RLS.
---

# Multi-tenant — GTQC

Esta guía **no implementa** el multi-tenant. Recoge las decisiones tomadas durante la
auditoría de la base de datos (v3, sep-2026) para que la implementación, cuando llegue,
no las contradiga.

**El aislamiento entre clientes no se agrega al final. Se diseña una vez y se respeta
en cada tabla, cada FK y cada endpoint que se escriba después.**

---

## Las cuatro reglas que no se negocian

> **1. NUNCA confiar en el `tenant_id` que envía el frontend.**
> Ni en un parámetro, ni en un header, ni en el body, ni en un campo oculto del formulario.
> El tenant se resuelve **desde la sesión autenticada en el servidor** y de ningún otro lugar.
> Un `tenant_id` que llega del cliente es una petición de acceso, no un dato.

> **2. Antes de crear una tabla, decidir si es GLOBAL o TENANT-SCOPED.**
> Se anota en su `COMMENT ON TABLE` y en este archivo. Una tabla sin esa decisión tomada
> no se crea.

> **3. Toda relación entre entidades tenant-scoped debe garantizar el mismo tenant.**
> No con disciplina del backend: con **FK compuesta**. La tabla padre declara
> `UNIQUE (tenant_id, id)` y la hija referencia ese par. Entonces el cruce de tenants deja
> de ser una regla que alguien debe recordar y pasa a ser imposible en el motor.

> **4. No modificar una tabla tenant-scoped sin revisar, en este orden:**
> `tenant_id` → constraints → índices → auditoría → futura política RLS.
> Saltarse uno de los cinco es como se abre una fuga.

---

## 1. Arquitectura elegida

**Una base, un esquema, `tenant_id` por fila.** No base por cliente, no esquema por cliente.

Por qué: el laboratorio es un negocio de decenas de cotizaciones al día, no de millones.
Una base por cliente multiplica migraciones, respaldos y conexiones por cada cliente nuevo;
un esquema por cliente rompe las consultas agregadas y complica el *pooling*. La fila con
`tenant_id` más FK compuestas más RLS da el mismo aislamiento efectivo con una fracción del
costo operativo — siempre que las cuatro reglas de arriba se cumplan.

**Defensa en capas.** La base es la **última** línea, no la única:

| Capa | Qué aísla |
|---|---|
| Autenticación | quién es el usuario |
| Autorización (rol) | qué puede hacer |
| Resolución de tenant | a qué laboratorio pertenece — **desde la sesión** |
| Consulta de la aplicación | filtra por tenant explícitamente |
| RLS de PostgreSQL | red de seguridad si la consulta se olvidó |
| FK compuestas | hacen el cruce imposible aunque todo lo anterior falle |

---

## 2. Tablas GLOBALES (sin `tenant_id`)

| Tabla | Por qué |
|---|---|
| `schema_migrations` | versión del esquema de la instalación |
| `tenants` | es el registro de los propios tenants |
| `roles` | los 4 roles son del producto. Si un laboratorio necesitara roles propios se agrega `roles_tenant`; **no** se duplican los básicos por cada cliente |

## 3. Tablas TENANT-SCOPED (llevan `tenant_id`)

`usuarios`* · `empresas` · `contactos` · `personas` · `categorias_ensayo` ·
`subcategorias_ensayo` · `ensayos_catalogo` · `ensayo_acreditacion_historial` ·
`paquete_componentes` · `correlativos` · `cotizaciones` · `cotizacion_items` ·
`cotizacion_historial_estados` · `integraciones` · `documentos_externos` · `auditoria`

\* `usuarios` admite `tenant_id NULL` para un único caso: el usuario `sistema` (id 1),
autor de los seeds y *fallback* de auditoría de todos los tenants.

**Las tablas hijas llevan `tenant_id` aunque solo sean alcanzables por su padre.**
Sin la columna, la política RLS de la hija tendría que consultar al padre en cada fila leída,
y un `JOIN` mal escrito en un reporte se salta el aislamiento. Con la columna y la FK
compuesta, una hija de otro tenant que su padre es imposible.

## 4. Tabla HÍBRIDA

`plantillas_cotizacion` — `tenant_id NULL` = las 3 plantillas base del producto, visibles
para todos; `tenant_id = N` = las que cree ese laboratorio. Su política RLS es distinta:
se **leen** las base y las propias, se **escriben** solo las propias.

---

## 5. Estrategia de identificadores

| Concepto | Tipo | Dónde se usa |
|---|---|---|
| ID técnico | `IDENTITY` (int/bigint) | PK. **Nunca sale a la API** |
| ID público | `UUID` (`public_id`) | URLs, QR del PDF, enlaces compartidos |
| Código de negocio | texto (`SU-01`, `COT-2026-001`, RUC, `slug`) | lo ve el usuario. No es clave de nada |

Un `id` secuencial en una URL (`/cotizaciones/8`) invita a probar el 9. Por eso la API
expone `public_id`. **Y aun así:** exponer un UUID no autoriza nada. Toda consulta por
`public_id` lleva igualmente `AND tenant_id = <el de la sesión>`. Un identificador difícil
de adivinar no es un control de acceso.

`public_id` va en las entidades que la API expone (usuarios, empresas, contactos, personas,
categorías, subcategorías, ensayos, plantillas, cotizaciones, integraciones, documentos).
No va en tablas hijas alcanzables solo por su padre.

---

## 6. Correlativos

```
correlativos(tenant_id, ambito, clave, periodo) → ultimo
```

Única puerta: `fn_siguiente_correlativo()`, construida sobre `INSERT … ON CONFLICT DO UPDATE`,
que es atómica bajo concurrencia.

- **Prohibido** `MAX(...)+1`. **Prohibido** que el frontend calcule un número.
- La serie de cotizaciones se reinicia por año (el periodo es parte de la clave).
- Los códigos de ensayo **no se reutilizan nunca**, aunque se elimine el ensayo.
- Con el tenant en la PK, cada laboratorio tiene su propio `COT-2026-001` y su propio `SU-29`.
- El número se consume **al emitir**, no al abrir el asistente: un borrador abandonado no
  deja un hueco en la serie oficial.

Verificado: 8 sesiones concurrentes, 200 cotizaciones, 0 duplicados, 0 huecos.

---

## 7. Auditoría

Un trigger genérico en las 14 tablas de negocio, escribiendo en `auditoria`: tabla, registro
(id técnico e id público), operación, **campos cambiados**, antes, después, usuario, IP, fecha.

- `tenant_id` va en la fila de auditoría: **el rastro de un laboratorio no se muestra a otro.**
- El usuario sale de `fn_app_usuario()` (contexto de sesión), **nunca** de una columna de la
  propia fila. Leerlo de la fila atribuye el cambio a quien creó el registro, no a quien lo
  modificó — la auditoría culpa a la persona equivocada, y se le cree.
- `auditoria` es **append-only**: sin `UPDATE`, y `DELETE` solo por `fn_purgar_auditoria()`,
  que exige más de 365 días y deja constancia de la purga.
- El control `I2` de `99_verificacion.sql` cuenta las filas a nombre del usuario `sistema`.
  Con backend en producción ese número debe tender a cero; si crece, hay un bug de contexto.

---

## 8. Integridad y FK

El patrón, tal como ya está en uso en la v3:

```sql
-- el padre publica la pareja
ALTER TABLE empresas ADD CONSTRAINT uq_empresas_tenant_id UNIQUE (tenant_id, id);

-- la hija referencia la pareja, no la columna suelta
ALTER TABLE cotizaciones ADD CONSTRAINT cotizaciones_empresa_id_fkey
    FOREIGN KEY (tenant_id, empresa_id) REFERENCES empresas (tenant_id, id);
```

Con columnas anulables, `MATCH SIMPLE` (el comportamiento por defecto) no evalúa la FK si
alguna es `NULL`. Eso es lo que permite "empresa sin contacto" y "persona natural sin
empresa" sin debilitar nada cuando ambas tienen valor.

Cuando la relación cruza tablas que un `CHECK` no puede mirar (por ejemplo, que la plantilla
de una cotización sea base o del mismo tenant), va un **trigger**, no una confianza.

**Otras reglas de integridad que no se tocan:**
lo que tiene historia no se borra (`activo BOOLEAN`, una sola convención); la cotización
emitida se congela; los ítems solo se editan en borrador; `ensayo_acreditacion_historial`
y `cotizacion_historial_estados` son append-only; la acreditación solo cambia por
`fn_cambiar_acreditacion()`.

---

## 9. Futura RLS

Escrita como bloque **no ejecutable** al final de `migrations/0003_multitenant_habilitar.sql`.

```sql
ALTER TABLE empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE empresas FORCE  ROW LEVEL SECURITY;
CREATE POLICY p_tenant ON empresas
    USING      (tenant_id = fn_app_tenant())
    WITH CHECK (tenant_id = fn_app_tenant());
```

Tres cosas que se olvidan y cuestan caro:

**`FORCE`** — sin él, el dueño de la tabla ignora sus propias políticas. Si el backend
conecta como dueño, RLS no hace nada y nadie se entera.

**`WITH CHECK`** — `USING` filtra lo que se **lee**; `WITH CHECK` impide **escribir** en otro
tenant. Con solo `USING`, un `INSERT` con `tenant_id` ajeno pasa sin ruido.

**El rol de conexión** — el backend conecta con un rol **sin `BYPASSRLS`** y que no sea dueño
de las tablas.

No activar RLS antes de que exista el backend que fije `app.tenant_id` en cada transacción:
la aplicación se queda ciega y se termina desactivando "temporalmente", que es peor que no
haberlo activado.

---

## 10. Reglas para el backend y la API

**Contexto en cada transacción, sin excepción:**
```sql
SET LOCAL app.tenant_id  = '<de la sesión autenticada>';
SET LOCAL app.usuario_id = '<de la sesión autenticada>';
SET LOCAL app.ip_origen  = '<del request>';
```
`SET LOCAL`, no `SET`: con *pooling*, un `SET` de sesión se filtra a la siguiente petición,
que puede ser de **otro tenant**.

**Contra IDOR / BOLA:** toda lectura por identificador lleva `AND tenant_id = <sesión>`.
Un recurso de otro tenant responde **404, no 403** — un 403 confirma que el recurso existe.
Nunca aceptar un `tenant_id` del cliente "para filtrar".

**Endpoints nuevos:** ninguno consulta una tabla tenant-scoped sin filtro de tenant, aunque
RLS esté activa. RLS es la red, no el piso.

**Escribir por funciones de caso de uso** (`fn_crear_cotizacion`, `fn_cambiar_estado_cotizacion`,
`fn_cambiar_acreditacion`, `fn_definir_componentes`) en vez de `INSERT`/`UPDATE` sueltos:
son atómicas y ya traen las reglas dentro.

**Documentos y archivos:** la ruta de almacenamiento incluye el tenant; las URLs firmadas se
emiten tras verificar pertenencia, no por conocer el `public_id`; `integraciones.token_ref`
apunta a un vault, la BD nunca guarda el token.

**Caché:** toda clave de caché lleva el tenant. Una clave `cotizacion:{public_id}` compartida
entre tenants es una fuga que ninguna FK puede detener.

**Colas y trabajos en segundo plano:** el mensaje transporta el `tenant_id`; el *worker* fija
el contexto antes de tocar la base. Un trabajo sin tenant no se ejecuta.

**Logs:** registrar el `tenant_id` para poder investigar, y **nunca** volcar filas completas
de datos de cliente al log.

**Respaldos:** son de toda la base, así que restaurar un tenant es una operación selectiva
por `tenant_id`, no un `pg_restore` completo. Probar ese procedimiento **antes** de
necesitarlo, y verificar que no reintroduce filas de otros tenants.

---

## 11. Pruebas de aislamiento (obligatorias)

No se da por implementado el multi-tenant sin estas pruebas automatizadas y en verde:

1. Con el tenant A en contexto, un `SELECT` **sin `WHERE`** sobre cada tabla tenant-scoped
   no devuelve **ni una** fila del tenant B.
2. Leer por `public_id` un recurso del tenant B desde el tenant A responde **404**.
3. Un `INSERT`/`UPDATE` con `tenant_id` ajeno es rechazado (`WITH CHECK` o FK).
4. Crear una cotización del tenant A apuntando a una empresa del tenant B → rechazado.
5. Crear una cotización con un contacto que no es de su empresa → rechazado.
6. Dos tenants pueden tener el mismo RUC, el mismo `SU-01` y el mismo `COT-2026-001`.
7. Cada tenant arranca su correlativo en 001, sin importar cuánto lleve el otro.
8. Una consulta **sin** `app.tenant_id` falla; no devuelve todo.
9. La auditoría del tenant A no es visible desde el tenant B.
10. Los puntos 1 a 9 siguen pasando después de la siguiente migración.

En la v3 ya están verificados los puntos 4, 5, 6, 7 y 8 sobre una copia desechable con la
migración 0003 aplicada. Los demás dependen del backend.

---

## 12. Checklist obligatorio

Antes de dar por terminada cualquier tarea que toque la base o la API:

```
[ ] ¿La tabla es GLOBAL, TENANT-SCOPED o HÍBRIDA? ¿Está en su COMMENT ON TABLE?
[ ] ¿Tiene tenant_id si corresponde, NOT NULL y con FK a tenants?
[ ] ¿Las FK hacia otras tablas tenant-scoped son COMPUESTAS (tenant_id, id)?
[ ] ¿El padre publica el UNIQUE (tenant_id, id) que esas FK necesitan?
[ ] ¿Los UNIQUE están en el ámbito correcto? (¿global de verdad, o debería ser por tenant?)
[ ] ¿Los índices empiezan por tenant_id?
[ ] ¿La auditoría cubre esta tabla y guarda su tenant_id?
[ ] ¿El id técnico, el id público y el código de negocio están separados?
[ ] ¿Los correlativos salen de fn_siguiente_correlativo() y no de MAX()+1 ni del frontend?
[ ] ¿Los snapshots históricos siguen protegidos? (ítems congelados, append-only intactos)
[ ] ¿Hay algún camino de cruce entre tenants? (JOIN, reporte, caché, cola, archivo, log)
[ ] ¿La futura política RLS podrá aplicarse tal cual sobre esta tabla?
[ ] ¿La API filtra por tenant además de RLS, y responde 404 y no 403 ante un recurso ajeno?
[ ] ¿Existen pruebas de aislamiento para lo que se agregó?
[ ] ¿Se actualizaron CLAUDE.md, docs/AUDITORIA_BD_v3.md y el diagrama ER?
```

---

## 13. Al aplicar la migración 0003

Precondiciones, **todas**:

1. `0002` aplicada y `99_verificacion.sql` limpio.
2. Backend que resuelve el tenant desde la sesión autenticada.
3. Ese backend abre cada transacción con `SET LOCAL app.tenant_id`.
4. Pruebas de aislamiento (§11) escritas.
5. Respaldo verificado y ventana de mantenimiento.

Después de aplicarla, **re-alcanzar por tenant** los controles de `99_verificacion.sql` que
hoy son globales: `A1` (códigos duplicados), `A3` (RUC/DNI duplicados), `A4` (prefijos
duplicados) y `F1`/`F2` (correlativos). Tal como están, con dos tenants darían falsas alarmas
—el mismo `SU-01` en dos laboratorios es correcto— y dejarían de detectar el problema real
dentro de un tenant.

Lo que 0003 **no** trae y sigue pendiente: RLS, autenticación, autorización por rol,
resolución del tenant, y aislamiento en caché, colas, logs y archivos.
