# MEMORY.md — PDAM

## Estado actual
* **Spec 013 cerrada el 2026-10-28:** T1–T14 implementadas y revisadas, T15 cerrada el 2026-10-27 y T10 cerrada el 2026-10-28. P2 aprobada el 2026-10-28 (55 g y 900 g, linealidad 0,046 %, error máximo 0,04 %, factor 482,7 sin cambios); P3 verificada con tres mediciones en rango 50–55 g (54,5 g; 51,1 g; 50,42 g) medidas con la celda calibrada, trazable a los patrones de 55 g y 900 g, sin báscula externa independiente, con la limitación registrada. P7 no concluyente (cables de la celda soldados).
* **Segunda ronda (2026-10-27):** con `check_pending_task` restaurado, P9, P11 y P12 aprobados, P8 por confirmación, P7 no concluyente, P13 cubierto en la ronda previa. Primera ronda: 5 dispensaciones de 50 g con croqueta de ~3 cm; 4 atascos reales resueltos con `reintentos=1` (57.3, 55.2, 54.9 y 52.4 g) y 1 limpio con `reintentos=0` (54.5 g); los 5 «objetivo alcanzado».
* **Specs 011 y 012 cerradas:** stock con refill offline (`pendingRefillGrams` en Isar, límite de 5 kg) y motor WSAVA único. Specs 001–010 cerradas; hardware real de 005 sin probar. Branding 2026-10-25 con `assets/logo_new.png` (el logo monocromático sigue siendo el anterior).

## Decisiones clave (Spec 013)
* Detección indirecta de atasco por peso con mediana móvil de 5 válidas y máximo observado de esa mediana: un pico de ruido no mueve la referencia ni declara atasco.
* Ventana continua de 5 s que se reinicia al llegar a 2 g (un flujo de 0,5 g/s nunca declara atasco), presupuesto de 30 s de motor como límite efectivo y 3 reintentos como red de seguridad.
* Retroceso a 180° de 1,2 s más pausa de 0,3 s; 3 500 ms es el mínimo para reintentar porque cubre retroceso, pausa y gracia. El reintento se cuenta solo al reanudar el avance.
* La gracia se mantiene en 2 s y los umbrales no se ajustan tras las pruebas físicas: los atascos con croqueta de ~3 cm son mecánicos, no de detección.
* Ciclo extraído a `dispensing_cycle.h` con `CyclePorts` para probarlo en nativo con servo simulado y `CycleLimits` como punto de inyección solo para pruebas, con las constantes aprobadas por defecto.
* HX711: DT 19 / SCK 18; servo GPIO4; `INPUT_PULLUP` en DT detecta el módulo desconectado (DT flotante → HIGH → timeout). Calibración de esta celda: factor `482.7` y signo `+1`.
* Verificación fija de 2 s con sondeo cada 200 ms y timeout de lectura de 100 ms; objetivo y fallo se confirman con 3 lecturas consecutivas.
* API: `serve:false`/`amount:0` es reposo sin error; `reset_wifi` con prioridad absoluta; HTTP se cierra antes del ciclo y la siguiente consulta es 20 s después de terminarlo.

## Errores a evitar
* No comparar el progreso contra lecturas individuales (falsos atascos) ni contar el reintento al iniciar el retroceso.
* No retroceder ante fallo de sensor u orden inválida, ni duplicar umbrales fuera de `dispensing_utils.h`.

## Motor WSAVA (Spec 011)
* `RER = 70·BW^0.75`, `MER = RER·factor`, snacks ≤ 10 % MER (alerta y recálculo), gramos = kcal / (kcal/kg ÷ 1000); variabilidad ±30 % perro y ±50 % gato.

## Validación (2026-10-27)
* 013: `pio test -e native` 137/137 (`test_provisioning_utils` 5, `test_dispensing_utils` 110, `test_dispensing_cycle` 22); `pio run -t clean && pio run` SUCCESS (RAM 64 444 B, 19,7 %; Flash 2 008 522 B, 63,8 %).
* 013 hardware: P1–P13 ejecutadas; P2 aprobada el 2026-10-28 con 55 g y 900 g (error 0,04 %); P3 aprobada el 2026-10-28 con 54,5 g, 51,1 g y 50,42 g (2 ejecuciones formales más un re-pesado, instrumento: la celda calibrada).
* 012/011: `pytest` 244 passed + 113 subtests; `flutter test` 286 passed; `flutter analyze` 0 errores.

## Riesgos residuales
* Par inverso a 180° puede aflojar el acoplamiento si el servo no es de rotación continua.
* Con croqueta de ~3 cm el tornillo se atasca con frecuencia (croqueta cuñada entre hélice y tubo); el retroceso lo resuelve cuando libera la croqueta y, si no, el ciclo termina en «atasco no resuelto» (RF-16). No se ajustan umbrales.
* Fallo de sensor que empieza en la pausa se detecta al reanudar el avance (prueba nativa desde 2026-10-27).
* Cambiar cualquier umbral invalida los razonamientos de tiempos de los tests.
* 10 SPS frente a timeout de 100 ms: `HX711::read()` sin cota; el timeout solo cubre el sondeo previo.
* Calibración válida solo para este montaje (celda y cableado); falso atasco con flujo lento (por debajo de 0,4 g/s); `CycleLimits` permite a un futuro llamador un presupuesto mayor de 30 s.
* Corte de energía durante el retroceso sin recuperación.
* P3 sin instrumento independiente: la celda calibrada mide su propia entrega y no detecta masa fuera de la taza; las dispensaciones con reintentos pueden sobrepasar (57,3 g con `reintentos=1`).
* La rama `pruebas/endpoint-fijo-hx711` tiene la spec 013 cerrada; queda pendiente el merge a `main`.

## Deuda aceptada
* Desconectar solo la celda con el HX711 alimentado puede dar lecturas plausibles; no garantiza RF-9. Deriva de stock del backend fuera de alcance.
* Ruta real `/dispenserscheck-taks/{mac}` (typo `taks`); firmware y datasource Flutter ya coinciden.

## Reglas vigentes
* Offline-First: logout **no** borra Isar; nunca `clearAllData()`. MAC normalizada en servidor; HTTP 409/400 con `detail={code,message}`. Registro/cambio de MAC/desactivación/eliminación exigen conexión; lecturas y reabastecimiento operan offline. Avisos con `AppNoticeDialog` (MD3), nunca SnackBars rojos.
