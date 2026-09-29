# SAC-GEO — Plan de pruebas de seguridad

> Fase 3D · 2026-09-28.
>
> Este plan cubre las pruebas A–T del requerimiento. Para cada una: objetivo, actor,
> precondiciones, operación, resultado esperado, capa que debe atajarlo y **dónde vive
> la prueba**.
>
> **Regla que ordena todo el documento:** una prueba que no puede ejercerse todavía se
> marca como tal. No se da por superada porque "debería funcionar". Un SKIP es deuda
> declarada; un PASS falso es una fuga que nadie volverá a mirar.

---

## 0. Dónde vive cada prueba

| Archivo | Qué prueba | Estado |
|---|---|---|
| `database/98_pruebas.sql` | Reglas de negocio en el motor | **71 PASS / 0 FAIL**, antes y después de `0003` |
| `database/99_verificacion.sql` | Integridad de los datos existentes | 37 controles, 35 en cero |
| `database/97_aislamiento.sql` | Aislamiento entre tenants | **16 PASS / 0 FAIL / 8 SKIP** con `0003` aplicada |
| *pendiente* `tests/seguridad/` | Autorización y API | No existe: requiere FastAPI |

Las pruebas de este plan que son de base de datos van a `97`. Las de autorización y
transporte van a la suite de la API, que todavía no existe.

### Pre-requisito que invalida la mitad del plan si se ignora

Toda prueba que dependa de RLS **debe ejecutarse con el rol de aplicación**
(`sacgeo_app`: sin `BYPASSRLS`, sin ser propietario de las tablas). Ejecutada como
`sacgeo_dev` no demuestra nada: el propietario ignora sus propias políticas salvo
`FORCE`, y aunque pasara, habría pasado por la vía estructural y no por RLS.

`97_aislamiento.sql` ya detecta esta condición y degrada a SKIP automáticamente.

---

## A · Lectura entre tenants

**Objetivo** — que el tenant A no lea ni una fila del tenant B.
**Actor** — usuario `comercial` del tenant A, autenticado.
**Precondiciones** — `0004` aplicada; sesión con `app.tenant_id = A`; existen datos de B.
**Operación** — `SELECT` **sin `WHERE`** sobre cada una de las 16 tablas tenant-scoped, y sobre las 8 vistas.
**Resultado esperado** — cero filas de B. No un error: **cero filas**.
**Capa** — RLS (`USING`). La API filtra además, pero esta prueba mide la red, no el piso.
**Dónde** — `97`, pruebas 1 y 3. Hoy **SKIP** (falta `0004`).

## B · Escritura sobre otro tenant

**Objetivo** — que A no pueda modificar filas de B.
**Actor** — usuario del tenant A.
**Precondiciones** — igual que A.
**Operación** — `UPDATE empresas SET razon_social='X' WHERE id=<id de B>`.
**Resultado esperado** — **0 filas afectadas**, sin error. La fila es invisible, no prohibida: un error confirmaría que existe.
**Capa** — RLS (`USING` en `UPDATE`).
**Dónde** — `97`, prueba 5. Hoy **SKIP**.

Variante crítica: `INSERT ... (tenant_id, ...) VALUES (<B>, ...)` debe ser **rechazado** por `WITH CHECK`. Sin `WITH CHECK`, un `INSERT` con tenant ajeno pasa en silencio. `97`, prueba 4.

## C · Borrado entre tenants

**Objetivo** — que A no pueda borrar nada de B.
**Actor** — usuario del tenant A, incluso con rol `admin`.
**Operación** — `DELETE FROM cotizaciones WHERE id = <id de B>`.
**Resultado esperado** — doble barrera: RLS no ve la fila (0 filas), y aunque la viera, `fn_prohibir_delete()` bloquea el borrado de cotizaciones **para cualquiera**.
**Capa** — RLS + trigger.
**Dónde** — la segunda mitad ya está **CONFIRMADA** en `98`, prueba 5 (*"eliminar una cotización"*, `23001`). La primera va a `97` con `0004`.

## D · IDOR

**Objetivo** — que conocer un identificador no otorgue acceso.
**Actor** — usuario del tenant A con el `public_id` de una cotización de B.
**Precondiciones** — FastAPI operativo.
**Operación** — `GET /cotizaciones/{public_id de B}`.
**Resultado esperado** — **`404`, no `403`.** Un `403` confirma que el recurso existe.
**Capa** — API (`AND tenant_id = <sesión>` en toda consulta por identificador) + RLS.
**Dónde** — suite de la API. **No existe todavía.**

Nota: el esquema ya separa `id` técnico, `public_id` y código de negocio. Exponer un UUID no autoriza nada — la consulta debe llevar el tenant igualmente.

## E · Escalada horizontal

**Objetivo** — que el tenant no se pueda cambiar desde el cliente.
**Actor** — usuario del tenant A.
**Operación** — enviar `tenant_id = B` en el cuerpo, en un header, en un parámetro y en un campo oculto del formulario. Los cuatro.
**Resultado esperado** — el valor se **ignora por completo**. La respuesta es idéntica a no haberlo enviado. El tenant sale de la sesión autenticada.
**Capa** — API. RLS no protege de esto: si el backend fija `app.tenant_id` con lo que llegó del cliente, RLS obedece obedientemente al atacante.
**Dónde** — suite de la API. **Es la prueba más importante de todo el plan.**

## F · Escalada vertical

**Objetivo** — que un usuario no amplíe su propio rol.
**Actor** — usuario `comercial`.
**Operación** — `PATCH /usuarios/{propio}` con `{"rol_id": 1}`; y `POST /usuarios` con `{"rol_id": 1, "tenant_id": null}`.
**Resultado esperado** — rechazado. `rol_id` y `tenant_id` no están en la lista blanca de campos editables por ese rol.
**Capa** — API (esquemas de entrada + permiso `usuarios.assign_role`).
**Dónde** — suite de la API. **PENDIENTE**: el permiso no existe todavía.

Componente de base ya disponible: el intento de crear un usuario global se topa con el índice único que reserva `tenant_id NULL` (§7 de `SEGURIDAD_RBAC.md`).

## G · Cotizador intentando aprobar

**Objetivo** — separación de funciones: quien crea no aprueba.
**Actor** — `comercial`, autor de la cotización.
**Operación** — aprobar su propia cotización.
**Resultado esperado** — rechazado por ser el autor, incluso si tuviera el permiso.

> **BLOQUEADA — no es implementable hoy.**
> `dom_estado_cotizacion` admite `borrador, emitida, aceptada, rechazada, cancelada`.
> `aceptada`/`rechazada` son la respuesta **del cliente**, no una aprobación interna.
> No existe estado de aprobación al que colgar la regla. Ver `SEGURIDAD_RBAC.md` §C-2.
>
> Requiere: estados nuevos, reescribir `fn_transicion_estado_valida()`, una regla
> `aprobador <> creado_por`, y actualizar `98` (que hoy afirma que el historial tiene
> exactamente 3 filas).

**Capa prevista** — API (regla contextual) + BD (la transición debe ser imposible desde el estado equivocado).

## H · Aprobador administrando usuarios

**Objetivo** — que un rol operativo no herede administración.
**Actor** — rol de aprobación (cuando exista; hoy el análogo es `laboratorio`).
**Operación** — `POST /usuarios`, `PATCH /usuarios/{id}`, `DELETE`.
**Resultado esperado** — `403` por permiso ausente (aquí sí `403`: el endpoint existe y no se revela nada del dato).
**Capa** — API.
**Dónde** — suite de la API. **PROPUESTO**.

## I · Administrador accediendo a otro tenant

**Objetivo** — que `admin` sea administrador **de su tenant**, no del sistema.
**Actor** — `admin` del tenant A.
**Operación** — cualquier lectura o escritura sobre datos de B.
**Resultado esperado** — indistinguible de un usuario sin privilegios: no ve nada de B.
**Capa** — RLS + API. El rol no entra en la política: la política solo mira `tenant_id`.
**Dónde** — `97` con `0004`.

Esto es deliberado y conviene que quede escrito: **el rol nunca aparece en una política RLS.** Mezclar rol y tenant en la misma política es como se abren los agujeros.

## J · Usuario desactivado

**Objetivo** — que `activo = FALSE` corte el acceso de inmediato.
**Actor** — usuario recién desactivado con un token todavía vigente.
**Operación** — cualquier petición con ese token.
**Resultado esperado** — `401`. La sesión se invalida al desactivar, no al expirar el token.
**Capa** — API.
**Dónde** — suite de la API.

Sub-prueba obligatoria: **el usuario `sistema` (id 1) no puede autenticarse.** Tiene `rol_id = 1` (`admin`) y `password_hash IS NULL`. Debe seguir siendo imposible iniciar sesión con él; si alguna vez se le asignara contraseña, sería un administrador global sin tenant.

## K · Rol inexistente

**Objetivo** — que un `rol_id` inválido no degrade en "permitir".
**Operación** — token o registro con `rol_id` que no existe o que fue desactivado.
**Resultado esperado** — denegar. El caso por omisión de la autorización es **NO**.
**Capa** — API + BD (`usuarios_rol_id_fkey` ya impide la fila inconsistente).
**Dónde** — parcialmente **CONFIRMADO** en la base (FK `ON DELETE RESTRICT`). El resto, API.

## L · Permiso inexistente

**Objetivo** — que pedir un permiso no catalogado deniegue, no conceda.
**Operación** — `exigir(usuario, "cotizaciones.aprobar_todo")` con un código que no está en `permisos`.
**Resultado esperado** — excepción y denegación, no `False` silencioso ni `True` por defecto.
**Capa** — API.
**Dónde** — suite de la API. **PENDIENTE**: `permisos` no existe todavía.

## M · Super Admin

**Objetivo** — que el acceso de plataforma sea explícito, acotado y trazable.
**Actor** — usuario con rol de `scope = 'plataforma'`.
**Pruebas**:
1. Sin concesión activa en `plataforma_accesos`, **no ve ningún tenant**. El rol por sí solo no abre nada.
2. Con concesión sobre el tenant A, ve A y **no ve B**.
3. La concesión caducada deja de funcionar sin intervención.
4. Cada acción queda en `auditoria` con `tenant_id` = el tenant afectado (no `NULL`).
5. `tenant_id IS NULL` en su fila de `usuarios` **no le concede nada por sí mismo**.

**Resultado esperado** — los cinco.
**Capa** — API + BD.
**Dónde** — pendiente. Requiere el modelo de §4 de `SEGURIDAD_RBAC.md`. **PROPUESTO.**

La prueba 5 es la que verifica que no se cayó en el anti-patrón de confundir "global" con "sin restricciones".

## N · Auditoría

**Objetivo** — que el rastro sea inalterable y correctamente atribuido.

| Sub-prueba | Estado |
|---|---|
| `UPDATE auditoria` bloqueado | **CONFIRMADO** — `98`, `23001` |
| `DELETE FROM auditoria` bloqueado | **CONFIRMADO** — `98`, `23001` |
| Purga de auditoría reciente (<365 días) bloqueada | **CONFIRMADO** — `98`, `23001` |
| El cambio se atribuye a quien lo hizo, no a quien creó el registro | **CONFIRMADO** — `98`, prueba 12 |
| Se registra la IP de origen | **CONFIRMADO** — `98`, prueba 12 |
| Se registra el valor anterior | **CONFIRMADO** — `98`, prueba 12 |
| Rastro de tenant A invisible desde B | `97`, prueba 16 — **SKIP** hasta `0004` |
| Cambios globales (`tenant_id NULL`) visibles para todos | `97`, prueba 17 — **SKIP** hasta `0004` |
| Login, logout y accesos denegados quedan registrados | **NO CUBIERTO** — ver `MODELO_AMENAZAS.md` §5 |
| Ningún secreto ni contraseña en `auditoria` | **PENDIENTE**: al habilitar login, excluir `password_hash` de `datos_anteriores`/`datos_nuevos` |

La última fila es un riesgo **nuevo y concreto**: `fn_auditar()` hace `to_jsonb(NEW)` de
la fila **entera**. En cuanto `usuarios.password_hash` deje de ser `NULL`, cada cambio de
contraseña **copiará el hash a `auditoria`**, que es append-only y no se puede limpiar.
Debe resolverse **antes** de habilitar la autenticación.

## O · `tenant_id` manipulado

Cubierta por **E**. Se separa aquí porque el vector es distinto: no es solo el cuerpo del
request, también el `path`, la *query string*, un header propio y una cookie.
**Resultado esperado** — el tenant nunca se lee de ninguna de esas fuentes.

## P · Acceso sin contexto de tenant

**Objetivo** — que la ausencia de contexto **falle**, no devuelva todo.
**Operación** — abrir transacción sin `SET LOCAL app.tenant_id` y operar.
**Resultado esperado** — excepción `42501` (`fn_app_tenant`). Nunca un resultado vacío ni un resultado completo.
**Capa** — BD.
**Dónde** — `97`, prueba 2. **Ya PASA** con `0003` aplicada (verificado: `INSERT` y `fn_hoy_lima()` fallan con `42501`).

Efecto colateral verificado: `99_verificacion.sql` **aborta entero** tras `0003` porque llama a `fn_hoy_lima()` sin contexto. Necesita una línea de contexto, igual que la necesitó `98`.

## Q · Contexto de tenant incorrecto

**Objetivo** — que fijar un tenant al que el usuario no pertenece no sirva de nada.
**Operación** — el backend fija `app.tenant_id = B` para un usuario de A (simulando un fallo del backend).
**Resultado esperado** — RLS obedece y le muestra B. **Esta es la prueba que demuestra que RLS NO protege de un backend comprometido.**
**Capa** — API. Es responsabilidad exclusiva del backend derivar el tenant de la sesión.
**Dónde** — suite de la API, como prueba **negativa documentada**: sirve para fijar el límite de lo que RLS puede garantizar.

## R · SQLSTATE esperado

**Objetivo** — que un bloqueo ocurra por la razón correcta.
**Operación** — cada prueba de bloqueo declara el SQLSTATE que espera.
**Resultado esperado** — coincidencia exacta.
**Capa** — BD.
**Dónde** — **CONFIRMADO**. `t_bloquea()` en `98` y `97` verifica el código; las 34 llamadas de `98` están anotadas con el SQLSTATE **observado**, no supuesto. Además falla explícitamente si el bloqueo vino de `42501` (falta de tenant) cuando no era eso lo que se probaba.

Códigos en uso: `23001` restrict_violation (20), `23514` check_violation (12), `23503` foreign_key_violation (1), `23505` unique_violation (1), `42501` insufficient_privilege (aislamiento).

## S · Integridad referencial

**Objetivo** — que el cruce entre tenants sea **imposible**, no improbable.
**Operación** — cotización de un tenant apuntando a empresa de otro; contacto sobre empresa ajena; componente de paquete de otro tenant.
**Resultado esperado** — `23503` por FK compuesta, **sin depender de RLS ni del backend**.
**Capa** — BD.
**Dónde** — `97`, pruebas 6, 7 y 8. **Ya PASAN** con `0003` aplicada.

Esta es la última línea de defensa, y la única que sigue en pie cuando todas las demás fallan.

## T · RLS futura

**Objetivo** — que RLS esté realmente activa y realmente aplicándose.
**Precondiciones** — `0004`; rol `sacgeo_app`; `ENABLE` + **`FORCE ROW LEVEL SECURITY`**.
**Pruebas**:
1. `relrowsecurity` y `relforcerowsecurity` verdaderos en las 16 tablas.
2. El rol de conexión **no** tiene `BYPASSRLS` ni es propietario.
3. Toda política tiene `USING` **y** `WITH CHECK`.
4. `plantillas_cotizacion`, `usuarios` y `auditoria` llevan la política **híbrida**, no la simple.
5. Las 8 vistas tienen `security_invoker = true` — **ya CONFIRMADO en `0003`**, verificado 8 de 8.
6. Repetir A, B, C e I y que pasen.

**Dónde** — `97` ya trae la detección de entorno (rol, propietario, `BYPASSRLS`, `FORCE`) y decide sola si una prueba de RLS vale o se marca SKIP.

---

---

# Anexo 3E — Pruebas de RBAC, aprobación y auditoría segura

Las pruebas A–T de la fase 3E se solapan parcialmente con las anteriores. Aquí van solo
las **nuevas**, con la misma estructura.

## E-3E · Cotizador no aprueba

**Objetivo** — segregación de funciones, garantizada por el motor.
**Actor** — `comercial`, autor de la cotización.
**Precondiciones** — migración `0006`; la cotización está en `en_revision`.
**Operación** — `fn_decidir_aprobacion(cot, 'aprobada', ...)` con `decidido_por = autor`.
**Resultado esperado** — `23514` por `ck_aprob_no_autoaprueba`. **Falla en la base, no en la API.**
**Capa** — BD (`CHECK` de fila) + API (permiso ausente).
**Estado** — PROPUESTO. Hoy imposible: no existe el flujo.

Variante que hay que probar aparte: el autor **tampoco** puede aprobar si le dieran el
permiso `cotizaciones.approve`. El `CHECK` no consulta permisos, así que sigue bloqueando.

## F-3E · Aprobador sí puede aprobar

**Actor** — `aprobador`, distinto del autor y de quien envió.
**Resultado esperado** — la fila se cierra con `decision='aprobada'` y la cotización pasa a `aprobada`, **sin número todavía**.
**Capa** — API + BD.

## G-3E · Aprobador no administra usuarios

**Actor** — `aprobador`.
**Operación** — `POST /usuarios`.
**Resultado esperado** — `403`. El endpoint existe y no revela ningún dato, así que `403` es correcto aquí (a diferencia del acceso a otro tenant, que es `404`).
**Capa** — API.

## H-3E · Administrador sí administra usuarios

**Resultado esperado** — permitido **dentro de su tenant**, y `usuarios.assign_role` solo con roles `scope='tenant'`. Asignar un rol de plataforma debe fallar.
**Capa** — API + BD (`fn_validar_scope_permiso` impide siquiera construir ese rol).

## J-3E · Super Admin sin concesión

**Objetivo** — que el rol por sí solo no abra nada.
**Actor** — usuario con `roles.scope='plataforma'`, sin fila vigente en `plataforma_accesos`.
**Operación** — intentar operar sobre el tenant 5.
**Resultado esperado** — denegado. **`tenant_id IS NULL` en su fila de `usuarios` no le concede nada.**
**Capa** — API.
**Por qué importa** — es la prueba que verifica que no se cayó en el anti-patrón de confundir "global" con "sin restricciones".

## K-3E · Super Admin con concesión

**Resultado esperado** — ve el tenant concedido **y solo ese**. Cada acción queda en `auditoria` con `tenant_id` = el tenant afectado, no `NULL`.

## L-3E · Concesión expirada

**Operación** — `hasta < now()`.
**Resultado esperado** — denegado, sin intervención humana. Las concesiones caducan solas.

Sub-prueba: `ck_plat_no_autoconcesion` impide que un super admin se conceda acceso a sí mismo (`23514`).

## M-3E · `password_hash` no aparece en auditoría — **CRÍTICA**

**Objetivo** — que ningún secreto quede archivado.
**Operación** — `UPDATE usuarios SET password_hash = '$argon2id$...'`.
**Resultado esperado**, las tres cosas a la vez:
1. `auditoria.campos_cambiados` **contiene** `password_hash` — la trazabilidad se conserva;
2. `datos_anteriores->>'password_hash'` y `datos_nuevos->>'password_hash'` valen `'[REDACTADO]'`;
3. **existe fila de auditoría** — verifica que no se rompió la salida anticipada de `fn_auditar()`.

**Capa** — BD.
**Estado hoy** — **FALLA.** Verificado ejecutándolo: el hash queda almacenado en claro en `datos_nuevos`. Ver `SEGURIDAD_RBAC.md` §7.

La prueba 3 es la que atrapa el error de orden: redactar antes de calcular los campos
cambiados haría que un cambio de contraseña no generase auditoría **en absoluto**.

## Q-3E · Estado manipulado directamente

**Operación** — `UPDATE cotizaciones SET estado='aprobada' WHERE id=...`, saltándose el flujo.
**Resultado esperado** — bloqueado. Doble barrera: el `UPDATE` directo de estado ya está prohibido (`23514`, **CONFIRMADO** en `98`), y el trigger de puerta exige la marca de sesión que solo pone `fn_decidir_aprobacion()`.
**Capa** — BD.

Variante: `borrador → emitida` con `tenants.requiere_aprobacion = TRUE` debe fallar (`23001`).

## S-3E · Rechazo y reenvío

**Operación** — enviar (ciclo 1) → rechazar con observación → editar → reenviar (ciclo 2) → aprobar.
**Resultado esperado**:
- el rechazo devuelve a `borrador` y **los ítems vuelven a ser editables**;
- rechazar sin observación falla (`ck_aprob_rechazo_motivado`);
- el ciclo 2 es una fila **nueva**; la del ciclo 1 sigue intacta;
- `uq_aprob_ciclo` impide duplicar un ciclo.
**Capa** — BD.

## T-3E · Historial de aprobaciones

**Resultado esperado** — `cotizacion_aprobaciones` es append-only: `UPDATE` y `DELETE` bloqueados (`23001`), igual que `auditoria`. Los tres ciclos de la prueba S siguen legibles después.
**Capa** — BD.

## P-3E · Mass assignment

**Operación** — `PATCH /usuarios/{id}` y `POST /cotizaciones` enviando `tenant_id`, `rol_id`, `estado`, `aprobado_por`, `creado_por`, `numero`.
**Resultado esperado** — todos ignorados o rechazados. Ninguno llega al modelo.
**Capa** — API (DTO con lista blanca). **No hay defensa en BD para esto**: si el backend escribe el campo, la base lo acepta. Es responsabilidad exclusiva de FastAPI y por eso debe probarse campo por campo.

---

## Resumen de cobertura

| Estado | Pruebas |
|---|---|
| **CONFIRMADO** (pasa hoy) | C parcial, K parcial, N (6 de 10), P, R, S |
| **SKIP hasta `0004`** | A, B, I, N (2), T |
| **Pendiente de FastAPI** | D, E, F, H, J, L, O, Q |
| **BLOQUEADA por diseño** | **G** — no existe estado de aprobación |
| **Pendiente de modelo** | **M** — no existe super admin |

**E es la prueba más importante y no se puede ejecutar todavía**, porque no hay backend.
Hasta entonces, el aislamiento descansa en las FK compuestas (verificadas) y, cuando
llegue, en RLS.
