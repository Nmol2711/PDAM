# Informe — Pruebas de la Spec 014 (registro de actividad y validación del dispensado)

## 1. Metadatos

| Campo | Valor |
|---|---|
| Fecha | 2026-10-29 |
| Spec | [Spec 014 — Registro de actividad y validación del descuento de stock](../../specs/014-logs-y-validacion-dispensado/spec.md) |
| Plan | [Plan 014](../../specs/014-logs-y-validacion-dispensado/plan.md) |
| Tareas | [Tasks 014](../../specs/014-logs-y-validacion-dispensado/tasks.md) |
| Subsistema | Backend (FastAPI) + App (Flutter) + Firmware (ESP32) |
| Alcance | Migración de `logs`, órdenes con plazo y descuento al confirmar, reporte del dispositivo, consulta filtrada y paginada, caché sin conexión, reabastecimiento idempotente y no regresión de las specs 011, 012 y 013 |
| Estado | **Aprobado: software (28 casos), S7, P-T8-A y P-T9-A a P-T9-D** |
| Commit de referencia | `fd4c047` en la rama `pruebas/endpoint-fijo-hx711` — «feat(spec-014): registro tipado de actividad y descuento al confirmar» |
| Informe relacionado | [Pruebas de hardware de la spec 013](informe-pruebas-hardware-spec-013-2026-10-23.md) |

> Este documento es el procedimiento de prueba con registro de resultados. Las cifras del
> §3 corresponden a la validación global registrada en `tasks.md` (auditoría del 2026-10-29)
> y se repiten aquí como criterio de éxito: una ejecución posterior debe dar cifras iguales
> o superiores y ningún fallo. El 2026-10-29 se ejecutó el bloque de software S2–S6 y S8
> (28 casos, 0 fallos), con los resultados del §12, y también las pruebas manuales y físicas
> que quedaban: S7 y P-T8-A en el móvil real, y P-T9-A a P-T9-D con el ESP32, la celda y el
> router. La evidencia está resumida en las filas del §12: líneas del monitor serie, códigos
> HTTP de cada intento, esperas medidas y cifras de stock y de historial. Las transcripciones
> en bruto no se versionan porque contienen datos de la red local; el §12 transcribe los
> valores observados. Con las cinco pruebas físicas aprobadas, la spec 014 queda cerrada.

---

## 2. Resumen

La Spec 014 convierte el historial en un registro tipado: cada operación relevante escribe
tipo de evento, resultado, causa, mascota, MAC parcial, descripción y contexto en la misma
transacción que el cambio de estado que la origina. La tabla `logs` se reconstruye en una
migración idempotente y los registros anteriores se conservan como «Sin clasificar».

El descuento de stock deja de ocurrir al emitir la orden: la consulta del dispositivo crea
una orden pendiente con identificador y plazo de 5 minutos, y el stock solo se descuenta
cuando el firmware reporta un cierre con gramos medidos que alcanzan los solicitados. El
descuento es lo medido, acotado al stock disponible, y se guarda separado de lo solicitado.
Las órdenes sin reporte se cierran por vencimiento con `sin_reporte`, mediante un barrido
de 30 segundos, sin tocar el stock.

El dispositivo envía el resultado del ciclo a `POST /dispensers/reports` con MAC, orden,
motivo, gramos y reintentos. El reporte se persiste en NVS antes de enviarse, se reintenta
a los 5 y 15 segundos ante fallo de red o 5xx, y se descarta ante 200 o 400 de negocio. La
consulta del historial pasa a un contrato con sobre `{items,total,page,page_size}`, cuatro
filtros combinables y rechazos 400 con `detail={code,message}`; la app lo cachea en Isar y
lo muestra sin conexión con un aviso de datos locales.

La suite automatizada ya acredita la lógica de dominio (catálogos, plazos, descuento
acotado, validación de consulta), la integración con SQLite (migración, transacciones,
idempotencia, concurrencia, rendimiento), la app (modelo, datasources, BLoC, widgets,
caché) y el firmware (JSON del reporte, política de reintentos y clasificación de
respuestas). Lo que **solo** puede acreditarse con el dispositivo y el router es el efecto
físico: que el servidor reciba el reporte tras una dispensación real (P-T9-A), que el
reporte sobreviva a una red caída y a un reinicio (P-T9-B), que un descarte no se reenvíe
(P-T9-C), que un firmware sin reporte cierre por plazo (P-T9-D) y que el historial se vea
sin desbordamientos en el móvil real (P-T8-A).

Antes de ejecutarse esas cinco pruebas, la spec quedó «implementada (pendiente de pruebas
físicas)», como registraba `tasks.md`. Ya están ejecutadas y aprobadas (2026-10-29) y la spec
figura como «implementada y validada». Las suites en verde no sustituyen a ninguna de ellas
(RNF-6); por eso la evidencia física se registra aparte en el §12 y en el cierre de
`tasks.md`.

### 2.1 Qué cambia respecto de la línea base

| Antes de la 014 | Después de la 014 |
|---|---|
| `logs` con texto libre (`event`, `timestamp`) y sin tipo ni resultado | `logs` con 18 columnas, tipo/resultado/causa cerrados y contexto JSON |
| El stock se descontaba al entregar la orden de dispensación | Se descuenta al confirmar el reporte, y lo descontado es lo medido |
| `pending_dispensing` como única señal de comida programada | Cola `dispensing_queue` con ocurrencia, cantidad y estado; la bandera solo se consume como herencia |
| Consulta con una única fecha | Rango `from`/`to` con desplazamiento explícito, paginación y catálogo |
| El firmware no informaba del resultado del ciclo | Reporte con motivo, gramos y reintentos, persistido en NVS y con reintentos |
| El historial de la app no tenía caché utilizable sin conexión | Caché Isar con filtros y paginación locales y aviso de datos locales |

---

## 3. Estado automatizado

Ejecutado el 2026-10-29 según la validación global registrada en `tasks.md`. Los comandos se
lanzan desde la ruta indicada, relativa a la raíz del repositorio.

| # | Comprobación | Comando | Ruta | Resultado esperado |
|---|---|---|---|---|
| A1 | Backend | `source venv/bin/activate && pytest` | `api/` | **530 passed + 541 subtests**, 0 fallos |
| A2 | App | `flutter test` | `app/app_movil_pdam/` | **412/412**, 0 omitidas |
| A3 | App estático | `flutter analyze` | `app/app_movil_pdam/` | **0 errores**, 95 avisos e infos preexistentes |
| A4 | Firmware nativo | `pio test -e native` | `DispensadorESP32/` | **157/157 en 4 suites** (`test_dispensing_utils` 110, `test_dispensing_cycle` 22, `test_provisioning_utils` 5, `test_report_utils` 20) |
| A5 | Firmware build | `pio run` | `DispensadorESP32/` | **SUCCESS** — RAM 64 444 B (19,7 %), Flash 2 030 750 B (64,6 %) |

Comandos completos:

```bash
cd api && source venv/bin/activate && pytest
```

```bash
cd app/app_movil_pdam && flutter test && flutter analyze
```

```bash
cd DispensadorESP32 && pio test -e native && pio run
```

Notas de las cifras:

- `pytest` incluye las suites nuevas de la 014 (`test_logs_domain`, `test_logs_migration`,
  `test_orders_dispensing`, `test_orders_concurrency`, `test_orders_expiry`,
  `test_feeding_queue`, `test_activity_logs_crud`, `test_refill_logs`, `test_logs_query`,
  `test_logs_errors`, `test_logs_performance` y `test_traceability_rf`). La línea base de la
  T1 era 244 passed + 113 subtests.
- `flutter test` subió de 286 (línea base) a 412; la última corrección de T8 dejó 405
  pruebas con tres de cambio de horario omitidas en la zona del equipo y **405/405 con
  `TZ=Europe/Madrid`**. La medición final es 412/412 sin omisiones.
- `flutter analyze` no añade avisos nuevos: los 95 son preexistentes y se midieron también
  al cerrar T8.
- `pio test -e native` pasó de 137 (013) a 157 con los 20 casos de `test_report_utils`, que
  figura en `test_ignore` de `platformio.ini` como las demás suites nativas.
- Sin dependencias externas nuevas (RNF-4): `requirements.txt` no cambia; en `pubspec.yaml`
  se añade `flutter_localizations` (SDK) y `intl` llega como transitiva; `platformio.ini`
  solo amplía `test_ignore`.

---

## 4. Cambios que se validan

| Área | Cambio implementado | Qué debe confirmarse |
|---|---|---|
| Migración de `logs` e históricos | `database._migrar_logs` reconstruye `logs` con 18 columnas cuando falta el esquema final, conserva `id`, `user_id`, `pet_id`, `description` y `created_at`, rellena `pet_name` y deja tipados y métricas en `NULL`; es idempotente y aborta sin borrar datos si el recuento no coincide. `GET /logs/` devuelve `event_label` «Sin clasificar» | Que una base anterior queda con 18 columnas sin perder filas, que los históricos siguen visibles sin filtros y que una segunda apertura no vuelve a migrar (§5, S2) |
| Orden de dispensación y descuento al confirmar | `check_pending_task` delega en `order_service.entregar_orden`: crea la orden pendiente con `order_id`, hora del servidor y sin tocar stock. El descuento ocurre al cerrar con éxito y es lo medido, acotado entre 0 y el stock (RF-13, RF-15, RF-22, RF-23) | Que la entrega no modifica el stock, que el cierre con medidos ≥ solicitados descuenta lo medido y que el stock resultante queda en 0–5000 g (§5, S4) |
| Reporte del dispositivo | `POST /dispensers/reports` normaliza la MAC, valida motivo y orden en ese orden, responde 200 con `outcome`, `cause`, gramos y stock, y 400 `mac_no_registrada`/`motivo_invalido`/`orden_desconocida` con `detail={code,message}`; un fallo de escritura responde 5xx (RF-14, RF-21, RNF-1) | Que el cuerpo es el del §5.2 del plan, que no se acepta stock del dispositivo y que el rechazo es 400 y nunca 422 (§5, S3) |
| Idempotencia del reporte | La transición es `UPDATE ... WHERE status='pending'` con `rowcount`; el segundo reporte recibe 200 con `ya_cerrada: true` y no escribe registro ni descuenta (RF-18, elemento 4 del §8 del plan) | Que un segundo reporte, idéntico o con otros gramos, no produce segundo cierre ni segundo descuento (§5, S4 y S5) |
| Vencimiento a 5 min con barrido de 30 s | `cerrar_vencidas` cierra con `sin_reporte` solo después del plazo más 1 s de tolerancia, sin stock; `main.py` programa un único job cada `INTERVALO_BARRIDO` (30 s) con `max_instances=1`; el cierre queda garantizado en 60 s (RF-19, RF-40, RNF-3) | Que el barrido no cierra antes del plazo y que el cierre aparece en el historial sin reiniciar el servidor (§9, P-T9-D y §5, S5) |
| Filtros y paginación | `GET /logs/` con `pet_id`, `event_type`, `outcome`, `from`, `to`, `page`, `page_size` (texto y validación en servicio), precedencia `rango_fechas_invalido → tipo_evento_invalido → resultado_invalido → pagina_invalida → tamano_pagina_invalido`, sobre con total y 50 por defecto; `GET /logs/catalog` (RF-26 a RF-32, RF-41) | Que cada caso válido devuelve el sobre y cada rechazo el 400 del catálogo, con `Z` y con desplazamiento (§5, S3) |
| Caché sin conexión | Isar guarda códigos y etiquetas con upsert por `remoteId`; el repositorio cae a la caché ante red, timeout y 5xx (no ante 400/401) y el BLoC conserva la lista previa con `isOffline` (RF-34, RF-35) | Que con el servidor apagado se ve el aviso de datos locales, que filtros y paginación funcionan sobre la caché y que no se borra la lista ya mostrada (§5, S7) |
| Reabastecimiento idempotente | `refill_operations` con única `(user_id, operation_id)`; `origen` `servidor` o `sincronizacion_sin_conexion`; los rechazos responden 400 del catálogo, dejan el stock intacto y registran el fallo en sesión independiente (RF-11, RF-12) | Que el mismo `operation_id` sincronizado dos veces suma una sola vez y deja un único `dispenser_refilled` (§5, S8) y que sin identificador el servidor no deduplica (§5, S3) |
| No regresión de la 013 | Ventanas de verificación, gracia y estancamiento, presupuesto de motor, tolerancias y temporizador de 20 s sin cambios; `dispensing_utils.h` y `dispensing_cycle.h` con `git diff` vacío (RF-38) | Que el dispensado por peso, los atascos y el intervalo de consulta siguen igual (§10) |
| Historial en el móvil | Cuatro filtros, «Limpiar filtros», «Página X de Y», vacío con texto exacto y error con reintento; textos en español (RF-33, RNF-1, RNF-5) | Que se pinta sin desbordamientos en el Samsung A15 con letra al 130 % (§9, P-T8-A) |

---

## 5. Pruebas de software

### S1. Suites automatizadas

Repetir los cinco comandos del §3 desde las rutas indicadas.

| Comprobación | Criterio de éxito |
|---|---|
| `pytest` | Todo en verde, con **≥ 530 passed + 541 subtests** y 0 fallos |
| `flutter test` | **≥ 412/412**, 0 fallos y 0 omitidas |
| `flutter analyze` | **0 errores**; los avisos no deben crecer respecto de 95 |
| `pio test -e native` | **≥ 157/157** en las cuatro suites |
| `pio run` | **SUCCESS**, sin errores de compilación en `esp32dev` |

Si una cifra baja, no se considera una regresión de la 014 hasta comprobar si la prueba se
renombró o se movió; si desaparece una prueba sin sustituto, la comprobación falla.

### S2. Migración y datos

Se ejecuta sobre una **copia** de la base real: la migración se dispara al arrancar la API y
nunca debe probarse sobre la base que se quiera conservar sin respaldo.

**Pasos.**

1. Detener la API y hacer la copia de seguridad, desde la raíz del repositorio:

```bash
cp -p api/app/db/pdam.db /tmp/opencode/pdam-pre-014.db
```

2. Arrancar la API (`cd api && source venv/bin/activate && uvicorn app.main:app --reload
   --port 8000 --host 0.0.0.0`) y esperar a que termine el arranque.
3. Inspeccionar el esquema y las filas conservadas:

```bash
python - <<'PY'
import sqlite3

c = sqlite3.connect("api/app/db/pdam.db")
columnas = [fila[1] for fila in c.execute("PRAGMA table_info(logs)")]
print("columnas:", len(columnas))
print("filas:", c.execute("SELECT COUNT(*) FROM logs").fetchone()[0])
for fila in c.execute(
    "SELECT id, event_type, outcome, cause, description FROM logs ORDER BY id"
):
    print(fila)
PY
```

4. Consultar el historial autenticado (`GET /logs/`, §5 S3) y comprobar que cada fila
   histórica llega con `event_type`, `outcome`, `cause`, `outcome_label` y `cause_label` en
   `null` y `event_label` igual a **«Sin clasificar»**.
5. Parar y volver a arrancar la API, y repetir el paso 3: los conteos no cambian y no queda
   ninguna tabla `logs_nueva` (`SELECT name FROM sqlite_master WHERE name LIKE 'logs%'`).

**Resultado esperado.**

| Comprobación | Valor esperado |
|---|---|
| Columnas de `logs` | **18**, en el orden del §6.1 del plan |
| Filas históricas | **4**, con identificadores 1 a 4 y `description` con el texto anterior de `event` |
| `event_type`, `outcome`, `cause` | `NULL` en las 4 filas |
| Etiqueta en la consulta | «Sin clasificar», sin etiquetas de resultado ni de causa |
| Segunda apertura | No vuelve a migrar: mismos índices, mismas filas, sin `logs_nueva` |
| Tablas nuevas | `dispensing_orders`, `dispensing_queue` y `refill_operations` presentes |

La base actual ya tiene el esquema final, de modo que la primera apertura de esta prueba
acredita la **idempotencia** y la conservación de los históricos. La **reconstrucción** de
una base legada o con columnas parciales ya está cubierta por
`tests/test_logs_migration.py` (clases `TestBaseLegada` y `TestColumnasParciales`), que forma
parte de S1.

**Criterio de aborto.** Si el número de filas copiadas no coincide con el de la tabla
original, `_migrar_logs` lanza `RuntimeError` con el mensaje «No se puede reconstruir
'logs': se copiaron N de M filas. Se conserva la tabla original y no se ha borrado ningún
dato.», la API **no arranca** y la tabla `logs` queda intacta. En ese caso se conserva el
mensaje, se restaura la copia con `cp -p /tmp/opencode/pdam-pre-014.db api/app/db/pdam.db`
y la prueba se marca fallida. Nunca se debe «arreglar» borrando filas a mano.

### S3. Humo de API con `curl`

Preparación, sin registrar credenciales en el informe:

```bash
BASE=http://<ip-del-servidor>:8000
TOKEN=$(curl -s -X POST "$BASE/auth/login" \
  -d "username=<correo>" -d "password=<contraseña>" \
  | python -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
MAC=<MAC-normalizada>
```

Todos los rechazos de negocio se devuelven con esta forma, y el mensaje es el del catálogo
de errores de la spec:

```json
{"detail": {"code": "<código>", "message": "<mensaje del catálogo>"}}
```

| Caso | Petición | Respuesta esperada | Qué demuestra |
|---|---|---|---|
| S3.1 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?page_size=50"` | 200 con `{"items":[...],"total":<n>,"page":1,"page_size":50}`; los históricos con `event_label` «Sin clasificar» | Sobre de respuesta, paginación por defecto y RF-41 |
| S3.2 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?event_type=feeding_dispensed"` | 200; todos los ítems con `event_type` `feeding_dispensed` y ninguno sin clasificar | Filtro por tipo del catálogo cerrado (RF-28) |
| S3.3 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?outcome=failure"` | 200; todos con `outcome` `failure`; ningún histórico | Filtro por resultado (RF-29) |
| S3.4 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?from=2026-10-01T00:00:00Z&to=2026-10-02T00:00:00Z"` | 200; `created_at` de los ítems dentro del intervalo, devueltos con sufijo `Z` | `Z` como desplazamiento explícito (RF-30, RNF-8) |
| S3.5 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?from=2026-10-01T00:00:00-05:00&to=2026-10-01T23:59:59-05:00"` | 200; mismos ítems que el día local en UTC-05:00; el intervalo incluye ambos extremos | Conversión de cada límite por su propio desplazamiento (RF-30) |
| S3.6 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?event_type=comida"` | 400 `tipo_evento_invalido` | Catálogo cerrado y rechazo explícito (RF-31) |
| S3.7 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?outcome=ok"` | 400 `resultado_invalido` | Filtro de resultado cerrado (RF-31) |
| S3.8 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?from=2026-10-02T00:00:00Z&to=2026-10-01T00:00:00Z"` | 400 `rango_fechas_invalido` | Orden de límites (RF-31) |
| S3.9 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?from=2026-10-01&to=2026-10-02"` | 400 `rango_fechas_invalido` | Límite sin `Z` ni desplazamiento: no se asume zona (RF-30, RF-31) |
| S3.10 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?page=0"` | 400 `pagina_invalida` | Sin recorte silencioso (RF-32) |
| S3.11 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?page_size=101"` | 400 `tamano_pagina_invalido` | Máximo de 100 sin recorte (RF-32) |
| S3.12 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/?pet_id=<pet_id>"` | 200; solo registros de esa mascota, incluidos los de una mascota ya eliminada cuyo identificador se conservó | Filtro por mascota y conservación de la referencia (RF-27) |
| S3.13 | `curl -s -H "Authorization: Bearer $TOKEN" "$BASE/logs/catalog"` | 200 con `event_types` (9) y `outcomes` (2), con etiquetas en español y sin causas | Catálogo único para poblar los filtros (RNF-7) |
| S3.14 | `curl -s -X POST "$BASE/dispensers/reports" -H "Content-Type: application/json" -d '{"mac":"<MAC no registrada>","order_id":1,"motivo":"objetivo_alcanzado","gramos_solicitados":50,"gramos_medidos":50.4,"reintentos":0}'` | 400 `mac_no_registrada`, sin registro nuevo en el historial | Rechazo por MAC antes de mirar motivo u orden (RF-21) |
| S3.15 | Mismo POST con `$MAC` y `"motivo":"exito"` | 400 `motivo_invalido`; la orden sigue pendiente y cerrará por plazo | Catálogo cerrado de motivos (RF-21) |
| S3.16 | Mismo POST con `$MAC`, `"motivo":"objetivo_alcanzado"` y `"order_id":999999` | 400 `orden_desconocida` y **un** registro `feeding_dispensed` con causa `orden_desconocida` | Única excepción de RF-2 además del rechazo de reabastecimiento (RF-21) |
| S3.17 | `curl -s -X POST "$BASE/dispensers/<id>/refill" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"amount":500,"unit":"g","operation_id":"<op-1>"}'` | 200 con el dispensador y el stock autoritativo (stock + 500) | Reabastecimiento con conexión y origen `servidor` (RF-11) |
| S3.18 | Repetir S3.17 con el mismo `operation_id` | 200 con el mismo stock: no suma dos veces | Idempotencia por `(user_id, operation_id)` (RF-11) |
| S3.19 | Repetir S3.17 con otro `operation_id` | 200 con el stock incrementado otra vez | Dos reabastecimientos legítimos no se confunden (RF-11) |
| S3.20 | `curl -s -X POST "$BASE/dispensers/<id>/refill" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"amount":500,"unit":"g"}'` | 200; se aplica una vez por petición, sin deduplicación entre reenvíos | Limitación declarada de un cliente sin identificador |
| S3.21 | Mismo POST con `"amount":0` | 400 `cantidad_invalida`, stock intacto y registro `dispenser_refilled` de fallo | Validación en servicio, nunca 422 (RF-12) |
| S3.22 | Mismo POST con `"amount":6000` | 400 `supera_capacidad`, stock intacto y registro de fallo | Capacidad máxima de 5000 g (RF-12, RF-22) |
| S3.23 | `curl -s -X PUT "$BASE/dispensers/<id>" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"pet_id":<pet_id>,"current_food_grams":100}'` | 200 con el stock del servidor sin cambios; repetir con 900, 6000 y 0 | El stock del cliente se ignora sin error (RF-23) |

Notas de S3:

- La ruta de consulta del dispositivo es `GET /dispenserscheck-taks/{mac}` (sin barra entre
  `dispensers` y `check-taks`); el nombre conserva el typo real del servidor y no debe
  «corregirse» al escribir las peticiones.
- `page` y `page_size` viajan como texto: si se envía `page=abc`, la respuesta es 400
  `pagina_invalida`, no 422.
- Un `pet_id` no numérico no tiene código en el catálogo y devuelve página vacía con total
  0, por decisión registrada en T7; no se considera fallo de esta prueba.
- No anotar en el informe el token, la contraseña, la MAC completa ni la IP real.

### S4. Reporte exitoso de punta a punta (sin hardware)

Objetivo: recorrer entrega, reporte, descuento e idempotencia por HTTP, sin ESP32.

**Pasos.**

1. Asegurar que el dispensador tiene mascota, al menos un horario con cantidad conocida y
   stock suficiente (por ejemplo 1000 g). Anotar `solicitados` = importe del horario.
2. Dejar preparada una entrega. El camino normal es programar una comida y esperar al
   barrido de 30 s; para repetir la prueba sin esperar, con la API detenida se activa la
   bandera heredada del §7.2 y se vuelve a arrancar.
3. Consultar la orden:

```bash
curl -s "$BASE/dispenserscheck-taks/$MAC"
```

Respuesta esperada:

```json
{"serve": true, "amount": 50.0, "order_id": 12}
```

Anotar `order_id`. Comprobar que el stock **no** cambió (`GET /dispensers/<id>`).

4. Enviar el reporte con medidos iguales o mayores que los solicitados:

```bash
curl -s -X POST "$BASE/dispensers/reports" -H "Content-Type: application/json" -d '{
  "mac": "'"$MAC"'",
  "order_id": 12,
  "motivo": "objetivo_alcanzado",
  "gramos_solicitados": 50.0,
  "gramos_medidos": 50.4,
  "reintentos": 0
}'
```

Respuesta esperada:

```json
{
  "order_id": 12,
  "outcome": "success",
  "cause": "objetivo_alcanzado",
  "requested_grams": 50.0,
  "measured_grams": 50.4,
  "discounted_grams": 50.4,
  "resulting_stock": 1149.6,
  "ya_cerrada": false
}
```

5. Comprobar en el historial (`GET /logs/?event_type=feeding_dispensed`) un único registro
   con `order_id`, `requested_grams`, `measured_grams`, `discounted_grams`,
   `resulting_stock` y `retry_count`, y que el stock del dispensador bajó exactamente
   `discounted_grams`.
6. Reenviar el mismo cuerpo: la respuesta es 200 con el resultado anterior y
   `"ya_cerrada": true`; el total de registros `feeding_dispensed` de esa orden no cambia y
   el stock tampoco.
7. Repetir el envío con otro motivo y otros gramos: sigue devolviendo el primer resultado
   con `ya_cerrada: true` y no reescribe el registro.

**Qué demuestra.** RF-13 (entrega sin descuento), RF-15 (descuento de lo medido), RF-18
(duplicado sin doble efecto) y RF-24 (contexto del dispensado). El criterio de fallo es
cualquier descuento en el paso 3, un descuento distinto de `discounted_grams`, o un segundo
registro o segundo descuento en los pasos 6 y 7.

### S5. Concurrencia

Objetivo: una sola transición de pendiente a cerrada por orden, y ningún gramo perdido entre
descuento y reabastecimiento (RNF-3).

**Pasos.**

1. Ejecutar cinco veces la suite de concurrencia:

```bash
cd api && source venv/bin/activate
for i in 1 2 3 4 5; do pytest tests/test_orders_concurrency.py -q || break; done
```

2. Ejecutar la exclusión mutua entre reporte y barrido:

```bash
pytest tests/test_orders_expiry.py::TestExclusionMutuaConElReporte -q
```

**Casos cubiertos y resultado esperado.**

| Caso | Prueba | Resultado esperado |
|---|---|---|
| Dos reportes simultáneos de la misma orden | `TestReportesSimultaneos::test_dos_reportes_simultaneos_en_sesiones_distintas` | Un único cierre, un único `feeding_dispensed` y un único descuento; el segundo recibe `ya_cerrada: true` |
| Sesión que leyó la orden y llega tarde | `TestReportesSimultaneos::test_una_sesion_que_leyo_la_orden_pendiente_no_duplica_el_cierre` | La transición condicional descarta el registro del perdedor |
| Reporte contra barrido | `TestExclusionMutuaConElReporte::test_el_barrido_cierra_y_el_reporte_tardio_devuelve_ya_cerrada` | Un único resultado: o cierre por reporte dentro del plazo o `orden_cerrada` con `ya_cerrada: true`; nunca doble escritura |
| Descuento y reabastecimiento simultáneos | `TestStockConcurrente::test_un_reabastecimiento_confirmado_no_se_pierde_al_cerrar_la_orden` y `test_un_descuento_confirmado_no_se_pierde_al_reabastecer` | El stock no pierde gramos (1000 → 1200 → 1150 y 1000 → 950 → 1150) |
| Dos descuentos simultáneos | `TestStockConcurrente::test_dos_descuentos_simultaneos_no_pierden_gramos` | 1000 → 900 |
| Dos entregas simultáneas | `TestEntregasSimultaneas::test_dos_entregas_simultaneas_no_dejan_dos_ordenes_pendientes` | Una única orden pendiente y la ocurrencia perdedora vuelve a la cola |

**Criterio de fallo.** Cualquier ejecución en rojo, o menos de 5 de 5 ejecuciones conformes
del paso 1. El intercalado es determinista desde la corrección del 2026-10-29: la prueba
pausa la sentencia de escritura del stock con `PausaAntesDeEscribirStock` y comprueba que la
lectura ya se había emitido, así que un fallo indica una regresión real y no una carrera
del planificador. Si se quiere verificar que la prueba sigue siendo sensible, se puede
reintroducir temporalmente el patrón antiguo de escritura absoluta en una copia del
repositorio: las tres pruebas de `TestStockConcurrente` deben fallar.

### S6. Rendimiento (RNF-2)

```bash
cd api && source venv/bin/activate
pytest tests/test_logs_performance.py -s -q
```

La prueba siembra **10 000 registros** del usuario repartidos en 20 días, aplica los cuatro
filtros (`event_type`, `outcome`, `from`, `to`, más `pet_id` en el primer caso), descarta tres
consultas de calentamiento y mide 100 consultas consecutivas con `time.perf_counter`.

**Cómo leer la medición.** Con `-s` se imprime una línea por caso:

```text
RNF-2 con <n> registros y 4 filtros: p50=<ms> ms, p95=<ms> ms, máximo=<ms> ms en 100 consultas
```

Se anota el **p95** de esa línea, no el máximo. Criterio: p95 inferior a **1000 ms** en los
dos casos (con filtros y primera página sin filtros) y que exista el índice compuesto
`ix_logs_user_id_created_at` con columnas `(user_id, created_at)`.

**Qué se considera fallo.** Un p95 igual o superior a 1 s, un `total` que no coincide con lo
sembrado, un ítem de página distinto de 50, o la ausencia del índice. Un p95 alto solo en la
primera ejecución sobre un equipo recién arrancado se repite una vez antes de concluir; si se
mantiene, se registra como fallo con el valor medido y el equipo empleado.

### S7. App sin conexión

Objetivo: RF-34 y RF-35 en el móvil real.

**Pasos.**

1. Con el servidor en marcha, abrir el historial y recorrer al menos dos páginas para que la
   caché Isar quede poblada.
2. Detener la API (o apagar el WiFi del móvil).
3. Forzar una consulta: cambiar un filtro, volver a la primera página y pulsar el reintento.
4. Repetir con un filtro de tipo y con un filtro de resultado, y con la paginación, siempre
   sin conexión.
5. Mirar el estado vacío: filtrar de modo que no haya resultados en caché.

**Resultado esperado.**

| Comprobación | Resultado esperado |
|---|---|
| Aviso | Aparece el aviso de datos locales y se indica que el total y las páginas se calculan sobre la caché |
| Lista previa | La lista ya mostrada no se vacía mientras falla la consulta; no hay parpadeo a vacío |
| Filtros | Funcionan sobre la caché con los mismos criterios que el servidor (mascota, tipo, resultado, rango) |
| Paginación | «Página X de Y» y los controles responden sobre el total de la caché, con los extremos deshabilitados |
| Sin datos locales | Si la caché está vacía, el texto informa de que no hay datos locales guardados |
| Recuperación | Al volver el servidor, el reintento devuelve datos remotos y el aviso desaparece |

**Criterio de fallo.** Que la lista se borre, que un filtro devuelva registros de otro tipo o
resultado, que el total de páginas sea el del servidor con datos locales, o que el aviso no
aparezca. El repositorio no debe caer a la caché ante 400/401: en ese caso se muestra el
error con reintento y se conservan los filtros.

### S8. Reabastecimiento sin conexión

Objetivo: RF-11 en el camino real de sincronización.

**Pasos.**

1. Con el servidor apagado, reabastecer desde la app con una cantidad conocida (por ejemplo
   300 g). La app guarda el pendiente con su stock optimista y su `pendingRefillId`.
2. Anotar el stock mostrado por la app y el stock del servidor antes de sincronizar
   (`GET /dispensers/<id>` cuando vuelva la conexión, antes de dejarlo sincronizar).
3. Encender el servidor y dejar que la sincronización envíe el pendiente.
4. Repetir el envío con el mismo pendiente: la forma controlada es ejecutar el mismo POST que
   hace la app dos veces y comprobar la deduplicación en el servidor.

```bash
OP=<operation_id del pendiente>
curl -s -X POST "$BASE/dispensers/<id>/refill" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"amount\":300,\"unit\":\"g\",\"operation_id\":\"$OP\",\"origen\":\"sincronizacion_sin_conexion\"}"
```

5. Verificar en la base (o por API) el resultado:

```bash
python - <<'PY'
import sqlite3

c = sqlite3.connect("api/app/db/pdam.db")
print("operaciones:", c.execute(
    "SELECT COUNT(*) FROM refill_operations WHERE operation_id = ?", ("<op>",)
).fetchone()[0])
print("registros:", c.execute(
    "SELECT COUNT(*) FROM logs WHERE event_type = 'dispenser_refilled'"
).fetchone()[0])
PY
```

**Resultado esperado.** Un único incremento de stock, una única fila en
`refill_operations` para ese `operation_id` y un único registro `dispenser_refilled` con
`origen` `sincronizacion_sin_conexion`, gramos añadidos y stock resultante; la fecha del
registro es la de la sincronización, no la del reabastecimiento offline. La app limpia
`pendingRefillGrams` y `pendingRefillId` tras la respuesta definitiva; si la respuesta no
llega, conserva ambos y el reintento reenvía el mismo identificador.

**Criterio de fallo.** Un segundo incremento, un segundo registro, o que el reintento envíe
un `operation_id` distinto (lo que rompería la deduplicación). Si el servidor responde 400
`supera_capacidad` por una carrera de stock, la app debe reconciliar el stock con el del
servidor y descartar el pendiente sin duplicar la cantidad.

---

## 6. Preparación del entorno

### 6.1 Backend

```bash
cd api
source venv/bin/activate
cp -p app/db/pdam.db /tmp/opencode/pdam-pre-014.db
uvicorn app.main:app --reload --port 8000 --host 0.0.0.0
```

- Hacer la copia **antes** del primer arranque (S2). La migración se ejecuta al abrir la base.
- El servidor debe escuchar en `0.0.0.0` para que el ESP32 lo alcance desde la red local.
- Verificación rápida: `curl -s "$BASE/"` debe devolver el estado del servidor.
- Autenticación de las pruebas manuales: `POST /auth/login` con `username` y `password` en
  formulario; guardar el `access_token` en `$TOKEN` (no registrarlo en el informe).

### 6.2 App móvil

```bash
cd app/app_movil_pdam
flutter run --debug --host-vmservice-port=8888
```

Con el Samsung A15 conectado. Para P-T8-A, subir el tamaño de letra del sistema al 130 %
antes de abrir el historial. Para S7 y S8 hace falta haber abierto el historial y el
dispensador al menos una vez con conexión, para que Isar tenga caché.

### 6.3 Firmware

```bash
cd DispensadorESP32
pio test -e native
pio run
pio run --target upload
pio device monitor -b 115200
```

El monitor debe mostrar la MAC del equipo y la inicialización del HX711. El reporte usa el
mismo host que `BASE_URL` y la constante `REPORTS_URL` documentada en `src/config/config.h`;
la consulta conserva la ruta real `/dispenserscheck-taks/{mac}`.

### 6.4 Red

- El PC, el móvil y el ESP32 en la **misma red local de 2.4 GHz**, sin aislamiento de
  clientes ni firewall en el puerto 8000.
- No registrar SSID, contraseñas, tokens ni MAC completas en capturas o transcripciones.
- Para P-T9-B y P-T9-D se necesita poder apagar el router (o el servidor) de forma
  controlada y medir tiempos con un cronómetro externo: el log serie no lleva marcas de
  tiempo.

---

## 7. Cómo provocar una orden y un reporte

### 7.1 Camino normal desde la app

1. Programar una comida a 2 minutos de la hora actual, con stock suficiente (≥ 100 g).
2. El barrido de 30 s encola la ocurrencia en `dispensing_queue` cuando llega la hora
   (ventana de 10 minutos).
3. El ESP32 consulta cada 20 s y recibe `{"serve": true, "amount": <g>, "order_id": <n>}`.
4. Al terminar el ciclo físico, el firmware envía el reporte y el servidor cierra la orden.
5. La siguiente consulta ocurre 20 s después del fin del ciclo (RF-38).

Una orden pendiente bloquea nuevas entregas durante 5 minutos; la comida programada que
coincida queda en espera y se entrega al cerrar o vencer la anterior.

### 7.2 Disparo reproducible por SQLite (bandera heredada)

Con la API **detenida**, para repetir S4 o provocar un ciclo sin esperar al planificador:

```bash
cd api
source venv/bin/activate
python - <<'PY'
import sqlite3

MAC = "<MAC normalizada, mayúsculas y sin separadores>"
with sqlite3.connect("app/db/pdam.db") as conn:
    cur = conn.execute(
        "UPDATE dispensers SET pending_dispensing = 1 WHERE mac_normalized = ?",
        (MAC,),
    )
    if cur.rowcount == 0:
        raise SystemExit("No existe un dispensador con esa MAC normalizada")
    conn.commit()
print("pending_dispensing activado para", MAC)
PY
```

Al arrancar la API y consultar, la bandera se consume en la misma transacción que crea la
orden, con la cantidad del primer horario de la mascota. Ya no es fuente de verdad: el
planificador no la escribe y `PUT /dispensers/{id}` la ignora; solo se atiende si ya estaba
puesta, como compatibilidad con datos anteriores. Sin horario asociado no hay cantidad y la
bandera no se consume.

### 7.3 Endpoint de diagnóstico

```text
GET http://<ip-del-servidor>:8000/dispenserscheck-taks-test/<MAC>
```

Responde como la entrega real pero **no escribe nada**: ni orden, ni cierre, ni banderas, ni
stock. Sirve para comprobar la forma de la respuesta sin consumir la orden. No usar el
endpoint real con `curl` antes que el ESP32 si se quiere que el dispositivo reciba esa orden:
la orden se consumiría y el firmware ya no la vería.

### 7.4 Reporte manual

Para S4 y S3 hay que enviar el reporte a mano. Solo se aceptan los campos del contrato; el
stock nunca se envía desde el cliente. Con una orden cerrada la respuesta es 200 con
`ya_cerrada: true`; con una orden de otro dispensador, 400 `orden_desconocida`.

---

## 8. Evidencia mínima por prueba

| Prueba | Evidencia a registrar |
|---|---|
| S1 | Salida de los cinco comandos con la cifra de cada suite |
| S2 | Número de columnas, número de filas, identificadores y nulos antes y después; ausencia de `logs_nueva`; salida de `PRAGMA table_info(logs)` |
| S3 | Petición y respuesta de cada caso del §5 S3 (cuerpo 200 o `detail={code,message}`) |
| S4 | `order_id`, stock antes y después, respuesta con `ya_cerrada: false` y con `ya_cerrada: true`, total de registros de la orden |
| S5 | Salida de las cinco ejecuciones y de la prueba de exclusión mutua; en caso de fallo, el intercalado observado |
| S6 | Línea `RNF-2 con … p50=… p95=…` de los dos casos y del índice |
| S7 | Captura del historial con el aviso de datos locales, el total y la página, y del intento con el servidor apagado |
| S8 | Stock antes y después, fila de `refill_operations`, registro `dispenser_refilled` con `origen` `sincronizacion_sin_conexion` |
| P-T8-A | Captura del historial a 130 % de letra en el Samsung A15, con filtros y paginación |
| P-T9-A | Líneas del monitor serie y registro del historial con solicitados, medidos, descontados y stock final |
| P-T9-B | Líneas de los tres intentos con los tiempos medidos y el reenvío tras el reinicio |
| P-T9-C | Línea de descarte y ausencia de `Reporte pendiente encontrado en NVS` tras reiniciar |
| P-T9-D | Registro `feeding_dispensed` con causa `sin_reporte`, sin descuento y con la hora del cierre |

No adjuntar credenciales, tokens, direcciones IP reales ni MAC completas en capturas o
transcripciones.

---

## 9. Pruebas de hardware y en dispositivo

Estas pruebas las ejecuta el usuario con el dispositivo: el agente no puede provocar el
efecto físico ni acceder al router. Ninguna bloquea la suite automatizada, pero sí el cierre
«sin reservas» de la spec (RNF-6).

### 9.1 P-T8-A — adaptación del historial al ancho del móvil (RF-33)

**Pasos.**

1. `cd app/app_movil_pdam && flutter run --debug --host-vmservice-port=8888` con el Samsung
   A15 conectado.
2. Ajustes del sistema → Pantalla → Tamaño de letra: **130 %**; abrir el historial.
3. Recorrer la lista con etiquetas largas («Fallo del sensor durante la dispensación»),
   abrir los cuatro filtros, aplicar un rango de fechas y llegar a la última página.
4. Provocar el error (servidor apagado) y el aviso sin conexión.
5. Repetir en horizontal si el montaje lo permite.

**Resultado esperado.** Sin franjas amarillas/negras de desbordamiento y sin texto cortado;
los controles de página deshabilitados en los extremos; «No hay registros para los filtros
seleccionados» cuando no hay resultados; «Página X de Y» legible; el aviso de datos locales
visible sin tapar la lista.

**Qué registrar.** Captura de la lista, de los filtros abiertos, de la última página y del
estado sin conexión, con el tamaño de letra usado.

**Criterio.** Aprobada si no hay desbordamientos ni texto cortado en ninguno de los estados y
los textos son los de la spec. Fallida ante cualquier franja de overflow o texto truncado.

### 9.2 P-T9-A — reporte real de fin de ciclo (RF-36)

**Pasos.**

1. Servidor en marcha y app abierta en el historial.
2. Programar una comida a 2 minutos, con al menos 100 g de stock.
3. `cd DispensadorESP32 && pio device monitor` antes de la hora programada.
4. Esperar el ciclo completo.

**Qué mirar en el monitor serie.** Que exista una línea con la orden y el motivo, el resumen
del cuerpo y el intento 1 con HTTP 200, seguida de la línea de descarte definitivo:

```text
Reporte de fin de ciclo: orden <order_id>, motivo <motivo>
Reporte a enviar: order_id=<order_id>, motivo=<motivo>, longitud=<n> bytes
Reporte de fin de ciclo: intento 1, HTTP 200
Reporte aceptado o rechazado de forma definitiva: se descarta y no se reintenta.
```

No debe aparecer `Reintentando el reporte en ...` si el servidor respondió 200.

**Qué mirar en el historial.** Un registro `feeding_dispensed` con resultado «Éxito», causa
«Objetivo alcanzado», la mascota, la MAC parcial (`**:XX:YY`), el `order_id` y los gramos; la
orden debe aparecer cerrada y no debe crearse una segunda orden pendiente para la misma
comida.

**Qué anotar.** Los cuatro números del ciclo:

| Dato | Valor |
|---|---|
| Solicitados (g) | |
| Medidos (g) | |
| Descontados (g) | |
| Stock final (g) | |
| `reintentos` del ciclo | |
| Motivo enviado | |

**Criterio.** Aprobada si el monitor muestra un único intento con 200, el historial tiene un
único registro `feeding_dispensed` con los gramos medidos como descontados y el stock final
es igual al stock previo menos los descontados. Fallida si no hay reporte, si el registro no
aparece, si el descuento no coincide con los medidos o si la orden se cierra dos veces. Si el
motivo es `entrega_incompleta` con medidos por debajo de los solicitados, la prueba del
reporte es válida pero el cierre es un fallo de dispensación: se registra como
«No concluyente» para RF-36 y se anota la causa.

### 9.3 P-T9-B — red caída con reinicio (RF-37)

**Pasos.**

1. Iniciar un ciclo con el firmware actual.
2. Apagar el router (o el servidor) durante el ciclo, antes de que termine.
3. Observar los tres intentos y las esperas en el monitor, con cronómetro externo.
4. Reiniciar el ESP32 con la red aún caída y restablecerla después; esperar el arranque.
5. Comprobar en el historial que la orden se cerró una sola vez.

**Tabla de tiempos esperados.**

| Paso | Acción | Log esperado | Tiempo esperado | Tiempo medido | Resultado |
|---|---|---|---|---|---|
| 1 | Primer envío con la red caída | `Reporte de fin de ciclo: intento 1, HTTP <código>` (código negativo o 5xx) | inmediato tras el ciclo | | |
| 2 | Espera del primer reintento | `Reintentando el reporte en 5000 ms...` | 5 s | | |
| 3 | Segundo envío | `Reporte de fin de ciclo: intento 2, HTTP <código>` | +5 s (más hasta 10 s de timeout por intento) | | |
| 4 | Espera del segundo reintento | `Reintentando el reporte en 15000 ms...` | 15 s | | |
| 5 | Tercer envío | `Reporte de fin de ciclo: intento 3, HTTP <código>` | +15 s | | |
| 6 | Se agota la política | `Reporte sin respuesta valida tras los reintentos: se conserva pendiente para reenviarlo tras un reinicio.` | al terminar el intento 3 | | |
| 7 | Reinicio del dispositivo | arranque normal; si entra en aprovisionamiento, el reenvío ocurre al volver a `STATE_NORMAL` | a los pocos segundos del arranque | | |
| 8 | Reenvío del pendiente | `Reporte pendiente encontrado en NVS` y `Reporte de fin de ciclo: intento 1, HTTP 200` | inmediato tras el arranque con red | | |
| 9 | Cierre único | Un solo registro `feeding_dispensed` y un único descuento | — | | |

Plantilla del bloque de intentos:

```text
Reporte de fin de ciclo: intento 1, HTTP -1
Reintentando el reporte en 5000 ms...
Reporte de fin de ciclo: intento 2, HTTP -1
Reintentando el reporte en 15000 ms...
Reporte de fin de ciclo: intento 3, HTTP -1
Reporte sin respuesta valida tras los reintentos: se conserva pendiente para reenviarlo tras un reinicio.
```

Plantilla del reenvío tras el reinicio:

```text
Reporte pendiente encontrado en NVS
Reporte a enviar: order_id=<order_id>, motivo=<motivo>, longitud=<n> bytes
Reporte de fin de ciclo: intento 1, HTTP 200
Reporte aceptado o rechazado de forma definitiva: se descarta y no se reintenta.
```

**Qué registrar.** Los tiempos medidos de cada espera, el código HTTP de cada intento y el
número de registros de la orden en el historial.

**Criterio.** Aprobada si se observan los tres intentos con esperas de 5 s y 15 s, el mensaje
de que se conserva pendiente, el reenvío tras el reinicio con `Reporte pendiente encontrado
en NVS` y un único cierre con un único descuento. Fallida si no hay reenvío, si el reporte se
pierde, si el pendiente no se conserva o si la orden se cierra dos veces. Esta es la única
prueba que acredita la persistencia en NVS y el reenvío: la suite nativa cubre la política de
timeout y reintentos, no `Preferences`.

### 9.4 P-T9-C — descarte definitivo (RF-39)

**Pasos.**

1. Con una orden ya cerrada por el barrido (esperar más de 6 minutos tras el ciclo) o con un
   `order_id` inexistente, ejecutar un ciclo.
2. Observar la respuesta en el monitor.
3. Reiniciar el ESP32 y volver a mirar el arranque.

**Resultado esperado.** Una sola línea de intento con **200** (con `ya_cerrada: true` en el
cuerpo) o con **400** y código `orden_desconocida`; a continuación la línea de descarte
definitivo y **ningún** `Reintentando el reporte en ...`. Tras el reinicio **no** debe
aparecer `Reporte pendiente encontrado en NVS`.

```text
Reporte de fin de ciclo: intento 1, HTTP 400, codigo orden_desconocida
Reporte aceptado o rechazado de forma definitiva: se descarta y no se reintenta.
```

**Criterio.** Aprobada si no hay reintentos y el pendiente no reaparece tras el reinicio. Un
400 no enumerado también se descarta por decisión defensiva del plan (§8.19); si se prueba
ese caso, se registra como comportamiento esperado y no como fallo.

### 9.5 P-T9-D — firmware antiguo (RF-40)

**Pasos.**

1. Flashear una build sin la llamada al reporte: comentar temporalmente el envío en
   `api_service.cpp` solo para esta prueba.
2. Provocar una dispensación y no reportar.
3. Esperar el vencimiento sin reiniciar el servidor.

**Resultado esperado.** A los 5 minutos del plazo, y a más tardar 60 s después del plazo más
la tolerancia de 1 s (barrido de 30 s), la orden se cierra en el historial como
`feeding_dispensed` con resultado «Fallo» y causa «Sin reporte», sin descuento de stock.

**Qué registrar.** Hora de entrega, hora del cierre, stock antes y después y el registro del
historial.

**Criterio.** Aprobada si la orden se cierra con `sin_reporte` dentro de la ventana y el stock
no cambia. Fallida si la orden queda pendiente indefinidamente o si el cierre descuenta.

**Restauración obligatoria.** Al terminar, devolver `api_service.cpp` al contenido
commiteado y comprobar con `git diff DispensadorESP32/` que no queda ninguna edición de
prueba.

---

## 10. Pruebas de no regresión

Se ejecutan sobre el mismo montaje, después de las pruebas de la 014.

| Área | Qué hacer | Qué debe seguir igual |
|---|---|---|
| 011 — nutrición | Calcular una ración desde la app con dos combinaciones de BCS, MCS, actividad, comidas y estatus reproductivo | Mismos gramos que antes de la 014; el aviso de variabilidad (±30 % perros, ±50 % gatos) sigue visible; `test_nutrition*` en verde (181 pruebas + 4 subtests con `test_schedule_service`) |
| 011 — horarios | Crear, modificar y desactivar un horario; provocar una comida | La comida se entrega a su hora (ahora vía cola), sin duplicarse y sin perderse si coincide con una orden pendiente o un dispensador desactivado |
| 012 — tarjeta de stock | Reabastecer con conexión y ver la tarjeta del dispensador | El stock mostrado es el del servidor y respeta el máximo de 5000 g; `test_dispenser_food` y `test_dispenser_mac` en verde (50 + 79 subtests) |
| 012 — reabastecimiento sin conexión | Reabastecer con el servidor apagado y sincronizar al volver | Un único incremento, sin duplicar; la vista optimista se reconcilia con el servidor; `test_sync` en verde |
| 013 — dispensado por peso | Repetir una dispensación de 50 g con alimento | Entrega en el rango del montaje, motivo `objetivo_alcanzado` y `Despacho:` con línea base, peso final e incremento; `test_dispensing_utils` (110) y `test_dispensing_cycle` (22) en verde |
| 013 — atascos | Provocar un atasco y liberarlo durante el reintento | Retroceso de 1,2 s, pausa de 0,3 s, reanudación y `objetivo_alcanzado` con `reintentos > 0`; sin atasco, `reintentos=0` |
| Aprovisionamiento BLE/WiFi | Flashear un build nuevo o ejecutar un reseteo de WiFi; aprovisionar desde la app | Aparece `PDAM-Config-<MAC>`, conecta a WiFi y valida con `Validación HTTP exitosa (Status 200). Entrando en estado normal.`; el servo no se mueve; `test_provisioning_utils` (5) en verde |
| Prioridad de `reset_wifi` | `POST /dispensers/{id}/reset-wifi` con el equipo inactivo y, opcionalmente, con una orden pendiente | La respuesta `{"serve": false, "amount": 0, "reset_wifi": true}` gana sobre cualquier dispensación; la NVS se borra y el equipo reinicia en BLE sin mover el servo |
| Temporizador de 20 s | Tras una dispensación, medir el tiempo hasta la siguiente consulta | Aproximadamente 20 s (20–21 s), no inmediato y sin reinicio del dispositivo; el envío del reporte no altera el intervalo |

Criterio general: cualquier diferencia de comportamiento, o una suite de las specs 011, 012
o 013 en rojo, se registra como regresión y bloquea el cierre aunque la 014 esté aprobada.

---

## 11. Matriz de aceptación

Rellenar la columna «Resultado» al ejecutar cada criterio.

| # | Criterio | Cómo se comprueba | Resultado |
|---|---|---|---|
| C1 | Las cinco comprobaciones automatizadas están en verde con las cifras del §3 | §5 S1 | Aprobado (§3 y §12, S1) |
| C2 | La migración conserva los históricos, deja 18 columnas y es idempotente | §5 S2 | Aprobado (§12, S2) |
| C3 | Los filtros, la paginación y los rechazos 400 del catálogo responden según el contrato | §5 S3 | Aprobado (§12, S3) |
| C4 | Un reporte con medidos ≥ solicitados descuenta lo medido y un duplicado no repite el efecto | §5 S4 | Aprobado (§12, S4) |
| C5 | Dos reportes simultáneos y el reporte contra el barrido producen un único cierre y un único descuento | §5 S5 | Aprobado (§12, S5) |
| C6 | El p95 de la consulta con 10 000 registros y cuatro filtros es inferior a 1 s | §5 S6 | Aprobado (§12, S6: p95 16,5 ms) |
| C7 | Sin conexión, el historial muestra la caché con aviso, filtros y paginación, sin borrar la lista | §5 S7 | Aprobado (§12, S7) |
| C8 | El mismo pendiente sincronizado dos veces con el mismo `operation_id` suma una sola vez | §5 S8 | Aprobado (§12, S8) |
| C9 | El historial se ve sin desbordamientos en el móvil con letra al 130 % | §9.1 P-T8-A | Aprobado (§12, P-T8-A) |
| C10 | El servidor recibe el reporte tras una dispensación real y la orden se cierra una vez | §9.2 P-T9-A | Aprobado (§12, P-T9-A) |
| C11 | El reporte sobrevive a una red caída, se conserva en NVS y se reenvía tras el reinicio | §9.3 P-T9-B | Aprobado (§12, P-T9-B) |
| C12 | Un reporte descartado no se reenvía tras el reinicio | §9.4 P-T9-C | Aprobado (§12, P-T9-C) |
| C13 | Una orden de un firmware sin reporte se cierra por plazo con `sin_reporte` y sin descuento | §9.5 P-T9-D | Aprobado (§12, P-T9-D) |
| C14 | Las specs 011, 012 y 013 no presentan regresiones | §10 | Aprobado (§3 A1–A4: ninguna suite de las specs previas en rojo) |
| C15 | No se añadieron dependencias externas nuevas (RNF-4) | Revisión de `requirements.txt`, `pubspec.yaml` y `platformio.ini` | Aprobado (§3, notas de dependencias) |
| C16 | Los 41 RF tienen prueba automatizada y los cinco con efecto físico o visual tienen su procedimiento manual | `tests/test_traceability_rf.py` y §9 | Aprobado (41/41 y las cinco pruebas manuales del §12) |

---

## 12. Registro de resultados

Rellenar únicamente después de ejecutar cada prueba. No completar con valores supuestos.

| ID | Fecha | Ejecutor | Resultado | Evidencia | Observaciones |
|---|---|---|---|---|---|
| S1 | 2026-10-29 | Agente | Aprobada | Auditoría del §3: `pytest` 530 passed + 541 subtests, `flutter test` 412/412, `flutter analyze` 0 errores (95 avisos), `pio test -e native` 157/157, `pio run` SUCCESS | Cifras iguales o superiores a las del §3; ningún fallo ni omisión |
| S2 | 2026-10-29 | Agente | Aprobada | `s2-despues-primera.txt`, `s2-despues-segunda.txt`, `s2-consulta.json`, `s2-aborto.log` (`/tmp/opencode/pruebas-014/`) | Ejecutada sobre una base legada reconstruida desde una **copia aislada**, no sobre la base de desarrollo: 18 columnas, 4 históricos con `description`/`created_at` conservados, 8 índices y las 3 tablas nuevas; la segunda apertura no remigró; el criterio de aborto pasó con `TestMigracionSegura` (1 passed, 0,44 s) |
| S3 | 2026-10-29 | Agente | Aprobada | `s3.log` (23 casos S3.1–S3.23) | 23/23 sobre una **copia aislada**; los 4 históricos de la copia son del 1–3 de septiembre, así que S3.4/S3.5 con fechas de octubre dan `total=0` y se añadieron las variantes S3.4b/S3.5b sobre septiembre (4 ítems, con `Z` y con UTC−05:00); stock 1200 → 2700 g con idempotencia por `operation_id`; todos los rechazos de negocio 400 con `detail={code,message}` |
| S4 | 2026-10-29 | Agente | Aprobada | `s4.log`, `s4.rep1`–`s4.rep3` | Copia aislada; la entrega no descuenta (2700 g), el cierre con 50,0 solicitados y 50,4 medidos descuenta 50,4 y deja 2649,6 g; los dos reenvíos responden 200 con `ya_cerrada=true`, sin segundo registro ni segundo descuento |
| S5 | 2026-10-29 | Agente | Aprobada | `s5.log` | **5/5** ejecuciones de `test_orders_concurrency.py` con 6 passed y 0 failed (1,09–1,30 s) y `TestExclusionMutuaConElReporte` con 4 passed; cumple el criterio de 5 de 5 |
| S6 | 2026-10-29 | Agente | Aprobada | `s6.log` | p95 **16,5 ms** con 10 000 registros y cuatro filtros; 15,7 ms en la primera página sin filtros; índice compuesto `ix_logs_user_id_created_at` presente; criterio p95 < 1000 ms cumplido |
| S7 | 2026-10-29 | Usuario (hardware/app real) | Aprobada | Historial del móvil con la API apagada: los registros se sirvieron desde la caché Isar y apareció el aviso de datos locales | Confirmado por el usuario; con el servidor detenido la app mostró los registros de la caché con el aviso de datos locales |
| S8 | 2026-10-29 | Agente | Aprobada | `s8.log` | Con `origen=sincronizacion_sin_conexion` y el mismo `operation_id`, un único incremento (2649,6 → 2949,6), una fila en `refill_operations` y un solo `dispenser_refilled`; sin identificador el servidor no deduplica (dos envíos, dos incrementos), limitación declarada |
| P-T8-A | 2026-10-29 | Usuario (hardware/app real) | Aprobada | Comprobación en el Samsung A15: los registros aparecen, los cuatro filtros y la paginación funcionan y el registro nuevo se reflejó al levantar la API | Confirmado por el usuario en el móvil real; la aprobación se basa en su comprobación directa, sin captura ni medición del tamaño de letra |
| P-T9-A | 2026-10-29 | Usuario (hardware/app real) | Aprobada | Dos ciclos reales con `Reporte de fin de ciclo: intento 1, HTTP 200` al primer intento. Orden 3: 17,27 g solicitados, 22,23 g medidos y descontados, stock 4637,16 → 4614,93 g. Orden 4: atasco no resuelto, −6,28 g medidos y sin descuento, stock 4614,93 g | La orden 1 (344,75 g medidos) se descarta como evidencia porque el usuario manipuló la celda al no tener la bandeja colocada; no es un fallo del sistema. El resumen del monitor mostraba «no disponible» y se corrigió en `f10802d`; el firmware reflasheado se verificó en el ciclo siguiente, que imprimió `order_id=5` y el motivo real |
| P-T9-B | 2026-10-29 | Agente | Aprobada | Tres intentos con la API caída: 15:51:47 HTTP −1, espera de 5 s, 15:52:02 HTTP −1, espera de 15 s, 15:52:27 HTTP −1 y «se conserva pendiente para reenviarlo tras un reinicio». Reinicio con la API caída: WiFi OK, validación HTTP −1 y vuelta a BLE con el pendiente conservado. Reinicio con la API en marcha: `Reporte pendiente encontrado en NVS`, reenvío de la orden 5 con HTTP 200 al intento 1 y cierre único (un solo registro, sin descuento, stock 4614,93 g) | Matiz aceptado por el usuario: el reinicio se retrasó más de 5 min, así que el barrido ya había cerrado la orden 5 como `sin_reporte`; el reenvío llegó 0,8 s después y se aceptó como orden ya cerrada. La prueba se aprueba tal como quedó ejecutada |
| P-T9-C | 2026-10-29 | Agente | Aprobada | El reenvío de P-T9-B recibió 200 de orden ya cerrada y el firmware descartó el reporte sin reintentar (ninguna línea `Reintentando el reporte en ...`); tras reiniciar de nuevo, la placa **no** mostró `Reporte pendiente encontrado en NVS` | Confirmado por el usuario en el arranque del equipo: no hay reintento ni pendiente que sobreviva al segundo reinicio |
| P-T9-D | 2026-10-29 | Agente | Aprobada | La orden 5 se cerró sola a los ~5 min como `feeding_dispensed` con causa `sin_reporte`, sin descuento y sin exigir reporte; el stock siguió en 4614,93 g | Evidencia del servidor, que es donde vive el comportamiento pedido para firmware antiguo; no se flasheó una build sin la llamada al reporte porque no hace falta para acreditar RF-40 |

Valores admitidos en «Resultado»: **Aprobada**, **Fallida**, **No concluyente**,
**No ejecutada**. En «Evidencia» se anota el nombre del log, la captura o la prueba
automatizada concreta, sin datos sensibles.

**Corrección derivada de P-T9-A (2026-10-29).** Durante la prueba el servidor respondió
200 y procesó bien los dos reportes, pero la línea de resumen del monitor mostraba
`order_id=no disponible, motivo=no disponible`: el resumen releía el cuerpo con un
`StaticJsonDocument<192>` en el que no caben los seis miembros del reporte, así que la
lectura fallaba y caía al texto de reserva. El resumen pasa a formatearse con los datos del
`ReporteCiclo` (`reporting::formatearResumenCiclo`), sin releer el JSON, y el reenvío desde
la NVS recupera orden y motivo con `reporting::extraerResumenReporte`. El cuerpo JSON, la
política de reintentos y el orden de los mensajes no cambian. Pruebas nuevas en
`test_report_utils.cpp` (6): `pio test -e native` pasa de 157 a **163/163** y `pio run`
sigue en SUCCESS (RAM 64 444 B, 19,7 %; Flash 2 024 874 B, 64,4 %). El firmware corregido se
flasheó en el ESP32 de pruebas el 2026-10-29 (`pio run --target upload`, hash verificado).

---

## 13. Riesgos, deudas y criterios de cierre

### 13.1 Deudas aceptadas

| Deuda | Consecuencia | Mitigación actual |
|---|---|---|
| Una entrega incompleta o un reporte tardío no descuentan stock | El stock del servidor queda por encima del real; solo se corrige con un reabastecimiento o un ajuste manual futuro, fuera de alcance | Desvío documentado en la spec y en `tasks.md`; no hay ajustes automáticos |
| Sin `operation_id` el servidor no puede deduplicar reenvíos | Un cliente antiguo duplicaría la cantidad al sincronizar el mismo pendiente | La app lo envía siempre y lo persiste con el pendiente; la limitación está en la spec |
| La persistencia del reporte en NVS y el reenvío tras reinicio solo se acreditan con P-T9-B | La suite nativa cubre la política de timeout y reintentos, no `Preferences` | Acreditada en P-T9-B el 2026-10-29 (§12); la suite nativa sigue sin cubrir `Preferences` |
| La ventana de 10 minutos de `encolar_comida` no recupera ocurrencias | Si el proceso cae más tiempo, la comida de ese hueco no se encola | Documentado en T5; el barrido corre cada 30 s |

### 13.2 Riesgos abiertos

| Riesgo | Impacto | Cómo se controla |
|---|---|---|
| Los umbrales de la 013 solo son válidos para este montaje (celda, cableado y croqueta de ~3 cm) | Atascos mecánicos frecuentes y exactitud dependiente del montaje | No se ajustaron umbrales; si se cambia el montaje, se repiten P2/P3 de la 013 antes de confiar en la 014 |
| La rama `pruebas/endpoint-fijo-hx711` con la 013 cerrada sigue sin fusionar a `main` | El código validado no está en la rama principal | Merge pendiente, fuera del alcance de este informe; el commit de referencia es `fd4c047` |

Riesgo cerrado el 2026-10-29: las cinco pruebas físicas y en dispositivo (P-T8-A y P-T9-A a
P-T9-D) están ejecutadas y aprobadas, con su evidencia en el §12 y en el cierre de
`tasks.md`. No queda ninguna prueba de esta spec sin ejecutar. El matiz de P-T9-B —el
reinicio llegó después de que el barrido cerrara la orden 5, y el reenvío se aceptó como
orden ya cerrada— fue aceptado por el usuario y no cambia el comportamiento implementado.

### 13.3 Cuándo se puede decir que «todo funciona»

Solo cuando se cumplan las tres condiciones a la vez:

1. Las cinco comprobaciones automatizadas del §3 en verde, con cifras iguales o superiores.
2. S2 a S8 aprobadas, con la evidencia registrada en el §12.
3. Las cinco pruebas físicas y en dispositivo aprobadas: P-T8-A, P-T9-A, P-T9-B, P-T9-C y
   P-T9-D.

**Las tres condiciones se cumplen a 2026-10-29:** las cinco suites están en verde (§3), S2 a
S8 están aprobadas (§12) y P-T8-A y P-T9-A a P-T9-D también (§12). Por eso la spec 014 se
actualiza a «implementada y validada (2026-10-29)» y `tasks.md` recoge el cierre de las
pruebas físicas. Las deudas aceptadas del §13.1 siguen vigentes tal como están descritas:
una entrega incompleta o un reporte tardío no descuentan stock, un cliente sin
`operation_id` no se puede deduplicar y la ventana de 10 minutos de `encolar_comida` no
recupera ocurrencias perdidas. Ninguna prueba manual sustituye a una automatizada, ni al
contrario (RNF-6).

---

## 14. Definiciones

- **Orden pendiente:** orden de dispensación entregada al dispositivo que todavía no ha sido
  cerrada, ni por reporte ni por vencimiento del plazo. Bloquea nuevas entregas al mismo
  dispensador.
- **Orden cerrada:** orden con resultado definitivo, sea éxito o fallo. No vuelve a cambiar de
  estado ni de resultado.
- **Medidos:** gramos que el dispositivo declara haber entregado según su celda de carga.
  Pueden faltar cuando el sensor no está disponible y entonces se registran como «no
  disponible».
- **Descontados:** gramos que el servidor resta del stock al cerrar con éxito. Es igual a los
  medidos acotado entre 0 y el stock disponible en ese instante, y se guarda en un campo
  distinto del de medidos.
- **Faltante:** diferencia entre medidos y descontados cuando los medidos superan el stock
  disponible. Se refleja en el contexto y nunca deja stock negativo.
- **Plazo y tolerancia:** 5 minutos desde la fecha y hora de entrega según el reloj del
  servidor, más una tolerancia explícita de 1 segundo que todavía cuenta como dentro del
  plazo. Pasado ese instante, un reporte cierra como `orden_cerrada` y el barrido puede
  haber cerrado antes como `sin_reporte`.
- **`ya_cerrada`:** indicador booleano de la respuesta del reporte que vale `true` cuando la
  orden ya tenía resultado. La respuesta repite el resultado guardado y no hay segundo
  registro ni segundo descuento.
- **Firmware antiguo:** versión que no envía reporte al terminar el ciclo. Sus órdenes se
  cierran por plazo como `sin_reporte`, sin descuento y sin exigir reporte.
- **MAC parcial:** representación del dispensador que conserva solo los dos últimos octetos
  en mayúsculas separados por dos puntos y oculta el resto con un prefijo literal de dos
  asteriscos, por ejemplo `**:AB:1F`. La MAC completa no se guarda en el registro ni se
  devuelve en la consulta.
- **Históricos sin clasificar:** registros anteriores a esta spec sin tipo de evento,
  resultado ni causa. Se muestran con la etiqueta «Sin clasificar», aparecen en la consulta
  sin filtros y quedan excluidos al filtrar por tipo o por resultado; no son un tipo del
  catálogo ni se pueden filtrar por causa.
