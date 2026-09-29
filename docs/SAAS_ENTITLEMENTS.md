# SAC-GEO — Planes, capacidades y límites

> Fase 3D · 2026-09-28. **Diseño. Nada de esto está implementado ni debe implementarse
> en `0003`.**
>
> Este documento existe para una sola cosa: fijar por escrito que el plan comercial, el
> rol, el permiso y la capacidad técnica son **cuatro conceptos distintos**, antes de que
> alguien escriba el primer `if plan == 'basico'`.

---

## 1. Los cuatro conceptos

| Concepto | Pregunta que responde | Quién lo decide | Dónde vive |
|---|---|---|---|
| **Plan** | ¿Qué contrató este laboratorio? | Comercial | `tenants.plan` (ya existe) |
| **Capacidad** | ¿Cuánto puede consumir? | Super Admin, dentro de lo que permite el plan | `tenant_capacidades` (futura) |
| **Rol** | ¿Qué es esta persona en su laboratorio? | Administrador del tenant | `usuarios.rol_id` (ya existe) |
| **Permiso** | ¿Qué acción concreta puede ejecutar? | El producto, por rol | `rol_permisos` (futura) |

Las dos preguntas que hay que saber separar:

- *"¿Puede este usuario crear otro usuario?"* → **permiso** (`usuarios.create`).
- *"¿Queda cupo de usuarios en este laboratorio?"* → **capacidad** (`usuarios.max`).

Son independientes. Un administrador con el permiso pero sin cupo recibe un error
**distinto** del de un cotizador sin permiso: el primero es *"contrate más"*, el segundo
es *"no le corresponde"*. Mezclarlos produce mensajes incomprensibles y, peor, controles
de acceso que dependen de la facturación.

---

## 2. La forma prevista

```
plan  ──►  plan_capacidades  ──►  tenant_capacidades  ──►  autorización
(qué       (el techo del        (lo que el Super Admin     (¿queda cupo?)
 contrató)  plan)                otorgó a ESTE tenant)
```

Tres tablas, todas **GLOBAL**:

| Tabla | Qué guarda |
|---|---|
| `planes` | `codigo` (`basico`/`standard`/`profesional`), nombre, precio, activo |
| `plan_capacidades` | El **techo** de cada capacidad por plan: `(plan, clave, valor)` |
| `tenant_capacidades` | Lo **efectivamente otorgado** a un tenant, más quién y cuándo |

`tenants.plan` ya existe en `0003` (`VARCHAR(20) DEFAULT 'estandar'`). Cuando llegue
`planes`, pasará a ser una FK. **Hoy es texto libre y conviene saberlo.**

### Por qué `tenant_capacidades` y no leer el plan directamente

Porque el requerimiento dice que la cantidad de usuarios depende también de *"capacidad
del VPS"* y *"capacidad técnica/operativa"*. Eso no es el plan: es una decisión del Super
Admin caso por caso. Con una sola tabla habría que elegir entre respetar el plan o
respetar la realidad del servidor. Con dos, el plan fija el techo y el Super Admin
concede dentro de él, dejando rastro.

### Claves de capacidad previstas

```
usuarios.max              plantillas.max
historial.dias_consulta   aprobacion.habilitada
dashboard.habilitado      integraciones.habilitadas
firma_digital.habilitada  qr.habilitado
almacenamiento.mb
```

Un `enum` cerrado, no texto libre: una clave mal escrita debe fallar al insertar, no
degradar silenciosamente en "sin límite".

---

## 3. Los planes como referencia comercial

No normativos. Los números son del área comercial y cambiarán.

| | BÁSICO $79 | STANDARD $149 | PROFESIONAL $249 |
|---|---|---|---|
| Usuarios | 1 | 7 | **administrable** |
| Plantillas propias | 1 | 2 | 3 |
| Historial consultable | 30 días | 180 días | sin límite |
| **Almacenamiento histórico** | **completo** | **completo** | **completo** |
| Aprobación | no | sí | sí |
| Dashboard | no | no | sí |
| Drive / M365 | no | no | sí |
| Firma y QR | no | no | sí |

---

## 4. "30 días" significa consulta, nunca borrado

**Esta es la regla que no se negocia.**

`historial.dias_consulta` limita **hasta dónde puede mirar el cliente en la interfaz**.
No autoriza a borrar absolutamente nada.

Prohibido, explícitamente:

- cualquier tarea programada que elimine filas de `auditoria` por el plan del tenant;
- cualquier borrado de `cotizaciones`, `cotizacion_items`, `cotizacion_historial_estados`
  o `ensayo_acreditacion_historial` por antigüedad;
- degradar de plan y perder datos.

Razones, en orden de peso:

1. **ISO 17025.** El historial de acreditación es lo primero que revisa un auditor, y las
   cotizaciones emitidas guardan el estado de acreditación del día en que se emitieron.
   Borrarlo por una decisión de facturación destruye la evidencia regulatoria del
   laboratorio.
2. La base ya lo impide en parte: `auditoria` es append-only y su única purga,
   `fn_purgar_auditoria()`, **exige más de 365 días** y deja constancia. Un plan de 30
   días de consulta no podría purgar aunque quisiera.
3. Las cotizaciones **no se eliminan, se cancelan**. Es una decisión ya tomada en
   `CLAUDE.md`.

Implementación correcta: un filtro `WHERE fecha >= hoy - dias_consulta` **en la lectura**,
aplicado por la API. El dato sigue ahí; si el cliente sube de plan, reaparece.

---

## 5. Cómo se consulta una capacidad

Un solo punto, como con los permisos:

```python
exigir_capacidad(tenant, "usuarios.max", consumo_actual + 1)
```

**Nunca** `if tenant.plan == 'basico'` disperso. Razones:

- añadir un plan no debe obligar a tocar veinte archivos;
- una condición olvidada en un solo sitio es una fuga de funcionalidad de pago;
- la decisión debe poder auditarse: quién concedió qué capacidad y cuándo.

El resultado se cachea por tenant, con la clave incluyendo el tenant (igual que toda
clave de caché en este sistema).

---

## 6. Relación con el defecto F-2

`fn_max_plantillas_activas()` codifica hoy un **3 literal** en un trigger. Después de la
corrección de la fase 3C ese 3 es **por tenant**, que es lo correcto desde el punto de
vista del aislamiento.

Pero el número sigue siendo fijo, y según la tabla de §3 debería ser 1, 2 o 3 según el
plan. **Eso no se arregla ahora y es deliberado:**

- la corrección de 3C resuelve un problema de **aislamiento** (un tenant consumía el cupo
  de otro), que es de seguridad y urgente;
- hacer el número dependiente del plan es **lógica comercial**, y meterla en `0003` es
  exactamente lo que el requerimiento prohíbe.

Cuando llegue `tenant_capacidades`, el trigger leerá `plantillas.max` en lugar del
literal. Hasta entonces, 3 por tenant es un techo razonable que no bloquea a nadie.

Queda además una **ambigüedad abierta**, documentada en la propia migración: si las 3
plantillas base del producto cuentan dentro del cupo del laboratorio. Se implementó que
**no** cuenten, porque bajo la lectura contraria el cupo nace agotado y crear plantillas
sería imposible. Es una decisión de producto pendiente de confirmar.

---

## 7. Qué NO se construye ahora

- `planes`, `plan_capacidades`, `tenant_capacidades`
- Facturación, pasarela de pago, ciclo de suscripción
- Degradación automática de plan
- Cualquier límite comercial dentro de `0003`

`tenants` ya trae `plan` y `activo`; con eso `0003` tiene lo estructural que necesita y
nada más.

---

## 8. Riesgo a vigilar

**Que un límite comercial acabe funcionando como control de acceso.**

Si `aprobacion.habilitada = false` se implementa ocultando el botón en Flutter, cualquiera
con la URL del endpoint aprueba igual. Y si se implementa en el endpoint pero como si
fuera un permiso, un fallo de facturación se convierte en un fallo de autorización.

La separación correcta:

- **permiso** — ¿le corresponde a esta persona? → `403`
- **capacidad** — ¿lo incluye el plan / queda cupo? → `402` o `409`, con mensaje comercial

Los dos se verifican. Ninguno sustituye al otro.
