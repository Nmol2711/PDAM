# MEMORY.md — PDAM

## Estado actual
* **Spec 013 implementada en firmware:** dispensado por peso con HX711 (T1–T9) y ampliación de detección y resolución de atascos (T11–T14); solo firmware, sin cambios en backend ni app.
* **T10 pendiente:** checklist físico previo (exactitud 50–55 g con báscula externa y P5–P12; definiciones en `docs/informes/informe-pruebas-hardware-spec-013-2026-10-23.md` §6).
* **T15 pendiente:** checklist físico de atasco (retroceso de 1,2 s, pausa de 0,3 s, reanudación, «atasco no resuelto», peso de bandeja, 5 Hz, 30 s de motor / 32 s de ciclo, acoplamiento).
* **Specs 011 y 012 cerradas:** stock con refill offline (`pendingRefillGrams` en Isar, límite de 5 kg) y motor WSAVA único. Specs 001–010 cerradas; hardware real de 005 sin probar.
* **Branding 2026-10-25:** logo e íconos Android/iOS con `assets/logo_new.png`; el logo monocromático sigue siendo el anterior.

## Decisiones clave (Spec 013)
* Detección indirecta de atasco por peso con mediana móvil de 5 válidas y máximo observado de esa mediana: un pico de ruido no mueve la referencia ni declara atasco.
* Ventana continua de 5 s que se reinicia al llegar a 2 g (un flujo de 0,5 g/s nunca declara atasco), presupuesto de 30 s de motor como límite efectivo y 3 reintentos como red de seguridad.
* Retroceso a 180° de 1,2 s más pausa de 0,3 s; 3 500 ms es el mínimo para reintentar porque cubre retroceso, pausa y gracia. El reintento se cuenta solo al reanudar el avance.
* Ciclo extraído a `dispensing_cycle.h` con `CyclePorts` para probarlo en nativo con servo simulado y `CycleLimits` como punto de inyección solo para pruebas, con las constantes aprobadas por defecto.
* HX711: DT 19 / SCK 18; servo GPIO4. `INPUT_PULLUP` en DT detecta el módulo desconectado (DT flotante → HIGH → timeout).
* Calibración de esta celda: factor `482.7` y signo `+1` (patrón de ~206,8 g; RAW 160658 vacío / 260500 cargado). El placeholder `7050`/`-1` era erróneo.
* Verificación fija de 2 s con sondeo cada 200 ms y timeout de lectura de 100 ms; objetivo y fallo se confirman con 3 lecturas consecutivas.
* API: `serve:false`/`amount:0` es reposo sin error; `reset_wifi` con prioridad absoluta; HTTP se cierra antes del ciclo y la siguiente consulta es 20 s después de terminarlo.

## Errores a evitar
* No comparar el progreso contra lecturas individuales (falsos atascos) ni contar el reintento al iniciar el retroceso.
* No retroceder ante fallo de sensor u orden inválida, ni duplicar umbrales fuera de `dispensing_utils.h`.

## Motor WSAVA (Spec 011)
* `RER = 70·BW^0.75`, `MER = RER·factor`, snacks ≤ 10 % MER (alerta y recálculo), gramos = kcal / (kcal/kg ÷ 1000); variabilidad ±30 % perro y ±50 % gato.

## Validación (2026-10-27)
* 013: `pio test -e native` 136/136 (`test_provisioning_utils` 5, `test_dispensing_utils` 110, `test_dispensing_cycle` 21); `pio run -t clean && pio run` SUCCESS (RAM 64 444 B, 19,7 %; Flash 2 008 522 B, 63,8 %).
* 013 hardware (2026-10-24): flasheo, BLE + WiFi + HTTP 200 y 12 ciclos con «objetivo alcanzado»; los incrementos se forzaron con presión manual, así que no miden exactitud.
* 012/011: `pytest` 244 passed + 113 subtests; `flutter test` 286 passed; `flutter analyze` 0 errores.

## Riesgos residuales
* Par inverso a 180° puede aflojar el acoplamiento si el servo no es de rotación continua.
* Un fallo de sensor que empieza en la pausa se detecta al reanudar el avance.
* Cambiar cualquier umbral invalida los razonamientos de tiempos de los tests.
* 10 SPS frente a timeout de 100 ms: la lectura puede llegar justo después del intento.
* Calibración válida solo para este montaje (celda y cableado).
* Falso atasco con flujo lento (por debajo de 0,4 g/s).
* `CycleLimits` permite a un futuro llamador un presupuesto mayor de 30 s.
* `HX711::read()` sin cota: el timeout solo cubre el sondeo previo.
* Endpoint fijo de 50 g commiteado en la rama de pruebas.
* Corte de energía durante el retroceso sin recuperación.

## Deuda aceptada
* Desconectar solo la celda con el HX711 alimentado puede dar lecturas plausibles; no garantiza RF-9. Deriva de stock del backend fuera de alcance.
* Ruta real `/dispenserscheck-taks/{mac}` (typo `taks`); firmware y datasource Flutter ya coinciden.
* `check_dispenser_taks` devuelve `serve:true`/50 g fijo: está commiteado en la rama `pruebas/endpoint-fijo-hx711` (commit `b009a5b`); restaurar `check_pending_task` antes de mergear a main.

## Reglas vigentes
* Offline-First: logout **no** borra Isar; nunca `clearAllData()`. MAC normalizada en servidor; HTTP 409/400 con `detail={code,message}`. Registro/cambio de MAC/desactivación/eliminación exigen conexión; lecturas y reabastecimiento operan offline. Avisos con `AppNoticeDialog` (MD3), nunca SnackBars rojos.
