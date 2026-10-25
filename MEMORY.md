# MEMORY.md — PDAM

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
* **Spec 013: T1–T9 y corrección de calibración implementadas; verificación física parcial 2026-10-24; T10 pendiente de exactitud con alimento real y pruebas de fallo.** Dispensado por peso con HX711 sustituye el giro fijo de 10 s; solo firmware, sin cambios en backend ni app.
* **Spec 012 cerrada (T1–T14).** Stock en tiempo real, refresco silencioso cada 5 s, pull-to-refresh y reabastecimiento offline con cola Isar.
* **Spec 011 cerrada (T1–T14).** Motor WSAVA único, `POST /nutrition/calculate`, espejo Dart con fixture y módulo unificado `features/dispenser/`.
* **Specs 001–010 cerradas.** Spec 004 y 005 `Estado: implementada`; hardware real de 005 sin probar.

## Decisiones clave (Spec 013)
* HX711: DT 19 / SCK 18; servo GPIO4. `INPUT_PULLUP` en DT detecta de forma determinista el módulo HX711 desconectado del ESP32 (DT flotante → HIGH → timeout).
* Verificación 2 s con sondeo cada 200 ms, cota de giro 30 s, timeout de lectura 100 ms; objetivo y fallo se confirman con 3 lecturas consecutivas; una inválida aislada no detiene.
* Calibración manual para esta celda: factor `482.7` y signo `+1`, medidos con patrón de ~206.8 g (RAW vacío 160658, RAW cargado 260500). El placeholder `7050`/`-1` queda descartado: convertía el vacío a ≈ −22.8 g y bloqueaba la verificación. No hay `tare()` ni comandos serie.
* Al fallar la verificación el firmware imprime RAW, gramos, factor, signo y causa probable, para no confundir un fallo de calibración con un sensor desconectado.
* API: `serve:false`/`amount:0` es reposo sin error; `reset_wifi` tiene prioridad absoluta; orden inválida solo advierte. HTTP se cierra antes del ciclo y la siguiente consulta es 20 s después de terminarlo.

## Decisiones clave (Spec 012)
* Reabastecimiento **aditivo**, rechazado si `stock + grams > 5000 g` (400 `refill_exceeds_capacity`); la respuesta del servidor es el stock autoritativo y se cachea.
* Refill offline: se guarda `pendingRefillGrams` en Isar; al refrescar se envía antes de consultar, se reconcilia si el servidor lo rechaza por límite y se conserva ante fallo de red.
* Mensajes de refill: solo `El reabastecimiento supera el límite de 5 kg` o `Reabastecimiento con éxito`; no se descuenta stock en el cliente.
* Refresco silencioso solo con Dispositivos visible, cada 5 s, pull-to-refresh y al volver del escaneo BLE; no pisa estados de escaneo/aprovisionamiento/detalle.

## Decisiones clave (Spec 011)
* `RER = 70·BW^0.75`, `MER = RER·factor`, snacks ≤10% MER (alerta + recálculo), `Final = max(0, MER − snacks)`, gramos = kcal / (kcal/kg ÷ 1000).
* Factores MER: canino adulto 1.8 / castrado 1.6 / crecimiento 2.0; felino 1.4 / 1.2 / 2.5. Ajustes de actividad, BCS y MCS según spec. Variabilidad ±30% perro, ±50% gato.
* `auto_generar_horarios_wsava` delega en `nutrition_service`; especie `otros` → sin límite (RF-2).

## Validación (2026-10-23, revisada 2026-10-24)
* 013: `pio test -e native` 72/72 (67 dispensing + 5 provisioning) y `pio run` SUCCESS (RAM 19.7 %, Flash 63.8 %) tras la corrección de calibración; backend/app sin cambios.
* 013 hardware (2026-10-24): flasheo correcto (`Build actual de compilacion: Oct 24 2026 23:14:35`), BLE `PDAM-Config-<MAC>` + WiFi + HTTP 200, y 12 ciclos con verificación superada (sin `sensor no disponible`) y `objetivo alcanzado`; línea base ≈333.1 g. Los incrementos de 52–530 g se lograron con **presión manual** sobre la celda: no sirven para exactitud.
* 012/011: `pytest` 244 passed + 113 subtests; `flutter test` 286 passed; `flutter analyze` 0 errores (warnings/infos preexistentes).

## Pendiente T10 (hardware)
* Exactitud real: 50 g → 50–55 g con alimento seco y báscula externa. Faltan P5/P6 (módulo HX711 desconectado al arranque y a medio giro), P7, P8 (≥5 Hz), P10 (reconexión/rollback), P11 (`reset_wifi`) y P12 (20 s con marcas de tiempo; el log no las incluye).
* El endpoint `check_dispenser_taks` (`api/app/api/endpoints/dispenser.py`) devuelve `serve:true`/50 g fijo: modo de prueba local que **no debe commitearse**.

## Deuda aceptada
* `HX711::read()` llama a `wait_ready()` sin cota: el timeout solo cubre el sondeo previo (riesgo residual bajo, no apto para producción sin mitigar).
* Desconectar solo la celda con el HX711 alimentado puede dar lecturas plausibles; no garantiza RF-9.
* Deriva de stock del backend (descuenta al emitir `serve:true`) fuera de alcance.
* Ruta real `/dispenserscheck-taks/{mac}` (typo `taks` y `/` faltante); firmware y datasource Flutter ya coinciden.

## Reglas vigentes
* Offline-First: logout **no** borra Isar; nunca `clearAllData()`.
* MAC normalizada en servidor; HTTP 409/400 con `detail={code,message}`.
* Registro/cambio de MAC/desactivación/eliminación exigen conexión; lecturas y reabastecimiento operan offline.
* Avisos con `AppNoticeDialog` (MD3), nunca SnackBars rojos.
