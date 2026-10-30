# Tareas 016 — Validación de línea base y plausibilidad del dispensado

Nueve tareas, en orden de dependencia. Tests primero en las tareas de lógica pura (T1, T4, T5, T6 y T7): se escriben
en rojo, se implementan y se ponen en verde dentro de la misma tarea. Ninguna se marca como hecha sin `pio run` en
SUCCESS y `pio test -e native` en verde. Cada tarea declara su validación frente a `docs/constitution.md`.

- [ ] **T1. Constantes nuevas y lógica pura de asentamiento, línea base, plausibilidad y compuerta, con pruebas
  nativas escritas primero.**
  Archivos: `DispensadorESP32/src/config/dispensing_utils.h` (modificar),
  `DispensadorESP32/src/config/scale_guard_utils.h` (nuevo),
  `DispensadorESP32/test/test_scale_guard_utils/test_scale_guard_utils.cpp` (nuevo),
  `DispensadorESP32/platformio.ini` (añadir la suite a `test_ignore`).
  RF: RF-1, RF-2, RF-3, RF-4, RF-5, RNF-3, RNF-5.
  Objetivo: que las cuatro decisiones de la 016 existan como funciones puras, con todas sus constantes en el único
  lugar de la 013, y que la suite nativa las fije antes de que nadie las consuma.
  - Hecho cuando: las pruebas se escriben primero y `pio test -e native` falla por símbolos ausentes; después pasan en
    verde y cubren 14 vs 15 lecturas de asentamiento, paso de 1,0 g frente a 1,01 g, inválida aislada sin retirar el
    asentamiento, 3 inválidas consecutivas que lo retiran, `invalidateSettlement`, mediana de todas las válidas con
    número par e impar, `UNSTABLE`/`INSUFFICIENT_READINGS`/`INVALID_BASELINE`, tope `max(3×amount, amount+10)`, suelo
    estricto en −10 g y contador de 3 con reinicio; `kSettlementReadings`, `kSettlementMaxStepGrams`,
    `kPlausibilityFactor`, `kPlausibilityMarginGrams`, `kPlausibilityFloorGrams` y `kPlausibilityConsecutiveReadings`
    están documentadas en español en `dispensing_utils.h` y no se repiten en otro archivo; `pio run` compila.
  - Dependencias: ninguna. Es la tarea spec-first que exige la constitución.
  - Constitución: Modelo en V (cada RF con su prueba en la misma tarea); separación lógica (cabecera sin Arduino, sin
    decisión en servicios ni tareas); política de tests (unitarias obligatorias antes de fusionar); español en
    documentación y mensajes; sin datos sensibles.

- [ ] **T2. Muestreo continuo del asentamiento e inicialización única de la celda.**
  Archivos: `DispensadorESP32/src/services/scale_guard_service.{h,cpp}` (nuevo),
  `DispensadorESP32/src/drivers/hx711_driver.{h,cpp}` (añadir `ensureHx711Initialized()`),
  `DispensadorESP32/src/services/dispensing_service.cpp` (usar la inicialización compartida),
  `DispensadorESP32/src/main.cpp` (`initScaleGuard()` en `setup()`, `updateSettlement()` en `loop()` antes de
  `runDispenserTask()`), `DispensadorESP32/src/config/config.h` (comentario de umbrales, sin duplicar valores).
  RF: RF-1, RF-2, RF-8, RNF-1, RNF-4.
  Objetivo: que el asentamiento se gane y se pierda en segundo plano desde el arranque, a 5 Hz, sin concurrencia ni
  lógica en las tareas y sin tocar el temporizador de 20 s.
  - Hecho cuando: `updateSettlement()` muestrea como máximo una vez cada `kSamplePeriodMs`, no lanza una lectura si la
    anterior sigue pendiente, usa `readHx711Raw` con `kReadTimeoutMs` y delega toda la decisión en
    `recordSettlementSample`; solo escribe en el log al ganar o perder el asentamiento (texto en español, sin emojis,
    sin credenciales); existe un único `hx711.begin()` en el firmware y tanto el muestreo como `dispenseWeight` pasan
    por `ensureHx711Initialized()`; `tasks/dispenser_task.cpp` queda intacto y `config.h` no duplica constantes;
    `pio test -e native` sigue en verde y `pio run` compila con la RAM y la Flash anotadas.
  - Dependencias: T1.
  - Constitución: separación lógica (la tarea y el servicio no deciden nada); tests obligatorios (lo nuevo con decisión
    ya está cubierto en T1, la integración se verifica por revisión y en físico); sin dependencias nuevas; sin datos
    sensibles en el log.

- [ ] **T3. Compuerta de asentamiento en la consulta: cierre del intento sin mover el servo.**
  Archivos: `DispensadorESP32/src/services/api_service.cpp` (modificar).
  RF: RF-1, RF-7, RF-8.
  Objetivo: que una orden que llegue sin asentamiento se cierre como fallo reportado, sin abrir ciclo, sin dejar de
  consultar y sin bloquear `reset_wifi` ni el reposo.
  - Hecho cuando: el `case DISPENSE` pasa por `decideDispenseEntry(DISPENSE, guard::settlementGained())`; sin
    asentamiento no se llama a `dispenseWeight`, no se toca el servo y se envía
    `reporteVacio(DispenseReason::SENSOR_UNAVAILABLE)` con el `order_id` y los `gramos_solicitados` recibidos y sin
    `gramos_medidos`; con asentamiento se invalida el estado (`guard::invalidateSettlement`) antes de dispensar y se
    conserva el reporte actual; `RESET_WIFI`, `REST` e `INVALID_ORDER` no cambian; el temporizador de 20 s y
    `dispenser_task.cpp` no se tocan; `pio test -e native` en verde y `pio run` compila.
  - Dependencias: T2.
  - Constitución: Modelo en V (la decisión está probada en T1 y aquí solo se cablea); separación lógica (ninguna
    condición nueva escrita en el servicio de API más allá del `switch`); español en el log; sin datos sensibles.

- [ ] **T4. Línea base validada en el ciclo, con motivo real en el log.**
  Archivos: `DispensadorESP32/src/config/dispensing_cycle.h` (modificar),
    `DispensadorESP32/src/services/dispensing_service.cpp` (diagnóstico),
    `DispensadorESP32/test/test_dispensing_cycle/test_dispensing_cycle.cpp` (ampliar).
  RF: RF-2, RF-3, RF-4, RNF-2, RNF-5.
  Objetivo: que la ventana de 2 s de la 013 solo acepte una línea base con 5 válidas y paso ≤1 g entre las últimas 5,
  manteniendo la mediana de todas las válidas, y que el log diga si fue `inestable`, `lecturas_insuficientes` o
  `linea_base_invalida`.
  - Hecho cuando: las pruebas se escriben primero y fallan por `assessBaseline` ausente; después `runDispenseCycle`
    sustituye la comprobación `verificationOutcome != VerificationOutcome::PASSED` de
    `dispensing_cycle.h:245` por `assessBaseline` con este orden interno: menos de 5 válidas →
    `INSUFFICIENT_READINGS`; mediana no calculable o fuera de 0–5000 g → `INVALID_BASELINE`; paso mayor de 1 g entre las
    últimas 5 válidas → `UNSTABLE`; si no → `ACCEPTED` (la salida temprana por 3 inválidas consecutivas de la ventana
    sigue siendo la de la 013 y no cambia, y `verificationOutcome` se conserva solo para ella); `CycleDiagnostics`
    expone `baselineRejection` y el servicio imprime una línea en español con el motivo, las válidas y la base **solo**
    cuando el cierre sea por rechazo de línea base, de modo que los tres motivos son alcanzables y no se anuncian en un
    cierre por otra causa; los perfiles de ventana inestable, 4 válidas y base fuera de rango terminan sin arrancar el
    servo; `verificationBaseline` sigue existiendo y las pruebas de la 013 siguen verdes; `pio run` compila.
  - Dependencias: T1.
  - Constitución: Modelo en V (RF-2 a RF-4 con prueba nativa y componente identificado); separación lógica (la
    validación es pura, el servicio solo imprime); tests obligatorios; español, sin emojis ni credenciales.

- [ ] **T5. Plausibilidad del incremento dentro del ciclo de motor.**
  Archivos: `DispensadorESP32/src/config/dispensing_cycle.h` (modificar),
    `DispensadorESP32/src/services/dispensing_service.cpp` (diagnóstico),
    `DispensadorESP32/test/test_dispensing_cycle/test_dispensing_cycle.cpp` (ampliar, incluida la actualización
    declarada de los perfiles `profileTargetInReverse` y `profileTargetInPause` de la 013).
  RF: RF-5, RF-6, RF-7, RNF-2, RNF-3.
  Objetivo: que un incremento imposible cierre el ciclo como fallo antes que el objetivo o el atasco, sin retroceso ni
  reintento, y que el log distinga `plausibilidad_tope` de `plausibilidad_suelo`.
  - Hecho cuando: las pruebas se escriben primero y fallan; después, en cada lectura válida de las tres fases se evalúa
    `recordPlausibilitySample` antes de `recordRotationSample`; 3 lecturas consecutivas fuera del intervalo cierran con
    `SENSOR_UNAVAILABLE`, cero `startReverse`, sin reanudación de avance y sin `COMPLETED`; 2 fuera y 1 dentro no
    cierran; el tope prevalece sobre el objetivo en la misma lectura; el cierre por tope o suelo durante retroceso o
    pausa no ejecuta retroceso adicional; un incremento dentro del intervalo termina en «objetivo alcanzado» con
    medidos disponibles; `CycleDiagnostics` expone `plausibility`, `topGrams` y `maxIncrementGrams`, y el servicio los
    imprime en una línea en español **solo** para los cierres por plausibilidad, sin volcar el diagnóstico de la
    ventana de verificación (que queda reservado al rechazo de línea base de T4); los perfiles
    `profileTargetInReverse` y `profileTargetInPause` bajan su salto a un valor plausible (por ejemplo 25 g con orden
    de 10 g) para seguir probando «objetivo en retroceso» y «objetivo en pausa» con resultado `COMPLETED`, y se añaden
    variantes nuevas con salto por encima del tope en esas mismas fases; el resto de las pruebas de la 013 no cambia su
    resultado esperado; la cota de 30 s de motor y 32 s de ciclo se mantiene en los perfiles nuevos; `pio run` compila.
  - Dependencias: T1, T4.
  - Constitución: Modelo en V; separación lógica (decisión pura, ciclo solo orquesta); tests obligatorios; español;
    sin datos sensibles.

- [ ] **T6. Pérdida y recuperación del asentamiento tras los cierres que lo exigen.**
  Archivos: `DispensadorESP32/src/services/scale_guard_service.{h,cpp}` (modificar),
    `DispensadorESP32/src/services/api_service.cpp` (modificar),
    `DispensadorESP32/test/test_scale_guard_utils/test_scale_guard_utils.cpp` (ampliar).
  RF: RF-5, RF-8.
  Objetivo: que tras un cierre por tope, por suelo o por 3 lecturas inválidas consecutivas el equipo exija una racha
  nueva antes de aceptar otra orden, en vez de reutilizar un estado viejo.
  - Hecho cuando: `invalidateSettlement(motivo)` registra en español el motivo de la pérdida y deja el estado sin
    racha; `api_service` lo invoca al cerrar por plausibilidad y al detectar el fallo de sensor del ciclo, además de al
    iniciar cualquier ciclo; el flujo queda conectado de forma que ninguna orden pueda abrir un ciclo con el
    asentamiento invalidado; las pruebas nativas cubren la transición, el requisito de 15 lecturas nuevas y las
    transiciones perdido/ganado con sus textos; `pio test -e native` en verde y `pio run` compila.
  - Dependencias: T3, T5.
  - Constitución: Modelo en V (RF-5 y RF-8 con prueba); separación lógica; tests obligatorios; español; sin datos
    sensibles.

- [ ] **T7. Reporte sin gramos medidos y contrato intacto.**
  Archivos: `DispensadorESP32/src/config/report_utils.h` (modificar),
    `DispensadorESP32/test/test_report_utils/test_report_utils.cpp` (ampliar).
  RF: RF-7, RNF-4.
  Objetivo: que los cierres por `sensor_no_disponible` no declaren gramos medidos y que el JSON conserve exactamente
  los campos de la 014, con `order_id`, solicitados y reintentos.
  - Hecho cuando: las pruebas se escriben primero y fallan; después `reporteDesdeResultado` deja `medidosAvailable` en
    falso cuando el motivo es `SENSOR_UNAVAILABLE` y lo conserva en los otros seis motivos; el JSON sigue teniendo
    `mac`, `motivo`, `reintentos` y, cuando existen, `order_id` y `gramos_solicitados`, sin campos nuevos; los tests
    existentes de la 014 revisados y actualizados solo donde esperasen medidos con ese motivo; `pio test -e native` en
    verde con las cuatro suites y `pio run` compila.
  - Dependencias: T5.
  - Constitución: Modelo en V (RF-7 con prueba de contrato); separación lógica (regla en cabecera pura); tests
    obligatorios; español; sin datos sensibles (el resumen del log sigue sin MAC ni JSON).

- [ ] **T8. Validación nativa completa, trazabilidad y no regresión de 013 y 014.**
  Archivos: `DispensadorESP32/test/test_dispensing_cycle/test_dispensing_cycle.cpp` (ampliar y actualizar los dos
    perfiles declarados),
    `DispensadorESP32/test/test_scale_guard_utils/test_scale_guard_utils.cpp` (ampliar),
    `DispensadorESP32/platformio.ini` (revisión), sin cambios en `src/`.
  RF: RF-1 a RF-8, RNF-1, RNF-2, RNF-3, RNF-4, RNF-5.
  Objetivo: cerrar la matriz de pruebas que exige la spec, incluido el caso feliz completo, y demostrar que la 013 y la
  014 no regresan.
  - Hecho cuando: existe una prueba nativa del caso feliz (asentamiento alcanzado, orden aceptada, base estable,
    incremento plausible, «objetivo alcanzado» con medidos disponibles); las pruebas de cota de 30 s y 32 s cubren los
    perfiles nuevos; las 165 pruebas de la familia del dispensado (132 de la 013 —110 de `test_dispensing_utils` y 22 de
    `test_dispensing_cycle`—, 28 de la 014 y 5 de provisión) pasan con la única actualización declarada de las dos
    pruebas de la 013 que se modifican: `profileTargetInReverse` y `profileTargetInPause` reducen su salto a un valor
    plausible (por ejemplo 25 g con orden de 10 g) para seguir probando «objetivo en retroceso» y «objetivo en pausa»,
    con variantes nuevas de salto por encima del tope en esas mismas fases; el resto de las pruebas de la 013 conserva
    su resultado esperado;
    `pio test -e native` en verde con el conteo de las cuatro suites anotado; `pio run -t clean && pio run` en SUCCESS
    con RAM y Flash anotadas; revisión de que `platformio.ini` no añade dependencias, de que las seis constantes están
    solo en `dispensing_utils.h`, de que no hay memoria dinámica en el camino de lectura y de que
    `tasks/dispenser_task.cpp` y el temporizador de 20 s están intactos; `pytest` en `api/` pasa sin cambios.
  - Dependencias: T1 a T7.
  - Constitución: Modelo en V (tabla RF→componente→prueba del plan §11 verificada); separación lógica; política de
    tests en todos los módulos; español; sin datos sensibles; sin dependencias nuevas.

- [ ] **T9. Pruebas físicas (a)–(d), no regresión física y `MEMORY.md`.**
  Archivos: `MEMORY.md` (actualizar); checklist documentado en la propia tarea o en `specs/016-.../tasks.md`.
  RF: RF-1 a RF-8, RNF-1, RNF-4, RNF-5.
  Objetivo: validar sobre la celda real lo que la lógica pura no puede demostrar y dejar el estado del proyecto al día.
  - Hecho cuando: (a) al encender y pedir una orden de inmediato el servo no se mueve, el intento se cierra como
    `sensor_no_disponible` con `order_id`, no hay descuento, el log muestra la ausencia de asentamiento y la consulta
    siguiente llega a los 20 s; (b) presionando la bandeja durante el ciclo el cierre es por tope, con
    `plausibilidad_tope` en el log, sin retroceso y sin descuento; (c) con la bandeja cargada por encima de 10 g y
    retirada a mitad de ciclo el cierre es por suelo con `plausibilidad_suelo`; (d) en un arranque normal la celda
    alcanza 15 lecturas con paso ≤1 g y una dispensación de 50 g termina en «objetivo alcanzado» con descuento de lo
    medido; la no regresión física de la 013 (exactitud, 5 Hz, fallo de sensor sin retroceso, atasco resuelto) se
    repite y se anota con fecha; `MEMORY.md` queda actualizado con estado, decisiones y pendientes, sin datos
    sensibles.
  - Dependencias: T8.
  - Constitución: Modelo en V (evidencia física de los RF cuyo efecto es físico); política de tests (la prueba física
    no sustituye a la automatizada); español; sin datos sensibles en `MEMORY.md`.

## Nota de alcance

No hay tareas de backend ni de app móvil: la 014 ya cierra `sensor_no_disponible` como fallo sin descuento y su
contrato de reporte no cambia. La 016 solo modifica el firmware y añade las tres modificaciones explícitas a la 013 y
la consecuencia defensiva (d) declaradas en la spec.
