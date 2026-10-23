# Plan 013 — Dispensado por peso con celda de carga HX711

Spec de referencia: `specs/013-dispensado-por-peso-hx711/spec.md` (aprobada).
Alcance exclusivo: firmware `DispensadorESP32`. No se modifica ni el backend
(`api/`) ni la aplicación móvil (`app/app_movil_pdam`).

## 1. Archivos y responsabilidades

### 1.1 `DispensadorESP32/src/config/dispensing_utils.h` (nuevo, sin Arduino)

Lógica pura y testable en `pio test -e native`. No incluye `<Arduino.h>` ni
`<WiFi.h>`, por lo que puede compilarse en el entorno nativo. Es la única fuente
de los límites y tiempos; `config.h` los reexpone para el firmware.

- Constantes: ventana de verificación 2 000 ms, periodo de muestreo 200 ms,
  timeout de lectura 100 ms, giro máximo 30 000 ms, mínimo 5 válidas, máximo 3
  inválidas consecutivas, objetivo confirmado con 3 lecturas consecutivas, rango
  válido 0–5 000 g, saturación raw −8 388 608 / 8 388 607, buffer de 16 muestras
  válidas para la mediana.
- `WeightSample` (respondió, raw, gramos) y clasificación de lectura válida.
- Conversión raw → gramos con factor y signo.
- Mediana de muestras válidas (par e impar).
- Clasificación pura de la orden de la API (reposo, dispensar, reset WiFi,
  inválida) y validación del factor de calibración.
- Máquinas de estado puras de verificación y de giro, con el instante `nowMs`
  como parámetro.
- `DispenseResult`, motivos de finalización y formateador del registro serie.
- `isCheckDue(lastCheckMs, nowMs, intervalMs)` para el temporizador periódico.
- Cubre RF-1, RF-2, RF-3, RF-4, RF-6, RF-7, RF-8, RF-9, RF-10, RF-11, RF-12,
  RF-13 (parte automatizable) y RNF-1, RNF-2, RNF-3, RNF-6.

### 1.2 `DispensadorESP32/src/config/config.h` (modificar)

- Pines HX711: `hx711SckPin = 18` (D18) y `hx711DtPin = 19` (D19). El servo se
  mantiene en `servoPin = 4`.
- Calibración: `hx711CalibrationFactor` como magnitud positiva (placeholder
  `7050.0f`, cuentas ADC por gramo) y `hx711RawSign = -1.0f` para reproducir el
  habitual `-7050` de la librería sin violar RF-11. Ambos documentados como
  editables antes de compilar.
- Reexporta las constantes de `dispensing_utils.h` para que el firmware las use
  con nombres locales, sin duplicar valores.
- Mantiene intactos UUID BLE, `BASE_URL`, `CHECK_INTERVAL` y `DeviceState`.
- Cubre RF-11 y RNF-4.

### 1.3 `DispensadorESP32/src/drivers/hx711_driver.{h,cpp}` (nuevo)

- `initHx711()`: `begin(dt, sck)`, log en español con los pines.
- `bool readHx711Raw(long *rawOut, unsigned long timeoutMs)`: espera con
  `is_ready()` hasta el plazo; si vence devuelve `false`; si hay dato, hace una
  única lectura `read()` y devuelve `true`. El sondeo previo está acotado por
  `timeoutMs`; `read()` tiene internamente `wait_ready()` sin cota (deuda
  aceptada de prototipo).
- No convierte a gramos ni decide: eso es lógica pura del servicio/utilidades.
- Sin `tare()` automático y sin calibración por Serial.
- Cubre RF-6 y RF-11 (transporte de la lectura; la conversión y validación son
  puras).

### 1.4 `DispensadorESP32/src/services/dispensing_service.{h,cpp}` (nuevo)

- `DispenseResult dispenseWeight(float amountGrams)`: orquesta verificación,
  línea base, arranque del servo, muestreo durante el giro, parada y registro.
- Valida factor y cantidad antes de tocar hardware.
- Garantiza que toda salida (objetivo, tiempo, fallo de sensor, sensor no
  disponible) deja el servo detenido.
- Rellena el `DispenseResult` con línea base, peso final, incremento y motivo, y
  emite una sola línea de log en español.
- Cubre RF-3, RF-4, RF-5, RF-6, RF-7, RF-8, RF-9, RF-11 y RF-12.

### 1.5 `DispensadorESP32/src/drivers/servo_driver.{h,cpp}` (modificar)

- Sustituye `dispensarAlimento()` (bloqueo fijo de 10 s) por `startServo()` y
  `stopServo()`. `initServo()` deja el servo detenido en 90°.
- `startServo()` escribe 0°; `stopServo()` escribe 90° y es idempotente.
- Se conserva `setServoAngle()` para usos puntuales.
- Único llamador actual de `dispensarAlimento()`: `api_service.cpp`; tras el
  cambio no queda ninguna referencia.
- Cubre RF-5, RF-7, RF-8 y RF-9.

### 1.6 `DispensadorESP32/src/services/api_service.cpp` (modificar)

- Parsea `serve`, `reset_wifi` y `amount` como número (no como cadena).
- Cierra el `HTTPClient` (`http.end()`) inmediatamente después de leer el
  payload y antes de cualquier ciclo de dispensación o reinicio.
- Prioridad: `reset_wifi:true` primero, aunque `serve` sea `true` o el payload
  traiga `serve:false, amount:0` (payload real del backend).
- Llama a `dispenseWeight(amount)` solo si la clasificación pura devuelve
  `DISPENSE`; registra advertencia si es `INVALID_ORDER`.
- Cubre RF-1, RF-2, RF-10, RF-11 y RF-12.

### 1.7 `DispensadorESP32/src/tasks/dispenser_task.cpp` (modificar)

- En `STATE_NORMAL`, asigna `lastCheckTime = millis()` **después** de
  `checkDispenserAction(serverUrl)`.
- En la transición desde `STATE_CONNECT_WIFI`, hace lo mismo tras la primera
  consulta, para que el ciclo no encadene una consulta inmediata.
- Mantiene el intervalo de 20 s ya existente.
- Cubre RF-13 y RNF-4.

### 1.8 `DispensadorESP32/platformio.ini` (modificar)

- Añade `bogde/HX711 @ ^0.7.5` a `lib_deps` (única dependencia nueva).
- Añade `test_dispensing_utils` a `test_ignore` del entorno `esp32dev`.
- `[env:native]` no cambia: Unity, `-I$PROJECT_DIR/src`, sin fuentes de Arduino.
- Cubre RNF-4 y RNF-6.

### 1.9 `DispensadorESP32/test/test_dispensing_utils/test_dispensing_utils.cpp` (nuevo)

- Pruebas Unity de toda la lógica pura. Se escriben antes de la implementación
  (en rojo) y se ejecutan con `pio test -e native`.
- Cubre RNF-6 y los criterios automatizables de RF-1, RF-2, RF-3, RF-4, RF-6,
  RF-7, RF-8, RF-9, RF-10, RF-11, RF-12 y RF-13.

## 2. Funciones puras (el instante es parámetro)

Todas viven en `dispensing_utils.h` y no leen `millis()` ni estado global.

| Función | Responsabilidad | RF |
|---|---|---|
| `OrderAction classifyOrder(bool resetWifi, bool serve, bool amountPresent, bool amountNumeric, float amount)` | Decide reposo, dispensar, reset o advertencia | RF-1, RF-2, RF-10 |
| `bool isCalibrationFactorValid(float factor)` | Finito y > 0 | RF-11 |
| `bool isRawSaturated(long raw)` | Raw en los extremos de 24 bits | RF-3, RF-6 |
| `bool isReadingValid(const WeightSample &s)` | Respondió, valor finito, 0–5 000 g, sin saturación | RF-3, RF-6 |
| `float convertRawToGrams(long raw, float factor, float sign)` | Conversión calibrada | RF-11 |
| `WeightSample makeSample(bool responded, long raw, float factor, float sign)` | Construye la muestra validada | RF-6, RF-11 |
| `bool median(const float *values, unsigned count, float *out)` | Mediana impar/par | RF-3 |
| `float targetGrams(float baseline, float amount)` | `baseline + amount` | RF-6, RF-7 |
| `void startVerification(VerificationState *s, unsigned long nowMs)` | Abre la ventana fija | RF-3 |
| `VerificationOutcome recordVerificationSample(VerificationState *s, const WeightSample &sample, unsigned long nowMs)` | Acumula válidas/inválidas y cierra la ventana | RF-3, RF-4 |
| `bool verificationBaseline(const VerificationState *s, float *out)` | Mediana de válidas de la ventana | RF-3 |
| `void startRotation(RotationState *s, unsigned long nowMs)` | Fija el inicio del giro | RF-5, RF-8 |
| `RotationOutcome recordRotationSample(RotationState *s, const WeightSample &sample, unsigned long nowMs, float baseline, float amount)` | Objetivo sostenido, fallo de sensor y tiempo límite | RF-6, RF-7, RF-8, RF-9 |
| `void formatDispenseLog(const DispenseResult &r, char *buffer, size_t size)` | Línea de registro con «no disponible» | RF-12 |
| `bool isCheckDue(unsigned long lastCheckMs, unsigned long nowMs, unsigned long intervalMs)` | Consulta periódica sin adelantos | RF-13 |

## 3. Algoritmo en pseudocódigo

### 3.1 Clasificación de la respuesta

```
classifyOrder(resetWifi, serve, amountPresent, amountNumeric, amount):
  si resetWifi: return RESET_WIFI            // prioridad absoluta (RF-10)
  si !serve: return REST
  si !amountPresent o !amountNumeric: return INVALID_ORDER
  si amount < 0: return INVALID_ORDER
  si amount == 0: return REST
  return DISPENSE
```

### 3.2 `dispenseWeight(amount)`

```
resultado = {solicitado: amount, todo no disponible}

si !isCalibrationFactorValid(factor):
  resultado.motivo = INVALID_CONFIG
  log "Error de configuracion: factor de calibracion no positivo"
  return resultado                            // no se mueve el servo (RF-11)

si amount <= 0:
  resultado.motivo = INVALID_AMOUNT
  return resultado

// --- Ventana fija de verificacion: 2 s exactos, no reiniciable (RF-3, RF-4)
estadoV = startVerification(millis())
siguiente = estadoV.inicio
while true:
  ahora = millis()
  si ahora >= siguiente:
    raw = 0
    respondio = readHx711Raw(&raw, 100 ms)    // maximo 100 ms (RNF-1)
    ahoraLectura = millis()                   // instante real de la muestra
    muestra = makeSample(respondio, raw, factor, signo)
    salida = recordVerificationSample(&estadoV, muestra, ahoraLectura)
    si salida != IN_PROGRESS: break
    siguiente = siguiente + 200 ms            // 5 Hz efectivos (RNF-1)
  dormir hasta min(siguiente, ahora + 5 ms)

si salida != PASSED:
  resultado.motivo = SENSOR_UNAVAILABLE
  log con linea_base/peso/incremento "no disponible"   // RF-4, RF-12
  return resultado
lineaBase = median(validas de estadoV)        // RF-3
resultado.lineaBase = lineaBase

// --- Giro con objetivo sostenido y topes (RF-5 a RF-9)
startServo()
estadoR = startRotation(millis())
limite = estadoR.inicio + 30000 ms
siguiente = estadoR.inicio
while true:
  ahora = millis()
  si ahora >= limite:                          // nunca mas de 30 s (RNF-3)
    stopServo(); resultado.motivo = TIME_LIMIT; break
  si ahora >= siguiente:
    raw = 0
    respondio = readHx711Raw(&raw, 100 ms)
    ahoraLectura = millis()                   // instante real de la muestra
    muestra = makeSample(respondio, raw, factor, signo)
    salida = recordRotationSample(&estadoR, muestra, ahoraLectura, lineaBase, amount)
    si salida == TARGET_REACHED:
      stopServo(); resultado.motivo = COMPLETED; break       // 3 consecutivas (RF-7)
    si salida == SENSOR_FAILURE:
      stopServo(); resultado.motivo = SENSOR_FAILURE; break  // 3 invalidas (RF-9)
    si salida == TIME_LIMIT:
      stopServo(); resultado.motivo = TIME_LIMIT; break
    siguiente = siguiente + 200 ms
  dormir hasta min(siguiente, limite, ahora + 5 ms)

stopServo()                                    // idempotente en toda salida
si estadoR.hayUltimaValida:
  resultado.pesoFinal = estadoR.ultimaValida
  resultado.incremento = pesoFinal - lineaBase
si no:
  peso/incremento = no disponible              // RF-12
log formatDispenseLog(resultado)
return resultado
```

### 3.3 Verificación pura

```
recordVerificationSample(s, muestra, ahora):
  // La ventana se cierra por tiempo antes de admitir una muestra posterior:
  // la muestra tomada en o despues de 2000 ms no se registra.
  si ahora - s.inicio >= 2000:
    return (s.validas >= 5) ? PASSED : WINDOW_EXPIRED
  si isReadingValid(muestra):
    si s.validas < MAX_BUFFER: s.valores[s.validas] = muestra.gramos
    s.validas++; s.invalidasConsecutivas = 0
  si no:
    s.invalidasConsecutivas++
  si s.invalidasConsecutivas >= 3:
    return ABORTED_BY_INVALID                 // no reinicia la ventana (RF-4)
  return IN_PROGRESS
```

### 3.4 Giro puro

```
recordRotationSample(r, muestra, ahora, lineaBase, amount):
  si ahora - r.inicio >= 30000: return TIME_LIMIT   // cota estricta (RF-8)
  si !isReadingValid(muestra):
    r.invalidasConsecutivas++
    r.consecutivasObjetivo = 0
    si r.invalidasConsecutivas >= 3: return SENSOR_FAILURE   // RF-9
    return CONTINUE
  r.invalidasConsecutivas = 0
  r.ultimaValida = muestra.gramos; r.hayUltimaValida = true
  si muestra.gramos >= lineaBase + amount:
    r.consecutivasObjetivo++
    si r.consecutivasObjetivo >= 3: return TARGET_REACHED    // RF-7
  si no:
    r.consecutivasObjetivo = 0
  return CONTINUE
```

### 3.5 Cotas de tiempo

- `100 ms`: plazo máximo de cada intento de lectura.
- `200 ms`: periodo máximo entre intentos, tanto en la verificación como en el
  giro; da al menos 5 intentos por segundo.
- `2 000 ms`: ventana fija de verificación, no reiniciable.
- `30 000 ms`: giro máximo desde el arranque del servo.
- `≤ 1 000 ms`: cota de detección de 3 inválidas consecutivas; con 200 ms entre
  intentos la tercera llega a los 400 ms de la primera.
- `32 000 ms`: duración máxima del ciclo completo (2 s de verificación + 30 s de
  giro); la verificación no consume el límite de giro.

### 3.6 Consulta periódica

```
checkDispenserAction(serverUrl)          // puede tardar hasta 32 s
lastCheckTime = millis()                 // se reinicia DESPUES del ciclo (RF-13)
siguiente consulta = ultimoFin + 20 s
```

## 4. Interfaz pública

```cpp
// hx711_driver.h
void initHx711();
bool readHx711Raw(long *rawOut, unsigned long timeoutMs);

// servo_driver.h
void initServo();
void startServo();
void stopServo();
void setServoAngle(int angle);

// dispensing_service.h
dispensing::DispenseResult dispenseWeight(float amountGrams);

// api_service.h (sin cambio de firma)
void checkDispenserAction(const String &serverUrl);
```

`DispenseResult` incluye: motivo (`COMPLETED`, `NOT_REACHED`,
`SENSOR_UNAVAILABLE`, `SENSOR_FAILURE`, `INVALID_CONFIG`, `INVALID_AMOUNT`),
gramos solicitados, línea base, peso final e incremento con sus banderas de
disponibilidad.

Formato de log (una línea, español, sin emojis ni credenciales):

```
Despacho: solicitado=50.0 g, linea_base=12.3 g, peso_final=63.4 g,
incremento=51.1 g, motivo=objetivo alcanzado
```

Con datos ausentes se sustituye el número por `no disponible`.

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
   el montaje típico de bogde usa `-7050`. Se guarda la magnitud `7050.0f` y
   `hx711RawSign = -1.0f`, equivalente a `-7050`, validando solo el factor. Se
   descarta usar `-7050.0f` directamente porque sería rechazado por RF-11.
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

## 6. Riesgos y mitigaciones

- **Factor de calibración desconocido:** el placeholder no es válido para el
  montaje real. Mitigación: documentarlo y ajustarlo con un peso patrón antes de
  la prueba física; sin ajuste, el peso medido será incorrecto aunque el ciclo
  funcione.
- **Signo/polaridad y offset:** con el cableado típico el raw baja al cargar; por
  eso existe `hx711RawSign`. Si el offset de reposo convierte fuera de 0–5 000 g,
  todas las lecturas serán inválidas. Mitigación: verificar la conversión con
  peso patrón y ajustar signo/factor; el riesgo se valida en la prueba física.
- **Resolución de una celda de 5 kg para 50 g:** el HX711 de 24 bits suele dar
  resolución suficiente, pero el ruido y la vibración pueden retrasar las 3
  lecturas consecutivas. Mitigación: mediana, 3 consecutivas y sobrepeso máximo
  aceptado del 10 % en la prueba física.
- **Timeout de 100 ms frente a 10 SPS del HX711:** a 5 Hz de muestreo el dato
  suele estar listo; si el módulo entrega a 10 Hz justo después del intento,
  puede contarse una inválida aislada. Mitigación: una inválida no detiene el
  ciclo; 3 consecutivas sí. Si en hardware se observan timeouts sistemáticos, se
  ajustará el modo de 80 SPS o el instante de muestreo (decisión posterior, no
  cambia la spec).
- **Vibración del servo:** puede producir lecturas inestables. Mitigación:
  mediana en la línea base y confirmación en 3 lecturas; el límite de 30 s sigue
  vigente.
- **Bloqueo de hasta 32 s:** WiFi puede degradarse o el servidor cerrar la
  conexión durante el ciclo. Mitigación: HTTP cerrado antes del ciclo, sin
  consultas solapadas y temporizador reiniciado al final (RF-13).
- **Saturación o `línea base + cantidad > 5 000 g`:** el objetivo no se alcanza
  dentro del rango válido. Mitigación: el ciclo termina por tiempo o por fallo
  de sensor y queda registrado el incremento parcial.
- **Alimento en caída tras detener el servo:** el peso final puede superar el
  objetivo. Aceptado por la spec; la prueba física admite hasta 10 % de
  sobrepeso y el log permite detectarlo.
- **Tamaño del JSON:** `StaticJsonDocument<200>` es suficiente para el payload
  real (`serve`, `amount`, `reset_wifi`); si se añaden campos en el futuro habrá
  que ampliarlo. No se toca el contrato del backend.

## 7. Estrategia de tests

### 7.1 Nativos (`pio test -e native`)

Se escriben antes de implementar y deben pasar en verde. No requieren hardware.

- `classifyOrder`: `serve:true` + amount > 0 → dispensar; `serve:false` y
  amount 0 → reposo; amount ausente, no numérico o negativo → orden inválida;
  `reset_wifi:true` gana con `serve:true`, con `serve:false` y con amount 0
  (RF-1, RF-2, RF-10).
- `isCalibrationFactorValid`: positivo válido; 0, negativo y NaN inválidos
  (RF-11).
- `convertRawToGrams`/`makeSample`: raw × signo / factor; lectura válida;
  inválida por timeout, NaN, fuera de 0–5 000 g y saturación en ambos extremos
  (RF-3, RF-6, RF-11).
- `median`: impar, par (promedio de los dos centrales), sin válidas (RF-3).
- Verificación: pasa con ≥ 5 válidas en 2 s; falla con 4; 3 inválidas
  consecutivas abortan sin reiniciar; una inválida aislada no reinicia la
  ventana; la ventana no se extiende más de 2 s; línea base correcta (RF-3,
  RF-4).
- Giro: arranque lógico tras verificación; incremento respecto a la línea base;
  parada con 3 lecturas consecutivas ≥ objetivo; dos consecutivas y una por
  debajo reinician el contador; una inválida aislada continúa; 3 inválidas
  consecutivas → fallo de sensor; 30 s → tiempo límite; nunca acepta objetivo en
  o después de los 30 s (RF-5, RF-6, RF-7, RF-8, RF-9, RNF-2, RNF-3).
- `formatDispenseLog`: incluye solicitado, línea base, peso final, incremento y
  motivo; usa «no disponible» cuando corresponde; sin emojis (RF-12, RNF-5).
- `isCheckDue`: no vence antes de 20 s y sí a los 20 s (RF-13, parte
  automatizable).

### 7.2 Requiere hardware o checklist manual

- RF-5: el servo arranca solo tras superar la verificación (observación).
- RF-9 (tiempo real): desconectar el módulo HX711 del ESP32 (DT/SCK; idealmente
  también VCC/GND) a mitad del giro detiene el servo dentro de 1 s desde la
  primera de las 3 inválidas. Desconectar solo la celda con el módulo alimentado
  puede dar lecturas plausibles y no es una prueba determinista.
- RF-11: ajuste del factor con peso patrón; con factor no positivo no se mueve
  el servo y se registra el error.
- RF-12: inspección del log real de una dispensación completa y de una abortada.
- RF-13 y RNF-4: checklist de no regresión de BLE, WiFi, reconexión, validación
  de servidor, reset de credenciales y consulta periódica 20 s después del fin.
- RNF-1: observación de al menos 5 lecturas por segundo durante verificación y
  giro.
- RNF-5: revisión del log en español, sin emojis ni credenciales.
- Prueba física de exactitud: 50 g solicitados → incremento entre 50 g y 55 g.

### 7.3 Mapa RF → verificación

| RF | Verificación principal |
|---|---|
| RF-1 | Nativa: `classifyOrder` → `DISPENSE` |
| RF-2 | Nativa: reposo vs orden inválida |
| RF-3 | Nativa: ventana 2 s, ≥ 5 válidas, mediana |
| RF-4 | Nativa: no supera → sensor no disponible; 3 inválidas abortan |
| RF-5 | Hardware: arranque solo tras verificación |
| RF-6 | Nativa: incremento; hardware: muestreo continuo |
| RF-7 | Nativa: 3 consecutivas ≥ objetivo |
| RF-8 | Nativa: 30 s → tiempo límite |
| RF-9 | Nativa: 3 inválidas → fallo; hardware: parada ≤ 1 s |
| RF-10 | Nativa: prioridad de `reset_wifi` |
| RF-11 | Nativa: conversión y factor; hardware: peso patrón |
| RF-12 | Nativa: formateador con «no disponible»; hardware: log real |
| RF-13 | Nativa: `isCheckDue`; manual: no regresión WiFi/BLE |
| RNF-1 | Nativa: periodo 200 ms; hardware: 5 Hz observados |
| RNF-2 | Nativa: 3 consecutivas |
| RNF-3 | Nativa: cota 30 s; revisión de bucle |
| RNF-4 | Revisión de `platformio.ini` + checklist |
| RNF-5 | Inspección del log |
| RNF-6 | `pio test -e native` en verde |

## 8. Orden de implementación

Configuración y dependencia → driver HX711 → lógica pura con tests en rojo y
verde → servo → servicio de dispensado → integración API y temporizador →
validación automatizada → checklist físico, no regresión y `MEMORY.md`.
