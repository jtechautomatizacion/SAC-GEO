# SAC-GEO — Autorización, roles y permisos

> Estado: **diseño**. Fases 3D y 3E. Última revisión: 2026-09-28.
> Nada de este documento está implementado en la base de datos.
>
> Cada afirmación sobre el esquema salió de consultar la base restaurada, no de la
> documentación. Donde el modelo actual no soporta algo, se dice.

---

## 1. Qué existe hoy (CONFIRMADO)

### 1.1 `roles` — cuatro etiquetas, cero permisos

```
id | codigo      | nombre        | es_sistema
 1 | admin       | Administrador | t
 2 | comercial   | Comercial     | t
 3 | laboratorio | Laboratorio   | t
 4 | lectura     | Solo lectura  | t
```

Cinco columnas. **Ninguna otorga un permiso.** `descripcion` es prosa para pantalla.

El trigger `a_proteger` impide **eliminar** un rol con `es_sistema = TRUE` y **cambiarle el
`codigo`**. Sí permite cambiar `nombre` y `descripcion`, y sí permite crear roles nuevos.

### 1.2 `usuarios` — un rol por usuario

`rol_id INTEGER NOT NULL REFERENCES roles(id)`. No hay tabla puente. La restricción a un
solo rol no está documentada en ningún sitio: es la consecuencia de que la columna sea
escalar.

Además: `password_hash` **nullable** y `NULL` en los 2 usuarios actuales; `activo` con
baja lógica; `uq_usuarios_email` **global**, sobre `lower(email)`; trigger `a_no_delete`.

### 1.3 Lo que NO existe

Inventario de las 19 tablas: no hay `permisos`, `rol_permisos`, `usuario_roles`,
`roles.scope` ni tabla de plataforma.

### 1.4 Ninguna función evalúa el rol

Busqué `rol_id`, `roles`, `permiso` y `autoriz` en las 42 funciones y 41 triggers. Las
únicas coincidencias son el trigger de auditoría sobre `roles` y `fn_proteger_rol_sistema()`.

**Cero funciones de negocio consultan el rol.** `fn_cambiar_estado_cotizacion()` acepta
cualquier transición válida de cualquier usuario.

### 1.5 El mockup no conoce los roles

Busqué `rol`, `permiso`, `admin`, `comercial`, `laboratorio` y `lectura` en
`app/gtqc_sistema_unificado_v2.html`. **No hay login, ni usuario, ni rol, ni cambio de
perfil.** Las coincidencias con "Admin" son nombres de pantallas de administración
(`renderCatalogoAdmin`, `renderPlantillasAdmin`), no roles.

Dato relevante para la decisión de §2: **los 4 roles son una decisión tomada solo en la
base, sin contraparte en la interfaz.** No hay compromiso de producto que defender ni
usuarios acostumbrados a ellos.

---

## 2. Resolución de los roles (TAREA 2)

No decidí por nombres. Partí de **qué operaciones existen realmente** en el dominio,
listando las funciones de caso de uso de `01_functions.sql`:

| Familia de operaciones | Funciones |
|---|---|
| **Cotización** | `fn_crear_cotizacion`, `fn_agregar_item`, `fn_recalcular_cotizacion`, `fn_cambiar_estado_cotizacion` |
| **Catálogo** | `fn_crear_categoria`, `fn_crear_ensayo`, `fn_crear_paquete`, `fn_definir_componentes` |
| **Acreditación ISO 17025** | `fn_cambiar_acreditacion`, `fn_acreditado_en_fecha` |
| **Consulta** | `fn_dashboard_kpis`, `fn_dashboard_por_categoria`, `fn_dashboard_top_clientes`, `fn_dashboard_evolucion`, `fn_dashboard_ensayos_top` |
| **Administración** | `fn_purgar_auditoria` |

Son **cinco familias separables**, y encajan con los 4 roles existentes más el que falta.

### 2.1 `laboratorio` — SE CONSERVA. Es el hallazgo de esta fase

**No es una etiqueta redundante.** Corresponde a la operación más protegida de todo el
esquema: la acreditación ISO 17025.

Evidencia:
- Solo se puede cambiar por `fn_cambiar_acreditacion()`. Un `UPDATE` directo está
  **bloqueado por trigger** (verificado: `98_pruebas.sql`, `23001`).
- Su historial es append-only y las cotizaciones congelan el estado de acreditación del
  día en que se emitieron.
- `CLAUDE.md`: *"es lo que les permite cobrar más y lo primero que les revisa un auditor"*.

**Fusionarlo con COTIZADOR sería un defecto de control interno**, no una simplificación:
el rol que vende decidiría qué ensayos están acreditados, que es justo el conflicto de
interés que la norma busca evitar. Un auditor ISO 17025 lo señalaría.

> **PROPUESTO** — conservar, renombrando `nombre` a "Laboratorio / Calidad" para que se
> entienda que es el responsable técnico, no "cualquiera del laboratorio".

### 2.2 `lectura` — SE CONSERVA, con menor convicción

Cinco funciones de dashboard justifican un perfil de solo consulta (gerencia,
contabilidad, un cliente interno). En un modelo RBAC es simplemente "el conjunto de
permisos de lectura", y cuesta una fila.

> **PROPUESTO** — conservar. Es el candidato a eliminar si se quiere un catálogo más
> corto; no rompe nada quitarlo, pero tampoco cuesta nada mantenerlo.

### 2.3 `comercial` → COTIZADOR: cambiar el nombre, **no** el código

El producto quiere que se llame COTIZADOR. `a_proteger` bloquea cambiar el `codigo` de un
rol de sistema, pero **no bloquea cambiar `nombre`**.

Y el `codigo` no se le muestra nunca a nadie: es el identificador que usarán
`rol_permisos` y el backend. Por tanto:

```sql
UPDATE roles SET nombre = 'Cotizador' WHERE codigo = 'comercial';
```

Coste cero, riesgo cero, y el producto obtiene el nombre que quiere.

> **Nota de seguridad, al margen:** `a_proteger` es evadible en dos pasos — primero
> `UPDATE roles SET es_sistema = FALSE`, después cambiar el `codigo`, porque el trigger
> solo mira `OLD.es_sistema AND NEW.codigo <> OLD.codigo`. Severidad **BAJA** (requiere ya
> tener escritura sobre `roles`, que será permiso de plataforma), pero conviene saberlo.
> Mitigación si se quiere cerrar: añadir `IF OLD.es_sistema AND NOT NEW.es_sistema THEN
> RAISE`. No es urgente.

### 2.4 `aprobador` — ROL NUEVO

No existe y hace falta para el flujo de `FLUJO_APROBACION.md`. Se crea con
`es_sistema = TRUE`, código `aprobador`.

### 2.5 Recomendación: **variante de la opción B, con 5 roles**

| # | `codigo` | `nombre` propuesto | Origen | Estado |
|---|---|---|---|---|
| 1 | `admin` | Administrador | existente | **CONFIRMADO** que existe |
| 2 | `comercial` | **Cotizador** | existente, renombrado | **PROPUESTO** |
| 3 | `aprobador` | Aprobador | **nuevo** | **PROPUESTO** |
| 4 | `laboratorio` | Laboratorio / Calidad | existente | **PROPUESTO** conservar |
| 5 | `lectura` | Solo lectura | existente | **PROPUESTO** conservar |

Ningún rol se elimina. Ninguno se renombra de `codigo`. Se añade uno.

> **DECISIÓN DEL PRODUCT OWNER** — la opción A (3 roles) exige decidir quién gestiona la
> acreditación ISO 17025 si desaparece `laboratorio`. Mi recomendación es que no
> desaparezca, por §2.1.

---

## 3. Modelo RBAC propuesto (TAREA 3)

### 3.1 Tres tablas nuevas, ninguna existente destruida

```sql
-- [GLOBAL] Catálogo de acciones del producto.
CREATE TABLE permisos (
    id          INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    codigo      VARCHAR(40)  NOT NULL,          -- 'cotizaciones.approve'
    descripcion VARCHAR(200) NOT NULL,
    scope       VARCHAR(12)  NOT NULL DEFAULT 'tenant',
    CONSTRAINT uq_permisos_codigo UNIQUE (codigo),
    CONSTRAINT ck_permisos_codigo CHECK (codigo ~ '^[a-z_]+\.[a-z_]+$'),
    CONSTRAINT ck_permisos_scope  CHECK (scope IN ('tenant','plataforma'))
);

-- [GLOBAL] Qué trae cada rol del producto.
CREATE TABLE rol_permisos (
    rol_id     INTEGER NOT NULL REFERENCES roles(id)    ON DELETE CASCADE,
    permiso_id INTEGER NOT NULL REFERENCES permisos(id) ON DELETE RESTRICT,
    PRIMARY KEY (rol_id, permiso_id)
);

ALTER TABLE roles ADD COLUMN scope VARCHAR(12) NOT NULL DEFAULT 'tenant'
    CONSTRAINT ck_roles_scope CHECK (scope IN ('tenant','plataforma'));
```

### 3.2 La restricción que impide la escalada por composición

```sql
-- Un rol de tenant NO puede contener un permiso de plataforma.
CREATE OR REPLACE FUNCTION fn_validar_scope_permiso() RETURNS TRIGGER AS $$
DECLARE v_rol VARCHAR(12); v_perm VARCHAR(12);
BEGIN
    SELECT scope INTO v_rol  FROM roles    WHERE id = NEW.rol_id;
    SELECT scope INTO v_perm FROM permisos WHERE id = NEW.permiso_id;
    IF v_perm = 'plataforma' AND v_rol <> 'plataforma' THEN
        RAISE EXCEPTION 'Un rol de tenant no puede recibir el permiso de plataforma %',
            (SELECT codigo FROM permisos WHERE id = NEW.permiso_id)
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
```

Esto responde directamente a *"no permitas que un cliente cree un rol que accidentalmente
tenga permisos de plataforma"*. **No depende de FastAPI**: es imposible en el motor.

### 3.3 `usuarios.rol_id` se conserva

Un rol por usuario cubre los cinco roles sin ambigüedad. **Cómo ampliar a multi-rol
después sin romper nada:**

1. Crear `usuario_roles (usuario_id, rol_id)` y poblarla desde `usuarios.rol_id`.
2. Sustituir la resolución de permisos por la unión sobre esa tabla.
3. Mantener `usuarios.rol_id` como "rol principal" (para mostrar) o retirarlo en una
   migración posterior.

Los tres pasos son aditivos. **No se añade ahora porque no hay caso de uso**: un usuario
que fuera COTIZADOR y APROBADOR a la vez contradice la segregación de funciones.

### 3.4 ¿Roles globales o creados por tenant?

**Recomendación: GLOBALES, del producto.**

| | Roles globales | Roles por tenant |
|---|---|---|
| Riesgo de escalada | Bajo — el catálogo lo controla el producto | **Alto** — un administrador podría fabricarse un rol con permisos que no le tocan |
| Soporte | Un solo modelo que entender | Cada cliente configurado distinto |
| Coherencia con el esquema | `skills/multi-tenant/SKILL.md` ya clasifica `roles` como GLOBAL | Contradice esa decisión |
| Flexibilidad | Menor | Mayor |

Si en el futuro un laboratorio necesita un rol propio, se resuelve con una tabla
`roles_tenant` **aparte**, con la misma validación de scope y sin poder otorgar permisos
que su creador no tenga. No duplicando los básicos por cliente.

---

## 4. Super Admin — reevaluación (TAREA 4)

La fase 3D propuso el modelo de concesiones. Lo evalué contra los ocho criterios pedidos
en lugar de darlo por bueno.

| Criterio | Valoración |
|---|---|
| **Seguridad** | Alta. El rol por sí solo no abre nada; hace falta concesión activa |
| **Complejidad** | Media. Una tabla y una comprobación. No es trivial, pero tampoco un subsistema |
| **Compatibilidad con RLS** | **Excelente, y es el argumento decisivo.** El super admin fija `app.tenant_id` como cualquiera; las políticas siguen siendo `tenant_id = fn_app_tenant()`, sin caso especial. **No evade RLS: la usa.** Un modelo que exigiera excepciones en cada política sería mucho más frágil |
| **Compatibilidad con FastAPI** | Buena. Una comprobación más en la resolución del tenant |
| **Auditoría** | Excelente. `auditoria.tenant_id` lleva el tenant concreto, no `NULL`, así que la acción aparece en el rastro **del laboratorio afectado** |
| **Riesgo de escalada** | Bajo. Ampliar el alcance exige insertar en `plataforma_accesos`, que es auditable |
| **Riesgo de token robado** | **Aquí está el valor real.** Un token de super admin robado solo sirve donde haya concesión vigente, y las concesiones caducan solas. Sin este modelo, ese token es acceso permanente a todos los laboratorios |
| **Operación** | Aceptable. Añade un paso ("conceder acceso al tenant X por el motivo Y"), y ese paso **es** el control |

**Se confirma el modelo.** Con una corrección de la fase 3D:

### 4.1 `sistema` y Super Admin deben separarse

La fase 3D los dejaba conviviendo bajo `tenant_id IS NULL`. Es un error: son cosas
distintas y mezclarlas repite el problema que se quería evitar.

| | `sistema` (id 1) | Super Admin |
|---|---|---|
| Qué es | Un **autor de registros**. Fallback de `fn_app_usuario()` | Una **identidad humana** de plataforma |
| ¿Inicia sesión? | **Nunca**. `password_hash IS NULL` | Sí |
| `tenant_id` | `NULL` | `NULL` |
| Cómo se distinguen | `roles.scope = 'tenant'` (`rol_id = 1`) | `roles.scope = 'plataforma'` |
| Qué le concede el `NULL` | **Nada** | **Nada** |

La regla que lo hace explícito: **`tenant_id IS NULL` significa "no pertenece a ningún
laboratorio". No significa "puede entrar en todos".** Lo que concede acceso es
`plataforma_accesos`, y solo a lo concedido.

`0003` ya reserva ese `NULL` con un índice único (§7), de modo que hoy solo `sistema` lo
tiene y añadir otro exige una migración revisable.

### 4.2 La tabla

```sql
CREATE TABLE plataforma_accesos (
    id            INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    usuario_id    INTEGER      NOT NULL REFERENCES usuarios(id),
    tenant_id     INTEGER      NOT NULL REFERENCES tenants(id),
    motivo        VARCHAR(300) NOT NULL CHECK (btrim(motivo) <> ''),
    otorgado_por  INTEGER      NOT NULL REFERENCES usuarios(id),
    desde         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    hasta         TIMESTAMPTZ  NOT NULL,
    revocado_en   TIMESTAMPTZ,
    CONSTRAINT ck_plat_vigencia CHECK (hasta > desde),
    CONSTRAINT ck_plat_no_autoconcesion CHECK (otorgado_por <> usuario_id)
);
```

`ck_plat_no_autoconcesion` es el equivalente de la segregación: un super admin no se
concede acceso a sí mismo. Como en el flujo de aprobación, es un `CHECK` de fila, no una
regla que el backend deba recordar.

`hasta` es `NOT NULL`: **toda concesión caduca**. Un acceso perpetuo es indistinguible de
no tener control.

---

## 5. Matriz de permisos (TAREA 3 y 7)

Mínimo viable: **22 permisos**. No se inventan permisos para llenar la tabla; cada uno
corresponde a una operación que existe o que el flujo de aprobación introduce.

Los roles se nombran por su `codigo` de base.

| Permiso | Super Admin | `admin` | `comercial` (Cotizador) | `aprobador` | `laboratorio` | `lectura` | Estado |
|---|---|---|---|---|---|---|---|
| `cotizaciones.read` | tenant concedido | ✅ | ✅ | ✅ | ✅ | ✅ | PROPUESTO |
| `cotizaciones.create` | — | ✅ | ✅ | — | — | — | PROPUESTO |
| `cotizaciones.update` | — | ✅ | ✅ | — | — | — | PROPUESTO |
| `cotizaciones.submit` | — | ✅ | ✅ | — | — | — | PROPUESTO |
| `cotizaciones.approve` | — | ver §5.1 | **—** | ✅ | — | — | PROPUESTO |
| `cotizaciones.reject` | — | ver §5.1 | **—** | ✅ | — | — | PROPUESTO |
| `cotizaciones.emit` | — | ✅ | ✅ | — | — | — | PROPUESTO |
| `cotizaciones.cancel` | — | ✅ | ✅ | — | — | — | PROPUESTO |
| `clientes.read` | tenant concedido | ✅ | ✅ | ✅ | ✅ | ✅ | PROPUESTO |
| `clientes.manage` | — | ✅ | ✅ | — | — | — | PROPUESTO |
| `catalogo.read` | tenant concedido | ✅ | ✅ | ✅ | ✅ | ✅ | PROPUESTO |
| `catalogo.manage` | — | ✅ | — | — | — | — | PROPUESTO |
| `acreditacion.manage` | — | ✅ | **—** | — | **✅** | — | PROPUESTO |
| `usuarios.read` | ✅ | ✅ | — | — | — | — | PROPUESTO |
| `usuarios.create` | ✅ | ver §5.2 | — | — | — | — | **PENDIENTE** |
| `usuarios.update` | ✅ | ✅ | — | — | — | — | PROPUESTO |
| `usuarios.disable` | ✅ | ✅ | — | — | — | — | PROPUESTO |
| `usuarios.assign_role` | ✅ | ✅ (solo `scope='tenant'`) | — | — | — | — | PROPUESTO |
| `auditoria.read` | ✅ | ✅ | — | — | — | — | PROPUESTO |
| `tenant.config.read` | ✅ | ✅ | — | — | — | — | PROPUESTO |
| `tenant.config.update` | ✅ | ✅ | — | — | — | — | PROPUESTO |
| `plataforma.acceso.grant` | ✅ | **—** | — | — | — | — | PROPUESTO (`scope='plataforma'`) |

**Lo que la base ya garantiza sin permiso alguno — CONFIRMADO:**

| Regla | Mecanismo |
|---|---|
| Nadie modifica `auditoria` | Append-only (`23001`) |
| Nadie la borra salvo `fn_purgar_auditoria()` con >365 días | Verificado |
| Nadie edita una cotización emitida | `a_congelar` |
| Nadie cambia la acreditación por `UPDATE` | Trigger |
| Nadie borra cotizaciones ni usuarios | `a_no_delete` |

Son prohibiciones **absolutas**: ni siquiera el Super Admin las evade por la API.

### 5.1 ¿El administrador puede aprobar?

`ck_aprob_no_autoaprueba` le impediría aprobar lo suyo en cualquier caso. Concedérselo
resuelve el laboratorio pequeño con un solo aprobador; no concedérselo mantiene la
segregación más limpia. **DECISIÓN DEL PRODUCT OWNER.**

### 5.2 ¿Quién crea usuarios?

El requerimiento dice que el Super Admin crea los usuarios de cada cliente, y también que
el Administrador administra usuarios del tenant. Son dos modelos:

- **(a)** solo el Super Admin da de alta; el Administrador edita y desactiva;
- **(b)** el Administrador da de alta hasta un tope que fija el Super Admin.

**(b)** encaja mejor con *"la cantidad real de usuarios será una capacidad
administrable"*. **DECISIÓN DEL PRODUCT OWNER.**

---

## 6. Autorización centralizada

```python
require_permission("cotizaciones.approve")
```

El backend comprueba, en este orden: identidad → usuario activo → tenant → rol →
permiso → recurso → estado de la operación. Si el recurso es de otro tenant, **`404`**,
no `403`.

**Prohibido** `if user.role == "admin"` disperso. Y el permiso nunca se consulta desde una
política RLS: **el rol jamás entra en una política.** Las políticas solo miran
`tenant_id`. Mezclar rol y tenant en la misma política es como se abren los agujeros.

### 6.1 Reglas que no son un permiso

Dependen del dato, no del rol, y por eso viven además en el motor:

- el aprobador no puede ser el autor → `ck_aprob_no_autoaprueba`;
- una cotización emitida no se edita → `a_congelar`;
- los ítems solo se tocan en borrador → `fn_items_solo_en_borrador`.

**La autorización decide quién puede intentar; la integridad decide qué es posible.** No
se sustituyen.

---

## 7. Auditoría segura y campos sensibles (TAREA 6)

### 7.1 La vulnerabilidad — CRÍTICA

`fn_auditar()` hace `to_jsonb(NEW)` sobre la fila **entera**. Lo verifiqué ejecutándolo:
puse un hash Argon2id simulado en un usuario y quedó guardado en
`auditoria.datos_nuevos->>'password_hash'`.

| | |
|---|---|
| **Severidad** | **CRÍTICA** |
| **Impacto** | Los hashes de contraseña de todos los usuarios quedan copiados en una tabla **append-only**, imposible de limpiar. Quien obtenga lectura de `auditoria` obtiene material para ataque offline, incluidas contraseñas ya rotadas |
| **Probabilidad** | **Certeza**, en el instante en que se habilite el login |
| **Capa afectada** | PostgreSQL (`fn_auditar`) |
| **Estado hoy** | Latente: los 2 usuarios tienen `password_hash IS NULL` |

### 7.2 La solución: catálogo de campos sensibles, no un parche

```sql
-- [GLOBAL] Campos que la auditoría registra como cambiados pero NUNCA almacena.
CREATE TABLE campos_sensibles (
    tabla   VARCHAR(63) NOT NULL,
    columna VARCHAR(63) NOT NULL,
    motivo  VARCHAR(200) NOT NULL,
    PRIMARY KEY (tabla, columna)
);

INSERT INTO campos_sensibles VALUES
    ('usuarios', 'password_hash', 'Hash de contraseña: nunca se archiva');
```

Y en `fn_auditar()`, **redacción en lugar de supresión**:

```sql
-- 1) Los campos cambiados se calculan con los valores REALES.
IF TG_OP = 'UPDATE' THEN
    SELECT array_agg(k ORDER BY k) INTO v_campos
    FROM jsonb_object_keys(v_new) AS k
    WHERE v_old -> k IS DISTINCT FROM v_new -> k;
    ...
END IF;

-- 2) Y SOLO DESPUÉS se redactan los valores.
FOR v_col IN SELECT columna FROM campos_sensibles WHERE tabla = TG_TABLE_NAME LOOP
    IF v_new ? v_col THEN v_new := jsonb_set(v_new, ARRAY[v_col], '"[REDACTADO]"'); END IF;
    IF v_old ? v_col THEN v_old := jsonb_set(v_old, ARRAY[v_col], '"[REDACTADO]"'); END IF;
END LOOP;
```

### 7.3 El orden importa, y es la parte que se puede equivocar

**Redactar antes de calcular `campos_cambiados` haría invisible el cambio de contraseña.**
Ambos valores pasarían a ser `"[REDACTADO]"`, serían iguales, el campo no aparecería como
cambiado, y —peor— `fn_auditar()` tiene una salida anticipada cuando solo cambiaron
`actualizado_en`/`actualizado_por`: un cambio de contraseña podría **no generar fila de
auditoría en absoluto**.

Calcular primero y redactar después conserva la trazabilidad (*"password_hash cambió"*) y
descarta el secreto. Es exactamente lo que se pedía.

### 7.4 Por qué una tabla y no una lista en el código

- Es **consultable**: se puede responder "¿qué campos no se archivan?" con un `SELECT`.
- Es **auditable**: `campos_sensibles` lleva su propio `trg_auditar`, así que quitar una
  protección deja rastro.
- Es **extensible sin tocar la función**: añadir un campo sensible es un `INSERT`.

Coste: una lectura pequeña e indexada por fila auditada. Se mitiga envolviendo la consulta
en una función `STABLE`, que PostgreSQL cachea dentro de la sentencia.

### 7.5 Campos sensibles previstos

| Tabla | Columna | Cuándo |
|---|---|---|
| `usuarios` | `password_hash` | Al habilitar login |
| `usuarios` | `mfa_secret` | Si se añade segundo factor |
| `usuarios` | `token_recuperacion` | Si se añade recuperación de contraseña |
| `integraciones` | `token_ref` | **Evaluar.** Es una referencia a vault, no el token; el control `J1` de `99_verificacion.sql` ya vigila que no degenere en un token real |
| *(sesiones)* | `refresh_token_hash` | Si se persisten sesiones |

### 7.6 ¿Entra en `0003`? — Sí, y es la recomendación

| A favor | En contra |
|---|---|
| `0003` **ya reemplaza `fn_auditar()`**: no añade rotación de función | `campos_sensibles` es estructura ajena a la multitenencia |
| Una vez el hash entra en `auditoria`, **no sale**: es append-only | La vulnerabilidad no se activa hasta que exista login |
| El invariante *"la auditoría nunca guarda secretos"* debería ser cierto desde el primer día | |

**Recomiendo incluirlo en `0003`.** El argumento decisivo es la irreversibilidad: el coste
de adelantarlo es una tabla de dos columnas; el de retrasarlo y olvidarlo es permanente.

> **DECISIÓN DEL PRODUCT OWNER** — cambia lo que registra la auditoría, y eso tiene
> implicaciones de cumplimiento. No lo aplico sin tu visto bueno.

---

## 8. Alcance (scope)

| Identidad | Scope | Cómo se determina |
|---|---|---|
| Super Admin | `PLATAFORMA` | `roles.scope='plataforma'` + concesión vigente en `plataforma_accesos` |
| `admin`, `comercial`, `aprobador`, `laboratorio`, `lectura` | `TENANT` | `usuarios.tenant_id` |
| `sistema` (id 1) | **ninguno** | Autor de registros. No inicia sesión |

---

## 9. Reparto por capa

| Responsabilidad | Capa |
|---|---|
| Quién es el usuario | FastAPI |
| A qué tenant pertenece | FastAPI, **desde la sesión**. Jamás del cliente |
| Qué permisos tiene | FastAPI, contra `rol_permisos` |
| Que un rol de tenant no reciba permisos de plataforma | **BD** (`fn_validar_scope_permiso`) |
| Que nadie apruebe lo suyo | **BD** (`ck_aprob_no_autoaprueba`) |
| Que no vea otro tenant | **BD**: FK compuestas (`0003`) + RLS (`0004`) |
| Que no altere la auditoría | **BD**, ya implementado |
| Que la auditoría no archive secretos | **BD** (`campos_sensibles`) |
| Ocultar botones | Flutter — comodidad, **nunca** control |
