# Plan 013 — Dispensado por peso con celda de carga HX711

Spec de referencia: `specs/013-dispensado-por-peso-hx711/spec.md` (aprobada),
incluida la ampliación de detección y resolución de atascos (RF-14 a RF-17).
Alcance exclusivo: firmware `DispensadorESP32`. No se modifica ni el backend
(`api/`) ni la aplicación móvil (`app/app_movil_pdam`).
Este plan cubre T1–T15: T1–T14 implementadas y revisadas; T10 (checklist físico
previo) y T15 (checklist físico de atasco) pendientes.

## 1. Archivos y responsabilidades

### 1.1 `DispensadorESP32/src/config/dispensing_utils.h` (modificar, sin Arduino)
Lógica pura, única fuente de límites y tiempos; `config.h` la reexpone.
- Nuevas constantes documentadas en español y en este único lugar (RNF-7): gracia 2 000 ms (`kStallGraceMs`), ventana 5 000 ms (`kStallWindowMs`), progreso mínimo 2,0 g (`kMinProgressGrams`), mediana móvil 5 (`kMovingMedianSize`), mínimo 5 válidas desde el arranque de avance (`kMinAdvanceValidReadings`), retroceso 1 200 ms (`kReverseMs`), pausa 300 ms (`kPauseMs`), máximo 3 reintentos (`kMaxStallRetries`), presupuesto mínimo de reintento 3 500 ms (`kMinRetryBudgetMs`), ángulo de retroceso 180° (`kReverseAngleDegrees`). `kMaxRotationMs` pasa a llamarse `kMotorBudgetMs` (avance + retroceso + pausa).
- `MovingMedianState` y `pushMovingMedian`: mediana móvil de las 5 válidas más recientes del ciclo de motor.
- `StallState`: mediana, válidas desde el último arranque, máximo observado, ventana (abierta, inicio, referencia), atasco pendiente y reintentos.
- `recordAdvanceSample` (solo avance), `startAdvance`, `resumeAdvanceAfterRetry`, `armStallWindow`, `stallWindowExpired`, `stallProgress`, `decideStallAction`, `motorBudgetRemainingMs`, `isMotorBudgetExhausted`, `budgetExhaustedReason`.
- `DispenseReason::STALL_UNRESOLVED`, `DispenseResult::retryCount`, `reintentos=N` en `formatDispenseLog` y helpers de tiempo en 32 bits.
- RF-8, RF-12, RF-14, RF-15, RF-16, RF-17 (parte pura), RNF-3, RNF-5, RNF-6, RNF-7.

### 1.2 `DispensadorESP32/src/config/dispensing_cycle.h` (nuevo, sin Arduino)
Unidad pura que orquesta el ciclo completo; existe para poder probar RF-17 «lógica pura y servicio con servo simulado» sin compilar Arduino (decisión 20).
- `enum class MotorPhase { ADVANCE, REVERSE, PAUSE }`.
- `CyclePorts`: contexto opaco más seis punteros a función (`startAdvance`, `startReverse`, `stop`, `readRaw`, `nowMs`, `waitUntil(deadlineMs)`); sin memoria dinámica ni métodos virtuales.
- `CycleDiagnostics`: muestras, respondidas, válidas, inválidas consecutivas, último raw y últimos gramos, para el diagnóstico de verificación del servicio.
- `runDispenseCycle(ports, amount, factor, sign, diagnostics)`: valida entradas sin tocar puertos, verifica 2 s, fija línea base, arranca, muestrea a 200 ms en las tres fases, aplica decisiones puras, ejecuta reintentos dentro del presupuesto y detiene el servo en toda salida. No imprime ni inicializa hardware.
- RF-5, RF-6, RF-7, RF-8, RF-9, RF-12, RF-14, RF-15, RF-16, RF-17, RNF-1, RNF-3.

### 1.3 `DispensadorESP32/src/services/dispensing_service.{h,cpp}` (modificar)
- `dispenseWeight` conserva firma y valida factor y cantidad antes de tocar hardware; inicializa la celda una sola vez, construye los `CyclePorts` sobre `startServo`, `reverseServo`, `stopServo`, `readHx711Raw`, `millis()` y una espera hasta vencimiento absoluto, y delega el ciclo.
- Conserva el diagnóstico de la verificación fallida y el `logDispenseResult` final; asigna `retryCount` desde el contador del ciclo (0 en salidas tempranas).
- RF-3, RF-4, RF-8, RF-11, RF-12, RF-14, RF-15, RF-16, RF-17, RNF-3.

### 1.4 `DispensadorESP32/src/drivers/servo_driver.{h,cpp}` (modificar)
- Añade `reverseServo()`: escribe el ángulo de retroceso (180°, `kReverseAngleDegrees`) y registra una línea en español por retroceso; marca el servo en movimiento para que `stopServo()` siga siendo idempotente.
- No cambia `initServo`, `startServo`, `stopServo` ni `setServoAngle`.
- RF-15.

### 1.5 `DispensadorESP32/src/config/config.h` (modificar)
- Reexporta las constantes mediante el `#include` de `dispensing_utils.h`, sin duplicar valores; añade un comentario en español que enumera los umbrales de atasco y recuerda que solo se ajustan allí. Mantiene pines, calibración, UUID BLE, `BASE_URL`, `CHECK_INTERVAL` y `DeviceState`.
- RF-11, RNF-4, RNF-7.

### 1.6 `DispensadorESP32/platformio.ini` (modificar)
- Añade `test_dispensing_cycle` a `test_ignore` del entorno `esp32dev` (la suite nativa no aplica al objetivo ESP32) y no añade ninguna dependencia: `bogde/HX711` sigue siendo la única. `[env:native]` no cambia.
- RNF-4, RNF-6.

### 1.7 Pruebas (`test/test_dispensing_utils` ampliado y `test/test_dispensing_cycle` nuevo)
- `test_dispensing_utils`: mediana móvil, máximo observado, apertura/reinicio/expiración de ventana, declaración, `decideStallAction` con reintentos y presupuesto inyectados, contabilidad del presupuesto, contador de reintentos, motivo nuevo y log con `reintentos=N`; se actualizan las cuatro aserciones de log existentes para exigir `reintentos=0`.
- `test_dispensing_cycle`: integración del ciclo con servo simulado (registra avance, retroceso y parada), celda por guion y reloj virtual en `waitUntil`.
- RF-12, RF-14, RF-15, RF-16, RF-17, RNF-6, RNF-7.

### 1.8 Sin cambios
`hx711_driver.{h,cpp}`, `api_service.cpp` y `dispenser_task.cpp` no se tocan: la orden inválida nunca llega al ciclo (RF-17) y el ciclo sigue bloqueante y acotado a 32 s (RF-13).

## 2. Funciones puras (el instante es parámetro)

| Función | Responsabilidad | RF |
|---|---|---|
| `classifyOrder`, `isCalibrationFactorValid`, `isRawSaturated`, `isReadingValid`, `convertRawToGrams`, `makeSample` | Orden de la API, factor, saturación, lectura válida y conversión calibrada | RF-1, RF-2, RF-3, RF-6, RF-10, RF-11 |
| `median`, `targetGrams` | Mediana impar/par y objetivo en gramos | RF-3, RF-6, RF-7 |
| `startVerification`, `recordVerificationSample`, `verificationBaseline` | Ventana fija de 2 s, válidas/inválidas y línea base | RF-3, RF-4 |
| `startRotation`, `recordRotationSample` | Objetivo sostenido, fallo de sensor y presupuesto agotado, en todas las fases | RF-6, RF-7, RF-8, RF-9 |
| `fillDispenseMeasurements` | Peso final e incremento con banderas | RF-12 |
| `resetMovingMedian`, `pushMovingMedian`, `movingMedianValue` | Mediana móvil de las 5 válidas más recientes; no existe con menos de 5 | RF-14 |
| `updateMaxObserved` | Eleva el máximo observado solo si la mediana lo supera; nunca lo baja | RF-14 |
| `startAdvance`, `resumeAdvanceAfterRetry` | Gracia de 2 s del avance actual, cierre de ventana y contador de reintentos (solo al reanudar) | RF-12, RF-14, RF-15 |
| `armStallWindow`, `stallWindowExpired`, `stallProgress` | Apertura y reinicio de la ventana fijando la referencia, expiración a 5 s y progreso | RF-14 |
| `recordAdvanceSample` | Evalúa una válida en avance y declara atasco; sin mediana no hay ventana ni declaración | RF-14, RF-17 |
| `decideStallAction` | Reintentar o parar con reintentos y presupuesto inyectados | RF-15, RF-16 |
| `motorBudgetRemainingMs`, `isMotorBudgetExhausted` | Contabilidad del presupuesto en 32 bits, tolerante al rollover | RF-8, RF-15, RNF-3 |
| `budgetExhaustedReason` | «atasco no resuelto» con atasco pendiente; «objetivo no alcanzado» sin él | RF-8, RF-16 |
| `dispenseReasonText`, `formatDispenseLog` | Texto del motivo nuevo y línea con `reintentos=N` siempre, 0 si no hubo | RF-12, RF-16, RNF-5 |
| `isCheckDue` | Consulta periódica sin adelantos | RF-13 |
| `runDispenseCycle` | Ciclo completo con servo y celda inyectables | RF-5 a RF-9, RF-12, RF-14 a RF-17, RNF-1, RNF-3 |

## 3. Algoritmo en pseudocódigo

```
runDispenseCycle(puertos, amount, factor, signo, diagnostico):
  resultado = {solicitado: amount, reintentos: 0, todo no disponible}
  si !isCalibrationFactorValid(factor): motivo = INVALID_CONFIG; return   // sin tocar puertos
  si !(amount > 0): motivo = INVALID_AMOUNT; return                       // rechaza NaN

  // 1. Verificacion fija de 2 s, no reiniciable (RF-3, RF-4)
  abrir ventana; muestrear cada 200 ms hasta 2000 ms
  si no se supera: puertos.stop(); motivo = SENSOR_UNAVAILABLE; return
  lineaBase = mediana de las validas

  // 2. Ciclo de motor con presupuesto absoluto (RF-5, RF-8, RNF-3)
  inicioPresupuesto = puertos.nowMs(); puertos.startAdvance()
  startRotation(&giro, inicioPresupuesto); startAdvance(&atasco, inicioPresupuesto)
  limite = inicioPresupuesto + 30000 ms; fase = ADVANCE; finFase = 0; siguiente = inicio

  mientras true:
    ahora = puertos.nowMs()
    si reachedMs(ahora, limite):                      // 2.a cota estricta
      puertos.stop(); motivo = budgetExhaustedReason(atasco.pendiente); break

    si fase == REVERSE y reachedMs(ahora, finFase):   // 2.b transiciones
      puertos.stop(); fase = PAUSE; finFase = ahora + 300 ms
    si no si fase == PAUSE y reachedMs(ahora, finFase):
      puertos.startAdvance(); resumeAdvanceAfterRetry(&atasco, ahora)  // cuenta aqui
      fase = ADVANCE; finFase = 0; siguiente = ahora

    si reachedMs(ahora, siguiente) y remainingMs(ahora, limite) > 100 ms:  // 2.c muestreo
      respondio = puertos.readRaw(&raw, 100 ms); ahoraLectura = puertos.nowMs()
      muestra = makeSample(respondio, raw, factor, signo)

      salida = recordRotationSample(&giro, muestra, ahoraLectura, lineaBase, amount)
      si salida == TARGET_REACHED:      // RF-7, prioridad sobre RF-14, en cualquier fase
        puertos.stop(); motivo = COMPLETED; break
      si salida == SENSOR_FAILURE:      // RF-9, RF-17: sin retroceso
        puertos.stop(); motivo = SENSOR_FAILURE; break
      si salida == TIME_LIMIT:
        puertos.stop(); motivo = budgetExhaustedReason(atasco.pendiente); break

      si fase == ADVANCE:               // 2.d deteccion solo en avance (RF-14)
        si recordAdvanceSample(&atasco, muestra, ahoraLectura) == STALL_DECLARED:
          accion = decideStallAction(atasco.reintentos,
                                     motorBudgetRemainingMs(inicioPresupuesto, ahoraLectura))
          si accion == GIVE_UP:         // sin reintentos o menos de 3500 ms (RF-16)
            puertos.stop(); motivo = STALL_UNRESOLVED; break
          puertos.startReverse()        // 2.e 180 grados durante 1200 ms
          fase = REVERSE; finFase = ahoraLectura + 1200 ms
      siguiente += 200 ms

    proximo = min(siguiente, limite)                 // 2.f nunca mas alla del presupuesto
    si fase != ADVANCE: proximo = min(proximo, finFase)
    waitUntil(proximo)

  puertos.stop()                                     // toda salida detiene el servo
  fillDispenseMeasurements(&resultado, true, lineaBase, &giro)
  resultado.reintentos = atasco.reintentos
  return resultado

// Deteccion (gracia 2000 ms, ventana 5000 ms, progreso minimo 2 g):
recordAdvanceSample: invalida -> CONTINUE; 5 validas -> mediana movil y maximo observado
  sin mediana -> CONTINUE; dentro de gracia -> CONTINUE; sin ventana -> abrir al vencer gracia
  progreso >= 2 g -> limpiar pendiente y reiniciar ventana; ventana vencida y >= 5 validas
  desde el arranque -> declarar atasco; ventana vencida con menos de 5 -> reiniciar sin declarar
```

`dispenseWeight` valida factor y cantidad, inicializa `initHx711()` una sola vez, construye los puertos, llama a `runDispenseCycle`, imprime el diagnóstico si el motivo es `SENSOR_UNAVAILABLE` y emite una sola línea con `reintentos=N`.

## 4. Interfaz pública

```cpp
// servo_driver.h
void startServo();      // 0°, avance
void reverseServo();    // 180°, retroceso de desatasco (RF-15)
void stopServo();       // 90°, idempotente
void setServoAngle(int angle);

// dispensing_service.h (sin cambio de firma)
dispensing::DispenseResult dispenseWeight(float amountGrams);

// dispensing_cycle.h (puro)
dispensing::DispenseResult runDispenseCycle(const dispensing::CyclePorts &ports,
                                            float amountGrams, float factor,
                                            float sign,
                                            dispensing::CycleDiagnostics *diagnostics,
                                            const CycleLimits &limits = CycleLimits{});
```
El sexto parámetro `limits` es un punto de inyección solo para pruebas: sus valores por defecto son las constantes aprobadas (`kMotorBudgetMs` y `kMaxStallRetries`) y el servicio no lo pasa, de modo que producción no puede separarse de ellas. `CyclePorts` = contexto opaco + `startAdvance`, `startReverse`, `stop`, `readRaw`, `nowMs`, `waitUntil(deadlineMs)`. `DispenseResult` añade `retryCount` (0 si no hubo) y el motivo `STALL_UNRESOLVED`. Log:

```
Despacho: solicitado=50.0 g, linea_base=12.3 g, peso_final=63.4 g, incremento=51.1 g, reintentos=1, motivo=objetivo alcanzado
```

## 5. Decisiones justificadas y alternativas descartadas

1. **`bogde/HX711` (elegido).** API mínima (`begin`, `is_ready`, `read`) que
   permite acotar el sondeo previo con `is_ready()` y el timeout de 100 ms. Su
   `read()` llama internamente a `wait_ready()` sin cota, por lo que ese tramo
   no queda acotado: deuda aceptada de prototipo. Se descartan `HX711_ADC` (más
   estado y filtros propios que compiten con la lógica pura) y el bit-bang
   manual (reinventa el protocolo y añade riesgo).
2. **Lógica pura separada en un header sin Arduino (elegido).** Permite cumplir
   RNF-6 y la constitución (pruebas unitarias obligatorias) con el entorno
   nativo ya existente. Se descarta probar solo en ESP32: requeriría hardware en
   cada cambio y no cubre los tiempos de forma determinista.
3. **Bloqueo controlado dentro del ciclo (elegido).** El firmware ya bloquea hoy
   10 s dentro de `dispensarAlimento()`; el ciclo completo está acotado a 32 s y
   la consulta periódica es serial. Se descarta una tarea FreeRTOS con mutex:
   añade concurrencia, estados compartidos y riesgo de regresión en WiFi/BLE sin
   que la spec lo pida.
4. **Mediana (elegido).** Es robusta frente a picos de vibración del servo y
   coincide con la definición de la spec. Se descarta la media: un outlier
   desplaza la línea base y adelanta o retrasa la parada.
5. **Línea base en gramos en lugar de `tare()` por ciclo (elegido).** El
   incremento cancela el offset del ADC y no se pierde el peso que ya esté sobre
   la bandeja; además `tare()` bloquea y exige estabilidad. Se descarta tarar
   cada ciclo porque reinicia la referencia y puede tardar más que la ventana.
6. **Objetivo = 3 lecturas consecutivas ≥ línea base + cantidad (elegido).**
   Evita parar por un pico aislado (RNF-2). Se descarta una sola lectura.
7. **Nunca dispensar a ciegas (elegido).** Si la verificación no se supera, el
   servo no arranca (RF-4). Se descarta dispensar por tiempo como respaldo: es
   exactamente el comportamiento que la spec 013 deroga.
8. **Aborto temprano con 3 inválidas consecutivas en la verificación
   (elegido).** La ventana sigue siendo fija y no se reinicia; solo se evita
   esperar los 2 s cuando ya es imposible cumplir el mínimo de 5 válidas. Se
   descarta esperar siempre los 2 s completos por ser tiempo muerto.
9. **Factor positivo + signo separado (elegido).** RF-11 exige factor positivo;
   el montaje real mide `482.7f` con signo `+1.0f` (patrón de ~206,8 g: RAW
   160658 en vacío y 260500 cargado), y se valida solo el factor. El valor
   inicial `7050.0f` con `-1.0f`, tomado del montaje típico de bogde, era
   erróneo para esta celda y queda como referencia histórica. Se descarta
   guardar el factor con signo negativo directamente porque sería rechazado por
   RF-11.
10. **Calibración en `config.h` y no en NVS/Serial (elegido).** Es lo aprobado y
    lo que pide la spec. Se descartan comandos Serial y NVS: añaden superficie y
    no están en alcance.
11. **Bucle con vencimientos absolutos (elegido).** `siguiente += 200 ms` y
    `limite = inicio + 30 s`, durmiendo hasta el próximo vencimiento, mantiene
    el periodo máximo y la cota de 30 s aunque una lectura tarde 100 ms. Se
    descarta `delay(200)` tras leer: el periodo real podría llegar a 300 ms y
    violar RNF-1/RNF-3.
12. **Cerrar HTTP antes del ciclo (elegido).** Libera el socket y evita mantener
    una conexión ociosa hasta 32 s. Se descarta dejarlo abierto como hoy.

13. **Ventana continua evaluada en cada lectura válida (elegido).** El progreso se mide contra la referencia vigente y se reinicia al llegar a 2 g, así un flujo constante de 0,5 g/s nunca declara atasco. Se descarta comparar bloques fijos de 5 s: un flujo de 1,9 g por bloque declararía atascos falsos y gastaría reintentos.
14. **Mediana móvil de 5 válidas en lugar de lecturas individuales (elegido).** Un pico de ruido desplazaría el progreso más de 2 g y reiniciaría la ventana, ocultando un atasco real. Se descartan la lectura individual y la media, que un outlier contamina.
15. **Máximo observado = máximo de la mediana móvil (elegido).** Un pico no eleva la referencia; si subiera, dejaría un déficit artificial de 2 g y un falso atasco permanente. Se descarta el máximo de lecturas válidas.
16. **Presupuesto de 30 s como límite efectivo y 3 reintentos como red de seguridad (elegido).** La primera declaración posible es a los 7 s y cada reintento añade 1,5 s más 2 s de gracia, así que el cuarto atasco no cabe en el presupuesto. Se descarta subir reintentos (rompe RNF-3) y acortar ventanas (más falsos atascos).
17. **Umbral de 3 500 ms para iniciar un reintento (elegido).** Es retroceso + pausa + gracia: por debajo no queda margen para observar si se resolvió. Se descarta 1 500 ms, que reanudaría sin gracia y contaría un reintento inútil.
18. **Sin sensor de corriente ni rediseño mecánico (elegido).** El MG996R no tiene realimentación y la celda ya da la señal indirecta. Se descarta el sensor de corriente (hardware y calibración nuevos) y el rediseño del tornillo (fuera de alcance).
19. **Retroceso sin efecto sobre la línea base ni el objetivo (elegido).** El giro inverso no retira alimento de la bandeja, así que un atasco resuelto puede alcanzar el objetivo. Se descarta retomar la línea base tras cada reintento: ocultaría lo ya entregado y podría parar antes de tiempo.
20. **Puertos inyectables para probar RF-17 en nativo (elegido).** El ciclo se mueve tal cual a `dispensing_cycle.h` con punteros a función y el servicio queda como adaptador Arduino, conservando firma y criterios de T1–T9. Se descartan cabeceras falsas de Arduino/`ESP32Servo`/`HX711`, `#ifdef UNIT_TEST` en producción y un `ServoPort`/`SensorPort` virtual (tabla virtual para seis operaciones que los punteros cubren sin memoria).
21. **Reintento contado al reanudar el avance (elegido).** Evita gastar reintentos en retrocesos interrumpidos por fallo de sensor o presupuesto. Se descarta contar al iniciar el retroceso.
22. **Presupuesto agotado resuelto en un único punto (elegido).** El bucle y el `TIME_LIMIT` puro consultan `budgetExhaustedReason`, de modo que el motivo no diverge. Se descarta decidirlo en el servicio: duplicaría la regla de RF-8/RF-16.
23. **Detección solo en avance (elegido).** En retroceso y pausa el tornillo no empuja y el alimento que cae inflaría el progreso. Se descarta evaluar en todas las fases.
24. **Sin dependencias nuevas (elegido).** RNF-4 lo exige. Se descarta cualquier librería de filtros o estadística: la mediana móvil son unas decenas de líneas.

## 6. Riesgos y mitigaciones

- **Factor de calibración desconocido:** el valor actual (`482.7`, signo `+1`) se midió con un patrón de ~206,8 g y no sirve para otro montaje. Mitigación: recalibrar con peso patrón antes de la prueba física; sin ajuste el peso medido será incorrecto aunque el ciclo funcione.
- **Polaridad y offset:** con el cableado típico el raw baja al cargar, de ahí `hx711RawSign`. Si el offset de reposo convierte fuera de 0–5 000 g, todas las lecturas serán inválidas. Mitigación: verificar la conversión con peso patrón y ajustar signo y factor.
- **Resolución de una celda de 5 kg para 50 g:** el HX711 de 24 bits suele bastar, pero el ruido y la vibración pueden retrasar las 3 lecturas consecutivas. Mitigación: mediana, 3 consecutivas y sobrepeso máximo del 10 % admitido en la prueba física.
- **Timeout de 100 ms frente a 10 SPS:** a 5 Hz el dato suele estar listo, pero un módulo que entrega justo después del intento cuenta una inválida aislada. Mitigación: una inválida no detiene el ciclo; 3 consecutivas sí. Si los timeouts son sistemáticos se ajusta el modo de 80 SPS o el instante de muestreo.
- **Vibración del servo:** produce lecturas inestables. Mitigación: mediana en la línea base y en el progreso, confirmación en 3 lecturas y presupuesto de 30 s vigente.
- **Falso atasco con flujo lento o cantidades pequeñas:** con menos de 0,4 g/s el umbral de 2 g en 5 s puede declararse antes de alcanzar el objetivo, sobre todo con raciones de pocos gramos. Mitigación: el reintento no impide alcanzar el objetivo, el log muestra `reintentos` mayor que 0 y los umbrales son configurables en un único lugar (RNF-7); la prueba física de dispensación normal exige `reintentos=0`, y si no se cumple se ajusta el umbral, no la lógica.
- **Pico de ruido que mueve la referencia:** mitigado por diseño con la mediana móvil de 5 y con el máximo observado tomado de la mediana (decisiones 14 y 15); un pico aislado, o incluso dos, no elevan la referencia ni reinician la ventana.
- **Atasco en el primer segundo de avance:** la gracia de 2 s impide declararlo antes; la primera declaración posible es a los 7 s. Mitigación adicional: el presupuesto sigue vigente, así que un bloqueo total termina como mucho a los 30 s.
- **Atasco repetido:** el presupuesto de 30 s se agota antes del cuarto atasco y el tope de 3 reintentos es red de seguridad. Mitigación: `GIVE_UP` por presupuesto o por contador produce «atasco no resuelto» con el incremento logrado, sin forzar más el motor.
- **Tamaño de croqueta próximo al paso de la hélice:** con croqueta de ~3 cm el tornillo sin fin se atasca con frecuencia porque la croqueta se cuña entre la hélice y el tubo. El retroceso, la pausa y la reanudación lo intentan resolver: el ciclo alcanza el objetivo cuando el retroceso libera la croqueta y, si no la libera, termina en «atasco no resuelto» (RF-16), sin que eso permita incumplir RF-14. Es una limitación mecánica que no se corrige con umbrales, y por eso no se ajustan.
- **Fallo de sensor durante retroceso o pausa:** las 3 inválidas consecutivas completadas detienen el servo, no se ejecuta otro retroceso y no se reanuda el avance; el reintento no se cuenta. Si el fallo empieza en la pausa y no completa las 3 antes de reanudar, el avance se reanuda y el fallo se detecta en el avance. Mitigación: `recordRotationSample` se evalúa en las tres fases.
- **Presupuesto agotado a mitad de una ventana de estancamiento:** sin atasco declarado el motivo es «objetivo no alcanzado»; con atasco pendiente, «atasco no resuelto». Mitigación: `budgetExhaustedReason` decide en un único punto (decisión 22) y la prueba nativa cubre ambos casos.
- **Declaración de atasco con hasta 200 ms de retraso:** la expiración se evalúa en la siguiente lectura válida, no por temporizador. Aceptado: el retraso es menor que un periodo de muestreo y no altera la prioridad del objetivo.
- **Aflojamiento del acoplamiento por el par inverso:** el giro a 180° somete el tornillo prisionero a un par contrario al habitual. Mitigación: retroceso limitado a 1,2 s y a 3 por dispensación, revisión del acoplamiento tras los ensayos y correlación de holguras con `reintentos`.
- **Desgaste del servo por los ciclos de retroceso:** cada reintento añade arranques y cambios de sentido. Mitigación: el presupuesto acota el tiempo total de motor con independencia de los reintentos; en las pruebas se vigilan temperatura, ruido y pérdida de par, y el umbral de 2 g se ajusta antes que el límite de reintentos.
- **Bloqueo de hasta 32 s:** WiFi puede degradarse o el servidor cerrar la conexión durante el ciclo. Mitigación: HTTP cerrado antes del ciclo, sin consultas solapadas y temporizador reiniciado al final (RF-13).
- **Saturación o `línea base + cantidad > 5 000 g`:** el objetivo no se alcanza dentro del rango válido. Mitigación: el ciclo termina por presupuesto o por fallo de sensor y queda registrado el incremento parcial.
- **Alimento en caída tras detener el servo:** el peso final puede superar el objetivo. Aceptado por la spec; la prueba física admite hasta 10 % de sobrepeso y el log permite detectarlo.

## 7. Estrategia de tests

### 7.1 Nativos (`pio test -e native`)
Se escriben antes de implementar. `test_dispensing_utils` (lógica de decisión) y `test_dispensing_cycle` (integración con servo simulado y reloj virtual).

- Base ya en verde (T3–T5): `classifyOrder` con prioridad de `reset_wifi`, factor válido/no válido, conversión raw→gramos, lectura válida e inválida en los extremos, mediana impar/par, ventana de 2 s no reiniciable con ≥ 5 válidas, objetivo con 3 consecutivas, una inválida aislada sin detener, 3 consecutivas → fallo, presupuesto agotado y `isCheckDue`.
- Mediana móvil: inexistente con 4 válidas; con 5 vale la mediana; la sexta desplaza la más antigua; una inválida no entra.
- Máximo observado: no sube con un pico aislado de +8 g; sube cuando sube la mediana; nunca baja.
- Ventana: no se abre antes de los 2 s de gracia; se abre al vencer la gracia o con la primera mediana posterior; se reinicia en el instante en que el progreso llega a 2 g; con 1,9 g no y con 4,9 g sí; expira a los 5 s.
- Declaración: sí con < 2 g y ≥ 5 válidas desde el arranque; no con 4 válidas (reinicia); nunca con lecturas inválidas alternas.
- `decideStallAction`: 0 y 2 reintentos con 3 500 ms → reintentar; 3 reintentos → parar; 3 499 ms → parar; 3 500 ms exactos → reintentar.
- Presupuesto: restante a 0, 1 000 y 30 000 ms; agotado en 30 000 y no en 29 999; rollover de 32 bits. `budgetExhaustedReason` con y sin atasco pendiente.
- Contador: `startAdvance` no incrementa; `resumeAdvanceAfterRetry` sí y devuelve el acumulado.
- Log: `reintentos=0`, `1` y `3`; texto «atasco no resuelto»; las cuatro aserciones existentes se actualizan.
- Ciclo puro: perfil de flujo por encima de 0,4 g/s sin atasco con «objetivo alcanzado» y `reintentos=0`; perfil de estancamiento con retroceso, pausa y reanudación; atasco resuelto con `reintentos=1`; objetivo con prioridad en la misma muestra y durante retroceso o pausa; `SENSOR_FAILURE` sin retroceso ni reanudación; lecturas alternas sin retroceso; orden inválida (0, negativo, NaN) sin avance ni retroceso; cota de 30 000 ms en todos los perfiles; última acción siempre `stop`.
- Límites inyectados del ciclo (`CycleLimits`): los valores por defecto son exactamente `kMotorBudgetMs` y `kMaxStallRetries`, de modo que el valor de producción no puede separarse de las constantes aprobadas (RNF-7); `maxRetries = 0` da «atasco no resuelto» sin retroceso y, con un presupuesto de 10 000 ms que deja menos de 3 500 ms al declararse el atasco, el ciclo también se rinde sin retroceso; un presupuesto de 10 000 ms con un perfil sin atasco y objetivo inalcanzable termina en «objetivo no alcanzado» con el motor detenido exactamente en 10 000 ms más los 2 s de verificación, lo que fija el agotamiento del bucle al presupuesto inyectado y no a la constante.
- Frontera del presupuesto mínimo de reintento: los 3 499 ms, los 3 500 ms exactos y el contador en 3 se verifican en `decideStallAction` (lógica pura). En el ciclo esa frontera no es alcanzable con el punto de inyección —el contador en 3 solo se alcanza tras 30 s de motor— y se cubre en la función pura, como pide RF-16 («no se verifica de extremo a extremo»).

### 7.2 Físicos y checklist manual
- Atasco inducido con la hélice bloqueada o croqueta cuñada: retroceso de 1,2 s, pausa de 0,3 s y reanudación; si persiste, «atasco no resuelto» con incremento y `reintentos` en el log.
- Atasco resuelto liberando el bloqueo durante un reintento: «objetivo alcanzado» con `reintentos` mayor que 0.
- Dispensación normal sin bloqueo: «objetivo alcanzado» y `reintentos=0`.
- No disminución del peso: peso de la bandeja antes y después del retroceso.
- Cota: cronómetro ≤ 30 s de motor y ≤ 32 s de ciclo completo.
- 5 Hz efectivos durante verificación, avance, retroceso y pausa.
- Fallo de sensor: módulo HX711 desconectado del ESP32 al arranque (no se mueve el servo) y a mitad del giro (parada en ≤ 1 s, sin retroceso).
- Exactitud con peso patrón: 50 g solicitados → incremento entre 50 g y 55 g.
- No regresión: BLE, WiFi, reconexión, validación de servidor, reset de credenciales y consulta 20 s después del fin; log en español, sin emojis ni credenciales.

### 7.3 Mapa RF → verificación

| RF | Verificación principal |
|---|---|
| RF-1, RF-2, RF-10 | Nativa: `classifyOrder`; ciclo puro sin avance ni retroceso con orden inválida |
| RF-3, RF-4 | Nativa: ventana de 2 s, ≥ 5 válidas, mediana y aborto sin mover el servo |
| RF-5, RF-6 | Nativa: arranque tras verificación, incremento y muestreo en las tres fases; física: 5 Hz |
| RF-7 | Nativa: 3 consecutivas ≥ objetivo en cualquier fase y prioridad sobre RF-14 |
| RF-8 | Nativa: presupuesto agotado con motivo según atasco pendiente |
| RF-9 | Nativa: 3 inválidas → fallo sin retroceso; física: parada ≤ 1 s |
| RF-11 | Nativa: conversión y factor; física: peso patrón |
| RF-12 | Nativa: log con `reintentos=0/1/3`; física: log real |
| RF-13 | Nativa: `isCheckDue`; manual: no regresión WiFi/BLE |
| RF-14 | Nativa: mediana móvil, máximo observado, gracia, ventana y declaración |
| RF-15 | Nativa: secuencia retroceso-pausa-reanudación con contadores inyectados; física: atasco resuelto |
| RF-16 | Nativa: `GIVE_UP` por contador y por 3 500 ms; física: atasco no resuelto |
| RF-17 | Nativa: ciclo puro con servo simulado, cero retrocesos ante fallo, orden inválida y falta de lecturas |
| RNF-1 | Revisión del bucle con vencimientos absolutos; física: 5 Hz en las tres fases |
| RNF-2 | Nativa: 3 consecutivas |
| RNF-3 | Nativa: cota de 30 s con reintentos; física: cronómetro |
| RNF-4 | Revisión de `platformio.ini` y checklist de no regresión |
| RNF-5 | Inspección del log |
| RNF-6 | `pio test -e native` en verde con las dos suites |
| RNF-7 | Revisión: diez constantes de umbral en `dispensing_utils.h`, sin duplicados |

## 8. Punto de inyección para RF-17

RF-17 exige «prueba de integración sobre lógica pura y servicio, con un servo simulado» y no duplica RF-2 ni RF-9: verifica la ausencia de la acción de retroceso. Hoy `dispensing_service.cpp` incluye `<Arduino.h>` y depende de `ESP32Servo`, `HX711` y `millis()`, así que no compila en `[env:native]`.

- **Mecanismo:** el ciclo completo se traslada, sin cambios de algoritmo, a `dispensing_cycle.h` (puro). El servicio construye `CyclePorts` con `startServo`, `reverseServo`, `stopServo`, `readHx711Raw`, `millis()` y una espera hasta vencimiento absoluto.
- **En nativo:** el test arma un contexto con reloj virtual, guion de lecturas y contadores de avance, retroceso y parada; `waitUntil` adelanta el reloj. Así se comprueba en milisegundos de CPU que `startReverse` no se invoca con `SENSOR_FAILURE`, con orden inválida ni con lecturas inválidas alternas, y sí en el perfil de estancamiento.
- **Alcance del refactor:** se mueven el bucle, los helpers de tiempo en 32 bits y el diagnóstico de verificación (`CycleDiagnostics`). `dispenseWeight` conserva firma, validación previa, inicialización única de la celda, diagnóstico y línea de log.
- **Qué queda intacto de T1–T9:** T1, T2, T4, T6, T8 y T9 sin cambios de criterio; T3 solo actualiza las cuatro aserciones de log por `reintentos=N`; T5 mantiene `RotationState` y `recordRotationSample` (solo se renombra `kMaxRotationMs` y se añaden `retryCount` y `STALL_UNRESOLVED`, que no rompen los tests); T7 conserva todos sus criterios de aceptación y delega el bucle.

## 9. Orden de implementación

1. T11: constantes de atasco y lógica pura (mediana móvil, máximo observado, ventana, decisión, presupuesto, motivo, log) con tests en rojo y verde.
2. T12: `reverseServo()` y extracción del ciclo a `dispensing_cycle.h` con puertos, más las pruebas de RF-17 en `test_dispensing_cycle`.
3. T13: integración del servicio con presupuesto absoluto, retroceso, pausa, reanudación, `retryCount` y log con `reintentos=N`.
4. T14: validación nativa completa (perfiles de flujo, contadores y presupuesto inyectados, cota de 30 s) y `pio run` sin regresiones.
5. T15: checklist físico de atasco inducido, atasco resuelto y dispensación normal, revisión del acoplamiento y actualización de `MEMORY.md`.
6. Cierre de T10 sobre el firmware final con desatasco.
