# Plan 016 — Validación de línea base y plausibilidad del dispensado

Spec de referencia: `specs/016-validacion-linea-base-y-plausibilidad/spec.md` (borrador corregido; 8 RF, 5 RNF).
Alcance exclusivo: firmware `DispensadorESP32`. No se toca `api/` ni `app/app_movil_pdam/`: la 014 ya cierra
`sensor_no_disponible` como fallo sin descuento y su contrato de reporte no cambia.
Cumplimiento: `docs/constitution.md` (trazabilidad Modelo en V, separación lógica, tests en todos los módulos, español,
sin datos sensibles) y `AGENTS.md` (Clean Architecture, sin dependencias nuevas, tests por módulo, `pio run` +
`pio test -e native`).
Ninguna tarea se implementa hasta aprobar este plan y `tasks.md`.

## 1. Punto de partida y alcance real

Estado del firmware hoy, relevante para el cambio:

- `dispensing_cycle.h` (puro) ya contiene la ventana de 2 s, la línea base como mediana de las válidas
  (`verificationBaseline`), el bucle de motor con presupuesto absoluto, la detección de atasco y el cierre con
  `stop()` en toda salida. Aquí se añaden la condición de estabilidad de la base y la plausibilidad del incremento.
- `dispensing_utils.h` es la única fuente de constantes de la 013 (`kMotorBudgetMs`, `kVerificationWindowMs`,
  `kMinValidReadings`, `kMaxConsecutiveInvalidReadings`, `kMedianBufferSize`, `kSamplePeriodMs`, `kReadTimeoutMs`,
  `kMaxValidWeightGrams`, …). Las constantes nuevas de la 016 se añaden aquí (RNF-3).
- `api_service.cpp` clasifica la orden con `dispensing::classifyOrder` y llama a `dispenseWeight`; conoce el
  `order_id` y ya sabe enviar un reporte de cierre sin ciclo (`reporteVacio`) para la orden inválida.
- `dispenser_task.cpp` es una máquina de estados no bloqueante con el temporizador de 20 s (`isCheckDue`). **No se
  modifica**: la consulta periódica debe seguir igual (decisión 1 del usuario).
- `main.cpp` solo llama a `runDispenserTask()` en `loop()`. Ahí se engancha el muestreo continuo.
- La celda se inicializa una sola vez con un `static bool` local de `dispensing_service.cpp`; hay que centralizarlo
  para que el muestreo de arranque no llame a `hx711.begin()` dos veces.
- `report_utils.h` (puro) construye el JSON y deriva los medidos de `DispenseResult::incrementAvailable`; los cierres
  por `sensor_no_disponible` deben omitir los medidos (RF-7).

Lo que **no** se hace: ni tarea FreeRTOS, ni memoria dinámica, ni cambios de umbrales/ventanas/presupuesto de la 013,
ni cambios en el catálogo de causas, ni backend, ni app.

## 2. Arquitectura del cambio

Tres capas, con la lógica siempre fuera de `tasks/` y de los servicios de hardware:

1. **Lógica pura nueva — `DispensadorESP32/src/config/scale_guard_utils.h`** (cabecera sin `<Arduino.h>`).
   Concentra las tres decisiones de la 016 y es lo único que se prueba en nativo:
   - máquina de estado del asentamiento (`SettlementState`, `recordSettlementSample`, `invalidateSettlement`,
     `settlementGained`);
   - evaluación de la línea base de la ventana de la 013 (`assessBaseline`) con su veredicto de motivo;
   - plausibilidad del incremento (`plausibilityTopGrams`, `recordPlausibilitySample`) con su veredicto;
   - decisión de entrada de una orden según el asentamiento (`decideDispenseEntry`).
   Las constantes **no** viven aquí: viven en `dispensing_utils.h` (RNF-3) y esta cabecera la incluye.
2. **Servicio adaptador — `DispensadorESP32/src/services/scale_guard_service.{h,cpp}`** (Arduino).
   Guarda un `SettlementState` estático, muestrea el HX711 cada `kSamplePeriodMs`, delega toda la decisión en la
   cabecera pura y solo registra en serie las transiciones (asentamiento ganado o perdido, con el motivo). Expone
   `initScaleGuard()`, `updateSettlement()`, `settlementGained()` e `invalidateSettlement(motivo)`.
   `main.cpp` lo arranca en `setup()` y lo alimenta en `loop()`; no se añade lógica a `tasks/dispenser_task.cpp`.
3. **Consumo de la decisión**:
   - `api_service.cpp` usa `decideDispenseEntry` para la compuerta (RF-1): si no hay asentamiento, no llama a
     `dispenseWeight` y envía `reporteVacio(SENSOR_UNAVAILABLE)` con el `order_id` y los solicitados recibidos.
   - `dispensing_cycle.h` usa `assessBaseline` en lugar de `verificationBaseline` y de la comprobación
     `verificationOutcome != PASSED` de la ventana agotada —la salida temprana por 3 inválidas consecutivas se conserva—
     y evalúa la plausibilidad en cada lectura válida antes del objetivo y del atasco (RF-5, RF-6).
   - `dispensing_service.cpp` imprime el diagnóstico del rechazo de línea base y de la plausibilidad, y sigue
     emitiendo la línea única de `formatDispenseLog`.

Flujo de una consulta (sin cambios de temporizador):

```
loop():  guard::updateSettlement()        // muestreo continuo, 5 Hz, fuera del ciclo
         runDispenserTask()               // intacto: consulta cada 20 s

GET /dispensers/check-taks/{mac} → classifyOrder
   RESET_WIFI                       → como hoy (no exige asentamiento)
   REST / INVALID_ORDER             → como hoy
   DISPENSE → decideDispenseEntry(DISPENSE, guard::settlementGained())
        REJECT_NO_SETTLEMENT → reporte {motivo: sensor_no_disponible, order_id, solicitados, medidos ausentes}
        DISPENSE             → guard::invalidateSettlement(); dispenseWeight(amount) → reporte del ciclo
```

## 3. Archivos afectados

| Archivo | Acción | Responsabilidad y RF |
|---|---|---|
| `DispensadorESP32/src/config/dispensing_utils.h` | modificar | Seis constantes nuevas documentadas en español en el único lugar (RNF-3), junto a las de la 013 y reutilizando `kMinValidReadings`, `kMedianBufferSize` y `kMaxConsecutiveInvalidReadings`. Nada más cambia. RF-5, RNF-3 |
| `DispensadorESP32/src/config/scale_guard_utils.h` | **nuevo**, puro | `SettlementState`/`recordSettlementSample`/`invalidateSettlement`/`settlementGained`; `BaselineVerdict`/`assessBaseline`; `PlausibilityState`/`plausibilityTopGrams`/`recordPlausibilitySample`; `DispenseEntry`/`decideDispenseEntry`; `baselineRejectionText`/`plausibilityCauseText`. RF-1, RF-2, RF-3, RF-4, RF-5, RNF-1, RNF-5 |
| `DispensadorESP32/src/config/dispensing_cycle.h` | modificar | Línea base por `assessBaseline`, que sustituye a la comprobación `verificationOutcome != PASSED` de la ventana agotada conservando la salida temprana por 3 inválidas de la 013 (RF-2, RF-3, RF-4); plausibilidad por lectura antes de objetivo y atasco (RF-5, RF-6); ampliación de `CycleDiagnostics` con `baselineRejection`, `plausibility`, `topGrams`, `maxIncrementGrams`; sin retroceso ni objetivo en el cierre por plausibilidad. RF-5, RF-6, RF-7, RNF-2 |
| `DispensadorESP32/src/services/scale_guard_service.{h,cpp}` | **nuevo**, Arduino | Muestreo continuo del asentamiento, transiciones en el log, invalidación explícita, `initScaleGuard()`. RF-1, RF-2, RF-8, RNF-1, RNF-4 |
| `DispensadorESP32/src/services/dispensing_service.cpp` | modificar | Usa `ensureHx711Initialized()` del driver; imprime una línea de diagnóstico con `linea_base`/`tope`/`incremento_max` y el motivo real; el bloque `logVerificationDiagnostics` (hoy en las líneas 131-134) se imprime **solo** cuando el cierre sea por rechazo de línea base, y un cierre por plausibilidad imprime únicamente la línea de `plausibilidad_tope`/`plausibilidad_suelo`, para no anunciar «ventana sin lecturas suficientes» en un ciclo que sí midió; conserva la línea única con `reintentos=N`. RF-3, RF-5, RF-7, RNF-4 |
| `DispensadorESP32/src/services/api_service.cpp` | modificar | Compuerta `decideDispenseEntry` e invalidación del asentamiento antes de `dispenseWeight`; cierre reportado con `order_id`. RF-1, RF-7, RF-8 |
| `DispensadorESP32/src/drivers/hx711_driver.{h,cpp}` | modificar | `ensureHx711Initialized()` con el `static bool` que hoy vive en el servicio, para que el muestreo de arranque y el ciclo compartan una única inicialización. RF-1, RNF-4 |
| `DispensadorESP32/src/config/report_utils.h` | modificar | `reporteDesdeResultado` deja los medidos ausentes cuando el motivo es `SENSOR_UNAVAILABLE` (RF-7). RF-7 |
| `DispensadorESP32/src/config/config.h` | modificar | Comentario en español con los umbrales nuevos; sin duplicar valores. RNF-3 |
| `DispensadorESP32/src/main.cpp` | modificar | `initScaleGuard()` en `setup()` y `updateSettlement()` en `loop()`, antes de `runDispenserTask()`. RF-1, RNF-1 |
| `DispensadorESP32/platformio.ini` | modificar | `test_scale_guard_utils` en `test_ignore` del entorno `esp32dev`; sin dependencias nuevas. RNF-5 |
| `DispensadorESP32/test/test_scale_guard_utils/test_scale_guard_utils.cpp` | **nuevo** | Matriz completa de asentamiento, línea base, plausibilidad y compuerta. RF-1 a RF-5, RNF-1, RNF-5 |
| `DispensadorESP32/test/test_dispensing_cycle/test_dispensing_cycle.cpp` | ampliar | Perfiles de tope, suelo, reinicio del contador, prioridad del tope y caso feliz con la nueva línea base; actualización declarada de `profileTargetInReverse` y `profileTargetInPause` (§10) y variantes nuevas con salto por encima del tope en esas fases. RF-2 a RF-7 |
| `DispensadorESP32/test/test_report_utils/test_report_utils.cpp` | ampliar | Medidos ausentes con `sensor_no_disponible` y conservados en los demás motivos. RF-7 |
| `DispensadorESP32/test/test_dispensing_utils/test_dispensing_utils.cpp` | sin cambios funcionales | Solo se añaden aserciones de las constantes nuevas si se decide fijarlas aquí; las 013 deben seguir verdes. RNF-3 |
| `MEMORY.md` | actualizar al cerrar | Estado, decisiones y pendientes físicos. — |

`tasks/dispenser_task.cpp`, `drivers/servo_driver.{h,cpp}`, `services/report_service.{h,cpp}`,
`services/wifi_service.{h,cpp}` y `config/provisioning_utils.h` no se tocan.

## 4. Funciones puras (el instante y las lecturas son parámetros)

| Función | Responsabilidad | RF |
|---|---|---|
| `recordSettlementSample(SettlementState*, const WeightSample&)` | Gana la racha con 15 válidas y paso ≤1 g; la rompe con un paso mayor, con 3 inválidas consecutivas o al invalidarla; devuelve `GAINED`/`LOST`/`IN_PROGRESS`, y solo devuelve `LOST` si el asentamiento estaba ganado (si no, `IN_PROGRESS` con la racha reiniciada) | RF-1, RF-2, RF-8, RNF-1 |
| `invalidateSettlement(SettlementState*)` | Deja el estado sin asentamiento, sin racha y sin lectura anterior; se usa al iniciar un ciclo y tras un cierre por tope o suelo | RF-5, RF-8 |
| `settlementGained(const SettlementState&)` | Consulta del estado para la compuerta | RF-1 |
| `decideDispenseEntry(OrderAction, bool settled)` | `REJECT_NO_SETTLEMENT` si la orden dispensa sin asentamiento; resto de acciones sin cambios | RF-1 |
| `plausibilityTopGrams(float amount)` | `max(3 × amount, amount + 10)` | RF-5, RF-6 |
| `recordPlausibilitySample(PlausibilityState*, float incrementGrams, float amount)` | Veredicto `PLAUSIBLE`/`ABOVE_TOP`/`BELOW_FLOOR` con 3 válidas consecutivas; una válida dentro del intervalo reinicia el contador | RF-5, RF-6 |
| `assessBaseline(const VerificationState&, float *baselineOut)` | Mediana de **todas** las válidas y veredicto `ACCEPTED`/`UNSTABLE`/`INSUFFICIENT_READINGS`/`INVALID_BASELINE` con el paso entre las últimas 5 | RF-2, RF-3, RF-4 |
| `baselineRejectionText`, `plausibilityCauseText` | Textos en español para el log (`inestable`, `lecturas_insuficientes`, `linea_base_invalida`, `plausibilidad_tope`, `plausibilidad_suelo`) | RF-3, RF-5, RNF-4 |
| `runDispenseCycle(...)` | Ciclo completo: línea base validada y plausibilidad por lectura con prioridad sobre objetivo y atasco | RF-2 a RF-7 |
| `reporteDesdeResultado(...)` | Medidos ausentes cuando el motivo es `SENSOR_UNAVAILABLE` | RF-7 |

`verificationBaseline` de la 013 **se conserva** aunque el ciclo use `assessBaseline`, para no romper sus pruebas ni
su semántica documentada.

Nota sobre el buffer de la mediana: `VerificationState::validValues` **no es un anillo**; se llena con el índice
`storedCount` y se detiene al llegar a `kMedianBufferSize` (`dispensing_utils.h:271-274`). `kMedianBufferSize` vale 16,
y en 2 s a 5 Hz entran 10–11 lecturas válidas (la ventana admite hasta 10 muestras por periodo de `kSamplePeriodMs`, más
la primera), así que el buffer cubre «todas las válidas de la ventana» y `assessBaseline` puede usar
`storedCount` como conjunto completo de la mediana. Al tocar constantes debe preservarse que
`kMedianBufferSize >= 11`; si se redujera, la mediana dejaría de ser la de todas las válidas de la ventana y RF-2
cambiaría de sentido sin avisar.

## 5. Algoritmo en pseudocódigo

### 5.1 Asentamiento (continuo, fuera del ciclo)

```
updateSettlement(ahora):
  si ahora - ultimaMuestra < kSamplePeriodMs: return        // 5 Hz, mismo periodo que la 013
  ultimaMuestra = ahora
  respondio = readHx711Raw(&raw, kReadTimeoutMs)            // nunca más de 100 ms de sondeo
  salida = recordSettlementSample(&estado, makeSample(respondio, raw, factor, signo))
  si salida == GAINED: log "Asentamiento alcanzado: %u lecturas consecutivas con paso <= %.1f g"
  si salida == LOST:   log "Asentamiento perdido: %s"      // paso_inestable | lecturas_invalidas 3

recordSettlementSample(estado, muestra):
  si !isReadingValid(muestra):
      estado.racha = 0; estado.hayAnterior = false
      ++estado.invalidasConsecutivas
      si estado.invalidasConsecutivas >= kMaxConsecutiveInvalidReadings:
          perdido = estado.ganado; estado.ganado = false
          return perdido ? LOST : IN_PROGRESS
      return IN_PROGRESS
  estado.invalidasConsecutivas = 0
  si estado.hayAnterior y |muestra.gramos - anterior| > kSettlementMaxStepGrams:
      perdido = estado.ganado                        // solo se pierde lo que estaba ganado
      estado.ganado = false; estado.racha = 1; estado.anterior = gramos
      return perdido ? LOST : IN_PROGRESS            // racha reiniciada en 1 en ambos casos
  ++estado.racha; estado.anterior = gramos; estado.hayAnterior = true
  si estado.racha >= kSettlementReadings y !estado.ganado:
      estado.ganado = true; return GAINED
  return IN_PROGRESS
```

### 5.2 Compuerta y cierre sin ciclo

```
DISPENSE:
  si !settlementGained():
      guard::invalidateSettlement()                 // deja constancia de la causa en el log
      reporte = reporteVacio(SENSOR_UNAVAILABLE)    // medidos no disponibles (RF-7)
      reporte.orderId = orderId; reporte.orderIdAvailable = orderIdAvailable
      reporte.solicitados = amount; reporte.solicitadosAvailable = amount > 0
      enviarReporte(mac, reporte, REPORTS_URL)
      break                                          // el servo no se toca y no se llama a dispenseWeight
  guard::invalidateSettlement("inicio de ciclo")      // el estado no puede quedar obsoleto durante el ciclo
  resultado = dispenseWeight(amount)
  enviarReporte(reporteDesdeResultado(resultado, orderIdAvailable, orderId))
```

### 5.3 Línea base (dentro de la ventana de 2 s de la 013)

```
tras cerrar la ventana:
  // La salida temprana por 3 lecturas inválidas consecutivas durante la ventana
  // sigue siendo la de la 013 (RF-4) y no cambia: el bucle de verificación ya
  // cerró con ABORTED_BY_INVALID, de modo que aquí solo se llega con la ventana
  // agotada por tiempo. Esta comprobación SUSTITUYE a `verificationOutcome !=
  // VerificationOutcome::PASSED` (dispensing_cycle.h:245) para que los tres
  // motivos de RF-3 sean alcanzables.
  veredicto = assessBaseline(verificacion, &lineaBase)
  si veredicto != ACCEPTED:
      stop(); motivo = SENSOR_UNAVAILABLE; diagnostico.motivoLineaBase = veredicto
      return                                          // sin arranque del servo (RF-3)
  // la mediana ya es la de TODAS las válidas de la ventana (decisión 4)

assessBaseline(verificacion, salida):     // orden interno obligatorio
  1) si verificacion.validCount < kMinValidReadings o
        verificacion.storedCount < kMinValidReadings:   return INSUFFICIENT_READINGS
  2) si !median(verificacion.validValues, verificacion.storedCount, salida) o
        *salida < kMinValidWeightGrams o *salida > kMaxValidWeightGrams:
                                                          return INVALID_BASELINE
  3) para i en [storedCount-5, storedCount-1):           // últimas 5 válidas
        si |validValues[i+1] - validValues[i]| > kSettlementMaxStepGrams:
                                                          return UNSTABLE
  4) return ACCEPTED
```

El orden interno importa: con menos de 5 válidas no se puede calcular la mediana ni hablar de estabilidad, y una mediana
no calculable o fuera de 0–5000 g es una causa más concreta que cualquier paso. `verificationOutcome` se conserva en el
estado de la 013 solo para la salida temprana por 3 inválidas consecutivas; sobre la ventana agotada decide
`assessBaseline`.

### 5.4 Plausibilidad en el ciclo de motor

```
en cada lectura del ciclo (avance, retroceso y pausa), antes del objetivo y del atasco:
  si isReadingValid(muestra):
      incremento = muestra.gramos - lineaBase
      veredictoPlausible = recordPlausibilitySample(&plausibilidad, incremento, amount)
      si veredictoPlausible != PLAUSIBLE:
          diagnostico.plausibility = veredictoPlausible
          diagnostico.top = plausibilityTopGrams(amount)
          diagnostico.maxIncremento = incremento
          motivo = SENSOR_UNAVAILABLE; break          // sin retroceso, sin reintento, sin objetivo
  salida = recordRotationSample(...)                  // objetivo y fallo de sensor de la 013
  ...
stop()                                                // toda salida detiene el servo
// el resultado conserva base, peso final e incremento para el LOG;
// el reporte los omite porque el motivo es SENSOR_UNAVAILABLE (RF-7)
```

## 6. Interfaz pública

```cpp
// config/scale_guard_utils.h (puro)
namespace dispensing {

enum class SettlementOutcome { IN_PROGRESS, GAINED, LOST };

struct SettlementState {
  unsigned streak;
  unsigned consecutiveInvalid;
  float previousGrams;
  bool hasPrevious;
  bool settled;
};

SettlementOutcome recordSettlementSample(SettlementState *state, const WeightSample &sample);
void invalidateSettlement(SettlementState *state);
bool settlementGained(const SettlementState &state);

enum class BaselineVerdict { ACCEPTED, UNSTABLE, INSUFFICIENT_READINGS, INVALID_BASELINE };
BaselineVerdict assessBaseline(const VerificationState &verification, float *baselineOut);
const char *baselineRejectionText(BaselineVerdict verdict);

enum class PlausibilityVerdict { PLAUSIBLE, ABOVE_TOP, BELOW_FLOOR };
struct PlausibilityState { unsigned consecutive; };
float plausibilityTopGrams(float amountGrams);
PlausibilityVerdict recordPlausibilitySample(PlausibilityState *state, float incrementGrams,
                                             float amountGrams);
const char *plausibilityCauseText(PlausibilityVerdict verdict);

enum class DispenseEntry { REST, DISPENSE, RESET_WIFI, REJECT_ORDER, REJECT_NO_SETTLEMENT };
DispenseEntry decideDispenseEntry(OrderAction action, bool settled);

} // namespace dispensing

// services/scale_guard_service.h (Arduino)
namespace guard {
void initScaleGuard();                 // inicializa la celda una sola vez
void updateSettlement();               // una llamada por iteración de loop(); muestrea a 5 Hz
bool settlementGained();
void invalidateSettlement(const char *motivo);  // nullptr = sin mensaje
} // namespace guard
```

`dispenseWeight(float)` conserva su firma y `DispenseResult` no añade campos: el cierre por plausibilidad usa
`DispenseReason::SENSOR_UNAVAILABLE`, que ya existe y ya se reporta como `sensor_no_disponible`.

## 7. Decisiones justificadas y alternativas descartadas

1. **Cabecera pura nueva (`scale_guard_utils.h`) y constantes en `dispensing_utils.h` (elegido).** Separa la máquina
   de estado nueva de las 700 líneas de la 013 y mantiene una única fuente de umbrales (RNF-3). Se descarta añadir
   todo a `dispensing_utils.h` (mezcla dos ciclos de vida y multiplica el riesgo de regresión en las 165 pruebas de la
   familia del dispensado: 132 de la 013 —110 de `test_dispensing_utils` y 22 de `test_dispensing_cycle`—, 28 de la 014
   y 5 de provisión) y se descarta un archivo de constantes propio (duplicaría la fuente que la 013 ya fijó).
2. **Muestreo del asentamiento en `loop()` mediante servicio adaptador (elegido).** No toca `dispenser_task.cpp`, no
   añade concurrencia y respeta «nada de lógica en las tareas». Se descarta una tarea FreeRTOS con mutex: añade
   estados compartidos con WiFi/BLE y riesgo de carrera justo donde el incidente ocurrió. Se descarta muestrear solo
   dentro de la consulta: la racha de 15 lecturas no cabría antes del `GET` sin retrasar la consulta.
3. **Compuerta en `api_service` con decisión pura (elegido).** Es el único punto que conoce el `order_id` y el
   `amount` recibidos, así que puede cerrar y reportar sin inventar datos (RF-1, RF-7); la decisión se prueba en
   nativo. Se descarta ponerla dentro de `dispenseWeight`: no tiene `order_id`, obligaría a cambiar su firma y el
   reporte de cierre quedaría en el servicio de dispensado, que no habla con la API.
4. **Invalidar el asentamiento al iniciar cualquier ciclo (elegido).** Durante el ciclo el muestreo no corre y el peso
   cambia, así que el estado quedaría obsoleto y la compuerta dejaría pasar una orden con una racha vieja. Se descarta
   mantener el estado y recalcularlo después: exigiría muestrear dentro del ciclo y competir con la lectura del ciclo.
5. **Línea base con la ventana de 2 s de la 013 y estabilidad sobre las últimas 5 válidas (elegido, decisión 4).** No
   añade tiempo muerto ni un muestreo previo nuevo y la mediana sigue siendo la de todas las válidas. Se descarta una
   ventana propia de la 016 (duplicaría tiempos y cambiaría más de lo necesario la 013).
6. **Estabilidad como paso entre lecturas consecutivas ≤1 g (elegido, decisión 3).** Es verificable, no depende de un
   conjunto indefinido y detecta la deriva. Se descarta la condición «la anterior no difiere de la mediana» (ambigua y
   no acotada por el número de lecturas) y el rango máximo−mínimo (una deriva lenta de 1 g por lectura pasaría el
   filtro y una vibración simétrica lo haría fallar).
7. **Plausibilidad evaluada en las tres fases y antes del objetivo y del atasco (elegido).** Un solo punto de decisión
   cumple la prioridad de RF-6 y detecta la bandeja retirada durante el retroceso. Se descarta evaluarla solo en avance
   (dejaría pasar una pérdida de masa durante el reintento y rompería «prevalece el tope»).
8. **Cierre con la causa existente `sensor_no_disponible` y causa real solo en el log (elegido, decisiones 5 y 6).**
   No reabre el catálogo cerrado de la 014 ni obliga a tocar backend ni app. Se descartan causas nuevas
   (`plausibilidad_tope`, `plausibilidad_suelo`) en el catálogo: exigirían spec nueva, migración de datos y cambios en
   la app, y el usuario ya decidió no tocarlo.
9. **Medidos ausentes en el reporte resueltos en `reporteDesdeResultado` (elegido).** Una sola regla pura y probada:
   con `SENSOR_UNAVAILABLE` no se envían `gramos_medidos`. Se descarta poner a cero las banderas de `DispenseResult`
   (dejaría el log serie sin el peso final ni el incremento, que es justo el diagnóstico que pide HU-3) y se descarta
   añadir un campo nuevo al resultado (más superficie para un dato que ya se deduce del motivo).
10. **Reutilizar `kMaxConsecutiveInvalidReadings` para perder el asentamiento y crear
    `kPlausibilityConsecutiveReadings` para la plausibilidad (elegido).** Las 3 inválidas consecutivas son la misma
    condición que ya usa la 013; las 3 lecturas fuera de límites son un concepto distinto y no deben cambiar si cambia
    el otro. Se descarta reutilizar `kMaxConsecutiveInvalidReadings` para ambas: acoplaría dos umbrales con significados
    distintos.
11. **`ensureHx711Initialized()` en el driver (elegido).** El muestreo de arranque y el ciclo deben compartir una
    única `begin()`; el flag deja de vivir en el servicio. Se descarta duplicar el `static bool` en cada servicio: dos
    `begin()` sobre los mismos pines son un riesgo innecesario.
12. **Sin dependencias ni memoria dinámica (elegido, RNF-4).** Todo son estructuras de tamaño fijo y el buffer de la
    mediana ya existe. Se descarta cualquier contenedor o librería de filtros.
13. **El temporizador de 20 s no se toca (elegido, decisión 1).** La compuerta afecta solo a la dispensación. Se
    descarta retrasar la consulta hasta tener asentamiento: rompería RF-13 de la 013 y dejaría de recibir
    `reset_wifi`.

## 8. Riesgos y mitigaciones

- **Estado de asentamiento obsoleto:** el muestreo no corre durante el ciclo ni durante los bloqueos de WiFi/BLE.
  Mitigación: invalidación explícita al iniciar el ciclo y al cerrar por tope, suelo o 3 inválidas; el estado solo se
  gana con lecturas tomadas después del bloqueo.
- **Primera orden tras el arranque cerrada como fallo:** es el comportamiento pedido (decisión 1), pero puede
  sorprender. Mitigación: el log muestra «sin asentamiento», el reporte lleva el `order_id`, la app ve el registro y
  está documentado en «Limitaciones aceptadas» de la spec.
- **Coste del muestreo continuo:** una lectura cada 200 ms con sondeo acotado a 100 ms. El tramo `read()` de
  `bogde/HX711` sigue sin cota (deuda aceptada de la 013); si bloqueara, retrasaría la consulta periódica.
  Mitigación: no se lanza una lectura si hay otra pendiente, el sondeo previo está acotado y el ciclo reinicia el
  temporizador como hoy.
- **Doble inicialización de la celda:** mitigado con `ensureHx711Initialized()` y una prueba de revisión de que solo
  existe un `hx711.begin()`.
- **Ruido real de la celda que impide el paso ≤1 g:** con vibración o con la mascota tocando la bandeja, la racha no
  se gana y la compuerta cierra como fallo. Mitigación: el umbral es constante configurable (RNF-3) y la prueba física
  (d) confirma que la celda real alcanza 15 lecturas con paso ≤1 g; si no, se ajusta el umbral, no la lógica.
- **Falso `inestable` en la ventana de 2 s:** el servo aún no gira, así que la única fuente de ruido es la celda y el
  entorno. Mitigación: la mediana es de todas las válidas y la estabilidad solo mira las últimas 5; el motivo queda en
  el log con la base para ajustar.
- **Tope demasiado estrecho para cantidades pequeñas:** para 5 g el tope es 15 g (factor 3) y para 2 g el margen de
  10 g da 12 g; el margen domina en cantidades pequeñas y evita falsos positivos. Riesgo residual: una entrega real
  muy por encima del triple en cantidades grandes cerraría como fallo; la 013 admite hasta un 10 % de sobrepeso, muy
  por debajo del triple.
- **Regresión en la 013:** el ciclo cambia su condición de línea base y añade una comprobación por lectura.
  Mitigación: `CycleLimits`, presupuesto, ventanas y textos existentes no se tocan; las 165 pruebas de la familia del
  dispensado (132 de la 013 —110 de `test_dispensing_utils` y 22 de `test_dispensing_cycle`—, 28 de la 014 y 5 de
  provisión) deben seguir verdes y se conserva `verificationBaseline`, con la única actualización declarada de las dos
  pruebas de «objetivo en retroceso» y «objetivo en pausa» descrita en §10.
- **Regresión en la 014:** `reporteDesdeResultado` cambia para `SENSOR_UNAVAILABLE`. Mitigación: revisar y actualizar
  las aserciones existentes de `test_report_utils` que esperasen medidos con ese motivo (hoy el motivo solo aparecía
  sin medición, así que el cambio debe ser compatible), y probar los seis motivos.
- **Backend:** no se toca. La causa `sensor_no_disponible` ya cierra como fallo sin descuento. Mitigación:
  verificación de no regresión ejecutando `pytest` y comprobando que ningún test cambia.

## 9. Estrategia de tests

Todo nativo con `pio test -e native` y lecturas inyectadas; ningún test depende de hardware, WiFi ni Arduino.

### 9.1 `test_scale_guard_utils` (nuevo)

- Asentamiento: 14 válidas estables → no ganado; 15 → ganado; paso de 1,0 g exacto → gana; 1,01 g → pierde y reinicia
  la racha en 1; una inválida aislada rompe la racha pero no retira un asentamiento ya ganado; 3 inválidas
  consecutivas → perdido y `LOST`; con 2 inválidas y una válida el contador se reinicia; tras perderlo hacen falta 15
  lecturas nuevas; `invalidateSettlement` lo deja perdido aunque la racha fuera completa; lectura saturada o fuera de
  0–5000 g cuenta como inválida.
- Compuerta: `decideDispenseEntry` con `DISPENSE` y sin asentamiento → `REJECT_NO_SETTLEMENT`; con asentamiento →
  `DISPENSE`; `REST`, `RESET_WIFI` e `INVALID_ORDER` no dependen del asentamiento.
- Línea base: 5 válidas idénticas → `ACCEPTED` con mediana exacta; 6 válidas (par) → promedio de las centrales;
  9 válidas con un pico en la primera → `ACCEPTED` (la mediana usa todas y la estabilidad solo las últimas 5); última
  lectura separada 1,01 g → `UNSTABLE`; 1,0 g → `ACCEPTED`; 4 válidas → `INSUFFICIENT_READINGS`; base 0,0 g →
  `ACCEPTED`; valores que dejan la mediana fuera de 0–5000 g o buffer vacío → `INVALID_BASELINE`; textos de los tres
  motivos en español.
- Plausibilidad: 17,27 g → tope 51,81 g (factor 3); 100 g → 300 g (factor 3) y no 110 g; 2 g → 12 g (margen);
  incremento igual al tope → `PLAUSIBLE`; 0,01 g por encima → `ABOVE_TOP` en la tercera consecutiva y no en la
  segunda; −10 g → `PLAUSIBLE`; −10,01 g → `BELOW_FLOOR` en la tercera; una lectura dentro del intervalo reinicia el
  contador; una lectura inválida no se cuenta aquí.
- Constantes: `kSettlementReadings`, `kSettlementMaxStepGrams`, `kPlausibilityFactor`, `kPlausibilityMarginGrams`,
  `kPlausibilityFloorGrams` y `kPlausibilityConsecutiveReadings` valen lo aprobado y viven en `dispensing_utils.h`.

### 9.2 `test_dispensing_cycle` (ampliado)

- Caso feliz: línea base estable de 5 válidas, flujo de 1 g/s hasta 50 g → `COMPLETED`, medidos disponibles,
  `retryCount = 0`, última acción `stop`.
- Tope: perfil que salta a base+80 g con orden de 20 g (tope 60 g) → `SENSOR_UNAVAILABLE`, cero `startReverse`, cero
  reanudaciones, sin `COMPLETED`, y una única parada final.
- Suelo: perfil que cae a base−20 g → `SENSOR_UNAVAILABLE` sin retroceso.
- Contador: dos lecturas por encima del tope y una dentro → el ciclo continúa y puede alcanzar el objetivo.
- Prioridad: una lectura que alcanza el objetivo y supera el tope → cierra por tope (no `COMPLETED`).
- Fases: tope durante el retroceso y durante la pausa → parada sin retroceso adicional ni reanudación.
- Línea base: ventana inestable → `SENSOR_UNAVAILABLE` con `baselineRejection = UNSTABLE` y servo inmóvil; ventana con
  4 válidas → `INSUFFICIENT_READINGS`; los perfiles de la 013 (atasco, presupuesto, fallo de sensor, orden inválida)
  siguen con el mismo resultado (los dos de objetivo en retroceso y en pausa se actualizan en la viñeta siguiente).
- Dos perfiles existentes se actualizan de forma declarada: `profileTargetInReverse` y `profileTargetInPause` saltan
  hoy a 50 g con una orden de 10 g (tope 30 g) y con la plausibilidad cerrarían por tope en lugar de `COMPLETED`; bajan
  su salto a un valor plausible (por ejemplo 25 g con orden de 10 g) para seguir probando «objetivo en retroceso» y
  «objetivo en pausa», y se añaden variantes nuevas con un salto por encima del tope en esas mismas fases (cubiertas en
  la viñeta de fases).
- Cota: en todos los perfiles nuevos el motor no pasa de 30 000 ms y el ciclo completo de 32 000 ms.

### 9.3 `test_report_utils` (ampliado)

- `SENSOR_UNAVAILABLE` con incremento disponible en el resultado → JSON sin `gramos_medidos`, con `order_id`,
  `gramos_solicitados` y `reintentos`.
- Los otros seis motivos conservan los medidos cuando están disponibles.
- `reporteVacio(SENSOR_UNAVAILABLE)` con `order_id` y solicitados → mismo criterio.

### 9.4 Revisión y regresión

- `pio test -e native` con las cuatro suites en verde y la 013 con la única actualización declarada de los dos perfiles
  de retroceso y pausa (§10).
- `pio run -t clean && pio run` en `esp32dev` en SUCCESS, con RAM y Flash anotadas.
- Revisión de código: un único `hx711.begin()`, cero memoria dinámica en el camino de lectura, `dispenser_task.cpp`
  intacto, temporizador de 20 s intacto, `platformio.ini` sin dependencias nuevas.
- `pytest` en `api/` sin cambios (no se toca backend).
- `flutter analyze` no aplica: no hay cambios en la app.

### 9.5 Pruebas físicas (checklist documentado)

- (a) Orden inmediata tras encender: sin servo, cierre `sensor_no_disponible` con `order_id`, sin descuento, log con
  ausencia de asentamiento y consulta siguiente a los 20 s.
- (b) Presión manual sobre la bandeja durante el ciclo: cierre por tope, `plausibilidad_tope` en el log, sin retroceso
  y sin descuento.
- (c) Bandeja cargada por encima de 10 g y retirada a mitad de ciclo: cierre por suelo con `plausibilidad_suelo`.
- (d) Arranque normal y dispensación correcta: 15 lecturas con paso ≤1 g, «objetivo alcanzado» y descuento de lo
  medido.
- No regresión física de la 013: exactitud, frecuencia de 5 Hz, fallo de sensor sin retroceso y atasco resuelto.

## 10. Migración y no regresión

- **Datos:** no hay migración; el cambio es de firmware y no persiste estado nuevo en NVS.
- **013:** se conservan constantes, ventanas, presupuesto, reintentos, retroceso, `CycleLimits`, `verificationBaseline`,
  `DispenseReason` y los textos existentes. **Dos pruebas de la 013 se actualizan de forma declarada**: en
  `test/test_dispensing_cycle/test_dispensing_cycle.cpp` los perfiles `profileTargetInReverse` y
  `profileTargetInPause` saltan hoy a 50 g con una orden de 10 g (tope 30 g), así que con la plausibilidad cerrarían
  por tope en lugar de `COMPLETED`; reducen su salto a un valor plausible —por ejemplo 25 g con orden de 10 g— para
  seguir probando «objetivo en retroceso» y «objetivo en pausa», y se añaden variantes nuevas con un salto por encima
  del tope en esas mismas fases. El resto de las pruebas de la 013 no cambia de resultado esperado. Los tres cambios de
  comportamiento y la consecuencia defensiva (d) están declarados en la spec y se cubren con pruebas nuevas.
- **014:** contrato del reporte, catálogo de causas y reintentos intactos; solo cambia la disponibilidad de
  `gramos_medidos` en el motivo `sensor_no_disponible`, que la spec 016 RF-7 exige.
- **Backend:** sin cambios; `sensor_no_disponible` ya cierra como fallo sin descuento.
- **Despliegue:** un solo firmware; el orden recomendado es desplegar con la bandeja vacía y estable para que la
  primera racha se gane antes de la primera comida programada.

## 11. Trazabilidad RF/RNF → componente → prueba

| Requisito | Componente | Prueba |
|---|---|---|
| RF-1 | `scale_guard_utils.h` (`recordSettlementSample`, `decideDispenseEntry`), `scale_guard_service`, `api_service.cpp` | Nativa de asentamiento y de `decideDispenseEntry`; revisión de que la consulta sigue cada 20 s; física (a) |
| RF-2 | `scale_guard_utils.h` (`assessBaseline`), `dispensing_cycle.h` | Nativa de línea base (par/impar, 1 g vs 1,01 g) y caso feliz del ciclo |
| RF-3 | `assessBaseline`, `CycleDiagnostics.baselineRejection`, `dispensing_service.cpp` | Nativa de `UNSTABLE`, `INSUFFICIENT_READINGS`, `INVALID_BASELINE` y servo inmóvil; log con el motivo |
| RF-4 | `assessBaseline` | Nativa de base 0,0 g aceptada y negativa rechazada |
| RF-5 | `plausibilityTopGrams`, `recordPlausibilitySample`, `dispensing_cycle.h` | Nativa de tope/suelo en tres consecutivas, reinicio, tres fases, sin retroceso ni objetivo |
| RF-6 | `dispensing_cycle.h` (orden de evaluación) | Nativa de prioridad del tope sobre objetivo y atasco, y de incremento plausible con «objetivo alcanzado» |
| RF-7 | `report_utils.h` (`reporteDesdeResultado`), `api_service.cpp` | Nativa de JSON sin `gramos_medidos`; física (a), (b), (c) con log serie |
| RF-8 | `recordSettlementSample`, `invalidateSettlement`, `scale_guard_service`, `api_service.cpp` | Nativa de pérdida por 3 inválidas y por cierre de plausibilidad, y de exigir 15 nuevas |
| RNF-1 | `scale_guard_service` (muestreo 5 Hz), `main.cpp` | Nativa de racha exacta a las 15 lecturas; revisión de que el muestreo está fuera del ciclo; física (d) |
| RNF-2 | `dispensing_cycle.h` | Nativa de cota de 30 s de motor y 32 s de ciclo en los perfiles nuevos |
| RNF-3 | `dispensing_utils.h`, `config.h` | Revisión de las seis constantes en un único lugar y de las tres reutilizadas |
| RNF-4 | `scale_guard_service`, `dispensing_service.cpp` | Revisión de estructuras fijas sin memoria dinámica; inspección del log en español |
| RNF-5 | `test_scale_guard_utils`, `test_dispensing_cycle` | `pio test -e native` en verde sin hardware; física (b), (c), (d) para la celda real |

## 12. Orden de implementación

1. Lógica pura y constantes, con sus pruebas en rojo y en verde (T1).
2. Servicio de muestreo continuo e inicialización única de la celda (T2).
3. Compuerta y cierre sin ciclo en `api_service` (T3).
4. Línea base validada con motivo en el ciclo (T4).
5. Plausibilidad en el ciclo (T5).
6. Invalidación del asentamiento tras cierre por tope, suelo o 3 inválidas (T6).
7. Reporte sin medidos y log del diagnóstico real (T7).
8. Validación nativa completa, trazabilidad y no regresión (T8).
9. Pruebas físicas y `MEMORY.md` (T9).

Dependencias: T2 necesita T1; T3 necesita T2; T4 y T5 necesitan T1 y comparten `dispensing_cycle.h`, así que van en
secuencia; T6 depende de T3 y T5; T7 depende de T5; T8 y T9 cierran el conjunto.
