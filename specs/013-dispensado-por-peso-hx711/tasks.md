# Tareas 013 — Dispensado por peso con celda de carga HX711

Quince tareas, en orden de dependencia: T1–T10 de la spec original y T11–T15 de
la ampliación de atascos. Ninguna se marca como hecha hasta completar su
comprobación. Tests primero en las tareas de lógica pura (T3, T4, T5, T11, T12 y
T14): se escriben en rojo, se implementan y se ponen en verde.

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
    `test_provisioning_utils` 5/5 y `test_dispensing_utils` 60/60. (cifras históricas previas a la corrección de calibración; ver la nota de T10 para el 72/72).
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
    cumplido y registrado; el checklist se ejecuta sobre el firmware final con
    desatasco (T11–T14) y repite la exactitud de 50 g y el fallo de sensor como
    no regresión; `MEMORY.md` queda actualizado con el estado, las
    decisiones y los pendientes de hardware.
  - Nota (2026-10-23): calibrar con peso patrón antes de medir exactitud y usar
    la desconexión del **módulo HX711 del ESP32** para las pruebas de RF-4/RF-9;
    desconectar solo la celda con el módulo alimentado puede dar lecturas
    plausibles.
  - Nota (2026-10-24): en la primera prueba física el log repitió
    `sensor no disponible` y el servo no se movió aunque el sensor respondía. La
    causa fue la calibración: el factor `7050` y el signo `-1` no correspondían a
    la celda; el RAW real es ≈ 160658 en vacío y ≈ 260500 con ~206.8 g
    (≈ 482.7 cuentas/g, signo `+1`). Se corrigió `config.h` a `482.7f`/`+1.0f`, se
    añadió diagnóstico en la ventana de verificación y 7 pruebas nuevas
    (`pio test -e native` 72/72). T10 sigue `[ ]`: falta verificar 50–55 g, los
    fallos de sensor, la frecuencia y la no regresión.
  - Nota (2026-10-24, verificación parcial): con el build corregido
    (`Build actual de compilacion: Oct 24 2026 23:14:35`) el flasheo limpió la
    NVS y el equipo aprovisionó por BLE (`PDAM-Config-<MAC>`), conectó a WiFi y
    validó HTTP 200. En 12 ciclos consecutivos la verificación se superó sin
    `sensor no disponible`, el servo giró y se detuvo, y el motivo fue
    `objetivo alcanzado`; la línea base fue ≈ 333.1 g (359.7 g y 421.7 g en dos
    ciclos, por peso residual sobre la bandeja). Los incrementos observados
    (52.4–530.5 g) se obtuvieron ejerciendo presión manual sobre la celda porque
    no había alimento seco, así que su variabilidad no mide exactitud. T10 sigue
    `[ ]`: faltan P3 con alimento real y medición externa de 50–55 g, P5, P6, P7,
    P8, P10, P11 y P12.

- [x] **T11. Constantes de atasco y lógica pura de detección, decisión y
  registro, con tests nativos primero en rojo.**
  RF-12, RF-14, RF-15, RF-16, RF-17, RNF-6, RNF-7
  - Hecho cuando: `dispensing_utils.h` define en un único lugar, documentadas en
    español, las constantes de gracia 2 000 ms, ventana 5 000 ms, progreso
    mínimo 2,0 g, mediana móvil 5, mínimo 5 válidas desde el arranque, retroceso
    1 200 ms, pausa 300 ms, máximo 3 reintentos, presupuesto mínimo de reintento
    3 500 ms y ángulo 180°, y renombra `kMaxRotationMs` a `kMotorBudgetMs`;
    existen mediana móvil, máximo observado, apertura/reinicio/expiración de la
    ventana, declaración de atasco, `decideStallAction`, contabilidad del
    presupuesto, `budgetExhaustedReason`, contador de reintentos,
    `DispenseReason::STALL_UNRESOLVED`, `DispenseResult::retryCount` y
    `reintentos=N` en `formatDispenseLog`; las pruebas se escriben antes y fallan
    por símbolos ausentes; `pio test -e native` pasa en verde y `pio run` compila.
  - Comprobación verificable: `pio test -e native` en rojo antes de implementar y
    en verde después, con las cuatro aserciones de log existentes actualizadas a
    `reintentos=0`.
  - Verificación (2026-10-26): con los 36 tests nuevos y sin implementación,
    `pio test -e native` falló por símbolos ausentes (`kStallGraceMs`,
    `kStallWindowMs`, `kMinProgressGrams`, `kMovingMedianSize`,
    `kMinAdvanceValidReadings`, `kReverseMs`, `kPauseMs`, `kMaxStallRetries`,
    `kMinRetryBudgetMs`, `kReverseAngleDegrees`, `kMotorBudgetMs`,
    `MovingMedianState`, `StallState`, `StallOutcome`, `StallAction`,
    `recordAdvanceSample`, `decideStallAction`, `motorBudgetRemainingMs`,
    `budgetExhaustedReason`, `STALL_UNRESOLVED`, `retryCount`). Tras añadirlos a
    `dispensing_utils.h` (header puro, tiempo por parámetro), `pio test -e native`
    pasa 108/108 (72 previos + 36 nuevos) y `pio run` en `esp32dev` termina en
    SUCCESS (RAM 64 444 B, 19.7 %; Flash 2 005 422 B, 63.8 %). Las 10 constantes
    de umbral quedan solo en `dispensing_utils.h` y `config.h` las reexpone por
    su `#include`, sin cambios. `grep` de `kMaxRotationMs` en `src/` y `test/` sin
    resultados. Decisión de lectura: RF-14 exige reiniciar la ventana con
    «progreso igual o mayor que 2 gramos», así que la prueba de 4,9 g verifica el
    reinicio (y la renovación de la referencia), no su ausencia; el límite
    inferior se cubre con 1,9 g, que no reinicia.

- [x] **T12. Retroceso explícito del servo y extracción del ciclo a una unidad
  pura con puertos inyectables.**
  RF-6, RF-7, RF-14, RF-15, RF-17, RNF-1, RNF-6
  - Hecho cuando: `servo_driver` expone `reverseServo()` a 180° con la constante
    `kReverseAngleDegrees`, sin cambiar `initServo`, `startServo`, `stopServo` ni
    `setServoAngle`; existe `dispensing_cycle.h` sin Arduino con `MotorPhase`,
    `CyclePorts`, `CycleDiagnostics` y `runDispenseCycle`, que muestrea cada
    200 ms en avance, retroceso y pausa, evalúa el atasco solo en avance,
    comprueba el objetivo en las tres fases y llama a `stop` en toda salida;
    `platformio.ini` añade `test_dispensing_cycle` a `test_ignore` sin
    dependencias nuevas; `pio test -e native` y `pio run` pasan.
  - Comprobación verificable: el servo simulado registra cero `startReverse` con
    `SENSOR_FAILURE`, con orden inválida y con lecturas inválidas alternas, y al
    menos uno en el perfil de estancamiento.
  - Verificación (2026-10-26): con el test nuevo y sin `dispensing_cycle.h`,
    `pio test -e native` falló por cabecera ausente
    (`config/dispensing_cycle.h: No such file or directory`) con las 108 pruebas
    previas en verde. Tras crear la unidad pura, `pio test -e native` pasa
    120/120: `test_provisioning_utils` 5, `test_dispensing_utils` 103 y
    `test_dispensing_cycle` 12. `pio run -t clean && pio run` en `esp32dev`
    termina en SUCCESS (RAM 64 444 B, 19.7 %; Flash 2 005 470 B, 63.8 %) y los
    avisos del build son solo de `bogde/HX711` y `ESP32Servo`. `reverseServo()`
    escribe `kReverseAngleDegrees` y deja el servo marcado en movimiento.
    `dispensing_service.cpp` conserva el bucle anterior hasta T13, así que el
    ciclo nuevo aún no se ejecuta en el firmware. Pruebas de mutación: quitar la
    comprobación del objetivo en retroceso y pausa, evaluar el atasco en las tres
    fases o contar el reintento al retroceder rompe las pruebas nuevas. El
    reintento no se cuenta cuando el objetivo detiene el ciclo dentro del
    retroceso o de la pausa (RF-12). Corrección documental en `plan.md` §7.1: el
    reinicio de la ventana ocurre con progreso igual o mayor que 2 g (con 1,9 g
    no y con 4,9 g sí).

- [x] **T13. Integración del ciclo en el servicio con presupuesto absoluto,
  retroceso, pausa y reanudación.**
  RF-8, RF-12, RF-15, RF-16, RNF-3, RNF-5
  - Hecho cuando: `dispenseWeight` delega en `runDispenseCycle` con los
    adaptadores Arduino (`startServo`, `reverseServo`, `stopServo`,
    `readHx711Raw`, `millis`, espera hasta vencimiento absoluto) y conserva la
    validación previa de factor y cantidad, la inicialización única de la celda,
    el diagnóstico de verificación y la línea de log; el presupuesto se cuenta
    desde el primer arranque de avance e incluye retroceso y pausa; un retroceso
    interrumpido por fallo de sensor o presupuesto no incrementa `retryCount`;
    la firma pública de `dispenseWeight` no cambia; `pio run` compila y
    `pio test -e native` pasa.
  - Comprobación verificable: `pio test -e native` en verde con `reintentos=0/1/3`
    y el motivo nuevo; búsqueda en `src` sin restos del bucle antiguo en
    `dispensing_service.cpp`.
  - Verificación (2026-10-27): `dispenseWeight` construye los `CyclePorts` sobre
    `startServo`, `reverseServo`, `stopServo`, `readHx711Raw`, `millis()` y una
    espera por tramos de 5 ms que recalcula el restante antes de cada `delay()`,
    así que nunca duerme más allá del vencimiento, y delega en
    `runDispenseCycle`. El servicio pasa de 292 a 141 líneas: desaparecen los
    bucles de verificación y de giro, el `switch` de motivos y los helpers de
    vencimientos locales (`reached`, `remainingMs`, `earlierDeadline`,
    `waitUntil`), y se reutilizan los de `dispensing_cycle.h`. Se conservan la
    validación previa, la inicialización única de la celda, el diagnóstico de la
    verificación fallida con `CycleDiagnostics` y la línea única de
    `formatDispenseLog`; `retryCount` sale del ciclo y queda en 0 en las salidas
    tempranas. `pio run -t clean && pio run` en `esp32dev` termina en SUCCESS
    (RAM 64 444 B, 19.7 %; Flash 2 008 370 B, 63.8 %) sin avisos nuevos en
    `src/`, y `pio test -e native` pasa 120/120 (`test_provisioning_utils` 5,
    `test_dispensing_utils` 103, `test_dispensing_cycle` 12). `grep` sin restos
    de `recordRotationSample`, `recordVerificationSample`, `startVerification`,
    `verificationBaseline`, `RotationState`, `earlierDeadline` ni
    `fillDispenseMeasurements` en el servicio; `api_service.cpp` y
    `dispenser_task.cpp` no se tocaron y la firma
    `DispenseResult dispenseWeight(float)` no cambió. La comprobación física del
    retroceso y del presupuesto queda en T15.

- [x] **T14. Validación nativa completa, aserciones de log y compilación.**
  RF-7, RF-8, RF-14, RF-15, RF-16, RF-17, RNF-3, RNF-6
  - Hecho cuando: la suite nativa cubre el perfil de flujo por encima de 0,4 g/s
    sin atasco con «objetivo alcanzado» y `reintentos=0`, los valores por
    defecto de `CycleLimits` iguales a `kMotorBudgetMs` y `kMaxStallRetries`, el
    presupuesto inyectado de 10 000 ms sin atasco con «objetivo no alcanzado» y
    parada del motor a los 10 000 ms, `maxRetries = 0` y un presupuesto que deja
    menos de 3 500 ms al declararse el atasco sin retroceso (la frontera de
    3 499/3 500 ms y el contador en 3 se verifican en `decideStallAction`,
    porque en el ciclo no son alcanzables con el punto de inyección), la cota de
    30 000 ms en todos los perfiles, la prioridad del objetivo sobre el atasco y
    que la última acción del ciclo es `stop`; las cuatro aserciones de log
    actualizadas pasan; `pio run -t clean && pio run` compila y se revisa que no
    hay dependencias nuevas.
  - Comprobación verificable: `pio test -e native` con todas las pruebas en PASS y
    `pio run` en SUCCESS, con conteo de tests y uso de RAM/Flash anotados.
  - Verificación (2026-10-27): `pio test -e native` pasa 130/130
    (`test_provisioning_utils` 5, `test_dispensing_utils` 109,
    `test_dispensing_cycle` 16) y `pio run -t clean && pio run` en `esp32dev`
    termina en SUCCESS (RAM 64 444 B, 19,7 %; Flash 2 008 370 B, 63,8 %) sin
    avisos en `src/` ni en `test/`: los únicos avisos del build son de
    `bogde/HX711` y `ESP32Servo`. `platformio.ini` no añade dependencias
    respecto a `HEAD` (`bogde/HX711 @ ^0.7.5` ya estaba; el único cambio es
    `test_dispensing_cycle` en `test_ignore`, de T12).
    Cierre de las lagunas de T12: la secuencia de reintento comprueba el
    instante de la parada tras el retroceso (`reverseStart + kReverseMs`) y el
    de la reanudación (`+ kPauseMs`), además de la suma de 1 500 ms, y un perfil
    con carga transitoria durante el retroceso y la pausa demuestra que el
    máximo observado incluye esas medianas (segundo atasco a los 17 500 ms y
    `reintentos=2`). Mutaciones verificadas en una copia en `/tmp` y
    revertidas: usar `kPauseMs` como duración del retroceso y `kReverseMs` como
    duración de la pausa rompe `test_stall_profile_reverses_with_fixed_sequence`
    (1200 esperado, 300 obtenido); quitar `feedMovingMedian` del retroceso y de
    la pausa, o solo de la pausa, rompe
    `test_reverse_and_pause_readings_raise_observed_max` (2 retrocesos
    esperados, 1 obtenido). `grep` de «mutacion» en `src/` y `test/` sin
    resultados.
    Matriz de §7.1: se añaden el perfil realista de 1 g/s con ruido alterno de
    0,4 g, el fallo de sensor durante el retroceso y durante la pausa (sin
    retroceso adicional, sin reanudar el avance y con `reintentos=0`), el pico
    doble de ruido que no eleva el máximo observado y la combinación de contador
    y presupuesto en `decideStallAction`; la cota de 30 000 ms y la parada final
    se comprueban en los doce perfiles del ciclo. Los casos de presupuesto de
    3 499 ms, 3 500 ms exactos y contador en 3 se cubren con valores inyectados
    en la función pura, como pide RF-16 («no se verifica de extremo a extremo»).
    Log: se añaden las aserciones de peso final e incremento no disponibles con
    línea base disponible, línea base no disponible al abortar antes de fijarla,
    los textos de los siete motivos en español y una comprobación de ASCII
    imprimible sin palabras sensibles (RNF-5), además de `reintentos=0`, `1` y
    `3` con «atasco no resuelto».
  - Corrección de la revisión de T14 (2026-10-27): la rama `GIVE_UP` del ciclo
    quedaba sin cobertura (sustituirla por `if (false)` mantenía 130/130), porque
    el ciclo usaba las constantes directamente y esa rama solo se alcanza tras
    30 s. Se añade en `dispensing_cycle.h` el punto de inyección `CycleLimits`
    (`motorBudgetMs` y `maxRetries` con los valores aprobados por defecto) como
    sexto parámetro con valor por defecto de `runDispenseCycle`, de modo que el
    servicio no cambia. Nuevas pruebas: `maxRetries = 0` y presupuesto de
    10 000 ms (3 000 ms restantes al declararse el atasco) dan «atasco no
    resuelto» sin retroceso; el ciclo completo se acota en 32 000 ms además de los
    30 000 ms de motor; invariante `kMinRetryBudgetMs >= kReverseMs + kPauseMs +
    kStallGraceMs` (RF-12, RF-16); y un perfil que sube 0,5 g/s en retroceso y
    pausa no declara allí ningún atasco (RF-14). `pio test -e native` 134/134
    (`test_provisioning_utils` 5, `test_dispensing_utils` 110,
    `test_dispensing_cycle` 19) y `pio run -t clean && pio run` en SUCCESS
    (RAM 64 444 B, 19,7 %; Flash 2 008 522 B, 63,8 %). La Flash sube 152 B frente
    a 2 008 370 B por el punto de inyección: 40 B del temporal del argumento por
    defecto en la llamada del servicio y 112 B de leer presupuesto y reintentos
    desde la estructura en vez de inmediatos, medido con una variante en `/tmp`
    que conserva la firma y usa las constantes en el cuerpo; la RAM no cambia.
    Mutaciones en `/tmp`, revertidas: `if (false)` en lugar de la comparación con
    `GIVE_UP` rompe las dos pruebas nuevas («Expected 1 Was 4» y «Was 2»);
    intercambiar `kReverseMs`/`kPauseMs` en el ciclo rompe la secuencia de
    reintento (1200 esperado, 300 obtenido); quitar `feedMovingMedian` del
    retroceso y la pausa rompe `test_reverse_and_pause_readings_raise_observed_max`
    (2 retrocesos esperados, 1 obtenido). La aserción de 32 s se comprobó con una
    igualdad temporal a 32 000 ms en el perfil de estancamiento (la última acción,
    la parada final, cae exactamente en 32 000 ms) y un desfase de 1 ms la rompe.

  - Cierre de huecos de la revisión (2026-10-27): dos aserciones nuevas.
    `test_cycle_limits_default_to_approved_constants` fija que `CycleLimits{}`
    vale `kMotorBudgetMs` y `kMaxStallRetries`, para que el valor de producción
    no pueda separarse de las constantes aprobadas (RNF-7); se coloca en
    `test_dispensing_cycle` porque `CycleLimits` vive en `dispensing_cycle.h` y no
    es visible desde `test_dispensing_utils`.
    `test_injected_budget_exhausts_cycle_without_stall` inyecta 10 000 ms con un
    perfil sin atasco (una lectura válida de cada dos y objetivo de 200 g): el
    ciclo termina en «objetivo no alcanzado», sin retroceso, con la parada final
    exactamente a los 10 000 ms de motor más los 2 s de verificación, lo que fija
    la comprobación de agotamiento del bucle al presupuesto inyectado y no a
    `kMotorBudgetMs`. `pio test -e native` pasa 136/136
    (`test_provisioning_utils` 5, `test_dispensing_utils` 110,
    `test_dispensing_cycle` 21) y `pio run -t clean && pio run` en `esp32dev`
    termina en SUCCESS. Mutaciones en la copia de `/tmp`, revertidas: el valor por
    defecto `maxRetries = 4` rompe la aserción de límites («Expected 3 Was 4»);
    devolver la comprobación de agotamiento del bucle a `kMotorBudgetMs` deja el
    ciclo nuevo sin terminar (bucle ocupado, el reloj virtual ya no avanza), así
    que `pio test` no completa y aborta por timeout; no existe una variante con
    fallo limpio porque el camino de espera también está acotado por el
    presupuesto inyectado.

- [ ] **T15. Checklist físico de atasco y actualización de `MEMORY.md`.**
  RF-14, RF-15, RF-16, RF-17, RNF-3, RNF-4
  - Hecho cuando: con la hélice bloqueada o una croqueta cuñada se observa el
    retroceso de 1,2 s, la pausa de 0,3 s y la reanudación, y si el bloqueo
    persiste el motivo es «atasco no resuelto» con incremento y `reintentos` en
    el log; liberando el bloqueo durante un reintento el motivo es «objetivo
    alcanzado» con `reintentos` mayor que 0; en dispensación normal el motivo es
    «objetivo alcanzado» con `reintentos=0`; el peso de la bandeja antes y
    después del retroceso no disminuye; se observan al menos 5 lecturas por
    segundo en las tres fases; el ciclo de motor no supera 30 s ni el completo
    32 s; se revisa el acoplamiento del tornillo sin fin; `MEMORY.md` queda
    actualizado con estado, decisiones y pendientes.
  - Comprobación verificable: log serie de las tres dispensaciones con
    `reintentos` y motivo, y checklist con fecha anotado en la tarea.

## Nota de alcance

No se incluyen tareas de backend ni de aplicación móvil: el contrato real de la
API (`serve`, `amount`, `reset_wifi`) ya envía la cantidad en gramos y el
descuento de stock sigue fuera de alcance.

La ampliación de detección y resolución de atascos añade T11–T15; la estructura
resultante de 15 tareas fue aprobada por el usuario junto con el plan, y
T11–T14 están implementadas y revisadas.
