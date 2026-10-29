# Plan — Spec 014

Spec de referencia: `specs/014-logs-y-validacion-dispensado/spec.md` (aprobada el 2026-10-28; 41 RF, 8 RNF, catálogos y mapeo RF→prueba).
Alcance: `api/`, `app/app_movil_pdam/` y `DispensadorESP32/`. No se implementa nada hasta aprobar este plan y `tasks.md`.
Cumplimiento: `docs/constitution.md` (FastAPI + SQLite + Flutter/BLoC/Isar + ESP32; trazabilidad RF→prueba; lógica fuera de las vistas; tests en las tres capas; sin datos sensibles; textos en español) y `AGENTS.md` (Clean Architecture, Offline-First, temas globales, sin dependencias nuevas).

## 0. Punto de partida: árbol limpio y descarte de la implementación parcial

Hay cambios **sin commit** en `api/app/models/models.py`, `api/app/schemas/schemas.py` y `api/app/services/logs_service.py` que el usuario ha decidido descartar. La primera tarea restaura esos tres archivos al estado de `HEAD` y no se reutiliza nada de ellos.

| Descartado (no reutilizar) | Sustituto en este plan |
|---|---|
| `ActivityLog.event` como texto libre | `description` (texto fijo en español) + `event_type` (código cerrado) |
| `ActivityLog.resultado` | `outcome` (`success`/`failure`) |
| `ActivityLog.stock_solicitado` / `stock_medido` / `stock_resultante` | `requested_grams` / `measured_grams` / `resulting_stock`, más `discounted_grams` |
| `ActivityLog.dispensador_mac_parcial` | `dispenser_mac_masked` |
| `ActivityLog.reintentos` | `retry_count` |
| `ActivityLog.descripcion_contexto` | `description` + `context` (JSON en `TEXT`) |
| `validar_stock_despues_dispensado`, `crear_log_con_stock`, `obtener_logs_paginados` | Funciones de dominio puras + `activity_service` transaccional |
| Columna `fecha` en `GET /logs/` | `from`/`to` ISO 8601 con desplazamiento explícito y paginación |
| Descuento de stock en `check_pending_task` | Descuento solo al cierre confirmado de la orden |

La migración es idempotente y **también repara** una base que hubiera llegado a tener las columnas parciales: reconstruye `logs` una sola vez y conserva las filas existentes como «Sin clasificar» (RF-41).

## 1. Arquitectura de la solución

- **Dominio puro** (`api/app/domain/`): catálogos cerrados, cálculo de cierre, descuento acotado, plazos, parseo de instantes, paginación y validación de filtros. Sin SQLAlchemy, sin FastAPI y con el instante `ahora` como parámetro.
- **Servicios** (`api/app/services/`): transacciones, consultas y orquestación. Reciben `db` y `ahora`; no leen el reloj directamente salvo el valor por defecto.
- **API** (`api/app/api/endpoints/`): contratos y códigos HTTP. Las validaciones de negocio se hacen en servicio para no responder 422.
- **Persistencia** (`api/app/models/`, `api/app/db/database.py`): tres tablas nuevas (`dispensing_orders`, `dispensing_queue`, `refill_operations`), `logs` reconstruida e índices de consulta.
- **App móvil**: entidad y modelo tipados, datasource remoto con el contrato nuevo, caché Isar con filtros y paginación, BLoC con el estado completo y vistas sin lógica.
- **Firmware**: cabecera pura `report_utils.h`, servicio de reporte con reintentos y NVS, y ajustes mínimos en `api_service` y `dispenser_task`.

## 2. Archivos y responsabilidades

### 2.1 Dominio backend (nuevo)

- `api/app/domain/catalogos.py`: catálogos cerrados de tipos de evento, resultados y causas con sus etiquetas en español; subconjunto de motivos admitidos en un reporte (`objetivo_alcanzado`, `objetivo_no_alcanzado`, `atasco_no_resuelto`, `sensor_no_disponible`, `fallo_sensor_dispensacion`, `orden_invalida`); catálogo de errores con `code` y `message` exactos de la spec; `resultado_para_motivo(motivo)`; `es_tipo_valido`, `es_resultado_valido`, `es_causa_de_reporte`; etiqueta «Sin clasificar». RF-2, RF-3, RF-7, RF-14, RF-17, RF-21, RF-24, RNF-1, RNF-7.
- `api/app/domain/tiempo.py`: `ahora_utc()`; `parsear_instante_explicito(texto)` (acepta `Z` como `+00:00`, rechaza naive e inválidos); `a_utc_naive(instante)`; `dentro_del_plazo(entregada_en, ahora)`; `plazo_vencido(entregada_en, ahora)` con tolerancia de 1 s inclusiva; constantes `PLAZO_ORDEN = 5 min`, `TOLERANCIA = 1 s`, `INTERVALO_BARRIDO = 30 s`. RF-19, RF-20, RF-30, RF-31, RNF-3, RNF-8.
- `api/app/domain/cierre.py`: `resolver_cierre_por_reporte(motivo, solicitados_orden, medidos, ahora, entregada_en)` → `(outcome, cause, motivo_late)`; reglas de `objetivo_alcanzado` con medidos ausentes/menores, causas de fallo y cierre tardío. `calcular_descuento` vive en `stock.py`. RF-15, RF-16, RF-17, RF-20.
- `api/app/domain/consulta.py`: `normalizar_paginacion(pagina, tamano)`; `validar_filtros(tipo, resultado, desde, hasta)` con precedencia definida; `total_paginas(total, tamano)` (`max(1, ceil)`); `orden_estable()` (`created_at DESC, id DESC`). RF-30, RF-31, RF-32, RNF-2.
- `api/app/domain/stock.py`: `calcular_descuento(medidos, stock_disponible)` → `(descontados, faltante)`; `normalizar_gramos(cantidad, unidad)`; `aplicar_descuento_acotado(stock, medidos)`; `aplicar_reabastecimiento(stock, gramos)`; `stock_fuera_de_rango`; `CAPACIDAD_MAXIMA_GRAMOS`. Reparto entre tareas: T3 deja `calcular_descuento` y la constante de capacidad; T4 añade el descuento acotado del cierre y los límites que lo validan (`aplicar_descuento_acotado`, `stock_fuera_de_rango`); T6 añade el reabastecimiento (`normalizar_gramos`, `aplicar_reabastecimiento`). El intervalo de stock lo validan esas dos funciones. RF-15, RF-22, RF-23.

Se amplía `api/app/services/mac_service.py` con `mask_mac(mac)` → `**:AB:1F` (normaliza primero, últimos dos octetos en mayúsculas, prefijo literal `**`). RF-3, RNF-1.

### 2.2 Modelos, esquemas y migración

- `api/app/models/models.py`: `ActivityLog` rediseñada (ver §6), `DispensingOrder`, `DispensingQueue`, `RefillOperation`; relaciones `User.logs` se conservan. RF-3, RF-6, RF-13, RF-24, RF-41.
- `api/app/models/__init__.py`: exporta los modelos nuevos.
- `api/app/schemas/logs.py` (nuevo): `ActivityLogItem`, `ActivityLogPage`, `ActivityLogContext`; etiquetas y campos tipados. RF-26, RF-32, RF-33.
- `api/app/schemas/reports.py` (nuevo): `DispenserReportRequest` permisivo con **todos** los campos `Any` y valor por defecto `None` (`mac`, `order_id`, `motivo`, `gramos_solicitados`, `gramos_medidos`, `reintentos`) y `extra="ignore"`, para que los rechazos sean 400 del catálogo y nunca 422; `DispenserReportResponse`. RF-14, RF-18, RF-20, RF-21.
- `api/app/schemas/dispenser.py`: `DispenserRefillRequest` deja de usar `gt=0` (la validación pasa al servicio) y añade `operation_id: Optional[str]` y `origen: Optional[str]`; `DispenserResponse` sigue devolviendo el stock autoritativo. RF-11, RF-12, RF-23.
- `api/app/schemas/schemas.py`: se retiran las clases `ActivityLog*` (pasan a `schemas/logs.py`); no se añaden reglas de negocio en Pydantic.
- `api/app/db/database.py`: migración `_migrar_logs(conexion, cursor)` extraída como función para poder probarla; se invoca en el listener `connect` antes de `create_all`; reconstruye `logs` si falta `event_type` o si existen columnas parciales; crea los índices de §6; `Base.metadata.create_all` crea las tablas nuevas en bases existentes. RF-3, RF-6, RF-41, RNF-8.
- `api/seed_logs.py`: adaptado a las columnas nuevas; siembra filas sin tipo para ejercitar «Sin clasificar».

### 2.3 Servicios backend

- `api/app/services/activity_service.py` (nuevo): `registrar(db, ...)` añade el registro **sin commit** (lo confirma el llamador en su transacción); `registrar_rechazo(...)` escribe en una `SessionLocal` independiente y confirma; `a_item(log)` serializa etiquetas y contexto. RF-1, RF-2, RF-3, RF-11, RF-12, RF-24, RNF-1.
- `api/app/services/order_service.py` (nuevo): `entregar_orden(db, mac, ahora)`, `procesar_reporte(db, payload, ahora)`, `cerrar_vencidas(db, ahora)`, `encolar_comida(db, ahora)`, `entregar_comida_en_espera(...)`. Toda transición usa `UPDATE ... WHERE status='pending'` y comprueba `rowcount`. RF-13 a RF-25, RF-40, RNF-3.
- `api/app/services/logs_service.py`: reescrito; solo consulta y serialización (sin `crear_log` público ni validación de stock). RF-26 a RF-32, RF-41.
- `api/app/services/dispenser_service.py`: `create_new_dispenser` recibe `user_id` y registra `dispenser_linked`; `update_dispenser` registra `dispenser_updated` con nombres de campos; `delete_dispenser` registra `dispenser_unlinked`; `reset_wifi_credentials` registra `dispenser_wifi_reset`; `refill_dispenser` registra aceptados y rechazados, aplica idempotencia y origen; `check_pending_task` deja de descontar y entrega `order_id`. RF-1, RF-2, RF-7 a RF-12, RF-13, RF-22, RF-23, RF-25.
- `api/app/services/pet_service.py`: registra `pet_created`, `pet_updated` (nombres de campos) y `pet_deleted` (referencia conservada) en la misma transacción. RF-4, RF-5, RF-6.
- `api/app/services/background_tasks/background_schedules.py`: `ejecutar_barrido` ejecuta primero `cerrar_vencidas` y después `encolar_comida`; pasa de activar `pending_dispensing` a encolar la comida programada una sola vez por ocurrencia. El ciclo de vencimiento para el firmware antiguo vive en `order_service.cerrar_vencidas` y se invoca desde este barrido. RF-19, RF-25, RF-40.
- `api/app/main.py`: un único job cada `INTERVALO_BARRIDO` (30 s) que ejecuta primero `cerrar_vencidas` y después `encolar_comida`; `max_instances=1` y `coalesce=True`. RF-19, RNF-3.

### 2.4 API

- `api/app/api/endpoints/logs.py`: `GET /logs/` con el contrato nuevo; `GET /logs/catalog` con tipos y resultados para los filtros; **se elimina** `POST /logs/`. RF-2, RF-26 a RF-33.
- `api/app/api/endpoints/dispenser.py`: `GET /dispensers/check-taks/{mac}` con `order_id`; `POST /dispensers/reports` (sin token, autenticado por MAC registrada); `POST /dispensers/{id}/refill` con `operation_id`/`origen`. RF-11 a RF-25, RF-36 a RF-40.
- `api/app/api/endpoints/pets.py`: pasa `user_id` a los servicios para el registro (sin cambiar el contrato de entrada/salida). RF-4, RF-5, RF-6.

### 2.5 Pruebas backend

- `api/tests/test_logs_migration.py`, `test_logs_domain.py`, `test_orders_dispensing.py`, `test_orders_expiry.py`, `test_feeding_queue.py`, `test_activity_logs_crud.py`, `test_refill_logs.py`, `test_logs_query.py`, `test_logs_errors.py`, `test_orders_concurrency.py`, `test_logs_performance.py`.
- Se reescriben: `test_dispenser_food.py` (el descuento al entregar pasa a «no descuenta» y los códigos de refill cambian), `test_protected_routes.py` y `test_api_basic.py` (sin `POST /logs/`, con `GET /logs/catalog`).
- Se conserva el patrón existente: `SessionLocal` sobre `test.db`, `app.dependency_overrides[get_current_user]` y `MagicMock` solo donde no se prueba persistencia.

### 2.6 App móvil

- `lib/features/logs/domain/entity/activity_log.dart`: entidad tipada (`eventType`, `eventLabel`, `outcome`, `outcomeLabel`, `cause`, `causeLabel`, `description`, `petId`, `petName`, `dispenserMacMasked`, `orderId`, gramos, `retryCount`, `context`) y `LogPage`/`LogCatalog`.
- `lib/features/logs/domain/entity/log_filters.dart` (nuevo): `LogFilters` inmutable, `copyWith`, `hasActiveFilters`; `LogSort` no aplica (orden fijo del servidor).
- `lib/features/logs/domain/utils/` (nuevo): `formatearInstanteConDesplazamiento(DateTime, {Duration? offset})`, `rangoDiaLocalAInstantes(DateTime inicio, DateTime fin, {Duration? offsetInicio, Duration? offsetFin})`, `calcularTotalPaginas(total, tamanoPagina)`, `formatearFechaHoraLocal(DateTime)`, `generarIdentificadorOperacion()` con `dart:math` (sin dependencias). RF-30, RF-32, RF-33, RNF-4.
- `lib/features/logs/data/models/activity_log_model.dart`: `fromJson`/`toJson` con el contrato nuevo.
- `lib/features/logs/data/datasource/remote/log_remote_datasource.dart`: parámetros `pet_id`, `event_type`, `outcome`, `from`, `to`, `page`, `page_size`; parsea el sobre; `getCatalog()`.
- `lib/features/logs/data/datasource/local/local_log_datasource.dart`: filtros, orden y paginación en Isar; `cacheLogs` hace upsert por `remoteId`; `countLogs` para los totales de caché. RF-34, RF-35.
- `lib/core/offline/models/local_log.dart` (+ `.g.dart` regenerado con `build_runner`): campos nuevos e índices (`remoteId` único, `timestamp`, `petRemoteId`, `eventType`, `outcome`).
- `lib/features/logs/data/repository_impl/log_repository_impl.dart`: remoto → caché; si falla, caché con los mismos filtros y página; nunca borra la lista previa antes de tener el nuevo resultado. RF-34, RF-35.
- `lib/features/logs/domain/repository/log_repositories.dart`, `use_case/get_logs_uc.dart`, `use_case/get_log_catalog_uc.dart` (nuevo): contrato con `LogFilters` y `page`.
- `lib/features/logs/presentation/bloc/log_event.dart`, `log_state.dart`, `log_bloc.dart`: estado con ítems, filtros, página, `total`, `isLoading`, `errorMessage`, `isOffline`, `catalog`; eventos de filtros, página, limpieza, reintento y catálogo. RF-33, RF-34, RNF-5.
- `lib/features/logs/presentation/views/logs_view.dart`: solo compone; sin `setState` de negocio.
- `lib/features/logs/presentation/widgets/`: `log_filters_bar.dart` (mascota, tipo, resultado, rango y «Limpiar filtros»), `log_item_widget.dart` (etiquetas, mascota, MAC parcial, gramos), `log_pagination_bar.dart` («Página X de Y · N registros», anterior/siguiente deshabilitados en extremos), `log_notice_widget.dart` (sin conexión / vacío / error con reintento). RF-33, RF-34.
- `lib/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart`: código `supera_capacidad`; `operation_id` persistido junto al pendiente; reconciliación al sincronizar sin duplicar. RF-11, RF-12.
- `lib/core/offline/models/local_dispenser.dart`: `pendingRefillId` (aditivo) y su `.g.dart`. RF-11.
- Pruebas: `test/features/logs/...` (modelo, utilidades, datasource local/remoto, repositorio, BLoC, widget) y actualización de las pruebas de refill existentes.

### 2.7 Firmware

- `DispensadorESP32/src/config/report_utils.h` (nuevo, sin Arduino): `MotivoReporte`; `motivoPara(DispenseReason)`; `ReporteCiclo` (orden, solicitados/medidos con disponibilidad, reintentos); `construirReporteJson(...)` con `snprintf` y omisión de campos no disponibles; `DecidirReintento` (`INTENTAR`, `REINTENTAR`, `DESCARTAR`, `CONSERVAR`); `clasificarRespuestaReporte(status, codigo)`; constantes `kReportTimeoutMs = 10000`, `kReportRetryDelaysMs = {5000, 15000}`. RF-36, RF-37, RF-39, RNF-4.
- `DispensadorESP32/src/services/report_service.{h,cpp}` (nuevo): persiste el JSON en NVS (`pdam_report`, clave `pending`), envía por HTTP, aplica la política de reintentos, descarta o conserva, y limpia NVS solo ante respuesta definitiva. RF-37, RF-39.
- `DispensadorESP32/src/services/api_service.cpp`: parsea `order_id`; envía reporte tras `dispenseWeight`; con `serve:true` y orden inválida envía `orden_invalida` sin gramos; cierra HTTP antes del ciclo. RF-36.
- `DispensadorESP32/src/tasks/dispenser_task.cpp`: al entrar en `STATE_NORMAL` reenvía el reporte pendiente antes de consultar; conserva el temporizador de 20 s. RF-37, RF-38.
- `DispensadorESP32/src/config/config.h`: URL de reporte y timeouts; **no** se tocan umbrales, ventanas, presupuesto ni `CHECK_INTERVAL`. RF-38.
- `DispensadorESP32/test/test_report_utils/` (nuevo) y `platformio.ini` (`test_ignore` incluye la suite nueva). RF-36, RF-37, RF-39, RF-38.

## 3. Funciones puras (el instante y el stock son parámetros)

| Función | Responsabilidad | RF |
|---|---|---|
| `mask_mac(mac)` | `AA:BB:CC:DD:AB:1F` → `**:AB:1F`; normaliza antes | RF-3, RNF-1 |
| `parsear_instante_explicito(texto)` | Acepta `Z` y desplazamientos; rechaza naive e inválidos; devuelve UTC | RF-30, RF-31 |
| `dentro_del_plazo(entregada_en, ahora)` / `plazo_vencido(...)` | Límite `entregada_en + 5 min + 1 s` inclusivo | RF-19, RF-20 |
| `resolver_cierre_por_reporte(motivo, solicitados, medidos, ahora, entregada_en)` | Decide `(outcome, cause)` y si es cierre tardío | RF-15, RF-16, RF-17, RF-20 |
| `calcular_descuento(medidos, stock)` | `descontados = clamp(medidos, 0, stock)`, `faltante = max(0, medidos - descontados)` | RF-15, RF-22 |
| `aplicar_reabastecimiento(stock, gramos)` | Suma válida en 0..5000 g o error de dominio | RF-12, RF-22 |
| `validar_filtros(...)` | Conjunción, catálogos cerrados y orden de rechazo | RF-31 |
| `normalizar_paginacion(pagina, tamano)` | 1..∞ y 1..100, sin recortes silenciosos | RF-32 |
| `total_paginas(total, tamano)` | `max(1, ceil(total / tamano))` | RF-32, RF-33 |
| `motivoPara(reason)` | Motivo del reporte por cada fin de ciclo | RF-36 |
| `construirReporteJson(...)` | JSON con MAC, orden, motivo, solicitados, medidos y reintentos; omite ausentes | RF-36 |
| `clasificarRespuestaReporte(status, codigo)` | Descarta 200 y 400 de `orden_desconocida`, `motivo_invalido`, `mac_no_registrada`; reintenta red/timeout/5xx | RF-39 |
| `formatearInstanteConDesplazamiento(...)` | ISO con `-05:00`/`Z`, offsets independientes por límite | RF-30, RNF-4 |
| `calcularTotalPaginas(total, tamano)` | Misma regla que el servidor para la caché | RF-34 |

## 4. Algoritmo en pseudocódigo

### 4.1 Entrega de una orden (`check_pending_task`)

```
ENTREGAR(mac, ahora_utc):
  disp = buscar por mac_normalized; si no existe → 404 (sin log)
  si disp.pending_wifi_reset → limpiar bandera, commit, {serve:false, reset_wifi:true} (sin orden)
  orden_vigente = orden pending del disp con dentro_del_plazo(delivered_at, ahora_utc)
  si orden_vigente → {serve:false, amount:0}          // RF-25; la cola permanece
  orden_vencida = orden pending con plazo_vencido(delivered_at, ahora_utc)
  si existe → cerrar_vencida(orden, ahora_utc); {serve:false, amount:0}
                                                     // la cola se entrega en la consulta siguiente
  si !disp.is_active → {serve:false, amount:0}       // RF-25; la cola permanece
  mientras haya ocurrencias sin consumir, de la más antigua a la más nueva:
    UPDATE dispensing_queue SET consumed_at=:ahora
      WHERE id=:id AND consumed_at IS NULL
    si rowcount == 0 → rollback; probar la siguiente  // otra consulta la sirvió
    orden = crear(status=pending, user_id=dueño, pet_id/item, dispenser_id, pet_name,
                  mac_masked, requested_grams=item.amount, delivered_at=ahora_utc)
    commit                                            // misma transacción; sin tocar stock (RF-13)
    return {serve:true, amount:item.amount, order_id:orden.id}
  si disp.pending_dispensing (solo dato heredado y ya no aceptado en PUT):
    UPDATE dispensers SET pending_dispensing=0 WHERE id=:id AND pending_dispensing=1
    si rowcount == 0 → {serve:false, amount:0}
    orden = crear(status=pending, ..., delivered_at=ahora_utc); commit
    return {serve:true, amount:horario.amount, order_id:orden.id}
  return {serve:false, amount:0}
```

La consulta que cierra una orden vencida responde reposo y **no** entrega la cola en esa
misma llamada: la ocurrencia espera a la consulta siguiente. Como el firmware consulta cada
20 s (RF-38), la entrega puede llegar hasta 20 s después del cierre, y no en la consulta
que lo provoca.

La bandera `pending_dispensing` ya no se acepta en `PUT /dispensers/{id}` (sale de
`DispenserUpdate` y un campo extra se ignora sin 422) y solo se consume si ya estaba puesta
en una base anterior. El planificador no la escribe y la cola no la consulta; se mantiene
como compatibilidad de una sola vez para no perder una solicitud heredada. La coexistencia
de una bandera preexistente con la cola puede producir una entrega heredada adicional
después de drenar la cola; es una deuda aceptada de la compatibilidad, no una vía para
crear nuevas solicitudes.

La ocurrencia se calcula en la hora local del servidor (`a_local_naive`) y `scheduled_for`
guarda esa hora de pared sin zona, así que un cambio de zona horaria reinterpreta los
horarios existentes sin convertir los ya encolados. La ventana de ocurrencia es de 10 min:
si el proceso está caído más tiempo, las ocurrencias de ese intervalo no se recuperan y
quedan sin dispensar, sin generar una entrega tardía.

### 4.2 Reporte, cierre, descuento e idempotencia

```
PROCESAR_REPORTE(payload, ahora):
  normalizar MAC; disp = buscar; si no → 400 mac_no_registrada (sin log)
  si motivo ∉ motivos_de_reporte → 400 motivo_invalido (sin log; la orden sigue pendiente)
  orden = buscar order_id + dispenser_id
  si no existe → tx independiente: log failure orden_desconocida (datos disponibles);
                 400 orden_desconocida; stock intacto

  abrir transacción:
    si orden.status == closed:
        rollback; return 200 {resultado guardado, ..., ya_cerrada:true}   // RF-18
    si ahora > orden.delivered_at + 5 min + 1 s:
        (outcome, cause) = (failure, orden_cerrada); descontados = 0     // RF-20
    si motivo == objetivo_alcanzado:
        si medidos == null o medidos < orden.requested_grams:
            (failure, entrega_incompleta); descontados = 0               // RF-16
        si no:
            (descontados, faltante) = calcular_descuento(medidos, stock)
            (success, objetivo_alcanzado)                                // RF-15
    si no:
        (failure, causa = motivo)                                        // RF-17
    actualizar orden con outcome/cause/medidos/descontados/stock/reintentos
    UPDATE orders SET status='closed', ... WHERE id=? AND status='pending'
    si rowcount == 0:
        rollback; releer orden; return 200 {resultado guardado, ya_cerrada:true}  // RNF-3
    registrar log en la MISMA transacción (medidos/descontados/stock/causa/reintentos,
        ausentes como "no disponible")
    si outcome == success: stock = stock - descontados
    commit
  si cualquier escritura falla → rollback → 500 (el dispositivo reintenta; RF-1)
  return 200 {..., ya_cerrada:false}
```

### 4.3 Descuento acotado

```
medidos = reporte.medidos (null si no disponible)
si medidos <= 0 → descontados = 0
si medidos >= stock → descontados = stock; faltante = medidos - stock
si no → descontados = medidos; faltante = 0
stock_nuevo = stock - descontados            // siempre dentro de [0, 5000]
```
Los medidos y los descontados se guardan en columnas distintas; el faltante va al contexto (RF-15, RF-24).

### 4.4 Vencimiento

```
CERRAR_VENCIDAS(ahora):
  candidatas = orders pending con delivered_at + 5 min + 1 s < ahora
  para cada una:
    tx:
      UPDATE ... SET closed, outcome=failure, cause=sin_reporte WHERE id=? AND status='pending'
      si rowcount == 1: log sin_reporte; commit         // sin descuento (RF-19, RF-40)
      si no: rollback                                    // otro la cerró (RNF-3)
```
El job corre cada 30 s: el cierre ocurre como máximo 30 s después del vencimiento, dentro de los 60 s que exige RF-19. En el instante exacto del límite no se cierra (tolerancia inclusiva).

### 4.5 Idempotencia del reabastecimiento

```
REABASTECER(disp, solicitud, ahora, origen):
  si solicitud.operation_id y existe (user_id, operation_id) → devolver disp actual (sin log, sin suma)
  gramos = normalizar(amount, unit); si no numérico o <= 0 → 400 cantidad_invalida + log fallo (tx aparte)
  si stock + gramos > 5000 → 400 supera_capacidad + log fallo (tx aparte)
  tx: stock += gramos; log success dispenser_refilled (gramos, stock, origen);
      insertar refill_operation (user_id, operation_id); commit
```
Un doble envío del mismo `operation_id` no incrementa ni registra dos veces (RF-11). El sincronizado usa `ahora` del servidor y `origen=sincronizacion_sin_conexion`.

### 4.6 Consulta

```
CONSULTAR(user_id, filtros, pagina, tamano):
  validar en orden: fechas (parseo y orden) → tipo → resultado → página → tamaño
  query = logs WHERE user_id = :user_id
  si pet_id: AND pet_id = :pet_id
  si tipo: AND event_type = :tipo            // NULL nunca coincide (RF-28, RF-41)
  si resultado: AND outcome = :resultado     // NULL nunca coincide (RF-29, RF-41)
  si desde: AND created_at >= :desde_utc
  si hasta: AND created_at <= :hasta_utc     // ambos extremos inclusivos (RF-30)
  total = count(query)
  items = query ORDER BY created_at DESC, id DESC OFFSET ... LIMIT ...
  return {items, total, page, page_size}
```

## 5. Contrato de la API

### 5.1 `GET /dispensers/check-taks/{mac}` (sin token)

200:
```json
{"serve": true, "amount": 50.0, "order_id": 12}
```
`{"serve": false, "amount": 0}` si hay orden pendiente en plazo, está desactivado, no hay comida en cola o no aplica. `{"serve": false, "amount": 0, "reset_wifi": true}` mantiene prioridad absoluta. Un dispensador no registrado sigue respondiendo 404 y no escribe registro (RF-2). RF-13, RF-25.

### 5.2 `POST /dispensers/reports` (sin token)

Request (los campos de gramos pueden faltar o ser `null`):
```json
{
  "mac": "AA:BB:CC:DD:AB:1F",
  "order_id": 12,
  "motivo": "objetivo_alcanzado",
  "gramos_solicitados": 50.0,
  "gramos_medidos": 50.4,
  "reintentos": 0
}
```
200:
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
Duplicado o tardío: mismo cuerpo con `ya_cerrada: true`. Errores 400 con `detail={code,message}`: `mac_no_registrada`, `motivo_invalido`, `orden_desconocida`. Cualquier fallo de escritura: 500 (el firmware reintenta). Orden de comprobación: MAC → motivo → orden. RF-14, RF-18, RF-20, RF-21.

### 5.3 `GET /logs/` (token)

Parámetros: `pet_id?`, `event_type?`, `outcome?`, `from?`, `to?`, `page=1`, `page_size=50`.
Todos los de filtro y paginación se declaran como texto y se validan en servicio, para que un valor inválido sea 400 del catálogo y nunca 422.
Precedencia de rechazo: `rango_fechas_invalido` → `tipo_evento_invalido` → `resultado_invalido` → `pagina_invalida` → `tamano_pagina_invalido`.

200:
```json
{
  "items": [
    {
      "id": 91,
      "created_at": "2026-10-01T17:00:00Z",
      "event_type": "feeding_dispensed",
      "event_label": "Comida dispensada",
      "outcome": "success",
      "outcome_label": "Éxito",
      "cause": "objetivo_alcanzado",
      "cause_label": "Objetivo alcanzado",
      "description": "Comida dispensada",
      "pet_id": 3,
      "pet_name": "Milo",
      "dispenser_mac_masked": "**:AB:1F",
      "order_id": 12,
      "requested_grams": 50.0,
      "measured_grams": 50.4,
      "discounted_grams": 50.4,
      "resulting_stock": 1149.6,
      "retry_count": 0,
      "context": {"faltante": 0.0, "solicitados_reporte": 50.0}
    }
  ],
  "total": 1,
  "page": 1,
  "page_size": 50
}
```
Registros históricos: `event_type`, `outcome`, `cause` y etiquetas de resultado/causa en `null`, `event_label` = «Sin clasificar», y se incluyen sin filtros (RF-41). `created_at` se devuelve en UTC con sufijo `Z` (RNF-8).

### 5.4 `GET /logs/catalog` (token)

```json
{
  "event_types": [{"code": "pet_created", "label": "Mascota creada"}, ...],
  "outcomes": [{"code": "success", "label": "Éxito"}, {"code": "failure", "label": "Fallo"}]
}
```
Sirve para poblar los cuatro filtros sin duplicar el catálogo cerrado en la app (RNF-7). No incluye causas: se muestran desde la etiqueta de cada ítem.

### 5.5 `POST /dispensers/{id}/refill` (token)

Request:
```json
{"amount": 500, "unit": "g", "operation_id": "9f2c...", "origen": "servidor"}
```
`origen` admite `servidor` y `sincronizacion_sin_conexion`; por defecto `servidor`. Respuesta: el `Dispenser` actual con el stock autoritativo. Errores 400: `cantidad_invalida`, `supera_capacidad`; nunca 422. RF-11, RF-12, RF-22, RF-23.

### 5.6 Catálogo de errores

Se implementa una única vez en `domain/catalogos.py` con los 11 códigos y mensajes exactos de la spec. Todos los rechazos de negocio responden 400 con `detail={code,message}`; el 5xx queda solo para fallos de escritura (RF-1). Prueba transversal que verifica que ningún RF cita un código sin fila, que ninguna fila queda sin uso y que ningún rechazo responde 422.

## 6. Modelo de datos y migración

### 6.1 `logs` (reconstruida)

| Columna | Tipo | Notas |
|---|---|---|
| `id` | Integer PK | se conserva |
| `user_id` | Integer FK `users.id`, nullable | nuevo registro siempre lo informa |
| `pet_id` | Integer, nullable, index | **instantánea sin FK**, para conservar la referencia tras eliminar la mascota (RF-6, RF-27) |
| `pet_name` | String, nullable | instantánea para mostrar aunque la mascota ya no exista |
| `dispenser_id` | Integer, nullable, index | instantánea sin FK |
| `dispenser_mac_masked` | String, nullable | `**:AB:1F`; nunca la MAC completa |
| `event_type` | String, nullable, index | `NULL` = histórico «Sin clasificar» |
| `outcome` | String, nullable, index | `success`/`failure` |
| `cause` | String, nullable | causa del catálogo |
| `description` | String, NOT NULL | texto fijo en español |
| `context` | Text, nullable | JSON con claves en español; ausentes como `"no disponible"` |
| `order_id` | Integer, nullable, index | orden de dispensación |
| `requested_grams` | Float, nullable | |
| `measured_grams` | Float, nullable | |
| `discounted_grams` | Float, nullable | `NULL` si no hubo descuento |
| `resulting_stock` | Float, nullable | |
| `retry_count` | Integer, nullable | |
| `created_at` | DateTime, NOT NULL, index | hora del servidor en UTC (naive) |

### 6.2 `dispensing_orders`

`id`, `user_id`, `pet_id` (instantánea), `pet_name`, `dispenser_id` (instantánea), `dispenser_mac_masked`, `requested_grams`, `delivered_at`, `status` (`pending`/`closed`), `closed_at`, `outcome`, `cause`, `measured_grams`, `discounted_grams`, `resulting_stock`, `retry_count`, `log_id`. Índice `(status, delivered_at)` y `(dispenser_id, status)`.

### 6.3 `dispensing_queue`

`id`, `dispenser_id` (FK CASCADE), `pet_id`, `schedule_id` (FK CASCADE), `amount`, `scheduled_for`, `consumed_at`. Restricción única `(dispenser_id, schedule_id, scheduled_for)` para no encolar dos veces la misma ocurrencia. RF-25.

### 6.4 `refill_operations`

`id`, `user_id`, `operation_id`, `dispenser_id`, `grams`, `applied_at`, `log_id`. Restricción única `(user_id, operation_id)`. RF-11.

### 6.5 Migración

1. En el listener `connect`, antes de `create_all`, se llama `_migrar_logs`.
2. Si `logs` no existe, no hace nada (base nueva; `create_all` la crea con el esquema final).
3. Si existe y le falta `event_type` (o conserva columnas parciales como `stock_solicitado`):
   - crea `logs_nueva` con el esquema final;
   - copia `id`, `user_id`, `pet_id`, `description = event`, `created_at = timestamp`;
   - rellena `pet_name` desde `pets` cuando exista;
   - deja `event_type`, `outcome`, `cause` y métricas en `NULL` → «Sin clasificar» (RF-41);
   - verifica que el número de filas copiadas coincide; si no, aborta sin borrar datos;
   - elimina `logs`, renombra `logs_nueva` y crea los índices.
4. `Base.metadata.create_all` crea `dispensing_orders`, `dispensing_queue` y `refill_operations` en bases existentes; no altera `logs`.
5. Todo el proceso es idempotente: una segunda apertura no encuentra la condición y no actúa.

## 7. Caché Isar y estado de la UI

### 7.1 `LocalLog`

Campos nuevos: `eventType?`, `eventLabel?`, `outcome?`, `outcomeLabel?`, `cause?`, `causeLabel?`, `description`, `petName?`, `dispenserMacMasked?`, `orderId?`, `requestedGrams?`, `measuredGrams?`, `discountedGrams?`, `resultingStock?`, `retryCount?`, `contextJson?`. Se conservan `remoteId` (único), `userId`, `petRemoteId`, `timestamp`, `isSynced`. Índices en `timestamp`, `petRemoteId`, `eventType`, `outcome`. La caché guarda códigos **y** etiquetas: los filtros funcionan sin conexión y la UI no duplica el catálogo.

### 7.2 Estado del BLoC

```
LogState {
  items, filters, page, pageSize, total, totalPages,
  isLoading, errorMessage, isOffline, catalog, hasLoaded
}
```
- `LogsRequested(filters, page)` carga remoto; al volver, cachea y emite con `isOffline=false`.
- `LogFiltersChanged`, `LogFiltersCleared`, `LogPageRequested`, `LogRetryRequested`, `LogCatalogRequested`.
- Si el remoto falla, consulta Isar con los mismos filtros y página, y emite `isOffline=true` con los totales de caché. No se vacía `items` mientras carga: `isLoading` es una bandera, no un estado que sustituya la lista. `isOffline` es la única señal de caché que consume la vista.
- Si la consulta falla y la caché también, conserva filtros y lista previa, y expone `errorMessage` con acción de reintento (RF-33).

### 7.3 Vistas

`LogsView` solo compone `LogFiltersBar`, `LogNoticeWidget`, la lista, `LogPaginationBar` y el aviso de datos locales. El rango de fechas se elige en un widget y se traduce a instantes ISO en el dominio; la vista no calcula zonas horarias, totales ni páginas. Textos exactos: «No hay registros para los filtros seleccionados», «Datos sin conexión», «No hay datos locales guardados», «Página X de Y».

## 8. Decisiones justificadas y alternativas descartadas

1. **Reconstruir `logs` en la migración (elegido).** Permite quitar la FK `ON DELETE SET NULL` de `pet_id`, eliminar `event` NOT NULL y curar las columnas parciales. Se descarta `ALTER TABLE ADD COLUMN`: no puede quitar la FK, deja columnas viejas y no garantiza RF-6/RF-27.
2. **`pet_id` y `dispenser_id` como instantáneas sin FK (elegido).** Conservan la referencia después de eliminar la mascota o el dispensador, que es lo que exigen RF-6, RF-27 y los casos límite. Se descarta la FK con `SET NULL`: borraría justo el identificador que hay que filtrar.
3. **Orden de dispensación como entidad propia (elegido).** RF-13, RF-18, RF-19 y RF-20 necesitan identificador, estado y hora de entrega. Se descarta inferirla del horario o del booleano `pending_dispensing`: no hay forma de distinguir «entregada», «pendiente» y «cerrada».
4. **Transición con `UPDATE ... WHERE status='pending'` y `rowcount` (elegido).** SQLite no tiene bloqueo de fila; la escritura condicional garantiza un único ganador entre reporte y barrido (RNF-3). Se descarta `SELECT ... FOR UPDATE`: no existe en SQLite.
5. **Reloj inyectado como `ahora` (elegido).** Permite probar el plazo, la tolerancia y el barrido con precisión de milisegundos sin dependencias (RNF-4). Se descarta congelar el reloj con una librería.
6. **Cola `dispensing_queue` en lugar del booleano `pending_dispensing` (elegido).** Guarda cantidad y ocurrencia, no pierde comidas y permite varias en espera (RF-25). Se descarta reutilizar el booleano: no tiene importe ni identidad de la comida.
7. **Un único job de 30 s que primero vence y después encola (elegido).** Cumple RF-19/RNF-3 y evita dos planificadores con orden indefinido. Se descarta mantener el job de 60 s para las comidas: el vencimiento quedaría fuera de plazo.
8. **Etiquetas y catálogo de filtros servidos por el backend (elegido).** Una sola fuente para el catálogo cerrado (RNF-7) y para «Sin clasificar». Se descarta duplicar los catálogos en Dart: cualquier ampliación exigiría dos despliegues y podría divergir.
9. **Isar guarda códigos y etiquetas, no solo etiquetas (elegido).** Los filtros offline necesitan los códigos. Se descarta guardar solo etiquetas: no se podría filtrar sin conexión.
10. **Upsert por `remoteId` en la caché (elegido).** Conserva la última versión y evita duplicados (RF-35). Se descarta borrar y reinsertar la página: perdería páginas anteriores ya cacheadas.
11. **Parámetros de consulta como texto y validación en servicio (elegido).** Garantiza 400 del catálogo y ningún 422 (RF-31, RF-32, RNF-7). Se descartan `date`, `int` y `Enum` de FastAPI: producen 422 automáticos.
12. **Esquema de reabastecimiento permisivo + validación en servicio (elegido).** `Field(gt=0)` responde 422 y RF-12 lo prohíbe. Se descarta mantener la validación de Pydantic.
13. **UTC naive en SQLite y respuesta con `Z` (elegido).** Ordena e indexa correctamente y es compatible con `DateTime` de SQLite. Se descarta guardar ISO como texto: rompe comparaciones e índices.
14. **`operation_id` generado por la app para el reabastecimiento (elegido).** Es la única forma de distinguir un reintento de dos reabastecimientos iguales legítimos (RF-11). Se descarta deduplicar por `(dispenser, gramos, fecha)`: rechazaría recargas repetidas válidas.
15. **Registro de rechazo de reabastecimiento en sesión independiente (elegido).** Persiste aunque la operación se revierta (RF-12). Se descarta escribirlo en la misma transacción: el `rollback` lo borraría.
16. **Descuento acotado en dominio y stock solo en servidor (elegido).** RF-15, RF-22 y RF-23. Se descarta aceptar `current_food_grams` del cliente: en `DispenserUpdate` solo se valida el rango; si está dentro se ignora como fuente de verdad y la respuesta devuelve el stock del servidor.
17. **JSON del reporte construido con `snprintf` en cabecera pura (elegido).** Se prueba en nativo sin ArduinoJson y sin dependencias nuevas (RF-36, RNF-4). Se descarta construirlo solo con ArduinoJson en el servicio: no sería verificable en `pio test -e native`.
18. **Reporte pendiente en NVS (elegido).** RF-37 exige reenviarlo tras reiniciar; se usa un namespace distinto de `pdam_wifi` para que el borrado de credenciales no lo elimine. Se descarta conservarlo solo en RAM.
19. **Descartar también un 400 no enumerado (elegido, defensivo).** Evita un bucle infinito ante un rechazo de negocio no previsto; los códigos enumerados por RF-39 se descartan explícitamente. Se descarta reintentar cualquier 400.
20. **`total_pages = max(1, ceil(...))` (elegido).** Con 0 resultados se muestra «Página 1 de 1» en lugar de «1 de 0». Se descarta devolver 0 páginas: la UI no tiene un estado natural para ello.
21. **Eliminar `POST /logs/` (elegido).** El historial solo lo escribe el servidor en la transacción de la operación (RF-1, RF-2). Se descarta mantenerlo: permitiría forjar registros y rompería la trazabilidad.
22. **`order_id` entero en lugar de UUID (elegido).** Cabe en el `StaticJsonDocument<200>` del firmware y simplifica la comparación. Se descarta UUID: más bytes y sin ventaja en este prototipo.

## 9. Estrategia de tests por capa

### 9.1 Backend — unitarias puras (`unittest`, sin DB)
- Catálogos: 9 tipos, 2 resultados, 12 causas, 6 motivos de reporte, 11 errores con mensaje exacto; `resultado_para_motivo` para todos los motivos; causas de servidor rechazadas como motivo.
- `mask_mac`: MAC completa, minúsculas, guiones, espacios, 6/8 octetos; siempre `**` y dos últimos octetos.
- `parsear_instante_explicito`: `Z`, `+00:00`, `-05:00`, fracciones, naive rechazado, texto inválido, fecha final anterior.
- Plazos: `ahora` antes, en el límite exacto (+5 min +1 s), 1 ms después; `dentro_del_plazo` inclusivo y `plazo_vencido` exclusivo.
- Descuento: medidos < stock, medidos = stock, medidos > stock, stock 0, medidos 0, medidos negativos.
- Paginación: 0/1/49/50/51/100/101, página 0, página negativa, página fuera del total.
- Firmware: motivo por cada `DispenseReason`, disponibilidad de gramos, JSON con y sin solicitados/medidos, clasificación de respuestas y retardos de reintento.

### 9.2 Backend — integración con SQLite (`test.db`)
- Migración: base legada con `logs(event, timestamp, pet_id)` y base con columnas parciales; se conservan id, usuario, mascota y fechas; las filas quedan sin tipo; borrar la mascota no borra `pet_id` del log; la migración es idempotente; recuento de filas igual antes y después.
- CRUD: crear, modificar y eliminar mascota y dispensador generan su registro en la misma transacción; si la escritura del log falla, la operación se revierte; contexto sin valores antiguos/nuevos ni secretos.
- Refill: aceptado con origen `servidor`; sincronizado con hora del servidor y origen `sincronizacion_sin_conexion`; doble `operation_id` → un solo incremento y un solo log; rechazos 400 con registro en transacción aparte; stock intacto; nunca 422.
- Órdenes: entrega sin descuento; éxito con medidos ≥ solicitados; medidos > stock; medidos < solicitados; sin medidos; cada motivo de fallo; duplicado; tardío dentro y fuera de la tolerancia; orden desconocida; motivo inválido; MAC no registrada; fallo de escritura → 500 y reintento con un único descuento.
- Vencimiento: reloj falso, límite exacto, cierre a los 60 s, `sin_reporte`, sin descuento, firmware antiguo; cola de comida que sobrevive a orden pendiente y a desactivación, y se entrega al cerrar/vencer/reactivar.
- Concurrencia: dos reportes de la misma orden en hilos con sesiones distintas → un cierre, un log, un descuento; reporte contra barrido → un único resultado.
- Consulta: solo registros del usuario, orden descendente estable, filtros combinados, mascota eliminada, históricos visibles sin filtros y excluidos por tipo/resultado, ambos extremos inclusivos, errores del catálogo, forma del sobre, default 50 y máximo 100.
- Rendimiento: 10 000 registros, 4 filtros, 100 consultas, percentil 95 < 1 s (RNF-2); se ejecuta en el entorno de pruebas y se documenta el resultado.
- Contrato: cada código del catálogo devuelve 400 con `detail={code,message}`, ningún rechazo de negocio responde 422, y todo código citado por un RF existe en el catálogo.

### 9.3 App móvil (`flutter test`)
- Utilidades: formateo de instantes con offsets inyectados (`-05:00`, `-04:00`, `Z`), rango de día local con cambio de horario, total de páginas, formateo de fecha local, identificador de operación (formato y unicidad).
- Modelo: `fromJson` con todos los campos, históricos con nulos, etiquetas.
- Datasource remoto: parámetros enviados exactos, sobre de respuesta, catálogo.
- Datasource local: filtros por mascota/tipo/resultado/rango, orden, paginación, conteo, upsert sin duplicados (RF-35).
- Repositorio: remoto cachea; fallo de red → caché con filtros y totales de caché; no pierde la lista previa.
- BLoC: carga, cambio de filtros, limpieza (vuelve a página 1), paginación, error con filtros conservados, reintento, aviso offline.
- Widget: lista, cuatro filtros, «Limpiar filtros», paginación con extremos deshabilitados, vacío con el texto exacto, error con reintento, etiquetas en español; prueba manual documentada del ancho del móvil sin desbordamientos (RF-33).
- Refill: código `supera_capacidad`, `operation_id` persistido, sincronización sin doble incremento.
- `flutter analyze` sin errores.

### 9.4 Firmware (`pio test -e native`)
- `test_report_utils`: cada motivo, campos disponibles/ausentes, JSON exacto, omisión de nulos, decisión de reintento (intento 0/1/2, 5 s, 15 s), clasificación de 200, 400 enumerados, 400 desconocido, 5xx y timeout.
- No regresión de 013: las constantes, ventanas y presupuesto no cambian; `test_dispensing_utils` y `test_dispensing_cycle` siguen en verde (RF-38).
- Manual/físico documentado: reporte recibido tras una dispensación real; red caída con reintentos y reinicio que reenvía; reporte descartado que no se reenvía; firmware antiguo que cierra por plazo.

### 9.5 Trazabilidad
`test_logs_errors.py` incluye una tabla de correspondencia RF→prueba; `tasks.md` cierra con la tabla RF→tarea y la validación global comprueba que los 41 RF tienen al menos una prueba automatizada (RNF-6).

## 10. Mapa RF → parte del plan

| RF | Dónde se implementa | Prueba principal |
|---|---|---|
| RF-1 | `order_service` (transacción única) | integración con fallo de log y reintento |
| RF-2 | `activity_service`, endpoints, `catalogos` | integración de rechazos sin registro |
| RF-3 | `models`, `activity_service`, `mask_mac` | integración de campos y saneado |
| RF-4 | `pet_service.crear_mascota` | integración de log `pet_created` |
| RF-5 | `pet_service.actualizar_mascota` | integración con nombres de campos |
| RF-6 | `pet_service.eliminar_mascota`, migración | integración de referencia tras borrado |
| RF-7 | `dispenser_service.create_new_dispenser` | integración `dispenser_linked` |
| RF-8 | `dispenser_service.update_dispenser` | integración sin secretos |
| RF-9 | `dispenser_service.delete_dispenser` | integración `dispenser_unlinked` |
| RF-10 | `dispenser_service.reset_wifi_credentials` | integración sin SSID |
| RF-11 | `dispenser_service.refill_dispenser`, `refill_operations`, app | integración de origen e idempotencia |
| RF-12 | `dispenser_service.refill_dispenser`, `stock` | integración de códigos y transacción aparte |
| RF-13 | `order_service.entregar_orden` | integración de orden sin descuento |
| RF-14 | `reports` schema, `order_service`, firmware | integración de ausencias y MAC normalizada |
| RF-15 | `cierre`, `stock`, `order_service` | integración de éxito y acotado |
| RF-16 | `cierre`, `order_service` | integración `entrega_incompleta` |
| RF-17 | `cierre`, `order_service` | integración de cada causa |
| RF-18 | `order_service.procesar_reporte` | integración de duplicado |
| RF-19 | `order_service.cerrar_vencidas`, `tiempo`, `main`, `background_schedules` | integración con reloj falso y 30 s |
| RF-20 | `tiempo`, `order_service` | integración tardía y tolerancia |
| RF-21 | `order_service`, `catalogos`, firmware | integración de los tres rechazos |
| RF-22 | `stock`, `dispenser_service` | integración de límites y `stock_fuera_de_rango` |
| RF-23 | `dispenser_service`, `stock`, app | integración de valor de cliente ignorado |
| RF-24 | `activity_service`, `models` | integración de campos y «no disponible» |
| RF-25 | `dispensing_queue`, `order_service`, `background_schedules` | integración de espera y reactivación |
| RF-26 | `logs_service` | integración de propiedad y orden |
| RF-27 | `logs_service`, app | integración de mascota eliminada |
| RF-28 | `logs_service`, app | integración de tipo y exclusión de nulos |
| RF-29 | `logs_service`, app | integración de resultado y exclusión de nulos |
| RF-30 | `consulta`, `tiempo`, `logs_service`, app | integración de `Z`, offsets y extremos |
| RF-31 | `consulta`, `logs_service` | integración de conjunción y errores |
| RF-32 | `consulta`, `logs_service`, app | integración de sobre, default y máximo |
| RF-33 | app (BLoC + widgets) | widget test y manual de ancho |
| RF-34 | app (repositorio + Isar + BLoC) | test de caché con filtros y totales |
| RF-35 | app (Isar upsert) | test de no duplicados y última versión |
| RF-36 | `report_utils`, `report_service`, `api_service` | nativa de motivo/campos + física |
| RF-37 | `report_service`, NVS | nativa de retardos + física con reinicio |
| RF-38 | no se tocan constantes de 013 | suites 013 en verde |
| RF-39 | `report_utils`, `report_service` | nativa de descarte/reintento + física |
| RF-40 | `order_service.cerrar_vencidas`, `background_schedules` | integración de firmware antiguo |
| RF-41 | migración, `logs_service`, app | integración histórica y filtros |
| RNF-1 | `catalogos`, descripciones, `activity_service` | revisión de patrones sensibles |
| RNF-2 | índices y consulta | rendimiento 10 000 registros |
| RNF-3 | `order_service`, barrido | concurrencia y 30 s |
| RNF-4 | sin dependencias nuevas | revisión de `pubspec`/`requirements`/`platformio.ini` |
| RNF-5 | dominio/servicios + BLoC | prueba de que la vista no calcula |
| RNF-6 | todas las capas | tabla RF→prueba |
| RNF-7 | `catalogos` | valores fuera de catálogo |
| RNF-8 | `tiempo`, `models`, `logs_service` | reloj y UTC |

## 11. Orden de implementación y dependencias

1. Limpieza y línea base (T1).
2. Migración y modelo (T2).
3. Dominio puro y contrato de errores (T3).
4. Órdenes y reportes (T4).
5. Vencimiento y cola (T5).
6. Registros CRUD y reabastecimiento (T6).
7. Consulta y filtros (T7).
8. App móvil (T8).
9. Firmware (T9).
10. Validación global y trazabilidad (T10).

Riesgos de secuencia: T2 debe ejecutarse antes de arrancar cualquier servicio nuevo contra una base existente; T8 depende de que el contrato de T7 no cambie; T9 depende del cuerpo de respuesta de T4; la prueba física de T9 exige servidor accesible y red controlada.

## Riesgos de secuencia

T2 debe ir antes de arrancar servicios nuevos sobre una base existente; T8 depende de congelar el contrato de T7; T9 depende del cuerpo de respuesta de T4; las pruebas físicas de T9 necesitan servidor accesible y red controlada.
