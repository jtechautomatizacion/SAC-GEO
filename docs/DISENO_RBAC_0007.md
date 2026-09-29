# SAC-GEO — Diseño de RBAC multi-rol (migración 0007)

> Fase 5C.2 · 2026-09-29. **Migración `0007` escrita. NO ejecutada, ni siquiera en base desechable.**
> Sustituye a la versión de la fase 5A de este mismo archivo y a `SEGURIDAD_RBAC.md` §3.3.
> Cada permiso se derivó de una función o una tabla verificada en `sacgeo_dev` con
> `0001–0006` aplicadas.
>
> **Pendiente de autorización explícita antes de crear un solo objeto.**

---

## 0. Correcciones acumuladas

### 0.0 · Decisiones aprobadas en 5C.2, ya implementadas en `0007`

- **Cinco roles.** No se crea «técnico»: SAC-GEO no modela muestras, resultados
  ni informes de ensayo, así que un técnico de ensayo no tendría operación
  propia. `laboratorio` **es** el responsable técnico/calidad.
- `admin` sin `catalogo.manage`, `acreditacion.manage` ni los ocho permisos de
  operación de cotizaciones.
- `comercial` sin `dashboard.read`.
- **`catalogo.price` separado de `catalogo.manage`** → el total pasa a **31**.
- Guardas de `p_usuario` en 7 funciones, conservando firmas. H-13.
- `usuario_roles` tenant-scoped con RLS FORCE. Índice sobre `rol_id`.

### 0.1 · Un tercer error de recuento, y el patrón que lo produce

PRE-API dijo 26. La versión 5A dijo 27 con una matriz de 29 filas. En 5C.1
recalculé mecánicamente: eran **30**. Con `catalogo.price`, **31**.

Los tres errores tienen la misma causa: **contar sobre una tabla en vez de sobre
una lista numerada**. Una tabla omite en silencio lo que no tiene columna
—`plataforma.acceso.grant` no tenía columna de rol porque no lo recibe nadie— y
el total se arrastra de un documento al siguiente sin recontar.

Por eso `0007` lleva la validación **9.1**, que cuenta en la base y aborta si no
son 31 / 30 tenant / 1 plataforma. El recuento deja de depender de que yo sume
bien.

### 0.2 · El CHECK del código de permiso rechazaba 3 de los 31

`SEGURIDAD_RBAC.md` §3.1 propone `CHECK (codigo ~ '^[a-z_]+\.[a-z_]+$')`. Ese
patrón **rechaza** `tenant.config.read`, `tenant.config.update` y
`plataforma.acceso.grant`, que llevan dos puntos: aplicarlo tal cual haría
fallar la siembra de la propia migración. `0007` usa
`^[a-z_]+(\.[a-z_]+){1,2}$` — tres segmentos como máximo.

### 0.3 · `catalogo.manage` incluía el precio

`ensayos_catalogo.precio_base` vive en la misma tabla que `norma` y `unidad`. Un
solo permiso juntaba dos autoridades: la técnica y la comercial. Dárselo entero
a `laboratorio` habría dejado al comercial sin poder cambiar un precio — el
espejo exacto del conflicto por el que se le retiró a `admin`.

⚠ **La separación la aplica la API, no el motor.** PostgreSQL solo ve un UPDATE;
lo que impide que `catalogo.price` toque `norma` es que su endpoint actualice
únicamente `precio_base`. Queda escrito para que nadie suponga una defensa que
no existe.

Nota: `fn_crear_ensayo` recibe `p_precio`, así que quien **crea** un ensayo fija
su precio inicial, y eso exige `catalogo.manage` → `laboratorio`. `comercial` lo
cambia después. Es coherente: el precio de alta lo pone quien define el ensayo.

### 0.4 · El recuento anterior (5C.1) era 30

La auditoría PRE-API dijo «26 permisos». La versión 5A de este documento dijo «27» y luego
presentó una matriz de 29 filas describiéndola como «29 filas, 27 permisos únicos más los
dos de administración», frase que no significa nada.

Enumerados por familia, una sola vez y sin agrupar:

| Familia | # | Permisos |
|---|:--:|---|
| Catálogo | 3 | `catalogo.read`, `catalogo.manage`, **`catalogo.price`** |
| Acreditación | 2 | `acreditacion.read`, `acreditacion.manage` |
| Clientes | 2 | `clientes.read`, `clientes.manage` |
| Cotizaciones | 9 | `read`, `create`, `update`, `submit`, `approve`, `reject`, `emit`, `cancel`, `close` |
| Dashboard | 1 | `dashboard.read` |
| Documentos | 2 | `documentos.read`, `documentos.create` |
| Integraciones | 2 | `integraciones.read`, `integraciones.manage` |
| Usuarios | 5 | `read`, `create`, `update`, `disable`, `assign_role` |
| Auditoría | 2 | `auditoria.read`, `auditoria.purge` |
| Configuración | 2 | `tenant.config.read`, `tenant.config.update` |
| Plataforma | 1 | `plataforma.acceso.grant` |
| **Subtotal 5C.1** | **30** | 29 tenant + 1 plataforma |
| **`catalogo.price`** (5C.2) | **+1** | tenant |
| **TOTAL** | **31** | **30 de scope `tenant` + 1 de scope `plataforma`** |

El error vino de contar sobre una tabla en vez de sobre una lista: la matriz de 5A omitía
`plataforma.acceso.grant` (que no se otorga a ningún rol de tenant y por eso no tenía
columna), y los totales anteriores se arrastraron sin recontar. Es el mismo tipo de fallo
que ya cometí con las aserciones de la suite 97.

### 0.2 · El rol «técnico» no existe

El encargo pide explicar qué puede hacer «técnico». En la base hay **cuatro** roles:

```
admin | comercial | laboratorio | lectura
```

Asumo que «técnico» se refiere a **`laboratorio`**, cuyo nombre propuesto es
«Laboratorio / Calidad» y cuyo titular es el responsable técnico del laboratorio. Lo trato
así en todo el documento. **Si querías un rol distinto —un técnico de ensayo que solo
consulta, separado del responsable de calidad que acredita— hay que decidirlo antes de
`0007`, porque parte el rol en dos y cambia la matriz.**

---

## 1. Numeración y alcance

`0006` está aplicada. El RBAC es **`0007`**. Plan completo:

| # | Contenido | Estado |
|---|---|---|
| 0006 | Autor de auditoría no falsificable (H-06) | ✅ aplicada |
| **0007** | **RBAC multi-rol + guardas de H-15 y H-13** | 📝 este documento |
| 0008 | Sesiones y refresh | ⏳ |
| 0009 | `eventos_seguridad` | ⏳ |
| 0010 | Flujo de aprobación | ⏳ |

---

## 2. Modelo

```
usuarios ──< usuario_roles >── roles ──< rol_permisos >── permisos
```

| Tabla | Clasificación | Por qué |
|---|---|---|
| `permisos` | **GLOBAL** | Catálogo del producto. Un cliente no inventa acciones |
| `roles` | **GLOBAL** (ya lo es) | Si un tenant pudiera crear roles, se fabricaría uno con permisos que no le tocan (V-2 del modelo de amenazas) |
| `rol_permisos` | **GLOBAL** | Qué trae cada rol lo decide el producto |
| `usuario_roles` | **TENANT-SCOPED** | Quién es quién pertenece al laboratorio. `tenant_id NOT NULL`, FK compuesta contra `usuarios (tenant_id, id)`, RLS estándar |

`usuarios.rol_id` **se conserva** durante la transición y se puebla `usuario_roles` desde
él. Se retira en una migración posterior, cuando nada lo lea.

---

## 3. Matriz completa: rol → permiso → caso de uso → función

Verificado en `sacgeo_dev`: **20 funciones de caso de uso** invocables por un endpoint.
La columna «Función BD» dice cuál protege cada permiso; «—» significa que es CRUD directo
sobre la tabla, sin función intermedia, y entonces el permiso es la **única** barrera de
autorización.

| Permiso | Caso de uso | Función BD | API | `admin` | `comercial` | `aprobador` | `laboratorio` | `lectura` |
|---|---|---|---|:--:|:--:|:--:|:--:|:--:|
| `catalogo.read` | Ver categorías, ensayos, paquetes | `fn_ensayos_de_categoria`, `fn_siguiente_codigo_ensayo`, `vw_catalogo_disponible` | `GET /catalogo/*` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `catalogo.manage` | Crear categoría, ensayo, paquete, componentes | `fn_crear_categoria`, `fn_crear_ensayo`, `fn_crear_paquete`, `fn_definir_componentes` | `POST/PUT /catalogo/*` | — | — | — | ✅ | — |
| `acreditacion.read` | Consultar acreditación a una fecha | `fn_acreditado_en_fecha`, `vw_acreditacion_vigente` | `GET /ensayos/{id}/acreditacion` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `acreditacion.manage` | Cambiar acreditación ISO 17025 | `fn_cambiar_acreditacion` | `POST /ensayos/{id}/acreditacion` | — | — | — | ✅ | — |
| `clientes.read` | Ver empresas, contactos, personas | — (CRUD) | `GET /empresas`, `/contactos`, `/personas` | ✅ | ✅ | ✅ | — | ✅ |
| `clientes.manage` | Alta y edición de clientes | — (CRUD) | `POST/PUT` de los tres | — | ✅ | — | — | — |
| `cotizaciones.read` | Ver cotizaciones y su PDF | `vw_cotizacion_pdf` | `GET /cotizaciones*` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `cotizaciones.create` | Crear cotización | `fn_crear_cotizacion` | `POST /cotizaciones` | — | ✅ | — | — | — |
| `cotizaciones.update` | Editar borrador, ítems, importes | `fn_agregar_item`, `fn_recalcular_cotizacion` | `PUT /cotizaciones/{id}` | — | ✅ | — | — | — |
| `cotizaciones.submit` | Enviar a revisión | `fn_enviar_a_revision` *(0010)* | `POST /{id}/enviar` | — | ✅ | — | — | — |
| `cotizaciones.approve` | Dar el visto bueno interno | `fn_decidir_aprobacion` *(0010)* | `POST /{id}/aprobar` | — | — | ✅ | — | — |
| `cotizaciones.reject` | Devolver a borrador con motivo | `fn_decidir_aprobacion` *(0010)* | `POST /{id}/rechazar` | — | — | ✅ | — | — |
| `cotizaciones.emit` | Emitir: consume el número | `fn_cambiar_estado_cotizacion(→emitida)` | `POST /{id}/emitir` | — | ✅ | — | — | — |
| `cotizaciones.cancel` | Cancelar | `fn_cambiar_estado_cotizacion(→cancelada)` | `POST /{id}/cancelar` | — | ✅ | — | — | — |
| `cotizaciones.close` | Registrar respuesta del **cliente** | `fn_cambiar_estado_cotizacion(→aceptada/rechazada)` | `POST /{id}/cerrar` | — | ✅ | — | — | — |
| `dashboard.read` | KPIs, evolución, top clientes y ensayos | `fn_dashboard_kpis`, `_por_categoria`, `_top_clientes`, `_evolucion`, `_ensayos_top` | `GET /dashboard/*` | ✅ | — | — | — | ✅ |
| `documentos.read` | Ver PDFs y documentos en nube | — (CRUD) | `GET /cotizaciones/{id}/documentos` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `documentos.create` | Registrar un documento | — (CRUD) | `POST /cotizaciones/{id}/documentos` | — | ✅ | — | — | — |
| `integraciones.read` | Ver conexiones Drive / M365 | — (CRUD) | `GET /integraciones` | ✅ | — | — | — | — |
| `integraciones.manage` | Conectar y revocar | — (CRUD) | `POST/DELETE /integraciones` | ✅ | — | — | — | — |
| `usuarios.read` | Ver personas del laboratorio | — (CRUD) | `GET /usuarios` | ✅ | — | — | — | — |
| `usuarios.create` | Dar de alta | — (CRUD) | `POST /usuarios` | ✅ | — | — | — | — |
| `usuarios.update` | Editar datos | — (CRUD) | `PUT /usuarios/{id}` | ✅ | — | — | — | — |
| `usuarios.disable` | Baja lógica | — (CRUD) | `POST /usuarios/{id}/desactivar` | ✅ | — | — | — | — |
| `usuarios.assign_role` | Asignar y retirar roles | `fn_asignar_rol` *(0007)* | `PUT /usuarios/{id}/roles` | ✅ | — | — | — | — |
| `auditoria.read` | Consultar el rastro | `vw_auditoria_legible` | `GET /auditoria` | ✅ | — | — | — | — |
| `auditoria.purge` | Purgar auditoría >365 días | `fn_purgar_auditoria` | *(sin endpoint)* | — | — | — | — | — |
| `tenant.config.read` | Ver datos del laboratorio | — (CRUD) | `GET /tenant` | ✅ | — | — | — | — |
| `tenant.config.update` | Editar datos del laboratorio | — (CRUD) | `PUT /tenant` | ✅ | — | — | — | — |
| `plataforma.acceso.grant` | Conceder acceso de soporte | *(0011+)* | *(sin endpoint)* | — | — | — | — | — |

**Recuento por rol:** `admin` 13 · `comercial` 13 · `aprobador` 6 · `laboratorio` 6 ·
`lectura` 6.

Dos permisos no los tiene nadie: `auditoria.purge` y `plataforma.acceso.grant` (§8).

---

## 4. Qué puede hacer cada rol, en palabras

### `admin` — Administrador
**Administra el laboratorio, no lo opera.** Da de alta y desactiva personas, les asigna
roles, conecta Drive o M365, edita los datos del laboratorio, lee la auditoría y ve el
dashboard. Ve todo lo demás (catálogo, clientes, cotizaciones, documentos) pero **no
crea, no edita, no emite y no acredita**.

### `comercial` — Cotizador
**Es quien vende.** Crea y edita clientes, crea cotizaciones, añade ítems, aplica
descuentos, las envía a revisión, las emite, las cancela y registra la respuesta del
cliente. Consulta el catálogo y la acreditación, pero **no los modifica**. **No ve el
dashboard**: los KPIs agregados del laboratorio no son su trabajo.

### `laboratorio` — Laboratorio / Calidad *(el «técnico» del encargo)*
**Es el responsable técnico.** Define el catálogo entero —categorías, ensayos, normas,
unidades, paquetes y componentes— y es **el único** que cambia el estado de acreditación
ISO 17025. Ve cotizaciones y documentos para saber qué se está vendiendo. **No toca
clientes ni cotizaciones, y no ve el dashboard comercial.**

### `aprobador` — Aprobador
**Un solo trabajo: el visto bueno interno.** Aprueba o rechaza con motivo. Ve
cotizaciones, clientes, catálogo y documentos porque necesita contexto para decidir.
**No crea, no edita, no emite.** Y no puede aprobar lo que él mismo creó o envió: lo
impide un `CHECK`, no el backend (§5.3).

### `lectura` — Solo lectura
**Consulta y nada más.** Catálogo, acreditación, clientes, cotizaciones, documentos y
**dashboard**. Es el perfil de gerencia o contabilidad: ve los números agregados sin poder
tocar una sola fila.

---

## 5. Cómo se evita cada ataque

### 5.1 · Escalada vertical de privilegios

Tres barreras, en tres sitios distintos:

1. **El JWT no lleva permisos.** Ya implementado: `jwt.py` mantiene una lista negra
   (`roles`, `permissions`, `scope`, `plan`…) y **rechaza el token** si aparecen, aunque la
   firma sea válida. Un permiso firmado sería inmutable 15 minutos e invitaría a confiar
   sin revalidar.
2. **Los permisos se leen de la base en cada petición**, dentro de la transacción ya
   contextualizada. Retirar un rol surte efecto en la petición siguiente. Sin ventana.
3. **`rol_permisos` es GLOBAL.** Un administrador de tenant no puede crear un rol ni
   cambiar qué trae uno existente, porque `sacgeo_app` solo tendrá `SELECT` sobre esas
   tablas.

Y una cuarta para el caso plataforma: `fn_validar_scope_permiso()` impide en el motor que
un rol de scope `tenant` reciba un permiso de scope `plataforma`. No depende de FastAPI.

**Residuo asumido:** `usuarios.assign_role` permite que un administrador **se dé a sí mismo
cualquier rol de tenant**. En un laboratorio de cinco personas, segregar también la
asignación de roles no es realista. Queda auditado: cada `INSERT` en `usuario_roles`
genera su fila en `auditoria` con autor real, que 0006 ya hace infalsificable.

### 5.2 · Mass assignment

El cliente **nunca** envía `tenant_id`, `id`, `public_id`, `rol_id`, roles, permisos,
`estado`, `creado_por`, `actualizado_por`, `usuario_id` de auditoría, `numero`,
`fecha_emision`, importes, ni ningún `*_snapshot`. DTO con lista blanca por endpoint.

`rol_id` merece mención aparte: hoy es una columna ordinaria de `usuarios` con `UPDATE`
concedido a `sacgeo_app`. Un `PATCH /usuarios/{id}` que aceptara el cuerpo entero sería una
escalada en una línea (H-02). En `0007` se cierra por partida doble: la columna sale del
DTO **y** los roles pasan a `usuario_roles`, que solo se modifica por
`fn_asignar_rol()`, no por CRUD directo.

### 5.3 · Aprobación propia

**No es un permiso, es un `CHECK` de fila.** Tener `cotizaciones.approve` autoriza a
*intentar* aprobar; la base decide si es posible:

```sql
CONSTRAINT ck_aprob_no_autoaprueba CHECK (
    decidido_por IS NULL OR (decidido_por <> autor_id AND decidido_por <> solicitado_por))
```

Llega con `0010`, no con `0007`. Pero es **el motivo por el que el multi-rol es seguro**:
una persona puede ser Cotizador y Aprobador a la vez y PostgreSQL seguirá impidiéndole
aprobar lo suyo, aunque el backend falle entero.

### 5.4 · Acceso entre tenants

Ya cerrado y certificado, y `0007` no lo toca: FK compuestas (`0003`) + RLS `ENABLE` **y**
`FORCE` en 17 tablas (`0004`) + `sacgeo_app` sin `BYPASSRLS` + arranque fail-closed.
Suite 97: **40 PASS / 0 FAIL / 0 SKIP**.

`usuario_roles` entra en ese mismo régimen: `tenant_id NOT NULL`, política tenant estándar,
FK compuesta. **Un rol asignado en el laboratorio A es invisible desde el B.**

Y una regla que no se negocia: **el rol jamás entra en una política RLS.** Las políticas
solo miran `tenant_id`. Mezclar rol y tenant en la misma política es como se abren los
agujeros.

### 5.5 · Ejecutar una función sin permiso

Hoy **ninguna función de negocio consulta el rol** — verificado. La barrera es la API:
`require_permission()` antes de que el endpoint llame a la función.

`0007` **no** añade comprobación de permisos dentro de las funciones SQL, y es deliberado:
una función que consultara `usuario_roles` acoplaría el dominio a la autorización y
duplicaría la regla en dos sitios que se desincronizarían. **La autorización decide quién
puede intentar; la integridad decide qué es posible.** Lo segundo ya está en el motor
(`a_congelar`, append-only, máquina de estados, `fn_items_solo_en_borrador`) y son
prohibiciones absolutas que ningún permiso levanta.

---

## 6. H-15 — las guardas de `p_usuario`

### El problema, reproducido

Siete funciones aceptan `p_usuario` y hacen `COALESCE(p_usuario, fn_app_usuario())`:

`fn_crear_categoria` · `fn_crear_ensayo` · `fn_crear_paquete` · `fn_definir_componentes` ·
`fn_crear_cotizacion` · `fn_cambiar_acreditacion` · `fn_purgar_auditoria`

Ejecutado como `sacgeo_app` con la sesión del usuario 1:

```
fn_crear_categoria(..., p_usuario := 2)
  categorias_ensayo.creado_por = 2     ← la fila miente sobre su autor
  auditoria.usuario_id         = 1     ← 0006 lo protege
```

**0006 no lo cierra.** Protege `auditoria.usuario_id`, no `creado_por`. Lo que sí hace es
volverlo **detectable**: auditoría y fila se contradicen.

### La guarda, idéntica en las siete

```sql
IF p_usuario IS NOT NULL AND p_usuario <> fn_app_usuario() THEN
    RAISE EXCEPTION
        'La autoría no se puede atribuir a un usuario distinto del que opera la sesión '
        '(se pidió %, la sesión es %)', p_usuario, fn_app_usuario()
        USING ERRCODE = 'insufficient_privilege';
END IF;
```

Va **al principio** de cada función, antes de cualquier escritura.

**Por qué así y no de otra forma:**

| Alternativa | Por qué no |
|---|---|
| Quitar el parámetro | Cambia siete firmas. Hoy no hay llamadas que romper, pero tampoco hace falta romperlas, y `p_usuario = fn_app_usuario()` sigue siendo un uso legítimo |
| Sustituirlo por `fn_app_usuario()` sin avisar | Un fallo silencioso. Si alguien pasa un usuario ajeno, debe enterarse |
| Solo validarlo en el backend | Es la regla que H-02 y H-06 ya demostraron que no basta. La base es la última barrera |

**Efecto conocido y buscado**, ya verificado en 5B con `fn_purgar_auditoria`: pasar un
`p_usuario` ajeno falla con `42501`. Pasar `NULL` o el propio usuario sigue funcionando.

**Control nuevo para `99_verificacion.sql`** (fuera de `0007`, en la fase que toque la
suite): filas cuyo `creado_por` no coincide con el `usuario_id` de su fila de auditoría de
alta. Hoy debe dar cero; si algún día no lo da, algo escribió autoría por otra vía.

### H-13, de paso

`fn_proteger_rol_sistema()` es evadible en dos pasos: `UPDATE roles SET es_sistema = FALSE`
y después cambiar el `codigo`, porque el trigger solo mira `OLD.es_sistema AND NEW.codigo
<> OLD.codigo`. Con `rol_permisos` en pie, renombrar un código rompería la resolución de
permisos. Se cierra con una línea:

```sql
IF OLD.es_sistema AND NOT NEW.es_sistema THEN
    RAISE EXCEPTION 'Un rol del sistema no deja de serlo' USING ERRCODE = 'restrict_violation';
END IF;
```

Entra en `0007` porque es ahí donde `roles` pasa a sostener la autorización.

---

## 7. Un usuario con varios roles, paso a paso

**Caso real:** laboratorio de seis personas. Ana es la dueña: administra el sistema y
también cotiza. Beto es el responsable técnico. Carla aprueba.

```
usuario_roles
  Ana   → admin, comercial
  Beto  → laboratorio
  Carla → aprobador
```

**Los permisos son la UNIÓN de los roles.** Ana tiene los 13 de `admin` más los 13 de
`comercial`; los cinco compartidos (`catalogo.read`, `acreditacion.read`, `clientes.read`,
`cotizaciones.read`, `documentos.read`) no se suman dos veces. Resultado: 21 permisos
efectivos.

```sql
CREATE FUNCTION fn_usuario_permisos(p_usuario INTEGER)
RETURNS TABLE (codigo VARCHAR) AS $$
    SELECT DISTINCT p.codigo
      FROM usuario_roles ur
      JOIN rol_permisos rp ON rp.rol_id = ur.rol_id
      JOIN permisos p      ON p.id      = rp.permiso_id
     WHERE ur.usuario_id = p_usuario;
$$ LANGUAGE sql STABLE;
```

`DISTINCT` porque la unión de dos roles repite permisos. `STABLE` para que PostgreSQL la
cachee dentro de la sentencia.

**Qué pasa cuando Carla se va de vacaciones.** Se le añade el rol `aprobador` a Ana
temporalmente. Ana **podrá aprobar las cotizaciones de otros y no las suyas** —
`ck_aprob_no_autoaprueba` se lo impide aunque tenga los tres roles. Al volver Carla, se
retira la fila. Ambos movimientos quedan en `auditoria` con autor infalsificable.

Esto es exactamente lo que el modelo de un solo rol no podía resolver: obligaba a elegir
entre bloquear el flujo o darle `approve` al administrador de forma permanente.

**Cuando se retira un rol**, el efecto es inmediato: la consulta siguiente ya no lo
devuelve. Pero **lo que ya decidió no se reescribe**: `cotizacion_aprobaciones` es
append-only y guarda `decidido_por` como hecho consumado. Igual que el snapshot de una
cotización no cambia cuando cambia el catálogo.

---

## 8. `dashboard.read` y `auditoria.purge`

### `dashboard.read` — lo tienen `admin` y `lectura`

**Existe porque cinco de las veinte funciones de caso de uso son de dashboard** y no
tenían permiso propio. Se trataron solo como capacidad del plan PROFESIONAL, pero el
propio `SAAS_ENTITLEMENTS.md` §1 separa los dos conceptos: la **capacidad** responde
*«¿lo contrató?»* y el **permiso** *«¿le corresponde?»*.

Un laboratorio con plan profesional no quiere que su cotizador junior vea el margen
agregado, los mejores clientes ni la evolución de ventas. Por eso **`comercial` no lo
tiene**: ve sus cotizaciones, no los números del laboratorio.

Y por eso **`lectura` sí**: es el perfil de gerencia o contabilidad, cuyo trabajo es
precisamente mirar los agregados.

Los dos controles se aplican en orden y con errores distintos: sin permiso → **403**
*«no le corresponde»*; sin capacidad → **409** *«su plan no lo incluye»*. Mezclarlos
produce mensajes incomprensibles y controles de acceso que dependen de la facturación.

### `auditoria.purge` — no lo tiene nadie, a propósito

`fn_purgar_auditoria` es **la única operación destructiva del sistema**. Hoy `sacgeo_app`
no puede ejecutarla: `0004` le revocó el `EXECUTE` y solo el dueño de la base la alcanza.

Se define el permiso igualmente por dos razones: para que el catálogo describa la
operación aunque no sea alcanzable, y para que el día que alguien quiera exponerla no haya
que inventarlo con prisa y acabe colgando de `admin` «porque es el administrador».

**Queda escrito aquí que su titular vacío es intencional**, no un olvido.

`plataforma.acceso.grant` está en la misma situación: `scope = 'plataforma'`, sin rol de
tenant que lo pueda recibir, esperando al Super Admin de una fase posterior.

---

## 9. Compatibilidad

| Con | Cómo encaja |
|---|---|
| **`require_permission()`** | Factoría de dependencias que se resuelve **después** de `get_db_tx`. Lee `fn_usuario_permisos()` dentro de la transacción ya contextualizada. Caché **solo por petición** |
| **`fn_app_tenant()`** | Sin cambios. `usuario_roles` lleva la política tenant estándar y por tanto depende de él como cualquier otra tabla |
| **`fn_app_usuario()`** | Sin cambios, y es la pieza sobre la que se apoyan las guardas de H-15 |
| **RLS** | `usuario_roles` suma una tabla con RLS: pasaría de **17 a 18** con `ENABLE` + `FORCE`, y de **18 a 19** políticas. `permisos`, `roles` y `rol_permisos` quedan globales, sin RLS, con `SELECT` para `sacgeo_app` |
| **Auditoría 0006** | `usuario_roles` llevará `trg_auditar`, y `b_auditoria_autor` garantiza que el autor de cada asignación de rol es real. **Sin 0006, el rastro de quién dio qué rol sería falsificable** — por eso 0006 iba primero |
| **`b_auditoria_sello` (0005)** | `usuario_roles` es TENANT (tenant_id NOT NULL) para `fn_clasificacion_tabla`, así que su auditoría **nunca** puede marcarse como global. Las tres tablas globales seguirán produciendo `tenant_id NULL` |
| **Sesiones (0008)** | Independientes. Se pueden construir en paralelo. Retirar un rol y revocar una sesión son cosas distintas: lo primero es inmediato porque los permisos se leen en cada petición; lo segundo necesita la tabla de 0008 |

⚠ **Las suites cambian de baseline.** `99_verificacion.sql` tiene controles que cuentan
tablas y RLS; al pasar de 17 a 18 tablas protegidas habrá que revisar si alguno los lleva
escritos a fuego. **Eso se comprueba antes de ejecutar `0007`, no después**, y si hay que
tocar la 99 será con autorización aparte.

---

## 10. Contenido propuesto de 0007

| | |
|---|---|
| **Tablas** | `permisos`, `rol_permisos`, `usuario_roles` |
| **Columnas** | `roles.scope` (`tenant` / `plataforma`) |
| **Datos** | 30 permisos · rol `aprobador` · `roles.nombre` de `comercial` → «Cotizador» · la matriz del §3 · `usuario_roles` poblada desde `usuarios.rol_id` |
| **Funciones** | `fn_usuario_permisos(INTEGER)` · `fn_asignar_rol(...)` · `fn_validar_scope_permiso()` |
| **Guardas** | H-15 en las 7 funciones · H-13 en `fn_proteger_rol_sistema` |
| **RLS** | `usuario_roles` con política tenant → 18/18 ENABLE+FORCE, 19 políticas |
| **Grants** | `SELECT` sobre `permisos`, `roles`, `rol_permisos`. `usuario_roles`: `SELECT` + `INSERT`/`DELETE` (lo que ejerce `usuarios.assign_role`) |
| **Pruebas internas** | Permisos resueltos por usuario · unión correcta en multi-rol · rol de plataforma imposible en rol de tenant · `p_usuario` ajeno bloqueado en las 7 · `es_sistema` no se puede apagar |
| **Rollback** | Backup **completo** (dump + globals, §4.3 bis de `CLAUDE.md`) validado por restauración **en otro clúster** |

---

## 11. Decisiones que requieren tu aprobación

1. **¿«técnico» es `laboratorio`, o quieres partirlo en dos roles?** (§0.2). Cambia la
   matriz si la respuesta es la segunda.
2. **`admin` deja de tener `catalogo.manage`, `acreditacion.manage` y los nueve permisos
   de operación de cotizaciones.** Es el cambio más visible y el que más puede chocar con
   la expectativa de quien hoy administra. Justificación en §4 y §3.
3. **`comercial` no ve el dashboard.** Consecuencia directa de §8.
4. **30 permisos**, con dos sin titular por diseño.
5. **Guardas de H-15 dentro de `0007`**, conservando las firmas.
6. **H-13 dentro de `0007`**.
7. **Revisar `99_verificacion.sql` antes de ejecutar**, por el cambio de 17 a 18 tablas
   con RLS.

---

## 12. Riesgos del diseño

1. **`admin` pierde permisos que hoy se le suponen.** Deliberado. El multi-rol lo
   compensa: si el administrador necesita cotizar, se le añade el rol — asignación visible
   y auditada en vez de potestad escondida dentro de la palabra «administrador». El efecto
   buscado es que `if role == "admin"` **no funcione ni escribiéndolo**.
2. **`usuario_roles` con `INSERT`/`DELETE` para `sacgeo_app`** es por donde se escalaría si
   `usuarios.assign_role` se comprobara mal. Mitigado por `fn_validar_scope_permiso()` y
   por la auditoría infalsificable, pero un administrador podrá darse cualquier rol **de
   tenant**. Asumido (§5.1).
3. **30 permisos para 5 roles es mucho catálogo.** El riesgo no es el número: es la
   tentación de agrupar después con comodines. Son atómicos a propósito.
4. **`0007` es la primera migración que añade una tabla con RLS.** Toca el baseline de las
   suites, que llevan cuatro fases estable. Conviene tratarlo como el cambio de perfil que
   es, no como una migración más.

---

## 13. Deuda declarada: el diff pendiente de `99_verificacion.sql`

En la fase 5C.3 se aplicó este diff y se revirtió en 5C.4, porque **K1 referencia
`usuario_roles` dentro de SQL dinámico** y la suite dejaba de correr contra
`sacgeo_dev`, que está en `0001–0006`. Comprobado: `ERROR: relation
"usuario_roles" does not exist`, y el baseline caía de 35/37 en cero a 34/37.

**Debe aplicarse en el MISMO despliegue en que entre `0007`, no antes:**

```diff
 (I1, línea 286)
-               ('cotizacion_items'),('integraciones'),('documentos_externos'),('roles')) AS v(t)
+               ('cotizacion_items'),('integraciones'),('documentos_externos'),('roles'),
+               ('usuario_roles')) AS v(t)

 (K1, tras la línea 419)
+          UNION ALL SELECT 'usuario_roles', COUNT(*) FROM usuario_roles WHERE tenant_id IS NULL
```

Sin él, la 99 **infra-cubre en silencio**: `usuario_roles` no se comprobaría ni
por trigger de auditoría (I1) ni por filas sin tenant (K1).

## 14. Hallazgo preventivo: `plantillas_cotizacion` sin `UNIQUE (tenant_id, id)`

`0003` añadió ese UNIQUE a las **8 tablas estrictamente tenant-scoped** y excluyó
las dos híbridas, `usuarios` y `plantillas_cotizacion`. La de `usuarios` se
resuelve en `0007` porque `usuario_roles` la necesita.

La de `plantillas_cotizacion` **no se toca ahora** (decisión de la fase 5C.4):
hoy nada la referencia compositivamente. Queda anotado para que la primera
migración que intente una FK compuesta hacia ella no se estrelle con el mismo
`42830` que detuvo el primer intento de `0007`.
