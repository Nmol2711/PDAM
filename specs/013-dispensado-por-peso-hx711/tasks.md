# Tareas 013 — Dispensado por peso con celda de carga HX711

Máximo 10 tareas, en orden de dependencia. Ninguna se marca como hecha hasta
completar su comprobación. Tests primero en las tareas de lógica pura (T3, T4 y
T5): se escriben en rojo, se implementan y se ponen en verde.

- [x] **T1. Configuración de hardware, calibración y dependencia HX711.**
  RF-11, RNF-4
  - Hecho cuando: `config.h` define `hx711SckPin = 18`, `hx711DtPin = 19`,
    `hx711CalibrationFactor` positivo con placeholder documentado y
    `hx711RawSign`, y reexporta los límites/tiempos; `platformio.ini` añade
    `bogde/HX711 @ ^0.7.5` como única dependencia nueva y
    `test_dispensing_utils` a `test_ignore`; `pio run` compila.
  - Verificación (2026-10-23): `pio run` en `esp32dev` termina en SUCCESS;
    `bogde/HX711` quedó descargado en `.pio/libdeps/esp32dev/`.

- [x] **T2. Driver HX711 con timeout de lectura.**
  RF-6, RF-11
  - Hecho cuando: `initHx711()` inicializa DT/SCK y registra los pines en
    español; `readHx711Raw(rawOut, timeoutMs)` devuelve `false` si no hay dato
    antes del plazo y `true` con una única lectura si lo hay; no usa `tare()`,
    no convierte a gramos y `pio run` compila sin errores.
  - Verificación (2026-10-23): `pio run` en `esp32dev` termina en SUCCESS y
    compila `hx711_driver.cpp` contra `HX711 @ 0.7.5`. El timeout se garantiza
    sondeando `is_ready()` con `millis()` y `delay(1)` antes de la única
    llamada a `read()`. `initHx711()` configura DT con `INPUT_PULLUP` tras
    `begin()`, de modo que la prueba determinista de «celda desconectada» es
    desconectar el **módulo HX711 del ESP32**: DT queda flotando, el pull-up lo
    mantiene en HIGH (sin dato) y `is_ready()` no produce lecturas falsas,
    cubriendo RF-4. Si solo se desconecta la celda con el módulo alimentado,
    las lecturas pueden parecer válidas y el firmware no garantiza RF-9 en ese
    modo.

- [x] **T3. Lógica pura base y tests nativos en rojo: orden, calibración, lectura,
  mediana y log.**
  RF-1, RF-2, RF-3, RF-6, RF-10, RF-11, RF-12, RNF-5
  - Hecho cuando: `test_dispensing_utils.cpp` contiene primero las pruebas de
    `classifyOrder` (incluida la prioridad de `reset_wifi`), validación del
    factor, conversión raw→gramos, lectura válida/inválida en los extremos,
    mediana impar/par/sin válidas y formateador con «no disponible»; las pruebas
    fallan antes de implementar (`pio test -e native` en rojo) y pasan después
    de crear `dispensing_utils.h` sin dependencias de Arduino.
  - Verificación (2026-10-23): con solo el test, `pio test -e native` falló por
    símbolos ausentes (`OrderAction`, `WeightSample`, `DispenseResult`,
    `classifyOrder`, `median`, etc.). Tras ampliar `dispensing_utils.h`
    (header-only, sin Arduino), `pio test -e native` pasa 34/34 (29 nuevas + 5
    existentes) y `pio run` en `esp32dev` termina en SUCCESS.

- [x] **T4. Lógica pura de la ventana de verificación y tests nativos.**
  RF-3, RF-4, RNF-1, RNF-3
  - Hecho cuando: las pruebas cubren que la ventana dura exactamente 2 000 ms,
    no se reinicia ni se extiende, pasa con ≥ 5 válidas, falla con 4, aborta con
    3 inválidas consecutivas, una inválida aislada no reinicia la ventana y la
    línea base es la mediana de las válidas; `pio test -e native` pasa en verde.
  - Verificación (2026-10-23): con los 12 tests nuevos y sin implementación,
    `pio test -e native` falló por símbolos ausentes (`VerificationOutcome`,
    `VerificationState`, `startVerification`, `recordVerificationSample`,
    `verificationBaseline`). Tras añadirlos a `dispensing_utils.h` (header puro,
    sin Arduino y con el tiempo por parámetro), `pio test -e native` pasa 46/46
    (34 previos + 12 nuevos) y `pio run` en `esp32dev` termina en SUCCESS.

- [x] **T5. Lógica pura del giro, objetivo, fallo de sensor, tiempo límite,
  resultado y temporizador; tests nativos.**
  RF-6, RF-7, RF-8, RF-9, RF-12, RF-13, RNF-2, RNF-3
  - Hecho cuando: las pruebas cubren parada con 3 lecturas consecutivas ≥
    objetivo, reinicio del contador al bajar del objetivo, una inválida aislada
    sin detener, 3 inválidas consecutivas → fallo de sensor, 30 000 ms → tiempo
    límite, cálculo del incremento, peso final disponible/no disponible y
    `isCheckDue` a 20 s; `pio test -e native` pasa en verde.
  - Verificación (2026-10-23): con los 14 tests nuevos y sin implementación,
    `pio test -e native` falló por símbolos ausentes (`RotationOutcome`,
    `RotationState`, `startRotation`, `recordRotationSample`, `isCheckDue`).
    Tras añadirlos a `dispensing_utils.h` (header puro, sin Arduino, tiempo por
    parámetro), `pio test -e native` pasa 60/60 (46 previos + 14 nuevos) y
    `pio run` en `esp32dev` termina en SUCCESS. `isCheckDue` resta en 32 bits
    para reproducir el rollover de `millis()` también en el entorno nativo
    (64 bits). Corrección posterior: `fillDispenseMeasurements` traslada la
    línea base y la última lectura válida a `DispenseResult`, calcula
    `incremento = peso_final - línea_base` y fija sus banderas (incremento no
    disponible cuando falta la línea base, RF-12); con 5 tests nuevos
    `pio test -e native` pasa 65/65 y `pio run` termina en SUCCESS.

- [x] **T6. Servo con arranque y parada explícitos, sin bloqueo de 10 s.**
  RF-5, RF-7, RF-8, RF-9
  - Hecho cuando: `servo_driver` expone `startServo()` (0°) y `stopServo()`
    (90°, idempotente), `dispensarAlimento()` ya no existe, no queda ninguna
    referencia a ella en el firmware y `pio run` compila.
  - Verificación (2026-10-23): `pio run` en `esp32dev` termina en SUCCESS y
    `pio test -e native` pasa 65/65. La búsqueda global en `DispensadorESP32`
    no encuentra referencias a `dispensarAlimento`; solo permanece en el sketch
    legado `arduino/sketch_jul3a/sketch_jul3a.ino`, que no forma parte del
    firmware de PlatformIO. `api_service.cpp` conserva el comportamiento previo
    mediante un puente temporal explícito (`startServo()`, `delay(10000)`,
    `stopServo()`) que T8 elimina al integrar `dispenseWeight(amount)`.

- [x] **T7. Servicio de dispensado por peso con registro.**
  RF-3, RF-4, RF-5, RF-6, RF-7, RF-8, RF-9, RF-11, RF-12
  - Hecho cuando: `dispenseWeight(amount)` valida factor y cantidad antes de
    tocar hardware, ejecuta la verificación, fija la línea base, arranca el
    servo, muestrea a un máximo de 200 ms, aplica las decisiones puras y detiene
    el servo en toda salida (objetivo, tiempo, fallo o aborto); emite una línea
    con solicitado, línea base, peso final, incremento y motivo, usando «no
    disponible» cuando corresponde; `pio run` compila.
  - Verificación (2026-10-23): `pio run` en `esp32dev` termina en SUCCESS y
    `pio test -e native` pasa 65/65. El servicio valida factor y cantidad antes
    de inicializar la celda, abre la ventana fija de 2 s, muestrea cada 200 ms y
    detiene el servo en toda salida. El cierre por vencimiento usa una muestra
    no respondida y no inicia lecturas cuyo plazo pudiera cruzar el límite, de
    modo que no extiende la ventana ni el giro. Compila; la validación física y
    la integración con `api_service` quedan pendientes de T8 y T10.
    Refuerzos de revisión (2026-10-23): la cantidad se valida con
    `!(amountGrams > 0.0f)` para rechazar también `NaN` con `INVALID_AMOUNT`, y
    el instante de arranque se captura antes de `startServo()` para que el tope
    de 30 s de RNF-3 incluya el arranque del servo. `pio run` en `esp32dev`
    termina en SUCCESS y `pio test -e native` pasa 65/65.

- [x] **T8. Integración con la API y reinicio del temporizador periódico.**
  RF-1, RF-2, RF-10, RF-11, RF-12, RF-13, RNF-4
  - Hecho cuando: `api_service.cpp` parsea `amount` numérico, aplica
    `reset_wifi` con prioridad, registra advertencia solo en orden inválida,
    cierra HTTP antes de dispensar o reiniciar y llama a `dispenseWeight` solo
    cuando la clasificación lo indica; `dispenser_task.cpp` asigna
    `lastCheckTime = millis()` después de `checkDispenserAction` tanto en
    `STATE_NORMAL` como en la transición desde `STATE_CONNECT_WIFI`; `pio run`
    compila.
  - Verificación (2026-10-23): `pio run` en `esp32dev` termina en SUCCESS y
    `pio test -e native` pasa 65/65. Se eliminó el puente temporal
    (`startServo`, `delay(10000)`, `stopServo`) y el include de `servo_driver.h`;
    no quedan coincidencias de `delay(10000)` ni de esas llamadas en
    `api_service`. `http.end()` se ejecuta inmediatamente después de leer el
    payload y también en el camino de error, antes de parsear o actuar. Con
    ArduinoJson 6.21.6, `is<float>()` usa `NUMBER_BIT`, que está activo tanto en
    enteros como en flotantes y no en cadenas, así que `amount` se distingue
    como número o no número; se añade `is<int>()` y `std::isfinite`. El
    temporizador usa `CHECK_INTERVAL` y se reinicia al final del ciclo en
    `STATE_NORMAL` y tras la primera consulta de `STATE_CONNECT_WIFI`. La
    prueba end-to-end con hardware queda en T10.

- [x] **T9. Validación automatizada y trazabilidad RF.**
  Criterios de finalización, RNF-4, RNF-6
  - Hecho cuando: `pio test -e native` pasa en verde con todas las pruebas de
    lógica pura, `pio run` compila sin errores, se revisa que la única
    dependencia nueva es `bogde/HX711` y cada RF tiene su prueba nativa o su
    comprobación manual identificada en `plan.md`.
  - Verificación (2026-10-23): `pio run -t clean && pio run` en `esp32dev`
    termina en SUCCESS (RAM 64 444 B, 19.7 % de 327 680 B; Flash 2 004 342 B,
    63.7 % de 3 145 728 B). `pio test -e native` pasa 65/65 en 0.84 s:
    `test_provisioning_utils` 5/5 y `test_dispensing_utils` 60/60.
    `platformio.ini` solo añade `bogde/HX711 @ ^0.7.5` a `lib_deps` (HX711
    0.7.5 en `.pio/libdeps/esp32dev`; Unity es el framework de test) y
    `test_dispensing_utils` a `test_ignore`. Sin restos de `delay(10000)`,
    `dispensarAlimento`, `startServo`/`stopServo` en `api_service`, ni
    `checkInterval` local, ni `TODO`/`FIXME` en `src`, `test` o `include`.
    Trazabilidad según §7.3 de `plan.md`; la comprobación física de RF-5, RF-9,
    RF-11, RF-12, RF-13 y RNF-1, RNF-4 y RNF-5, la exactitud de 50 g y la no
    regresión quedan exclusivamente en T10.

- [ ] **T10. Checklist físico, no regresión y actualización de `MEMORY.md`.**
  RF-5, RF-9, RF-11, RF-12, RF-13, RNF-1, RNF-4, RNF-5
  - Hecho cuando: con el módulo HX711 desconectado del ESP32 (DT/SCK;
    idealmente también VCC/GND) al arrancar el servo no se mueve;
    desconectándolo a mitad del giro el servo se detiene dentro de 1 s desde la
    primera de las 3 inválidas; con 50 g solicitados el incremento medido está
    entre 50 g y 55 g; se observan ≥ 5 lecturas/s; el log está en español, sin
    emojis ni credenciales; el checklist de BLE, WiFi, reconexión, validación de
    servidor, reset de credenciales y consulta 20 s después del fin queda
    cumplido y registrado; `MEMORY.md` queda actualizado con el estado, las
    decisiones y los pendientes de hardware.
  - Nota (2026-10-23): calibrar con peso patrón antes de medir exactitud (el
    factor `7050` es placeholder) y usar la desconexión del **módulo HX711 del
    ESP32** para las pruebas de RF-4/RF-9; desconectar solo la celda con el
    módulo alimentado puede dar lecturas plausibles.

## Nota de alcance

No se incluyen tareas de backend ni de aplicación móvil: el contrato real de la
API (`serve`, `amount`, `reset_wifi`) ya envía la cantidad en gramos y el
descuento de stock sigue fuera de alcance.
