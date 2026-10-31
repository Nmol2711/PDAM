# Tareas 016 — Validación de línea base y plausibilidad del dispensado

Nueve tareas, en orden de dependencia. Tests primero en las tareas de lógica pura (T1, T4, T5, T6 y T7): se escriben
en rojo, se implementan y se ponen en verde dentro de la misma tarea. Ninguna se marca como hecha sin `pio run` en
SUCCESS y `pio test -e native` en verde. Cada tarea declara su validación frente a `docs/constitution.md`.

- [x] **T1. Constantes nuevas y lógica pura de asentamiento, línea base, plausibilidad y compuerta, con pruebas
  nativas escritas primero.**
  Archivos: `DispensadorESP32/src/config/dispensing_utils.h` (modificar),
  `DispensadorESP32/src/config/scale_guard_utils.h` (nuevo),
  `DispensadorESP32/test/test_scale_guard_utils/test_scale_guard_utils.cpp` (nuevo),
  `DispensadorESP32/platformio.ini` (añadir la suite a `test_ignore`).
  RF: RF-1, RF-2, RF-3, RF-4, RF-5, RNF-3, RNF-5.
  Objetivo: que las cuatro decisiones de la 016 existan como funciones puras, con todas sus constantes en el único
  lugar de la 013, y que la suite nativa las fije antes de que nadie las consuma.
  - Hecho cuando: las pruebas se escriben primero y `pio test -e native` falla por símbolos ausentes; después pasan en
    verde y cubren 14 vs 15 lecturas de asentamiento (racha ganada exactamente a las 15, no antes), paso de 1,0 g exacto
    frente a 1,01 g, inválida aislada sin retirar el asentamiento, 3 inválidas consecutivas que lo retiran,
    `invalidateSettlement`, mediana de todas las válidas con número par e impar, `UNSTABLE` con 1,01 g y `ACCEPTED` con
    1,0 g, `INSUFFICIENT_READINGS` con 4 válidas, base 0,0 g aceptada, base negativa que no entra en la mediana y deja
    la ventana con menos de 5 válidas → `INSUFFICIENT_READINGS`, y `INVALID_BASELINE` **solo** con un `VerificationState`
    manipulado a mano (buffer vacío con `storedCount = 0` o valores inyectados fuera de 0–5000 g): con muestras reales es
    inalcanzable porque `recordVerificationSample` solo guarda las que pasan `isReadingValid`
    (`dispensing_utils.h:301-306`); tope `max(3×amount, amount+10)` (17,27 g → 51,81 g), suelo estricto en −10 g,
    contador de 3 con reinicio por lectura dentro del intervalo y `resetPlausibility` que lo deja a cero, incluido
    «2 fuera / 1 inválida / 1 fuera» → sin veredicto de cierre (RF-5 exige 3 lecturas válidas consecutivas); el caso (d)
    con factor 0, −1, NaN e infinito: `isReadingValid` rechaza la muestra, `recordSettlementSample` nunca devuelve
    `GAINED` tras 40 respuestas y `decideDispenseEntry(DISPENSE, false)` → `REJECT_NO_SETTLEMENT`; `decideDispenseEntry`
    devuelve además `REST`, `RESET_WIFI` y `REJECT_ORDER` para `REST`, `RESET_WIFI` e `INVALID_ORDER` **con y sin**
    asentamiento, de modo que la compuerta no altera el resto de acciones; `dispensing_utils.h` incluye
    `static_assert(kMedianBufferSize >= 11, ...)` y la prueba lo asevera junto con las seis constantes nuevas
    (`kSettlementReadings`, `kSettlementMaxStepGrams`, `kPlausibilityFactor`, `kPlausibilityMarginGrams`,
    `kPlausibilityFloorGrams` y `kPlausibilityConsecutiveReadings`), documentadas en español en ese único archivo y sin
    repetirse en otro; `pio run` compila.
  - Dependencias: ninguna. Es la tarea spec-first que exige la constitución.
  - Constitución: Modelo en V (cada RF con su prueba en la misma tarea); separación lógica (cabecera sin Arduino, sin
    decisión en servicios ni tareas); política de tests (unitarias obligatorias antes de fusionar); español en
    documentación y mensajes; sin datos sensibles.
  - Cierre (2026-10-30): hecha. `pio test -e native` en verde con 202 pruebas (37 nuevas de `test_scale_guard_utils`;
    las de la 013 y la 014 sin regresión) y `pio run` en SUCCESS (RAM 19,7 % / 64 444 B, Flash 64,4 % / 2 024 914 B).

- [x] **T2. Muestreo continuo del asentamiento e inicialización única de la celda.**
  Archivos: `DispensadorESP32/src/services/scale_guard_service.{h,cpp}` (nuevo),
  `DispensadorESP32/src/drivers/hx711_driver.{h,cpp}` (añadir `ensureHx711Initialized()`),
  `DispensadorESP32/src/services/dispensing_service.cpp` (usar la inicialización compartida),
  `DispensadorESP32/src/main.cpp` (`initScaleGuard()` en `setup()`, `updateSettlement()` en `loop()` antes de
  `runDispenserTask()`), `DispensadorESP32/src/config/config.h` (comentario de umbrales, sin duplicar valores).
  RF: RF-1, RF-2, RF-8, RNF-1, RNF-4.
  Objetivo: que el asentamiento se gane y se pierda en segundo plano desde el arranque, a 5 Hz, sin concurrencia ni
  lógica en las tareas y sin tocar el temporizador de 20 s.
  - Hecho cuando: `updateSettlement()` muestrea como máximo una vez por `kSamplePeriodMs` (nunca dos lecturas dentro
    del mismo periodo, criterio observable en el código y en la revisión), sondea con `readHx711Raw` acotado por
    `kReadTimeoutMs` y toma la muestra con `makeSample`, delegando toda la decisión en `recordSettlementSample`; el
    tramo `hx711.read()` de la librería queda como deuda declarada de la 013, sin cota propia, y no se inventa una
    guarda de «lectura pendiente» porque la lectura es síncrona; solo escribe en el log al ganar o perder el
    asentamiento (texto en español, sin emojis, sin credenciales) y, si el factor de calibración no es finito o no es
    positivo, `initScaleGuard()` imprime una única línea que nombra esa causa (caso (d)), sin decidir nada; no hay tarea
    FreeRTOS nueva, ni memoria compartida, ni muestreo desde dentro del ciclo de motor: `updateSettlement()` se llama
    solo desde `loop()`; existe un único `hx711.begin()` en el firmware y tanto el muestreo como `dispenseWeight` pasan
    por `ensureHx711Initialized()`; `tasks/dispenser_task.cpp` queda intacto y `config.h` no duplica constantes;
    `pio test -e native` sigue en verde y `pio run` compila con la RAM y la Flash anotadas.
  - Dependencias: T1.
  - Constitución: separación lógica (la tarea y el servicio no deciden nada); tests obligatorios (lo nuevo con decisión
    ya está cubierto en T1, la integración se verifica por revisión y en físico); sin dependencias nuevas; sin datos
    sensibles en el log.
  - Cierre (2026-10-30): hecha. `scale_guard_service.{h,cpp}` muestrea a 5 Hz desde `loop()`, `ensureHx711Initialized()`
    centraliza el único `hx711.begin()` (ya no queda `initHx711` ni el `static bool` del servicio) y `main.cpp` arranca
    el guardia antes de `runDispenserTask()`. `pio test -e native` en verde con 202 pruebas en las cinco suites (sin
    suite Arduino nueva) y `pio run -t clean && pio run` en SUCCESS (RAM 19,7 % / 64 476 B, Flash 64,4 % /
    2 026 218 B). `tasks/dispenser_task.cpp` intacto.

- [x] **T3. Compuerta de asentamiento en la consulta: cierre del intento sin mover el servo.**
  Archivos: `DispensadorESP32/src/services/api_service.cpp` (modificar).
  RF: RF-1, RF-7, RF-8.
  Objetivo: que una orden que llegue sin asentamiento se cierre como fallo reportado, sin abrir ciclo, sin dejar de
  consultar y sin bloquear `reset_wifi` ni el reposo.
  - Hecho cuando: el `case DISPENSE` pasa por `decideDispenseEntry(DISPENSE, guard::settlementGained())`; sin
    asentamiento no se llama a `dispenseWeight`, no se toca el servo y se envía
    `reporteVacio(DispenseReason::SENSOR_UNAVAILABLE)` con el `order_id` y los `gramos_solicitados` recibidos y sin
    `gramos_medidos`; la compuerta va **antes** de cualquier comprobación de factor, de modo que un factor de
    calibración inválido se reporta como `sensor_no_disponible` y nunca como `orden_invalida` (caso (d)); con
    asentamiento se invalida el estado (`guard::invalidateSettlement`) antes de dispensar y se conserva el reporte
    actual; `RESET_WIFI`, `REST` e `INVALID_ORDER` no cambian; el temporizador de 20 s y `dispenser_task.cpp` no se
    tocan; `pio test -e native` en verde y `pio run` compila.
  - Dependencias: T2.
  - Constitución: Modelo en V (la decisión está probada en T1 y aquí solo se cablea); separación lógica (ninguna
    condición nueva escrita en el servicio de API más allá del `switch`); español en el log; sin datos sensibles.
  - Cierre (2026-10-30): hecha. El `switch` de `api_service.cpp` pasa a `decideDispenseEntry(classifyOrder(...),
    guard::settlementGained())` con los cinco resultados: `RESET_WIFI`, `DISPENSE`, `REJECT_NO_SETTLEMENT`,
    `REJECT_ORDER` y `REST`. `REJECT_NO_SETTLEMENT` no llama a `dispenseWeight`, no invalida el asentamiento y envía
    `reporteVacio(SENSOR_UNAVAILABLE)` con `order_id` y `gramos_solicitados` y sin `gramos_medidos`; `DISPENSE` invoca
    `guard::invalidateSettlement(nullptr)` antes de `dispenseWeight(amount)` —invalida el asentamiento al abrir el ciclo
    sin registrar el motivo, porque el cierre es quien informa del motivo— y conserva el reporte del ciclo.
    `pio test -e native` en verde con 202 pruebas en las cinco suites (sin suites nuevas) y `pio run -t clean && pio run`
    en SUCCESS (RAM 19,7 % / 64 476 B, Flash 64,4 % / 2 026 846 B). `tasks/dispenser_task.cpp`, el temporizador de 20 s
    y `servo_driver` intactos.

- [x] **T4. Línea base validada en el ciclo, con motivo real en el log.**
  Archivos: `DispensadorESP32/src/config/dispensing_cycle.h` (modificar),
    `DispensadorESP32/src/services/dispensing_service.cpp` (diagnóstico),
    `DispensadorESP32/test/test_dispensing_cycle/test_dispensing_cycle.cpp` (ampliar).
  RF: RF-2, RF-3, RF-4, RF-8, RNF-2, RNF-5.
  Objetivo: que la ventana de 2 s de la 013 solo acepte una línea base con 5 válidas y paso ≤1 g entre las últimas 5,
  manteniendo la mediana de todas las válidas, que un aborto por 3 inválidas no evalúe base alguna, y que el log diga
  si el rechazo fue `inestable` o `lecturas_insuficientes` (los alcanzables desde el ciclo; `linea_base_invalida` queda
  como caso defensivo y se prueba en T1) o si la ventana se abortó por inválidas.
  - Hecho cuando: las pruebas se escriben primero y fallan por `assessBaseline` ausente; después `runDispenseCycle`
    sustituye la comprobación equivalente, hoy en `dispensing_cycle.h:333-337`, por una **guarda explícita previa** y
    `assessBaseline`: si `verificationOutcome == ABORTED_BY_INVALID` (el `break` de `dispensing_cycle.h:286-288` cae al
    código posterior y antes de la 016 llegaba a la evaluación de la base; hoy lo intercepta la guarda de
    `dispensing_cycle.h:310-314`), el ciclo hace `stop()`,
    cierra con `SENSOR_UNAVAILABLE` y no produce veredicto de línea base —con 5 válidas previas más 3 inválidas
    consecutivas `assessBaseline` aceptaría una base de una ventana abortada—; con la ventana agotada por tiempo, el
    orden interno es: menos de 5 válidas → `INSUFFICIENT_READINGS`; mediana no calculable o fuera de 0–5000 g →
    `INVALID_BASELINE` (defensivo); paso mayor de 1 g entre las últimas 5 válidas → `UNSTABLE`; si no → `ACCEPTED`;
    `verificationOutcome` se conserva solo para la guarda; `CycleDiagnostics` expone `baselineRejection` y el servicio
    imprime **una línea en español por cada uno de los tres caminos de cierre**: rechazo de línea base →
    `logVerificationDiagnostics` más el motivo real, las válidas y la base; aborto por 3 inválidas → conserva
    `logVerificationDiagnostics` de la 013 (muestras, respondidas, últimas inválidas y su «causa probable», que es lo
    que distingue un sensor desconectado) y no añade veredicto de base, que no existe; cierre por plausibilidad (T5) →
    solo su línea, nunca el diagnóstico de la ventana; los perfiles de ventana inestable (última lectura a 1,01 g),
    4 válidas, base negativa (que no entra en la mediana y deja menos de 5 válidas) y **5 válidas estables más 3
    inválidas consecutivas** terminan sin arrancar el servo, con el motivo correspondiente en el log y texto en español
    (`inestable`, `lecturas_insuficientes`, `linea_base_invalida`); el perfil de las 5 estables y 3 inválidas comprueba
    que el servo queda inmóvil y que el cierre es el de RF-4 de la 013 (`SENSOR_UNAVAILABLE` sin arranque), no un
    veredicto nuevo; **no** se perfila «base fuera de rango», porque `recordVerificationSample` solo guarda lecturas
    que pasan `isReadingValid` (`dispensing_utils.h:301-306`) y la mediana nunca sale de 0–5000 g: `INVALID_BASELINE`
    se cubre en T1 con un `VerificationState` manipulado; la mediana se comprueba con número par e impar de válidas y
    el límite de 1,0 g exacto se acepta mientras 1,01 g se rechaza; `verificationBaseline` sigue existiendo y las
    pruebas de la 013 siguen verdes; `pio run` compila.
  - Dependencias: T1.
  - Constitución: Modelo en V (RF-2 a RF-4 y RF-8 con prueba nativa y componente identificado); separación lógica (la
    validación es pura, el servicio solo imprime); tests obligatorios; español, sin emojis ni credenciales.
  - Cierre (2026-10-30): hecha. `runDispenseCycle` resuelve **antes** el aborto por 3 inválidas (`stop()`,
    `SENSOR_UNAVAILABLE`, sin veredicto de base) y sustituye `verificationOutcome != PASSED` por `assessBaseline`;
    `verificationOutcome` solo se usa para esa guarda y `verificationBaseline` se conserva (da la mediana solo para el
    log). `CycleDiagnostics` expone `baselineRejection` (`BaselineStatus`, con `NOT_EVALUATED` porque el veredicto puro
    no tiene «sin veredicto»), `hasBaseline` y `baselineGrams`; el servicio imprime una línea de rechazo con
    `inestable`/`lecturas_insuficientes`/`linea_base_invalida`, las válidas y la base, conserva intacto el diagnóstico
    de la 013 en el aborto y mantiene la línea única de `formatDispenseLog`. Seis pruebas nuevas en
    `test_dispensing_cycle` (inestable, 4 válidas, negativas, aborto sin veredicto, 1,0 g frente a 1,01 g, mediana
    par/impar) y se comprobó que la del aborto falla si se retira la guarda. `pio test -e native` en verde con 208
    pruebas (provisión 5, dispensing_utils 110, dispensing_cycle 28, report_utils 28, scale_guard_utils 37) y
    `pio run -t clean && pio run` en SUCCESS (RAM 19,7 % / 64 476 B, Flash 64,5 % / 2 027 862 B).

- [x] **T5. Plausibilidad del incremento dentro del ciclo de motor.**
  Archivos: `DispensadorESP32/src/config/dispensing_cycle.h` (modificar),
    `DispensadorESP32/src/services/dispensing_service.cpp` (diagnóstico),
    `DispensadorESP32/test/test_dispensing_cycle/test_dispensing_cycle.cpp` (ampliar, incluida la actualización
    declarada de los perfiles `profileTargetInReverse` y `profileTargetInPause` de la 013).
  RF: RF-5, RF-6, RF-7, RNF-2, RNF-3.
  Objetivo: que un incremento imposible cierre el ciclo como fallo antes que el objetivo o el atasco, sin retroceso ni
  reintento, y que el log distinga `plausibilidad_tope` de `plausibilidad_suelo`.
  - Hecho cuando: las pruebas se escriben primero y fallan; después, en cada lectura válida de las tres fases se evalúa
    `recordPlausibilitySample` antes de `recordRotationSample`, y toda lectura inválida llama a `resetPlausibility`
    (RF-5 exige 3 lecturas **válidas** consecutivas); 3 lecturas consecutivas fuera del intervalo cierran con
    `SENSOR_UNAVAILABLE`, cero `startReverse`, sin reanudación de avance y sin `COMPLETED`; 2 fuera y 1 dentro no
    cierran, y **2 fuera / 1 inválida / 1 fuera tampoco**, porque la inválida reinicia el contador; el tope prevalece
    sobre el objetivo en la misma lectura y sobre el atasco declarado en la misma muestra; el cierre por tope o suelo
    durante retroceso o pausa no ejecuta retroceso adicional; un incremento dentro del intervalo termina en «objetivo
    alcanzado» con medidos disponibles; una llamada directa con factor 0, NaN o infinito sigue devolviendo
    `INVALID_CONFIG` sin tocar puertos, como la 013 (el caso (d) se cierra en la compuerta, T3); `CycleDiagnostics`
    expone `plausibility`, `topGrams` y `maxIncrementGrams`, y el servicio los imprime en una línea en español **solo**
    para los cierres por plausibilidad, sin volcar el diagnóstico de la ventana de verificación (que queda reservado al
    rechazo de línea base y al aborto por inválidas de T4); los perfiles `profileTargetInReverse` y
    `profileTargetInPause` bajan su salto a un valor plausible (por ejemplo 25 g con orden de 10 g) para seguir probando
    «objetivo en retroceso» y «objetivo en pausa» con resultado `COMPLETED`, y se añaden variantes nuevas con salto por
    encima del tope en esas mismas fases; el resto de las pruebas de la 013 no cambia su resultado esperado; la cota de
    30 s de motor y 32 s de ciclo se mantiene en los perfiles nuevos; `pio run` compila.
  - Dependencias: T1, T4.
  - Constitución: Modelo en V; separación lógica (decisión pura, ciclo solo orquesta); tests obligatorios; español;
    sin datos sensibles.
  - Cierre (2026-10-30): hecha. `runDispenseCycle` evalúa `recordPlausibilitySample` en cada lectura válida de avance,
    retroceso y pausa **antes** de `recordRotationSample` y llama a `resetPlausibility` en toda lectura inválida; el
    cierre llena `CycleDiagnostics` con `plausibility`, `topGrams` y `maxIncrementGrams`, hace `stop()`, cierra con
    `SENSOR_UNAVAILABLE` y no ejecuta `startReverse`, ni reanudación, ni reintento, ni objetivo alcanzado. El tope
    prevalece sobre el objetivo en la misma lectura (se comprobó desactivando la guarda: `profileAboveTopInAdvance` y
    `profileTargetAndTop` terminaban en `COMPLETED`) y el suelo sobre el atasco que la 013 declararía en esa misma
    muestra (`profileFloorAtStallExpiry`: sin la guarda cerraba con `STALL_UNRESOLVED`). No existe una muestra de
    atasco por encima del tope, porque todo incremento mayor que el tope (≥ cantidad + 10 g) supera también el
    objetivo, que la 013 ya comprueba antes del atasco; la prioridad sobre el atasco queda fijada por el caso del
    suelo. `maxIncrementGrams` guarda el mayor incremento observado en el ciclo de motor, incluido un ciclo
    íntegramente negativo: se inicializa con el primer incremento válido (bandera `hasIncrement`) y no con cero, así que
    con la bandeja retirada desde la primera muestra informa del menos negativo y nunca de un 0 g que no se midió; en el
    cierre por tope coincide con la lectura de cierre y en el cierre por suelo conserva el pico previo. El peso final de
    la lectura de cierre se traslada a `RotationState` solo para que el log serie lo muestre (el reporte lo omitirá por
    RF-7). Catorce pruebas nuevas en `test_dispensing_cycle`: tope en avance, suelo en avance, 2 fuera / 1 dentro, 2
    fuera / 1 inválida / 1 fuera, tope sobre objetivo en la misma lectura, suelo sobre atasco en la misma muestra, tope
    y suelo en retroceso y en pausa, incremento plausible desde una base de 12 g con medidos disponibles, −3 g dentro
    del suelo con el comportamiento de la 013, factor 0/−1/NaN/infinito con `INVALID_CONFIG` sin tocar puertos y un
    ciclo con todos los incrementos negativos (−12 g constantes) que cierra por suelo e informa `maxIncrementGrams`
    = −12 g.
    `profileTargetInReverse` y `profileTargetInPause` bajan su salto de 50 g a 25 g con orden de 10 g (tope 30 g) y
    siguen dando `COMPLETED`; los perfiles nuevos entran en las cotas de 30 s de motor y 32 s de ciclo. El servicio
    imprime solo su línea (`Cierre por plausibilidad: motivo=..., incremento_max=..., base=..., tope=...`) y conserva
    intactos los diagnósticos de T4. `pio test -e native` en verde con 222 pruebas (provisión 5, dispensing_utils 110,
    dispensing_cycle 42, report_utils 28, scale_guard_utils 37) y `pio run -t clean && pio run` en SUCCESS
    (RAM 19,7 % / 64 476 B, Flash 64,5 % / 2 028 866 B).

- [x] **T6. Pérdida y recuperación del asentamiento tras los cierres que lo exigen.**
  Archivos: `DispensadorESP32/src/services/scale_guard_service.{h,cpp}` (modificar),
    `DispensadorESP32/src/services/api_service.cpp` (modificar),
    `DispensadorESP32/test/test_scale_guard_utils/test_scale_guard_utils.cpp` (ampliar).
  RF: RF-5, RF-8.
  Objetivo: que tras un cierre por tope, por suelo o por 3 lecturas inválidas consecutivas el equipo exija una racha
  nueva antes de aceptar otra orden, en vez de reutilizar un estado viejo.
  - Hecho cuando: `invalidateSettlement(motivo)` registra en español el motivo de la pérdida y deja el estado sin
    racha; `api_service` lo invoca al iniciar cualquier ciclo y ante **cualquier** cierre del ciclo con
    `SENSOR_UNAVAILABLE` o `SENSOR_FAILURE` —sin pretender distinguir tope de suelo en el servicio, que solo ve el
    motivo del cierre—; la distinción de causa (tope, suelo, 3 inválidas) se prueba en la lógica pura, no en
    `api_service`; el flujo queda conectado de forma que ninguna orden pueda abrir un ciclo con el asentamiento
    invalidado; las pruebas nativas cubren la transición de ganado a perdido con 3 lecturas inválidas consecutivas y
    tras un cierre por tope y por suelo, que no se vuelve a ganar hasta completar 15 lecturas nuevas (ni con 14), y los
    textos en español de cada transición; `pio test -e native` en verde y `pio run` compila.
  - Dependencias: T3, T5.
  - Constitución: Modelo en V (RF-5 y RF-8 con prueba); separación lógica; tests obligatorios; español; sin datos
    sensibles.
  - Cierre (2026-10-30): hecha. `guard::invalidateSettlement(motivo)` ya delegaba en la función pura y solo imprime
    `Asentamiento invalidado: <motivo>` cuando el motivo no es nulo (con `nullptr` no imprime nada); se documentó esa
    condición en la cabecera. `api_service.cpp` conserva la invalidación al abrir el ciclo —con `nullptr`, sin línea de
    log— y, tras `dispenseWeight`, invalida ante `SENSOR_UNAVAILABLE` («cierre sin medicion fiable») y ante
    `SENSOR_FAILURE` («fallo de sensor»), sin distinguir tope, suelo ni 3 inválidas y sin umbrales nuevos; `COMPLETED`
    y los atascos reintentados no invalidan nada. Con la apertura en `nullptr`, la línea `Asentamiento invalidado:
    <motivo>` solo la imprimen esos dos cierres. La compuerta sigue consultando
    `guard::settlementGained()`, así que ninguna orden abre un ciclo con el estado invalidado. Pruebas: las transiciones
    de ganado a perdido con 3 inválidas consecutivas y las 14/15 lecturas nuevas tras una pérdida ya estaban en T1; se
    añadieron dos casos de pérdida simulada desde el consumidor (cierre por tope con base de 10 g y por suelo con base
    de 12 g, ambos con 14 lecturas insuficientes y 15 suficientes y con sus textos
    `plausibilidad_tope`/`plausibilidad_suelo`) y se completó la prueba de textos con `incremento_plausible`.
    La lógica pura no cambió, así que las pruebas nacieron en verde contra T1: no había símbolo nuevo que hiciera falta
    implementar. `pio test -e native` en verde con 224 pruebas (provisión 5, dispensing_utils 110, dispensing_cycle 42,
    report_utils 28, scale_guard_utils 39) y `pio run -t clean && pio run` en SUCCESS (RAM 19,7 % / 64 476 B, Flash
    64,5 % / 2 028 978 B).

- [x] **T7. Reporte sin gramos medidos y contrato intacto.**
  Archivos: `DispensadorESP32/src/config/report_utils.h` (modificar),
    `DispensadorESP32/test/test_report_utils/test_report_utils.cpp` (ampliar).
  RF: RF-7, RNF-4.
  Objetivo: que los cierres por `sensor_no_disponible` no declaren gramos medidos y que el JSON conserve exactamente
  los campos de la 014, con `order_id`, solicitados y reintentos.
  - Hecho cuando: las pruebas se escriben primero y fallan; después `reporteDesdeResultado` deja `medidosAvailable` en
    falso cuando el motivo es `SENSOR_UNAVAILABLE` y lo conserva en los otros seis motivos; el JSON sigue teniendo
    `mac`, `motivo`, `reintentos` y, cuando existen, `order_id` y `gramos_solicitados`, sin campos nuevos; existe un caso
    `SENSOR_UNAVAILABLE` con `retryCount = 2` que comprueba `reintentos:2` en el JSON y la ausencia total de
    `gramos_medidos` (el contador de reintentos no se pierde al omitir la medición); los tests existentes de la 014
    revisados y actualizados solo donde esperasen medidos con ese motivo; `pio test -e native` en verde con las cuatro
    suites y `pio run` compila.
  - Dependencias: T5.
  - Constitución: Modelo en V (RF-7 con prueba de contrato); separación lógica (regla en cabecera pura); tests
    obligatorios; español; sin datos sensibles (el resumen del log sigue sin MAC ni JSON).
  - Cierre (2026-10-30): hecha. `reporteDesdeResultado` declara los medidos solo cuando
    `incrementAvailable` y el motivo no es `SENSOR_UNAVAILABLE`; `order_id`, `gramos_solicitados` y `reintentos`
    conservan su derivación y el JSON mantiene exactamente las claves de la 014 (sin campos nuevos, mismo orden).
    `construirReporteJson` y el resumen del log serie no cambiaron (RNF-4). Pruebas escritas primero y verificadas en
    rojo (`test_sensor_no_disponible_no_declara_gramos_medidos` y
    `test_sensor_no_disponible_conserva_los_reintentos_sin_medidos` fallaban): (a) `SENSOR_UNAVAILABLE` con incremento
    disponible → JSON exacto sin `gramos_medidos`, con `order_id`, solicitados y reintentos; (b) `retryCount = 2` →
    `reintentos:2` y ausencia total de `gramos_medidos`; (c) los otros seis motivos conservan los medidos cuando están
    disponibles; (d) `reporteVacio(SENSOR_UNAVAILABLE)` con orden y solicitados aplica el mismo criterio. Las 28
    pruebas previas de la 014 no necesitaron cambios (el único caso con ese motivo ya usaba
    `incrementAvailable = false`). `pio test -e native` en verde con 228 pruebas (provisión 5, dispensing_utils 110,
    dispensing_cycle 42, report_utils 32, scale_guard_utils 39) y `pio run -t clean && pio run` en SUCCESS (RAM
    19,7 % / 64 476 B, Flash 64,5 % / 2 029 002 B).

- [x] **T8. Validación nativa completa, trazabilidad y no regresión de 013 y 014.**
  Archivos: `DispensadorESP32/test/test_dispensing_cycle/test_dispensing_cycle.cpp` (ampliar y actualizar los dos
    perfiles declarados),
    `DispensadorESP32/test/test_scale_guard_utils/test_scale_guard_utils.cpp` (ampliar),
    `DispensadorESP32/platformio.ini` (revisión), sin cambios en `src/`.
  RF: RF-1 a RF-8, RNF-1, RNF-2, RNF-3, RNF-4, RNF-5.
  Objetivo: cerrar la matriz de pruebas que exige la spec, incluido el caso feliz completo, y demostrar que la 013 y la
  014 no regresan.
  - Hecho cuando: existe una prueba nativa del caso feliz (asentamiento alcanzado, orden aceptada, base estable,
    incremento plausible, «objetivo alcanzado» con medidos disponibles); están cubiertos los perfiles que exige la spec:
    mediana de todas las válidas con número par e impar, 5 válidas con paso de 1 g exacto y con 1,01 g, cuatro válidas,
    base negativa, 5 válidas estables más 3 inválidas consecutivas (aborto de ventana con servo inmóvil y cierre de
    RF-4 de la 013), dos lecturas fuera y una dentro sin cierre, 2 fuera / 1 inválida / 1 fuera sin cierre, tope
    prevaleciendo sobre objetivo y sobre atasco, tope y suelo en retroceso y en pausa, transición a perdido tras 3
    inválidas y tras cierre por tope y por suelo con 15 lecturas nuevas, racha ganada exactamente a las 15, caso (d)
    con factor 0, −1, NaN e infinito, `INVALID_BASELINE` con un `VerificationState` manipulado (no desde el ciclo: es
    inalcanzable con lecturas 0–5000 g) y textos del log (`inestable`, `lecturas_insuficientes`, `linea_base_invalida`,
    `plausibilidad_tope`, `plausibilidad_suelo`) solo en el monitor serie; el log distingue los tres caminos de cierre
    (rechazo de base con motivo, aborto por inválidas con el diagnóstico de la 013 y plausibilidad con su línea); las
    pruebas de cota de 30 s de motor y 32 s de ciclo cubren los perfiles nuevos; las 165 pruebas de la familia del
    dispensado (132 de la 013 —110 de `test_dispensing_utils` y 22 de `test_dispensing_cycle`—, 28 de la 014 y 5 de
    provisión) pasan con la única actualización declarada de las dos pruebas de la 013 que se modifican:
    `profileTargetInReverse` y `profileTargetInPause` reducen su salto a un valor plausible (por ejemplo 25 g con orden
    de 10 g) para seguir probando «objetivo en retroceso» y «objetivo en pausa», con variantes nuevas de salto por
    encima del tope en esas mismas fases; el resto de las pruebas de la 013 conserva su resultado esperado;
    `pio test -e native` en verde con el conteo de las cuatro suites anotado; `pio run -t clean && pio run` en SUCCESS
    con RAM y Flash anotadas; revisión de que `platformio.ini` no añade dependencias, de que
    `static_assert(kMedianBufferSize >= 11, ...)` está junto a la constante y de que las seis constantes están solo en
    `dispensing_utils.h`, de que no hay memoria dinámica en el camino de lectura, ni tarea FreeRTOS o memoria compartida
    nuevas, ni muestreo desde dentro del ciclo, y de que `tasks/dispenser_task.cpp` y el temporizador de 20 s están
    intactos; `pytest` en `api/` pasa sin cambios.
  - Dependencias: T1 a T7.
  - Constitución: Modelo en V (tabla RF→componente→prueba del plan §11 verificada); separación lógica; política de
    tests en todos los módulos; español; sin datos sensibles; sin dependencias nuevas.
  - Cierre (2026-10-30): hecha. Caso feliz completo en `test_dispensing_cycle`
    (`test_happy_path_settles_accepts_the_order_and_completes_with_measurements`): 14 lecturas estables que no ganan
    el asentamiento, 15 que lo ganan, compuerta `decideDispenseEntry(DISPENSE, true)` → `DISPENSE`, perfil nuevo
    `profileHappyPath` (base 0 g, 1 g/s) con `COMPLETED`, cero reintentos y cero retrocesos, cotas de 30 s de motor y
    32 s de ciclo, y `reporteDesdeResultado` → JSON de la 014 con `objetivo_alcanzado` y `gramos_medidos`. Se usan
    20 g con 1 g/s en lugar de los 50 g del plan: 50 g exigirían 50 s de motor y superarían el presupuesto de 30 s.
    Hueco de cobertura del revisor cerrado en `test_report_utils`
    (`test_sin_incremento_por_causa_distinta_al_sensor_tampoco_hay_medidos`): `incrementAvailable = false` con
    `NOT_REACHED` (0 reintentos) y `SENSOR_FAILURE` (1 reintento) exige JSON exacto sin `gramos_medidos`; con la
    mutación de quitar `incrementAvailable &&` falla ese caso mientras el antiguo de `SENSOR_UNAVAILABLE` seguía
    pasando, así que el hueco era real. `profileHappyPath` entra en el vector de cotas y los trece perfiles de
    plausibilidad ya estaban; las pruebas de línea base y de plausibilidad se revisaron una a una (par/impar, 1,0 vs
    1,01 g, 4 válidas, base negativa, 5+3 inválidas, 2 fuera/1 dentro, 2 fuera/1 inválida/1 fuera, tope sobre
    objetivo, tope y suelo en retroceso y pausa, pérdida y 15 nuevas, racha exacta a 15, caso (d), `INVALID_BASELINE`
    manipulado y textos). Se documentó en el archivo de pruebas por qué «tope sobre atasco» es inalcanzable (todo
    incremento > tope supera el objetivo y reinicia la ventana de estancamiento) y que la prioridad de RF-6 se fija
    con el suelo. Mutaciones en copia de `/tmp/opencode`: quitar `incrementAvailable &&` (falla el caso nuevo), ganar
    la racha a las 14 (falla el caso feliz) y evaluar la plausibilidad solo en avance (fallan los cuatro perfiles de
    retroceso y pausa). Revisión de código sin cambios en `src/`: `platformio.ini` solo añade la suite a `test_ignore`
    y no toca `lib_deps`; `static_assert(kMedianBufferSize >= 11, ...)` junto a la constante; seis constantes solo en
    `dispensing_utils.h` y `config.h` sin duplicar valores; sin `new`/`malloc`/contenedores en el camino de lectura;
    sin tarea FreeRTOS ni memoria compartida; `updateSettlement()` solo desde `loop()`; un único `hx711.begin()`;
    `tasks/dispenser_task.cpp` no aparece en `git diff` y `CHECK_INTERVAL = 20000` sigue intacto; los cinco motivos de
    log solo se consumen en `dispensing_service.cpp`. Criterios sin prueba nativa, por diseño: la consulta cada 20 s,
    el `order_id` del cierre sin ciclo, la ausencia de memoria dinámica y los textos del log son revisión de código;
    las pruebas físicas (a)–(d) y la inspección del log real son T9; la rama defensiva
    `storedCount < kMinValidReadings` de `assessBaseline` es inalcanzable con el buffer de 16. `pio test -e native` en
    verde con 230 pruebas (provisión 5, dispensing_utils 110, dispensing_cycle 43, report_utils 33, scale_guard_utils
    39) y `pio run -t clean && pio run` en SUCCESS (RAM 19,7 % / 64 476 B, Flash 64,5 % / 2 028 994 B). `pytest -q`
    en `api/`: 685 passed y 848 subtests, sin cambios; la 013 y la 014 no cambian de expectativa salvo los dos
    perfiles declarados en T5.

- [ ] **T9. Pruebas físicas (a)–(d), no regresión física y `MEMORY.md`.**
  Archivos: `MEMORY.md` (actualizar); checklist documentado en la propia tarea o en `specs/016-.../tasks.md`.
  RF: RF-1 a RF-8, RNF-1, RNF-4, RNF-5.
  > **Estado (2026-10-30):** **Pendiente** de las pruebas físicas (a)–(d) y de la no regresión física de la 013; el
  > resto de la tarea está documentado. El usuario decidió aplazar esas pruebas por ahora. No queda trabajo de código:
  > el plan ya está alineado con lo implementado (§5.3 y §5.4, y §9.2 con el caso feliz a 20 g en lugar de 50 g
  > porque 50 g a 1 g/s superarían el presupuesto de 30 s de motor de RNF-2). T9 se marcará hecha solo con la
  > evidencia del checklist siguiente anotada.
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
  - Checklist ejecutable (pendiente; la evidencia se anota aquí mismo, con fecha):
    1. Preparación: `cd DispensadorESP32 && pio run --target upload` y, en otra terminal,
       `cd DispensadorESP32 && pio device monitor`. Anotar fecha, versión cargada y la línea de arranque; dejar la
       báscula vacía y estable durante 10 s antes de (d).
    2. **(a) Orden inmediata tras encender**: reiniciar la placa y pedir una orden desde la app antes de 3 s (antes
       de que la racha de 15 lecturas a 5 Hz pueda ganarse). En el monitor serie: ninguna línea de `objetivo alcanzado`
       ni de `Asentamiento invalidado` (la apertura del ciclo invalida con `nullptr` y no imprime), solo la línea
       `Sin asentamiento de la celda: la orden se cierra como sensor_no_disponible sin mover el servo.` que emite
       `api_service.cpp:128-129` al rechazar la orden (el servicio de guardia no imprime nada sobre la ausencia). En la
       app/servidor: cierre `sensor_no_disponible` con `order_id`, sin
       `gramos_medidos`; el stock no baja; la consulta siguiente aparece a
       los 20 s (±1 s). Evidencia: fecha, orden, línea de log del cierre y stock antes/después.
    3. **(b) Presión sobre la bandeja**: con asentamiento ganado, iniciar una orden y presionar la bandeja a mitad de
       ciclo. En el monitor serie: cierre por `plausibilidad_tope` (nunca `objetivo alcanzado`) y ausencia de
       retroceso del servo. En la app/servidor: `sensor_no_disponible` y sin descuento. Evidencia: fecha,
       `incremento_max` y `tope` de la línea de log, y si hubo o no descuento.
    4. **(c) Bandeja cargada y retirada**: cargar la bandeja **por encima de 10 g** (limitación aceptada de la spec:
       con ≤10 g no hay margen para el suelo), ganar el asentamiento, iniciar la orden y retirar la carga a mitad de
       ciclo. En el monitor serie: `plausibilidad_suelo`, parada sin retroceso. En la app/servidor:
       `sensor_no_disponible` y sin descuento. Evidencia: peso inicial de la bandeja, línea de log y stock.
    5. **(d) Arranque normal**: con la celda vacía y estable, encender y anotar cuándo se gana el asentamiento; el log
       debe confirmar 15 lecturas con paso ≤1 g (la racha no se gana antes, ni con 14). Pedir 50 g y comprobar
       «objetivo alcanzado» con `gramos_medidos` en el JSON y descuento del stock por lo medido; verificar que la celda
       real sostiene 5 Hz (una muestra cada 200 ms) sin inválidas encadenadas. Evidencia: fecha, línea de
       asentamiento, medidos frente a solicitados y stock antes/después.
    6. **No regresión física de la 013**: repetir exactitud (peso dispensado frente a solicitado con la tolerancia de
       la 013), muestreo a 5 Hz, fallo de sensor (desconectar la celda a mitad de ciclo → `sensor_no_disponible` sin
       retroceso) y atasco resuelto (bloquear el flujo y confirmar retroceso más reintento hasta «objetivo
       alcanzado» o el cierre propio de la 013). Anotar fecha y resultado de cada caso.
    7. Cierre: marcar T9 como hecha solo si los seis puntos anteriores tienen evidencia anotada; si algo falla,
       dejarla abierta con la línea de log y abrir la corrección como tarea nueva.

## Nota de alcance

No hay tareas de backend ni de app móvil: la 014 ya cierra `sensor_no_disponible` como fallo sin descuento y su
contrato de reporte no cambia. La 016 solo modifica el firmware y añade las tres modificaciones explícitas a la 013 y
la consecuencia defensiva (d) declaradas en la spec.

Se mantienen nueve tareas porque los criterios de finalización nuevos encajan en las existentes y no hace falta una T10:
el caso (d) se prueba en la lógica pura y en la compuerta (T1 y T3) y se revisa en T8; el `static_assert` de
`kMedianBufferSize >= 11` se crea y se asevera en T1 y se revisa en T8; los perfiles nuevos de línea base, plausibilidad
y asentamiento viven en T4, T5 y T6 y se cierran de forma exhaustiva en T8.
