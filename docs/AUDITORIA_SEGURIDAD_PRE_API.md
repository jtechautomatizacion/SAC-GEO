# SAC-GEO — Auditoría y diseño de seguridad antes de las APIs

> Fase PRE-API · 2026-09-29. **Análisis y diseño. No se implementó nada.**
>
> Cada afirmación sobre el esquema salió de consultar `sacgeo_dev` con `0001–0005`
> aplicadas, y cada afirmación sobre el backend salió de leer el código. Donde la
> documentación previa no coincide con la base, se dice y no se corrige en silencio.

---

## 0. Contradicciones entre documentación, SQL y backend

Se señalan, no se corrigen. Son cinco.

### C-1 · `SEGURIDAD_RBAC.md` dice que nada está implementado, y su §7 sí lo está

La cabecera afirma: *«Nada de este documento está implementado en la base de datos»*.
Es falso desde `0003`:

```
campos_sensibles: EXISTE
  usuarios | password_hash | 'Hash de contrasena. La auditoria es append-only…'
```

`fn_auditar()` redacta el valor **después** de calcular `campos_cambiados`, exactamente
como propone §7.3. Verificado en la fase 4B: el valor archivado es `[REDACTADO]` y hay
**0 filas** de `auditoria` con un hash Argon2id o bcrypt.

**Consecuencia:** la vulnerabilidad **V-1 (CRÍTICA)** del `MODELO_AMENAZAS.md` está
**mitigada**, no «latente». Los dos documentos siguen describiéndola como pendiente.

### C-2 · `MODELO_AMENAZAS.md` describe controles de `0004` como futuros

Marca como pendientes el rol sin `BYPASSRLS`, `FORCE ROW LEVEL SECURITY` y las vistas con
`security_invoker`. Las tres están aplicadas y certificadas (17/17 ENABLE + FORCE, 18
políticas, 97 en 40/0/0 con `sacgeo_app`).

### C-3 · El modelo de un solo rol frente al multi-rol exigido

`SEGURIDAD_RBAC.md` §3.3 recomienda **conservar un rol por usuario**, y lo argumenta:

> *«No se añade ahora porque no hay caso de uso: un usuario que fuera COTIZADOR y
> APROBADOR a la vez contradice la segregación de funciones.»*

El encargo de esta fase pide explícitamente **multi-rol**, y además que un usuario pueda
ser Cotizador + Aprobador. Es una contradicción directa con el diseño aprobado.

**No es una contradicción técnica** —el multi-rol es implementable— sino de criterio.
Se resuelve en §3 de este documento: el argumento de §3.3 confunde *tener los dos roles*
con *ejercerlos sobre el mismo documento*. Lo segundo es lo que hay que impedir, y se
impide por fila (`ck_aprob_no_autoaprueba`), no por rol.

**Recomendación: adoptar multi-rol** y marcar §3.3 como superado.

### C-4 · Inventario de usuarios desactualizado

`MODELO_AMENAZAS.md` y `SEGURIDAD_RBAC.md` dicen «los 2 usuarios actuales», todos con
`password_hash IS NULL`. Hoy `sacgeo_dev` tiene **3**, y uno de ellos
(`certificacion_4b@gtqc.local`, desactivado en la fase 4B) **sí tiene hash**. Es residuo
declarado de la certificación, no un usuario real.

### C-5 · El rol `aprobador` sigue sin existir

Los dos documentos lo dan por decidido. La base tiene cuatro roles: `admin`, `comercial`,
`laboratorio`, `lectura`. `FLUJO_APROBACION.md` depende de él por completo.

### Falso positivo descartado

`FLUJO_APROBACION.md` §3 basa la elección de nombres de estado en que
`dom_estado_cotizacion` es `VARCHAR(12)`. **Es correcto.** Una consulta con
`format_type(t.oid, t.typtypmod)` muestra `(16)` porque incluye la cabecera varlena; el
tipo base real es `character varying(12)`. El documento no se equivoca.

---

## 1. Estado real, verificado

| Capa | Qué hay |
|---|---|
| **Aislamiento** | FK compuestas (`0003`), RLS `ENABLE` **y** `FORCE` en 17/17 tablas, 18 políticas, 8 vistas con `security_invoker` |
| **Rol de conexión** | `sacgeo_app`: sin `SUPERUSER`, sin `BYPASSRLS`, 0 tablas propias, GRANTs acotados |
| **Arranque** | Fail-closed: comprueba privilegios (incluida herencia vía `pg_has_role`) y nombre del rol; aborta si algo falla |
| **Autenticación** | Argon2id, JWT con `sub`/`jti`/`iat`/`exp` y lista negra de claims de autorización, fallo de login en tiempo constante, `sistema` no autenticable |
| **Integridad** | Append-only en `auditoria`, historial de estados y de acreditación; congelado del documento emitido; correlativos atómicos |
| **Auditoría** | Actor desde el contexto, IP, campos cambiados, redacción de campos sensibles, sello de tenant coherente (`b_auditoria_sello`) |
| **Autorización** | **NO EXISTE. Ni una línea.** |

Confirmado por consulta: **ninguna función de negocio consulta `rol_id`, `roles` ni
permiso alguno.** Las únicas coincidencias son el trigger de auditoría sobre `roles` y
`fn_proteger_rol_sistema()`.

### Tablas que la documentación propone y que NO existen

`permisos` · `rol_permisos` · `usuario_roles` · `plataforma_accesos` ·
`cotizacion_aprobaciones` · `sesiones` · `sesion_tokens` · `eventos_seguridad` ·
`planes` · `plan_capacidades` · `tenant_capacidades`

Columnas que tampoco: `roles.scope`, `tenants.requiere_aprobacion`.

---

## 2. Hallazgos

Severidad según impacto sobre este producto, no según catálogo genérico.

### H-01 · No existe capa de autorización — **CRÍTICA**

| | |
|---|---|
| **Componente** | Backend (FastAPI) |
| **Evidencia** | `grep -rn "permission\|require_" backend/src/` → ninguna coincidencia funcional. `deps.py` resuelve identidad y tenant, y entrega la transacción. Nada más |
| **Impacto** | RLS impide que el tenant A vea al B. **No impide nada dentro del tenant A.** `sacgeo_app` tiene `SELECT/INSERT/UPDATE/DELETE` sobre las 14 tablas tenant-scoped |
| **Explotación** | Con `POST /cotizaciones` publicado, cualquier usuario autenticado —incluido el de rol `lectura`— crea, edita, emite y cancela cotizaciones de su laboratorio. El rol no se consulta en ninguna parte |
| **Mitigación** | Tablas `permisos`/`rol_permisos`/`usuario_roles` + `require_permission()` como dependencia de FastAPI |
| **SQL** | Sí · **Backend** Sí · **Frontend** No |
| **¿Antes de las APIs?** | **Sí. Es el bloqueo principal** |
| **Prueba** | `usuario sin permiso → 403` y `usuario con permiso → 200`, por cada permiso |

### H-02 · Escalada vertical por mass assignment sobre `usuarios` — **CRÍTICA**

| | |
|---|---|
| **Componente** | Backend + BD |
| **Evidencia** | `sacgeo_app` tiene `INSERT, SELECT, UPDATE` sobre `usuarios`. `rol_id INTEGER NOT NULL` es una columna ordinaria sin trigger que la proteja |
| **Impacto** | Un `PATCH /usuarios/{public_id}` que acepte el cuerpo entero permite a un usuario fijarse `rol_id = 1` (admin). Con `tenant_id` en el cuerpo, la política `WITH CHECK` lo frena; con `rol_id`, **nada lo frena** |
| **Explotación** | `PATCH /usuarios/<mi-public-id>` con `{"rol_id": 1}` |
| **Mitigación** | DTO con lista blanca **y** —defensa en profundidad— trigger que exija que el cambio de `rol_id` venga de `fn_asignar_rol()`, igual que la acreditación |
| **SQL** | Sí (recomendado) · **Backend** Sí · **Frontend** No |
| **¿Antes de las APIs?** | **Sí** |
| **Prueba** | Enviar `rol_id`, `tenant_id`, `id`, `public_id`, `creado_por`, `activo` en el cuerpo y verificar que se ignoran o se rechazan |

### H-03 · La acreditación ISO 17025 no tiene control de acceso — **ALTA**

| | |
|---|---|
| **Componente** | BD + Backend |
| **Evidencia** | `fn_cambiar_acreditacion()` es ejecutable por `sacgeo_app` y no consulta el rol. Ninguna función lo hace |
| **Impacto** | El activo regulatorio del producto. `CLAUDE.md` §9: *«es lo que les permite cobrar más y lo primero que les revisa un auditor»*. Cualquier usuario autenticado puede marcar un ensayo como acreditado |
| **Explotación** | Un comercial marca acreditados los ensayos que no lo están para cobrar más. Queda en la auditoría, pero nadie lo impide |
| **Mitigación** | Permiso `acreditacion.manage`, exclusivo de `laboratorio` y `admin` |
| **¿Antes de las APIs?** | **Sí**, en cuanto exista el endpoint de catálogo |

### H-04 · No hay segregación de funciones: quien cotiza, emite — **ALTA**

| | |
|---|---|
| **Componente** | BD |
| **Evidencia** | `fn_transicion_estado_valida`: `borrador → emitida` directo. No existen `en_revision` ni `aprobada`, ni `cotizacion_aprobaciones` |
| **Impacto** | Ningún segundo par de ojos antes de que el documento salga del laboratorio. Sin control interno sobre precios y descuentos |
| **Mitigación** | `FLUJO_APROBACION.md` completo: dos estados, tabla append-only, `ck_aprob_no_autoaprueba`, trigger de puerta |
| **¿Antes de las APIs?** | **No para el primer endpoint de lectura. Sí antes de `POST /cotizaciones/{id}/emitir`** |

### H-05 · Una sesión no se puede revocar — **ALTA**

| | |
|---|---|
| **Componente** | Backend + BD |
| **Evidencia** | No existen `sesiones` ni `sesion_tokens`. `refresh.py` se niega a emitir refresh tokens por falta de persistencia — decisión correcta |
| **Impacto** | Un access token robado es válido hasta 15 minutos y **no hay forma de cortarlo** salvo desactivar al usuario entero. No hay logout real: el cliente olvida el token, el servidor no se entera |
| **Atenuante verificado** | Desactivar a un usuario **sí** surte efecto inmediato: `fn_sesion_resolver_usuario` devuelve `activo` y `resolver_sesion()` lanza en cada petición |
| **Mitigación** | Tabla de sesiones con familia de refresh, rotación y detección de reuso |
| **¿Antes de las APIs?** | **Recomendado sí.** Sin ella la sesión útil dura 15 minutos y el producto es inusable |

### H-06 · La auditoría es forjable por el backend — **ALTA**

| | |
|---|---|
| **Componente** | BD |
| **Evidencia** | Reproducido como `sacgeo_app` con contexto de tenant 1: `INSERT INTO auditoria (…, usuario_id) VALUES (…, 2, …)` **tuvo éxito**. `b_auditoria_sello` solo comprueba la coherencia del `tenant_id` |
| **Impacto** | `MODELO_AMENAZAS.md` §1 identifica `auditoria` como **el activo crítico**: *«si es alterable, todo lo demás pierde valor probatorio»*. No se puede borrar ni modificar, pero **sí se pueden inyectar filas falsas** atribuidas a otro usuario |
| **Explotación** | Un backend comprometido, o un endpoint con una inyección, escribe rastro falso para encubrir o incriminar |
| **Mitigación** | Extender `b_auditoria_sello` para exigir `NEW.usuario_id = fn_app_usuario()`. Coste: una comparación. Cierra la repudiación por el lado del backend |
| **¿Antes de las APIs?** | **Sí.** Es barato y el activo es el más valioso |

### H-07 · `/docs`, `/redoc` y `/openapi.json` expuestos sin condición — **MEDIA**

| | |
|---|---|
| **Componente** | Backend |
| **Evidencia** | `main.py`: `FastAPI(title=…, version=…, lifespan=…)`. Sin `docs_url=None` ni `openapi_url=None` |
| **Impacto** | En producción publica el mapa completo de la API a cualquiera. Hoy es inofensivo (3 endpoints); deja de serlo con los de negocio |
| **Mitigación** | Condicionar a `settings.es_desarrollo`, como ya se hace con `/salud/rol` |
| **¿Antes de las APIs?** | Sí, es una línea |

### H-08 · Sin límite de intentos en `/auth/login` — **MEDIA**

| | |
|---|---|
| **Componente** | Backend / Infra |
| **Evidencia** | No hay `slowapi` ni middleware de límite. `grep` sobre `backend/src/` y `pyproject.toml`: ninguno |
| **Impacto** | Fuerza bruta sin freno. Y Argon2id es caro a propósito, así que el propio login es un vector de DoS: unas decenas de peticiones concurrentes saturan CPU |
| **Mitigación** | Límite por IP y por cuenta. El de cuenta **no** debe permitir que un tercero deje fuera a un usuario legítimo |
| **¿Antes de las APIs?** | Sí para `/auth/login`; el resto puede esperar a Nginx |

### H-09 · Mapeo de errores incompleto — **MEDIA**

| | |
|---|---|
| **Componente** | Backend |
| **Evidencia** | `errors.py` mapea 6 SQLSTATE. Los que el esquema realmente lanza son: `23001`, `23514`, `42501`, `22023` (`invalid_parameter_value`), `P0002`. **`22023` no está mapeado** → cae en el 500 genérico |
| **Dato útil** | **0 funciones lanzan `RAISE` sin `ERRCODE`**, así que `P0001` no ocurre nunca. El mapeo puede ser exhaustivo |
| **Impacto** | Errores de negocio legítimos se presentan como fallo interno. Confunde al cliente y ensucia los logs de error reales |
| **¿Antes de las APIs?** | Sí |

### H-10 · No hay `eventos_seguridad` — **MEDIA**

Login correcto y fallido, logout, acceso denegado e intento cross-tenant no dejan rastro
en ninguna parte. `fn_auditar()` es un trigger de tabla: sin fila, no hay auditoría.
Confirmado: `auth.py` registra `log.info("login fallido")` sin usuario, en un log rotativo.

### H-11 · La contraseña real del clúster de desarrollo está versionada — **MEDIA**

| | |
|---|---|
| **Evidencia** | `backend/.env.example`, líneas `DATABASE_URL` y `TEST_DATABASE_URL`: contienen la credencial que **funciona** contra `sac-geo-postgres-dev` |
| **Impacto** | Limitado a desarrollo, pero establece el hábito. Un `.env.example` debe llevar placeholders, como ya hace con `JWT_SECRET` |
| **Acción** | Sustituir por `CAMBIAR_ESTE_VALOR` y rotar la del contenedor |

*No se imprime el valor en este documento.*

### H-12 · PDFs reales del cliente versionados — **MEDIA**

`insumos/` contiene **3 presupuestos reales de GTQC** con nombres de obra y cliente
(`ALDEM S.A.C.`, `BOTADERO-CERRO DE PASCO`), **rastreados por Git**. Son datos
comerciales de un cliente real en el historial del repositorio. Decidir si se conservan
(y con qué control de acceso al repo) o se mueven fuera.

### H-13 · `a_proteger` sigue siendo evadible en dos pasos — **BAJA**

Confirmado sin cambios desde la fase 3E:

```sql
IF OLD.es_sistema AND NEW.codigo <> OLD.codigo THEN RAISE …
```

`UPDATE roles SET es_sistema = FALSE` y después cambiar el `codigo`. Con `rol_permisos`
en pie, renombrar un código rompería la resolución de permisos. Se cierra añadiendo
`IF OLD.es_sistema AND NOT NEW.es_sistema THEN RAISE`.

### H-14 · Sin cabeceras de seguridad ni política de CORS — **BAJA hoy**

No hay `CORSMiddleware`, lo que significa que **hoy el navegador bloquea cualquier origen
cruzado**: el estado por omisión es restrictivo, que es el correcto. El riesgo es futuro:
añadir `allow_origins=["*"]` junto a `allow_credentials=True` —combinación que el propio
estándar prohíbe y que los frameworks aceptan en silencio—. Faltan también
`X-Content-Type-Options`, `Referrer-Policy` y HSTS, que corresponden a Nginx.

---

## 3. RBAC propuesto

### 3.1 Multi-rol: se adopta, y por qué el argumento en contra no se sostiene

`SEGURIDAD_RBAC.md` §3.3 rechaza el multi-rol porque *«un usuario que fuera COTIZADOR y
APROBADOR a la vez contradice la segregación de funciones»*.

**Confunde dos cosas.** La segregación no exige que una persona no tenga ambas
capacidades; exige que no las ejerza **sobre el mismo documento**. Un laboratorio de
cinco personas no puede permitirse una persona por función, y el propio
`FLUJO_APROBACION.md` §10.2 reconoce el problema («si el único aprobador está de
vacaciones, el flujo se detiene»).

La regla correcta es de fila, no de rol, y ya está diseñada:

```sql
CONSTRAINT ck_aprob_no_autoaprueba CHECK (
    decidido_por IS NULL OR (decidido_por <> autor_id AND decidido_por <> solicitado_por))
```

Con eso, dar los dos roles a la misma persona es seguro: podrá aprobar las cotizaciones
de sus compañeros y **PostgreSQL le impedirá aprobar las suyas**, aunque el backend falle.

Añadido: el multi-rol resuelve el caso real de la suplencia sin inventar un rol
«aprobador de respaldo», y hace innecesaria la decisión pendiente de §5.1 de
`SEGURIDAD_RBAC.md` («¿el administrador puede aprobar?»): se le da también el rol
`aprobador` a quien haga falta, cuando haga falta, y queda auditado.

### 3.2 Modelo

```
usuarios ──< usuario_roles >── roles ──< rol_permisos >── permisos
```

- `usuario_roles` — **TENANT-SCOPED**. La asignación pertenece al laboratorio.
- `roles`, `permisos`, `rol_permisos` — **GLOBAL**. El catálogo lo controla el producto;
  es lo que impide la escalada por composición (V-2 del modelo de amenazas).
- `usuarios.rol_id` se **conserva** durante la transición como «rol principal» y se
  retira en una migración posterior, cuando nada lo lea.

### 3.3 Los cinco roles

| `codigo` | `nombre` | Estado |
|---|---|---|
| `admin` | Administrador | existe |
| `comercial` | **Cotizador** (solo cambia `nombre`) | existe |
| `aprobador` | Aprobador | **nuevo** |
| `laboratorio` | Laboratorio / Calidad | existe |
| `lectura` | Solo lectura | existe |

Ningún `codigo` cambia — `a_proteger` lo impide y además rompería `rol_permisos`.

### 3.4 Permisos — 26, derivados de las operaciones que existen

Cada permiso corresponde a una función de caso de uso real de `01_functions.sql` o a una
operación que el flujo de aprobación introduce. No se inventan para llenar la tabla.

| Permiso | Operación que lo justifica |
|---|---|
| `catalogo.read` | `fn_dashboard_*`, lectura del catálogo |
| `catalogo.manage` | `fn_crear_categoria`, `fn_crear_ensayo`, `fn_crear_paquete`, `fn_definir_componentes` |
| `acreditacion.read` | `fn_acreditado_en_fecha` |
| `acreditacion.manage` | `fn_cambiar_acreditacion` |
| `clientes.read` | `empresas`, `contactos`, `personas` |
| `clientes.manage` | alta y edición de las tres |
| `cotizaciones.read` | lectura y `vw_cotizacion_pdf` |
| `cotizaciones.create` | `fn_crear_cotizacion` |
| `cotizaciones.update` | `fn_agregar_item`, `fn_recalcular_cotizacion` |
| `cotizaciones.submit` | `fn_enviar_a_revision` *(futura)* |
| `cotizaciones.approve` | `fn_decidir_aprobacion` *(futura)* |
| `cotizaciones.reject` | idem |
| `cotizaciones.emit` | `fn_cambiar_estado_cotizacion(→ emitida)` |
| `cotizaciones.cancel` | `fn_cambiar_estado_cotizacion(→ cancelada)` |
| `cotizaciones.close` | `→ aceptada` / `→ rechazada`: **respuesta del cliente**, no aprobación interna |
| `documentos.read` / `documentos.create` | `documentos_externos` |
| `integraciones.read` / `integraciones.manage` | `integraciones` |
| `usuarios.read` / `usuarios.create` / `usuarios.update` / `usuarios.disable` / `usuarios.assign_role` | gestión de personas |
| `auditoria.read` | `vw_auditoria_legible` |
| `tenant.config.read` / `tenant.config.update` | datos del laboratorio |
| `plataforma.acceso.grant` | `scope = 'plataforma'` |

**`cotizaciones.close` es un permiso nuevo respecto al diseño previo.** `aceptada` y
`rechazada` son la respuesta del **cliente** al documento entregado, no un visto bueno
interno: registrarlas es trabajo comercial, no de aprobación. Confundirlo con
`cotizaciones.approve` mezcla dos actos distintos en el mismo permiso.

### 3.5 Matriz ROL × PERMISO

| Permiso | `admin` | `comercial` | `aprobador` | `laboratorio` | `lectura` |
|---|:--:|:--:|:--:|:--:|:--:|
| `catalogo.read` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `catalogo.manage` | ✅ | — | — | ✅ | — |
| `acreditacion.read` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `acreditacion.manage` | — | — | — | ✅ | — |
| `clientes.read` | ✅ | ✅ | ✅ | — | ✅ |
| `clientes.manage` | ✅ | ✅ | — | — | — |
| `cotizaciones.read` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `cotizaciones.create` | — | ✅ | — | — | — |
| `cotizaciones.update` | — | ✅ | — | — | — |
| `cotizaciones.submit` | — | ✅ | — | — | — |
| `cotizaciones.approve` | — | — | ✅ | — | — |
| `cotizaciones.reject` | — | — | ✅ | — | — |
| `cotizaciones.emit` | — | ✅ | — | — | — |
| `cotizaciones.cancel` | ✅ | ✅ | — | — | — |
| `cotizaciones.close` | ✅ | ✅ | — | — | — |
| `documentos.read` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `documentos.create` | ✅ | ✅ | — | — | — |
| `integraciones.read` | ✅ | — | — | — | — |
| `integraciones.manage` | ✅ | — | — | — | — |
| `usuarios.read` | ✅ | — | — | — | — |
| `usuarios.create` | ✅ | — | — | — | — |
| `usuarios.update` | ✅ | — | — | — | — |
| `usuarios.disable` | ✅ | — | — | — | — |
| `usuarios.assign_role` | ✅ | — | — | — | — |
| `auditoria.read` | ✅ | — | — | — | — |
| `tenant.config.read` | ✅ | — | — | — | — |
| `tenant.config.update` | ✅ | — | — | — | — |
| `plataforma.acceso.grant` | — | — | — | — | — |

**Tres decisiones que se apartan del diseño previo, y el porqué:**

1. **`admin` NO recibe `acreditacion.manage`.** El diseño previo se lo daba. Es el
   conflicto de interés que §2.1 de `SEGURIDAD_RBAC.md` identifica correctamente y
   después contradice en su propia matriz. Quien administra usuarios y configuración no
   debería decidir qué ensayos están acreditados ante un auditor ISO 17025. Si un
   administrador necesita hacerlo, **se le añade el rol `laboratorio`** — que es
   precisamente lo que el multi-rol permite, y queda auditado.

2. **`admin` NO recibe `cotizaciones.create/update/emit`.** Mismo criterio: administrar
   no es vender. Si hace falta, se añade el rol `comercial`.

3. **`admin` NO recibe `cotizaciones.approve`.** Resuelve la decisión pendiente de §5.1:
   ya no hay que elegir entre comodidad y segregación. Quien deba aprobar recibe el rol
   `aprobador`, y `ck_aprob_no_autoaprueba` sigue impidiéndole aprobar lo suyo.

El efecto es que `admin` deja de ser un comodín. **`if role == "admin"` no funcionaría ni
aunque alguien lo escribiera**, que es justo lo que se pedía.

### 3.6 Lo que ningún permiso concede

Prohibiciones absolutas del motor, verificadas: nadie modifica ni borra `auditoria` (salvo
`fn_purgar_auditoria` con >365 días); nadie edita una cotización emitida; nadie cambia la
acreditación por `UPDATE` directo; nadie borra cotizaciones ni usuarios; nadie salta la
máquina de estados. **Ni siquiera el Super Admin por la API.**

---

## 4. Segregación de funciones — reparto por capa

| Garantía | Capa | Mecanismo |
|---|---|---|
| Solo un `aprobador` decide | **API** | `require_permission("cotizaciones.approve")` |
| Nadie aprueba lo que creó o envió | **BD** | `ck_aprob_no_autoaprueba` (CHECK de fila) |
| La copia de `autor_id` es verdadera | **BD** | Trigger de validación al insertar |
| Un rechazo lleva motivo | **BD** | `ck_aprob_rechazo_motivado` |
| No se salta el flujo | **BD** | Trigger de puerta + bloqueo del `UPDATE` directo |
| No se edita durante la revisión | **BD** | `a_congelar` y `fn_items_solo_en_borrador`, **que ya sirven sin tocarlas** |
| El aprobador es del mismo tenant | **BD** | FK compuesta `(tenant_id, cotizacion_id)` |
| El intento denegado deja rastro | **API** | `eventos_seguridad` |

### Preguntas del encargo, respondidas

- **¿Un usuario puede ser Cotizador + Aprobador?** Sí, y es el caso normal en un
  laboratorio pequeño.
- **¿Puede aprobar una cotización que él mismo creó?** **No.** Lo impide un `CHECK`, no el
  backend. Tampoco puede aprobar una que él envió a revisión.
- **¿Un administrador puede aprobar?** Solo si además tiene el rol `aprobador`. No por ser
  administrador.
- **¿Qué pasa si pierde un rol?** Deja de poder ejercerlo desde la petición siguiente: los
  permisos se resuelven contra la base en cada petición, no desde el token.
- **¿Y las aprobaciones históricas?** Intactas. `cotizacion_aprobaciones` es append-only y
  guarda `decidido_por` como hecho consumado. Quitarle el rol a alguien no reescribe lo
  que decidió — igual que el snapshot de una cotización no cambia cuando cambia el
  catálogo.

---

## 5. Sesiones y refresh tokens

El diseño previo (7 días absolutos, refresh que **no** extiende, access de 15 minutos,
rotación, reuso ⇒ revocar familia, hash del refresh) **sigue siendo compatible**. Dos
precisiones obligadas por `0004`:

1. **`sesiones` y `sesion_tokens` son TENANT-SCOPED**, con `tenant_id NOT NULL`, `UNIQUE
   (tenant_id, id)` y FK compuestas — como toda tabla de negocio desde `0003`.
2. **Su RLS no puede ser la política estándar.** El refresh llega **antes** de conocer el
   tenant: misma circularidad que el login. Se resuelve con el patrón ya auditado de
   `0004` — una función `SECURITY DEFINER` propiedad de `sacgeo_auth`,
   `fn_sesion_por_refresh(hash)`, que devuelve lo mínimo (`sesion_id`, `usuario_id`,
   `tenant_id`, `estado`) y **nunca** el hash ni el token.

**Discrepancia que no resuelvo sola:** el diseño previo hablaba de la migración `0005`,
que ya existe y está aplicada con otro contenido. La numeración se replantea en §9.

---

## 6. Eventos de seguridad

**No es auditoría de datos.** `auditoria` responde *«quién cambió esta fila»* y la escribe
un trigger. `eventos_seguridad` responde *«qué intentó esta persona»* y la escribe la
aplicación, incluso cuando **no hay fila que cambiar** — que es exactamente el hueco.

| Evento | Persistir | Motivo |
|---|---|---|
| `login.ok`, `login.fallido` | Sí | Detección de fuerza bruta y de acceso indebido |
| `logout`, `sesion.expirada`, `sesion.revocada` | Sí | Ciclo de vida de la sesión |
| `refresh.ok`, `refresh.rechazado`, `refresh.reuso` | Sí | **`refresh.reuso` es señal de token robado** |
| `permiso.denegado` | Sí | Un usuario que tantea permisos que no tiene |
| `tenant.cruzado` | Sí | Intento de acceso a otro laboratorio: **la señal más grave** |
| `usuario.desactivado`, `password.cambiada`, `roles.cambiados` | Sí | Ya dejan rastro en `auditoria`; aquí se correlacionan con la sesión |
| Lectura ordinaria | **No** | Volumen sin valor |

**Campos:** `id`, `tenant_id` (nullable — un login fallido puede no tener tenant),
`usuario_public_id` (nullable), `tipo`, `resultado`, `motivo`, `ip_origen`, `user_agent`
(truncado), `correlacion` (el mismo `ref` que devuelve `errors.py`), `ocurrido_en`.

**Nunca:** contraseña, JWT completo, refresh token, `password_hash`, secretos. Del token
se guarda como mucho el `jti`, que es un identificador sin valor por sí solo.

Append-only como `auditoria`, con retención propia y más corta.

---

## 7. Autorización en FastAPI

```
Request
  └─ get_sesion()          JWT → fn_sesion_resolver_usuario() → (usuario_id, tenant_id)
       └─ get_db_tx()      BEGIN + set_config ×3            ← existe
            └─ get_current_user()                            ← existe
                 └─ get_permisos()   SELECT contra rol_permisos, DENTRO de la transacción
                      └─ require_permission("x.y")           ← NUEVO
                           └─ endpoint
```

- `require_permission(...)` es una **factoría de dependencias**, no un decorador: así
  FastAPI la resuelve en la misma cadena y el permiso aparece en el OpenAPI.
- Los permisos se leen **dentro de la transacción ya contextualizada**, en una sola
  consulta cacheada por petición. Nunca del token.
- `require_any_permission` / `require_all_permissions` sobre la misma base.
- Las comprobaciones que dependen del **dato** (¿es mía esta cotización? ¿está en
  borrador?) no son permisos: van en el servicio de dominio y, cuando son invariantes,
  en el motor.
- Los **entitlements** (¿queda cupo?) son una comprobación **distinta** y con error
  distinto: permiso denegado → `403`; cupo agotado → `409` con mensaje de plan.

**Nunca se acepta del cliente:** `tenant_id`, rol, permisos, `created_by`, `updated_by`,
`usuario_id` de auditoría, `estado` arbitrario, `id` técnico.

---

## 8. Mass assignment

Leyenda: **C** el cliente puede enviarlo · **S** lo calcula el servidor · **B** lo calcula
la base · **✗** prohibido.

### `usuarios`
| Campo | | Nota |
|---|:--:|---|
| `nombres`, `apellidos`, `email` | C | |
| `password` (en claro, solo alta/cambio) | C | Nunca se almacena |
| `rol_id` / roles | **✗** | Solo vía `usuarios.assign_role` y endpoint propio |
| `activo`, `desactivado_en`, `desactivado_por` | **✗** | Solo vía `usuarios.disable` |
| `id`, `public_id`, `tenant_id`, `password_hash` | **✗** | |
| `creado_por`, `actualizado_por`, `ultimo_acceso_en` | S | Del contexto |

### `cotizaciones`
| Campo | | Nota |
|---|:--:|---|
| `empresa_id`/`contacto_id`/`persona_id`, `proyecto_nombre`, `validez_dias`, `plantilla_id`, `moneda`, `notas` | C | Los ids como `public_id`, traducidos en el servidor |
| `descuento_tipo`, `descuento_valor`, `descuento_razon` | C | Sujeto a `cotizaciones.update` |
| `subtotal`, `igv`, `igv_tasa`, `descuento_monto`, `total` | **B** | `fn_recalcular_cotizacion` |
| `numero`, `fecha_emision` | **B** | Al emitir. El número no se reutiliza jamás |
| `estado` | **✗** | Solo por `fn_cambiar_estado_cotizacion` |
| `id`, `public_id`, `tenant_id`, `creado_por`, `actualizado_por` | **✗** / S | |

### `cotizacion_items`
`ensayo_id` (por `public_id`) y `cantidad` son del cliente. **Los 8 campos `*_snapshot`,
`subtotal`, `precio_unitario` y `categoria_id` los calcula la base**: son la foto
congelada de lo que se cotizó y el cliente no tiene voz en ella.

### `empresas`, `contactos`, `personas`
Datos de negocio del cliente; `id`/`public_id`/`tenant_id`/`creado_por`/`actualizado_por`
prohibidos o del servidor.

### `documentos_externos`
`tipo_documento`, `nombre_archivo` del cliente. `hash_sha256` y `subido_por` del servidor.
`url_externo` **validado** contra el proveedor de la integración, nunca aceptado tal cual.

### `integraciones`
`proveedor`, `cuenta_email` del cliente. **`token_ref` jamás llega del cliente**: lo emite
el vault. `estado`, `conectado_por`, `revocado_en` del servidor.

---

## 9. Migraciones propuestas — cuatro, no una

`0005` ya está ocupada. La numeración correcta arranca en **`0006`**, y el diseño previo
que la llamaba `0005` debe leerse desplazado.

| # | Nombre | Propósito | Depende de |
|---|---|---|---|
| **0006** | `rbac_permisos_y_multirol` | `permisos`, `rol_permisos`, `usuario_roles`, `roles.scope`, rol `aprobador`, `fn_validar_scope_permiso`, `fn_usuario_permisos()`. Endurecer `b_auditoria_sello` con `usuario_id = fn_app_usuario()` (H-06) y cerrar H-13 | 0005 |
| **0007** | `sesiones_y_refresh` | `sesiones`, `sesion_tokens`, `fn_sesion_por_refresh` (SECURITY DEFINER, `sacgeo_auth`), rotación y detección de reuso | 0006 |
| **0008** | `eventos_seguridad` | Tabla append-only + política RLS híbrida (`tenant_id` nullable) | 0007 |
| **0009** | `flujo_aprobacion` | Estados `en_revision`/`aprobada`, `cotizacion_aprobaciones`, `tenants.requiere_aprobacion`, las dos funciones puerta | 0006 |

**Se separan a propósito.** Cada una tiene su propio backup, su propia certificación y su
propio rollback. Meterlas juntas haría que un fallo en el flujo de aprobación obligara a
revertir el RBAC.

Entitlements (`planes`, `plan_capacidades`, `tenant_capacidades`) quedan para después del
primer endpoint: no bloquean nada y su diseño depende de decisiones comerciales abiertas.

Cada una con el procedimiento ya probado tres veces: precheck con SHA, backup **validado
por restauración**, transacción única, validaciones internas, `schema_migrations`, y
certificación con 97 (`sacgeo_app`, 0 FAIL / 0 SKIP), 98 (71/0/0) y 99 (37 / 0 ERROR).

⚠ **Recordatorio operativo:** `0004` solo puede aplicarse una vez por clúster
(`sacgeo_auth` no puede preexistir y los roles son del clúster). Toda base desechable
nueva exige un contenedor nuevo.

---

## 10. Contrato de API

- **Versionado en la ruta:** `/api/v1`. El router actual monta `/auth` en la raíz: hay que
  moverlo antes de publicar nada.
- **Error estándar:** `{"error": "<mensaje público>", "ref": "<correlación>"}`. Ya lo hace
  `errors.py`; se extiende con `codigo` legible por máquina para el frontend.
- **Colección:** `{"items": [...], "total": n, "limit": l, "offset": o}`. `limit` por
  omisión 50, **máximo 200** — la paginación obligatoria es también un control de DoS
  (§D del modelo de amenazas).
- **Filtros y orden:** lista blanca por endpoint. Nunca un campo de ordenación que venga
  del cliente sin validar.
- **Identificadores:** solo `public_id` sale y entra. El `id` técnico no aparece en
  ninguna respuesta.

### Mapeo de errores

| SQLSTATE / caso | HTTP | Mensaje |
|---|---|---|
| Sin token / token inválido o expirado | **401** | `no autenticado` |
| Permiso insuficiente | **403** | `acceso no autorizado` |
| Recurso de otro tenant, o inexistente | **404** | `no encontrado` — **nunca 403** |
| `23505` unique | 409 | `ya existe un registro equivalente` |
| `23503` FK | 409 | `referencia inválida` |
| `23001` restrict | 422 | `la operación no está permitida en este estado` |
| `23514` check | 422 | `la operación no cumple una regla del sistema` |
| `23502` not null · `22001` truncamiento · `22P02` · **`22023`** | 422 | `datos inválidos` |
| `P0002` no_data_found | 404 | `no encontrado` |
| **`42501`** | **500** | Bug nuestro: falta contexto de tenant. **Nunca 403** |
| Cupo de plan agotado | 409 | `límite del plan alcanzado` |

`42501` como 500 es deliberado y ya está implementado: con RLS bien puesta, ese código
solo aparece si el backend abrió una transacción sin contexto. Devolverlo como 403 lo
convertiría en ruido.

**Nunca al cliente:** SQL, nombres de tabla o función, stack trace, `password_hash`,
detalles de funciones `SECURITY DEFINER`, credenciales, DSN.

---

## 11. IDOR

La regla ya está escrita en `CLAUDE.md` §5 y se cumple: el `id` técnico no sale, el
`public_id` (UUID) sí. **Pero un UUID no es autorización.** La protección real son tres
capas:

1. **Contexto de tenant** fijado en la transacción,
2. **RLS**, que hace que la fila ajena literalmente no exista para esa sesión,
3. **Permiso**, que decide si puede operar sobre la que sí ve.

Por eso el `404` no es una ficción defensiva: es la respuesta verdadera.

**Pruebas obligatorias por cada endpoint con `{public_id}`:** tenant A → recurso A (200) ·
tenant A → recurso B (**404**) · tenant B → recurso A (**404**) · usuario sin permiso →
recurso propio (**403**) · usuario con permiso → recurso propio (200) · `id` técnico en la
ruta (**404/422**, jamás resuelto).

---

## 12. Rate limiting

**Seguridad de aplicación** (lo que debe existir antes de exponer la API):

| Endpoint | Límite sugerido |
|---|---|
| `POST /auth/login` | 5/min por IP · 10/hora por cuenta, con backoff |
| `POST /auth/refresh` | 30/min por sesión |
| Búsquedas y listados | Paginación obligatoria con tope 200 |
| Generación de PDF | 1 concurrente por usuario |

En FastAPI basta `slowapi` con almacenamiento en memoria para un proceso; en cuanto haya
más de uno hace falta Redis. **Protección de infraestructura** (Nginx): límite de tamaño
de cuerpo, `limit_req` de borde, timeouts, y `statement_timeout` en PostgreSQL.

El bloqueo por cuenta **no debe permitir que un tercero deje fuera a un usuario legítimo**:
se implementa como retardo creciente, no como bloqueo duro.

---

## 13. Tests de seguridad

| # | Prueba | Estado |
|---|---|---|
| 1 | Sin autenticación → 401 | **EXISTE** |
| 2 | JWT inválido → 401 | **EXISTE** |
| 3 | JWT expirado → 401 | **EXISTE** |
| 4 | Usuario desactivado → 401 | **EXISTE** |
| 5 | Sesión revocada | **PENDIENTE** (no hay sesiones) |
| 6-7 | Refresh usado dos veces / reuso | **PENDIENTE** |
| 8 | Tenant A → tenant B | **EXISTE** (backend y 97) |
| 9-10 | Usuario sin/con permiso | **PENDIENTE** |
| 11 | Cambio de rol surte efecto | **PENDIENTE** |
| 12-15 | Mass assignment: `tenant_id`, rol, `id` técnico | **PENDIENTE** |
| 16 | `public_id` ajeno → 404 | **PENDIENTE** |
| 17 | `42501` no llega como 403 | **PARCIAL** (implementado, sin test) |
| 18 | Errores sin fuga | **PARCIAL** |
| 19 | `password_hash` nunca aparece | **EXISTE** (BD y respuesta) |
| 20-21 | JWT / refresh nunca en logs | **PARCIAL** (existe para contraseña y DSN) |
| 22 | `SECURITY DEFINER` no ejecutable por `PUBLIC` | **EXISTE** (0004, validación 6.x) |
| 23-24 | El pool no conserva tenant ni usuario | **EXISTE** (5B) |
| 25 | RLS sigue con FORCE | **EXISTE** (97 y arranque fail-closed) |

**11 existen, 3 parciales, 11 pendientes.** Las 11 pendientes son todas de autorización,
sesiones y mass assignment — es decir, de lo que esta fase propone construir.

---

## 14. Orden de implementación

| Fase | Contenido | Depende de | GO si |
|---|---|---|---|
| **P1** | `0006` RBAC + multi-rol + endurecer auditoría (H-06) y `a_proteger` (H-13) | 0005 | 97/98/99 verdes · permisos resueltos por usuario · rol de plataforma imposible en rol de tenant |
| **P2** | `require_permission()` y resolución de permisos en FastAPI | P1 | Tests 9, 10, 11 en verde · ningún `if role ==` en el código |
| **P3** | `0007` sesiones + refresh con rotación y detección de reuso | P1 | Tests 5, 6, 7 en verde · reuso revoca la familia |
| **P4** | `0008` `eventos_seguridad` + escritura desde la API | P3 | Login, denegación y cross-tenant dejan rastro sin secretos |
| **P5** | Contrato: `/api/v1`, errores completos, paginación, DTO con lista blanca, `/docs` condicionado, rate limit en login | P2 | Tests 12-18 en verde |
| **P6** | **Primer endpoint de negocio** (lectura: `GET /api/v1/empresas`) | P5 | Las 6 pruebas de IDOR del §11 en verde |
| **P7** | `0009` flujo de aprobación | P1, P6 | Ningún usuario aprueba lo suyo, con el backend desactivado |

**P1 y P3 son independientes entre sí** y pueden ir en paralelo si hay dos personas. Todo
lo demás es secuencial.

El flujo de aprobación (**P7**) va **después** del primer endpoint a propósito: es la
pieza más grande y no bloquea la lectura. Pero debe estar **antes** de publicar
`POST /cotizaciones/{id}/emitir`.

---

## 15. Decisiones que requieren aprobación

1. **Multi-rol** frente al modelo de un rol de `SEGURIDAD_RBAC.md` §3.3. Recomiendo
   multi-rol (§3.1).
2. **`admin` deja de poder gestionar acreditación, cotizar y aprobar.** Es el cambio de
   criterio más visible: hoy la expectativa es que el administrador lo pueda todo.
3. **`cotizaciones.close` como permiso separado** de `approve`.
4. **¿La aprobación es por tenant o por monto?** Pendiente desde `FLUJO_APROBACION.md`
   §10.1.
5. **¿Quién da de alta usuarios?** Super Admin, o administrador con tope.
6. **`insumos/`** — 3 PDFs reales de GTQC versionados (H-12).
7. **Rotar la credencial de desarrollo** que está en `.env.example` (H-11).
8. **M-07 — descuento después del IGV.** Sigue abierta y bloquea todo lo relativo a
   importes.
