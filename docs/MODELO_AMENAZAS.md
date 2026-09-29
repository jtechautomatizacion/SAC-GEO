# SAC-GEO — Modelo de amenazas

> Fase 3D · 2026-09-28. Marco: STRIDE, con referencias a OWASP Top 10 y ASVS.
> Alcance: qué amenaza es real **en SAC-GEO**, no un catálogo genérico.
>
> Estado de cada control: **YA** (implementado y verificado) · **0003** · **0004** ·
> **API** (FastAPI, fase 5/6) · **UI** (Flutter) · **INFRA** (Nginx/Docker/VPS) ·
> **OP** (procedimiento humano).

---

## 1. Qué protegemos

| Activo | Por qué importa | Impacto si se filtra |
|---|---|---|
| Catálogo y precios de un laboratorio | Es su estructura comercial completa | Un competidor conoce sus márgenes |
| Cotizaciones emitidas | Documento con valor comercial y legal | Fuga de cartera de clientes y precios pactados |
| Estado de acreditación ISO 17025 | Determina qué puede cobrar más y qué revisa un auditor | Pérdida de confianza regulatoria |
| `auditoria` | Es la prueba ante un auditor | Si es alterable, **todo lo demás pierde valor probatorio** |
| Credenciales de usuarios | Acceso al sistema | Suplantación |
| `integraciones.token_ref` | Apunta al vault de Drive/M365 | Acceso a los documentos del laboratorio |

El activo crítico no es obvio: es **`auditoria`**. Si un atacante puede borrar su rastro,
ningún otro control se puede verificar después.

---

## 2. Superficies y actores

```
Flutter Web/PWA ──HTTPS──► Nginx ──► FastAPI ──► PostgreSQL
                                        │
                                        └──► Vault / Drive / M365
```

| Actor hostil | Capacidad de partida | Qué busca |
|---|---|---|
| **A1** Usuario legítimo del tenant A | Sesión válida, rol `comercial` | Ver datos del tenant B; elevar su propio rol |
| **A2** Ex-empleado desactivado | Token todavía no expirado | Seguir entrando |
| **A3** Atacante sin cuenta | Solo la superficie HTTP | Credenciales, enumeración, IDOR |
| **A4** Super admin comprometido | Identidad de plataforma | Todos los tenants |
| **A5** Operador con acceso al VPS | Shell / `psql` | Todo, incluida la auditoría |
| **A6** Tenant hostil | Es cliente de pago, conoce el producto | Datos de la competencia alojada en el mismo SaaS |

**A6 es el modelo de amenaza que define este producto.** Los laboratorios de ensayos en
Perú compiten entre sí; alojar a dos en la misma base hace del aislamiento un requisito
de negocio, no una buena práctica.

---

## 3. STRIDE

### S — Suplantación (Spoofing)

| Amenaza | Control | Capa |
|---|---|---|
| Credenciales débiles o reutilizadas | Argon2id; `usuarios.password_hash` nunca guarda la contraseña | API |
| Hoy `password_hash` es **nullable** y los 2 usuarios lo tienen en `NULL` | Al habilitar login, ningún usuario activo puede quedar sin hash. Requiere `CHECK` o validación de alta | **API** + revisar en 0004+ |
| Fuerza bruta | Límite por IP y por cuenta, backoff, bloqueo temporal | API + INFRA |
| Token robado (A2, A4) | Vida corta, `jti` revocable, invalidación al desactivar usuario | API |
| El usuario `sistema` (id 1) tiene rol `admin` | No puede autenticarse (`password_hash NULL`). **Debe seguir sin poder**; prueba J | YA / OP |

### T — Manipulación (Tampering)

| Amenaza | Control | Capa |
|---|---|---|
| Alterar una cotización emitida | Trigger `a_congelar`: solo estado, notas y auditoría | **YA** |
| Reescribir el historial de estados o de acreditación | Append-only por trigger | **YA** |
| **Borrar o editar `auditoria`** | Append-only; `DELETE` solo vía `fn_purgar_auditoria()` con >365 días y constancia | **YA** |
| Renumerar una cotización | Bloqueado por trigger | **YA** |
| Mass assignment: enviar `tenant_id`, `rol_id`, `estado`, `creado_por` en el cuerpo del request | Esquemas de entrada con lista blanca. Nunca `Model(**request.json())` | **API** |
| Saltarse la máquina de estados con un `UPDATE` directo | Bloqueado por trigger | **YA** |
| SQL injection | `psycopg` con parámetros. Prohibido componer SQL por concatenación | API |

Las seis primeras filas ya están cerradas **en el motor**, y eso es lo que las hace
valer: siguen en pie aunque el backend tenga un fallo.

### R — Repudio

| Amenaza | Control | Capa |
|---|---|---|
| "Yo no cambié ese precio" | `auditoria` guarda actor, IP, campos, antes y después | **YA** |
| Auditoría atribuida al usuario equivocado | El autor sale de `fn_app_usuario()` (contexto), no de la fila | **YA** |
| Backend que no fija el contexto ⇒ todo a nombre de `sistema` | Control `I2` de `99_verificacion.sql` lo cuenta; debe tender a cero | **YA** (detección) / API (causa) |
| Acción de super admin sin rastro del tenant afectado | Decisión A: `auditoria.tenant_id` lleva el tenant concreto sobre el que operó | **0003** |
| Falta rastro de eventos sin fila: login, logout, login fallido, cambio de contraseña | **No cubierto.** `fn_auditar()` es un trigger de tabla: si no hay `INSERT/UPDATE/DELETE`, no hay auditoría | **Pendiente** — ver §5 |

### I — Divulgación (Information disclosure)

| Amenaza | Control | Capa |
|---|---|---|
| **Tenant A lee datos de tenant B** | FK compuestas (`0003`) + RLS (`0004`) + filtro explícito en la API | 0003 / 0004 / API |
| Vista que atraviesa el aislamiento | Las 8 recreadas con `security_invoker = true` | **0003** |
| IDOR: `/cotizaciones/8` | La API expone `public_id` (UUID), y **aun así** toda consulta lleva `AND tenant_id = <sesión>` | API |
| Recurso ajeno responde `403` y confirma que existe | Responder **`404`** | API |
| Mensajes de error con SQL, nombres de tabla o *stack trace* | Error genérico al cliente; detalle solo al log | API |
| PDF accesible por URL adivinable | Ruta con tenant + URL firmada y caducable, verificando pertenencia | API + INFRA |
| Caché compartida entre tenants | Toda clave de caché lleva el tenant | API |
| Log con filas completas de cliente | Registrar identificadores, nunca el contenido | API + OP |
| Respaldo sin cifrar o accesible | Cifrado en reposo, acceso restringido | INFRA + OP |
| `.env` versionado | Verificado: no está en git; solo `.env.example` | **YA** |
| Token real en `integraciones.token_ref` | Control `J1` de `99_verificacion.sql` lo detecta; el campo es una referencia a vault | **YA** |

### D — Denegación de servicio

| Amenaza | Control | Capa |
|---|---|---|
| Un tenant agota CPU o conexiones de todos | Límites por tenant, *pool* acotado, *statement_timeout* | INFRA + API |
| Consultas sin filtro sobre tablas grandes | Índices con `tenant_id` al frente (`0003`) + paginación obligatoria | 0003 + API |
| Subida de archivos sin tope | Tamaño máximo y cuota por tenant | API + INFRA |
| Fuerza bruta como DoS de cuenta | El bloqueo no debe permitir que un tercero deje fuera a un usuario legítimo | API |

### E — Elevación de privilegios

| Amenaza | Control | Capa |
|---|---|---|
| **Horizontal** — usuario del tenant A actúa sobre el tenant B | El tenant sale de la sesión autenticada, **nunca** del request | API + 0004 |
| El cliente envía `tenant_id = 99` | Se ignora. No es un dato, es una petición de acceso | API |
| **Vertical** — un `comercial` se asigna rol `admin` | `usuarios.assign_role` es permiso de administrador; además un administrador solo asigna roles con `scope = 'tenant'` | API (pendiente) |
| Crear un usuario global (`tenant_id NULL`) y volverse visible en todos los tenants | Accidental: cerrado en 3C con `DEFAULT fn_app_tenant()`. Deliberado: **índice único que reserva el `NULL`** | **0003** |
| Super admin usado como "administrador de todos los tenants" | Concesión explícita, acotada en el tiempo y auditada (`plataforma_accesos`) | Pendiente (post-0004) |
| Cotizador aprueba su propia cotización | **No implementable hoy**: no existe estado de aprobación | Ver `SEGURIDAD_RBAC.md` §C-2 |
| Backend conecta como dueño de las tablas ⇒ RLS no se aplica | Rol `sacgeo_app` sin `BYPASSRLS` y sin ser dueño, más `FORCE ROW LEVEL SECURITY` | **0004** |

---

## 4. Las cinco amenazas que más importan aquí

Ordenadas por impacto real sobre este producto, no por frecuencia genérica.

**1 · Fuga entre tenants por consulta sin filtro (A6).** Es la que mata el producto
comercialmente. Defensa en tres capas: la API filtra, RLS respalda, y las FK compuestas
hacen el cruce imposible aunque las dos anteriores fallen. Las FK ya están escritas en
`0003` y verificadas; RLS llega en `0004`.

**2 · Backend que conecta como dueño de las tablas.** Silenciosa y total: RLS queda
activa, las políticas existen, y **no se aplican ninguna**. `97_aislamiento.sql` lo
detecta explícitamente y se niega a dar PASS con `sacgeo_dev`.

**3 · Manipulación de la auditoría.** Ya cerrada en el motor, y hay que mantenerla
cerrada: ninguna migración futura debe quitar el `trg_append_only` "temporalmente" sin
volver a encenderlo. `0003` lo apaga durante el relleno y lo reenciende en la misma
transacción — es el patrón correcto, y debe seguir siéndolo.

**4 · Super admin sin alcance acotado.** Hoy no existe; el riesgo es introducirlo mal.
La opción A del requerimiento (`tenant_id NULL` = todo) produciría exactamente eso.

**5 · Mass assignment sobre `tenant_id`, `rol_id` o `estado`.** Un `PATCH /usuarios/{id}`
que acepte el JSON entero es una escalada vertical en una línea de código. Se previene
con esquemas de entrada, no con revisión.

---

## 5. Hueco identificado: eventos sin fila

`fn_auditar()` es un trigger sobre tablas. Cubre **cambios de datos**. No cubre:

- login correcto y login fallido
- logout y expiración de sesión
- intento de acceso denegado por permiso
- intento de acceso a otro tenant
- lectura de información sensible
- concesión y revocación de acceso de plataforma

El requerimiento pide trazar el login explícitamente. **Ninguna de esas acciones escribe
en una tabla de negocio**, así que hoy no dejan rastro.

Solución propuesta (no ahora): tabla `eventos_seguridad`, append-only como `auditoria`,
escrita por la API. Separada de `auditoria` porque su origen es distinto —la aplicación,
no un trigger— y porque su volumen y su política de retención también. Llega con la fase
de autenticación, no antes.

---

## 5 bis. Amenazas incorporadas en la fase 3E

### V-1 · La auditoría archiva los hashes de contraseña — **CRÍTICA**

| | |
|---|---|
| **Impacto** | `fn_auditar()` hace `to_jsonb(NEW)` de la fila entera. En cuanto `usuarios.password_hash` deje de ser `NULL`, cada cambio de contraseña copia el hash a `auditoria`, que es **append-only**. Quien logre leer `auditoria` obtiene material para ataque offline, incluidas contraseñas ya rotadas, y **no hay forma de limpiarlo** |
| **Probabilidad** | **Certeza** el día que se habilite el login |
| **Capa** | PostgreSQL |
| **Mitigación** | Catálogo `campos_sensibles` + redacción **después** de calcular `campos_cambiados` (`SEGURIDAD_RBAC.md` §7) |
| **Estado** | **Verificado ejecutándolo.** Latente: hoy no hay contraseñas |

### V-2 · Escalada por composición de rol — **ALTA (si se permiten roles por tenant)**

| | |
|---|---|
| **Impacto** | Un administrador de tenant que pudiera crear roles se fabricaría uno con permisos de plataforma y saldría de su laboratorio |
| **Probabilidad** | Nula hoy (no hay roles por tenant); alta si se implementan sin control |
| **Capa** | PostgreSQL + FastAPI |
| **Mitigación** | Roles **globales del producto**; y si algún día hay roles por tenant, el trigger `fn_validar_scope_permiso()` impide que un rol de tenant reciba un permiso de plataforma. **Imposible en el motor, no confiado a la API** |

### V-3 · Aprobación de la propia cotización — **ALTA**

| | |
|---|---|
| **Impacto** | Sin segregación, quien cotiza aprueba: desaparece el control interno sobre precios y descuentos que sale del laboratorio |
| **Probabilidad** | **Total hoy**: no existe flujo de aprobación |
| **Capa** | PostgreSQL + FastAPI |
| **Mitigación** | `ck_aprob_no_autoaprueba` como `CHECK` de fila — se aplica aunque la API falle y no se puede desactivar con `DISABLE TRIGGER USER` |

### V-4 · Saltarse el flujo de aprobación por `UPDATE` directo — **MEDIA**

| | |
|---|---|
| **Impacto** | Pasar de `borrador` a `aprobada` sin dejar fila de aprobación: estado e historial divergen, que es justo lo que invalida un rastro ante un auditor |
| **Probabilidad** | Baja: el `UPDATE` directo de estado ya está bloqueado (`23514`, verificado) |
| **Capa** | PostgreSQL |
| **Mitigación** | Trigger de puerta con marca de sesión, igual que protege `fn_cambiar_acreditacion()` |

### V-5 · `a_proteger` es evadible en dos pasos — **BAJA**

| | |
|---|---|
| **Impacto** | `UPDATE roles SET es_sistema = FALSE` y después cambiar el `codigo`: el trigger solo comprueba `OLD.es_sistema AND NEW.codigo <> OLD.codigo`. Renombrar el código de un rol rompería `rol_permisos` y la resolución de permisos |
| **Probabilidad** | Baja: exige escritura sobre `roles`, que será permiso de plataforma |
| **Capa** | PostgreSQL |
| **Mitigación** | Añadir `IF OLD.es_sistema AND NOT NEW.es_sistema THEN RAISE`. No urgente |

### V-6 · Mass assignment — **ALTA, y sin defensa en la base**

| | |
|---|---|
| **Impacto** | Un `PATCH /usuarios/{id}` que acepte el JSON entero permite fijar `rol_id`, `tenant_id` o `estado`: escalada vertical en una línea de código |
| **Probabilidad** | Alta si no se usan DTO con lista blanca |
| **Capa** | **FastAPI, en exclusiva** |
| **Mitigación** | Esquemas de entrada explícitos. **PostgreSQL no puede ayudar aquí**: si el backend escribe el campo, la base lo acepta como legítimo |

V-6 es la única de las seis sin defensa en profundidad posible. Por eso debe probarse
campo por campo (prueba P-3E).

---

## 6. Reparto por capa

| Capa | Le corresponde |
|---|---|
| **PostgreSQL** | Aislamiento (FK compuestas, RLS), integridad (CHECK, dominios, triggers), append-only, congelado del documento, correlativos atómicos, `least privilege` del rol de conexión |
| **FastAPI** | Autenticación, autorización, resolución del tenant, validación de entrada, paginación, `404` en vez de `403`, saneado de errores, rate limiting, URLs firmadas, claves de caché con tenant, `eventos_seguridad` |
| **Flutter** | Nada de seguridad. Comodidad de interfaz. No almacenar tokens en `localStorage` si hay alternativa, y ninguna decisión de autorización en el cliente |
| **Nginx / Docker** | TLS, cabeceras de seguridad, CORS restrictivo, límites de tamaño, rate limiting de borde, aislamiento de red del contenedor de base |
| **Operación** | Secretos en vault, credenciales de administración separadas de las de la aplicación, respaldos cifrados y probados, rotación de claves, revisión de `I2` |

---

## 7. Lo que este modelo NO cubre

Con honestidad, porque un modelo de amenazas que pretende cubrirlo todo no sirve:

- **A5 (operador con acceso al VPS).** Quien tiene `psql` como propietario puede leerlo y
  cambiarlo todo, incluida la auditoría. Se mitiga con procedimiento y separación de
  credenciales, no con esquema.
- **Compromiso de la cadena de suministro** (dependencias de Python o Flutter).
- **Ingeniería social** sobre el personal del laboratorio.
- **Disponibilidad y continuidad** más allá de lo mencionado; no hay plan de recuperación
  probado todavía.
