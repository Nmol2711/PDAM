#ifndef DISPENSING_UTILS_H
#define DISPENSING_UTILS_H

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>

// Límites y tiempos del dispensado por peso (Spec 013).
// Cabecera pura: no incluye <Arduino.h> para poder probarse en el entorno nativo.
// Es la única fuente de estos valores; config.h la incluye y no los duplica.

// Ventana fija de verificación previa al giro (2 s), no reiniciable.
constexpr unsigned long kVerificationWindowMs = 2000;

// Periodo máximo entre intentos de lectura (5 Hz efectivos).
constexpr unsigned long kSamplePeriodMs = 200;

// Plazo máximo de respuesta de una lectura de la celda.
constexpr unsigned long kReadTimeoutMs = 100;

// Tiempo máximo de giro del servomotor desde su arranque.
constexpr unsigned long kMaxRotationMs = 30000;

// Lecturas válidas mínimas dentro de la ventana de verificación.
constexpr unsigned kMinValidReadings = 5;

// Lecturas inválidas consecutivas que abortan la verificación o el giro.
constexpr unsigned kMaxConsecutiveInvalidReadings = 3;

// Lecturas consecutivas sobre el objetivo necesarias para detener el servo.
constexpr unsigned kConsecutiveTargetReadings = 3;

// Rango de peso considerado válido.
constexpr float kMinValidWeightGrams = 0.0f;
constexpr float kMaxValidWeightGrams = 5000.0f;

// Extremos del ADC de 24 bits del HX711; en ellos la lectura está saturada.
constexpr long kRawSaturationMin = -8388608L;
constexpr long kRawSaturationMax = 8388607L;

// Muestras válidas que se conservan para calcular la mediana.
constexpr unsigned kMedianBufferSize = 16;

namespace dispensing {

// Acción a ejecutar a partir de la respuesta de la API (RF-1, RF-2, RF-10).
enum class OrderAction { REST, DISPENSE, RESET_WIFI, INVALID_ORDER };

// Motivo de finalización de una dispensación (RF-12).
enum class DispenseReason {
  COMPLETED,
  NOT_REACHED,
  SENSOR_UNAVAILABLE,
  SENSOR_FAILURE,
  INVALID_CONFIG,
  INVALID_AMOUNT
};

// Una lectura de la celda: si respondió, el valor en bruto y su conversión.
struct WeightSample {
  bool responded;
  long raw;
  float grams;
};

// Resultado de una dispensación con banderas de disponibilidad (RF-12).
struct DispenseResult {
  float requestedGrams;
  DispenseReason reason;
  bool baselineAvailable;
  float baselineGrams;
  bool finalAvailable;
  float finalGrams;
  bool incrementAvailable;
  float incrementGrams;
};

// reset_wifi tiene prioridad absoluta; después decide serve y amount.
inline OrderAction classifyOrder(bool resetWifi, bool serve, bool amountPresent,
                                 bool amountNumeric, float amount) {
  if (resetWifi) {
    return OrderAction::RESET_WIFI;
  }
  if (!serve) {
    return OrderAction::REST;
  }
  if (!amountPresent || !amountNumeric) {
    return OrderAction::INVALID_ORDER;
  }
  if (amount < 0.0f) {
    return OrderAction::INVALID_ORDER;
  }
  if (amount == 0.0f) {
    return OrderAction::REST;
  }
  return OrderAction::DISPENSE;
}

// El factor debe ser finito y positivo (RF-11).
inline bool isCalibrationFactorValid(float factor) {
  return std::isfinite(factor) && factor > 0.0f;
}

// El ADC de 24 bits está saturado en sus dos extremos.
inline bool isRawSaturated(long raw) {
  return raw <= kRawSaturationMin || raw >= kRawSaturationMax;
}

// Conversión calibrada; un factor inválido produce NaN sin recortar.
inline float convertRawToGrams(long raw, float factor, float sign) {
  if (!isCalibrationFactorValid(factor)) {
    return NAN;
  }
  return (static_cast<float>(raw) * sign) / factor;
}

inline WeightSample makeSample(bool responded, long raw, float factor,
                               float sign) {
  WeightSample sample;
  sample.responded = responded;
  sample.raw = raw;
  sample.grams = responded ? convertRawToGrams(raw, factor, sign) : 0.0f;
  return sample;
}

// Lectura válida: respondió, gramos finitos en 0-5000 g y raw sin saturar.
inline bool isReadingValid(const WeightSample &sample) {
  return sample.responded && std::isfinite(sample.grams) &&
         sample.grams >= kMinValidWeightGrams &&
         sample.grams <= kMaxValidWeightGrams && !isRawSaturated(sample.raw);
}

namespace detail {

// k-ésimo valor ordenado (1-based) sin modificar el array ni reservar memoria.
inline float orderStatistic(const float *values, unsigned count, unsigned k) {
  for (unsigned i = 0; i < count; ++i) {
    const float candidate = values[i];
    unsigned less = 0;
    unsigned lessOrEqual = 0;
    for (unsigned j = 0; j < count; ++j) {
      if (values[j] < candidate) {
        ++less;
      }
      if (values[j] <= candidate) {
        ++lessOrEqual;
      }
    }
    if (less < k && k <= lessOrEqual) {
      return candidate;
    }
  }
  return values[0];
}

} // namespace detail

// Mediana sin modificar la entrada; en un número par promedia los centrales.
inline bool median(const float *values, unsigned count, float *out) {
  if (values == nullptr || count == 0 || out == nullptr) {
    return false;
  }
  if (count % 2 == 1) {
    *out = detail::orderStatistic(values, count, count / 2 + 1);
  } else {
    const float lower = detail::orderStatistic(values, count, count / 2);
    const float upper = detail::orderStatistic(values, count, count / 2 + 1);
    *out = (lower + upper) / 2.0f;
  }
  return true;
}

// Resultado de la ventana fija de verificacion previa al giro (RF-3, RF-4).
enum class VerificationOutcome {
  IN_PROGRESS,
  PASSED,
  WINDOW_EXPIRED,
  ABORTED_BY_INVALID
};

// Estado acumulado de la ventana de verificacion. El instante entra por
// parametro: la logica no lee millis() ni depende de Arduino.
struct VerificationState {
  unsigned long startMs;
  float validValues[kMedianBufferSize];
  unsigned validCount;      // total de validas en la ventana
  unsigned storedCount;     // valores guardados (max. kMedianBufferSize)
  unsigned consecutiveInvalid;
  bool finished;
  VerificationOutcome outcome;
};

// Abre la ventana fija de 2 s y reinicia los contadores.
inline void startVerification(VerificationState *state, unsigned long nowMs) {
  if (state == nullptr) {
    return;
  }
  state->startMs = nowMs;
  state->validCount = 0;
  state->storedCount = 0;
  state->consecutiveInvalid = 0;
  state->finished = false;
  state->outcome = VerificationOutcome::IN_PROGRESS;
}

// Registra una muestra de la ventana de verificacion.
// La ventana se cierra por tiempo ANTES de admitir la muestra, de modo que
// una lectura tomada en o despues de los 2 s no se registra ni extiende el
// plazo. Una invalida aislada no reinicia la ventana ni borra las validas.
inline VerificationOutcome
recordVerificationSample(VerificationState *state, const WeightSample &sample,
                         unsigned long nowMs) {
  if (state == nullptr) {
    return VerificationOutcome::IN_PROGRESS;
  }
  if (state->finished) {
    return state->outcome;
  }

  if (nowMs - state->startMs >= kVerificationWindowMs) {
    state->finished = true;
    if (state->validCount >= kMinValidReadings &&
        state->consecutiveInvalid < kMaxConsecutiveInvalidReadings) {
      state->outcome = VerificationOutcome::PASSED;
    } else {
      state->outcome = VerificationOutcome::WINDOW_EXPIRED;
    }
    return state->outcome;
  }

  if (isReadingValid(sample)) {
    if (state->storedCount < kMedianBufferSize) {
      state->validValues[state->storedCount] = sample.grams;
      ++state->storedCount;
    }
    ++state->validCount;
    state->consecutiveInvalid = 0;
  } else {
    ++state->consecutiveInvalid;
    if (state->consecutiveInvalid >= kMaxConsecutiveInvalidReadings) {
      state->finished = true;
      state->outcome = VerificationOutcome::ABORTED_BY_INVALID;
      return state->outcome;
    }
  }

  state->outcome = VerificationOutcome::IN_PROGRESS;
  return state->outcome;
}

// Linea base: mediana de las validas guardadas de la ventana (RF-3).
inline bool verificationBaseline(const VerificationState *state, float *out) {
  if (state == nullptr || out == nullptr || state->storedCount == 0) {
    return false;
  }
  return median(state->validValues, state->storedCount, out);
}

// Peso objetivo en la balanza: línea base más la cantidad solicitada.
inline float targetGrams(float baseline, float amount) {
  return baseline + amount;
}

// Resultado de la maquina de estado del giro (RF-6, RF-7, RF-8, RF-9).
enum class RotationOutcome {
  CONTINUE,
  TARGET_REACHED,
  SENSOR_FAILURE,
  TIME_LIMIT
};

// Estado acumulado del giro. El instante entra por parametro: la logica no lee
// millis() ni depende de Arduino.
struct RotationState {
  unsigned long startMs;
  unsigned consecutiveInvalid;
  unsigned consecutiveTarget;
  bool hasLastValid;
  float lastValidGrams;
  bool finished;
  RotationOutcome outcome;
};

// Inicia el giro y reinicia los contadores.
inline void startRotation(RotationState *state, unsigned long nowMs) {
  if (state == nullptr) {
    return;
  }
  state->startMs = nowMs;
  state->consecutiveInvalid = 0;
  state->consecutiveTarget = 0;
  state->hasLastValid = false;
  state->lastValidGrams = 0.0f;
  state->finished = false;
  state->outcome = RotationOutcome::CONTINUE;
}

// Registra una muestra del giro.
// El tope de tiempo se comprueba ANTES de admitir la muestra, de modo que una
// lectura tomada en o despues de los 30 s no se registra. La tercera invalida
// consecutiva detiene el ciclo sin esperar el tiempo limite (RF-9).
inline RotationOutcome recordRotationSample(RotationState *state,
                                            const WeightSample &sample,
                                            unsigned long nowMs, float baseline,
                                            float amount) {
  if (state == nullptr) {
    return RotationOutcome::CONTINUE;
  }
  if (state->finished) {
    return state->outcome;
  }

  if (nowMs - state->startMs >= kMaxRotationMs) {
    state->finished = true;
    state->outcome = RotationOutcome::TIME_LIMIT;
    return state->outcome;
  }

  if (!isReadingValid(sample)) {
    ++state->consecutiveInvalid;
    state->consecutiveTarget = 0;
    if (state->consecutiveInvalid >= kMaxConsecutiveInvalidReadings) {
      state->finished = true;
      state->outcome = RotationOutcome::SENSOR_FAILURE;
      return state->outcome;
    }
    state->outcome = RotationOutcome::CONTINUE;
    return state->outcome;
  }

  state->consecutiveInvalid = 0;
  state->lastValidGrams = sample.grams;
  state->hasLastValid = true;

  if (sample.grams >= targetGrams(baseline, amount)) {
    ++state->consecutiveTarget;
    if (state->consecutiveTarget >= kConsecutiveTargetReadings) {
      state->finished = true;
      state->outcome = RotationOutcome::TARGET_REACHED;
      return state->outcome;
    }
  } else {
    state->consecutiveTarget = 0;
  }

  state->outcome = RotationOutcome::CONTINUE;
  return state->outcome;
}

// Traslada la linea base y la ultima lectura valida del giro al resultado de la
// dispensacion, calculando el incremento solo cuando hay linea base (RF-12).
// No modifica la cantidad solicitada ni el motivo, que fija el servicio.
inline void fillDispenseMeasurements(DispenseResult *result,
                                     bool baselineAvailable,
                                     float baselineGrams,
                                     const RotationState &rotation) {
  if (result == nullptr) {
    return;
  }

  result->baselineAvailable = baselineAvailable;
  result->baselineGrams = baselineAvailable ? baselineGrams : 0.0f;

  if (!rotation.hasLastValid) {
    result->finalAvailable = false;
    result->finalGrams = 0.0f;
    result->incrementAvailable = false;
    result->incrementGrams = 0.0f;
    return;
  }

  result->finalAvailable = true;
  result->finalGrams = rotation.lastValidGrams;

  if (baselineAvailable) {
    result->incrementAvailable = true;
    result->incrementGrams = rotation.lastValidGrams - baselineGrams;
  } else {
    // Sin linea base no es posible atribuir el incremento (RF-12).
    result->incrementAvailable = false;
    result->incrementGrams = 0.0f;
  }
}

// Vencimiento del temporizador periodico. La resta se hace en 32 bits para
// reproducir el rollover de millis() del ESP32 tambien en el entorno nativo.
inline bool isCheckDue(unsigned long lastCheckMs, unsigned long nowMs,
                       unsigned long intervalMs) {
  const unsigned long elapsed = static_cast<unsigned long>(
      static_cast<std::uint32_t>(nowMs) -
      static_cast<std::uint32_t>(lastCheckMs));
  return elapsed >= intervalMs;
}

// Texto del motivo para el registro serie (RNF-5: español, sin emojis).
inline const char *dispenseReasonText(DispenseReason reason) {
  switch (reason) {
  case DispenseReason::COMPLETED:
    return "objetivo alcanzado";
  case DispenseReason::NOT_REACHED:
    return "objetivo no alcanzado";
  case DispenseReason::SENSOR_UNAVAILABLE:
    return "sensor no disponible";
  case DispenseReason::SENSOR_FAILURE:
    return "fallo del sensor durante la dispensacion";
  case DispenseReason::INVALID_CONFIG:
    return "configuracion invalida: factor de calibracion no positivo";
  case DispenseReason::INVALID_AMOUNT:
    return "orden de dispensacion invalida";
  }
  return "motivo desconocido";
}

namespace detail {

inline void formatWeightField(char *out, std::size_t size, bool available,
                              float grams) {
  if (available) {
    std::snprintf(out, size, "%.1f g", grams);
  } else {
    std::snprintf(out, size, "no disponible");
  }
}

} // namespace detail

// Una línea de registro con "no disponible" en los valores ausentes.
// Si el buffer no es usable no escribe nada; no informa del resultado.
inline void formatDispenseLog(const DispenseResult &result, char *buffer,
                              std::size_t size) {
  if (buffer == nullptr || size == 0) {
    return;
  }

  char baseline[32];
  char finalWeight[32];
  char increment[32];
  detail::formatWeightField(baseline, sizeof(baseline),
                            result.baselineAvailable, result.baselineGrams);
  detail::formatWeightField(finalWeight, sizeof(finalWeight),
                            result.finalAvailable, result.finalGrams);
  detail::formatWeightField(increment, sizeof(increment),
                            result.incrementAvailable, result.incrementGrams);

  std::snprintf(buffer, size,
                "Despacho: solicitado=%.1f g, linea_base=%s, peso_final=%s, "
                "incremento=%s, motivo=%s",
                result.requestedGrams, baseline, finalWeight, increment,
                dispenseReasonText(result.reason));
}

} // namespace dispensing

#endif // DISPENSING_UTILS_H
