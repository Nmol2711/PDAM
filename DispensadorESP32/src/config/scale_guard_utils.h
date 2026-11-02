#ifndef SCALE_GUARD_UTILS_H
#define SCALE_GUARD_UTILS_H

#include <cmath>

#include "dispensing_utils.h"

// Lógica pura de la validación de línea base y de la plausibilidad del
// dispensado (Spec 016). Cabecera sin <Arduino.h>: el instante y las lecturas
// entran por parámetro y las constantes viven en dispensing_utils.h (RNF-3),
// de modo que todo se verifica en el entorno nativo (RNF-5).
//
// Cuatro decisiones, sin memoria dinámica ni buffers nuevos:
// - asentamiento de la celda (recordSettlementSample / invalidateSettlement);
// - aceptación de la línea base de la ventana de la 013 (assessBaseline);
// - plausibilidad del incremento (recordPlausibilitySample / resetPlausibility);
// - compuerta de entrada de una orden (decideDispenseEntry).

namespace dispensing {

// --- Asentamiento de la celda (RF-1, RF-2, RF-8, RNF-1) ---

// Resultado de registrar una muestra en el estado de asentamiento.
enum class SettlementOutcome { IN_PROGRESS, GAINED, LOST };

// Estado de tamaño fijo del asentamiento: solo la racha, el contador de
// inválidas consecutivas y la lectura válida anterior en gramos.
struct SettlementState {
  unsigned streak;              // válidas consecutivas con paso acotado
  unsigned consecutiveInvalid;  // inválidas consecutivas
  float previousGrams;          // última lectura válida de la racha
  bool hasPrevious;             // false si no hay lectura anterior en la racha
  bool settled;                 // asentamiento ganado
};

// Registra una lectura del muestreo continuo.
// Una válida alarga la racha y la gana al llegar a kSettlementReadings; un paso
// mayor que kSettlementMaxStepGrams rompe la racha y la reinicia en 1; una
// inválida rompe la racha y suma al contador de inválidas; al acumular
// kMaxConsecutiveInvalidReadings se retira el asentamiento. Solo devuelve
// GAINED al ganarlo y LOST si estaba ganado cuando se pierde.
inline SettlementOutcome recordSettlementSample(SettlementState *state,
                                                const WeightSample &sample) {
  if (state == nullptr) {
    return SettlementOutcome::IN_PROGRESS;
  }

  if (!isReadingValid(sample)) {
    state->streak = 0;
    state->hasPrevious = false;
    ++state->consecutiveInvalid;
    if (state->consecutiveInvalid >= kMaxConsecutiveInvalidReadings) {
      const bool wasSettled = state->settled;
      state->settled = false;
      return wasSettled ? SettlementOutcome::LOST
                        : SettlementOutcome::IN_PROGRESS;
    }
    return SettlementOutcome::IN_PROGRESS;
  }

  state->consecutiveInvalid = 0;

  if (state->hasPrevious &&
      std::fabs(sample.grams - state->previousGrams) >
          kSettlementMaxStepGrams) {
    // Paso inestable: solo se pierde lo que estaba ganado y la racha
    // reinicia en esta misma lectura.
    const bool wasSettled = state->settled;
    state->settled = false;
    state->streak = 1;
    state->previousGrams = sample.grams;
    state->hasPrevious = true;
    return wasSettled ? SettlementOutcome::LOST
                      : SettlementOutcome::IN_PROGRESS;
  }

  ++state->streak;
  state->previousGrams = sample.grams;
  state->hasPrevious = true;

  if (state->streak >= kSettlementReadings && !state->settled) {
    state->settled = true;
    return SettlementOutcome::GAINED;
  }
  return SettlementOutcome::IN_PROGRESS;
}

// Retira el asentamiento y deja el estado como recién arrancado. Se usa al
// iniciar un ciclo y tras un cierre por tope, suelo o 3 inválidas consecutivas.
inline void invalidateSettlement(SettlementState *state) {
  if (state == nullptr) {
    return;
  }
  state->streak = 0;
  state->consecutiveInvalid = 0;
  state->previousGrams = 0.0f;
  state->hasPrevious = false;
  state->settled = false;
}

// Consulta del estado para la compuerta de entrada (RF-1).
inline bool settlementGained(const SettlementState &state) {
  return state.settled;
}

// --- Línea base de la ventana de verificación (RF-2, RF-3, RF-4) ---

// Veredicto de la línea base; INVALID_BASELINE es defensivo y no se alcanza
// con lecturas reales, porque la 013 solo guarda las que pasan isReadingValid.
enum class BaselineVerdict {
  ACCEPTED,
  UNSTABLE,
  INSUFFICIENT_READINGS,
  INVALID_BASELINE
};

// Evalúa la línea base de la ventana de 2 s de la 013.
// La mediana es la de todas las lecturas válidas guardadas; las últimas
// kMinValidReadings válidas solo se usan como condición de estabilidad (paso
// entre lecturas consecutivas). Devuelve ACCEPTED y escribe la mediana en
// baselineOut, o el motivo del rechazo dejando baselineOut intacto.
inline BaselineVerdict assessBaseline(const VerificationState &verification,
                                      float *baselineOut) {
  if (baselineOut == nullptr) {
    return BaselineVerdict::INVALID_BASELINE;
  }

  // Sin las válidas mínimas la ventana no puede sostener una línea base. Con
  // muestras reales storedCount es min(validCount, kMedianBufferSize), así que
  // este primer control cubre también el buffer corto.
  if (verification.validCount < kMinValidReadings) {
    return BaselineVerdict::INSUFFICIENT_READINGS;
  }

  // RF-3: si la mediana no puede calcularse o queda fuera de 0-5000 g, el
  // motivo es linea_base_invalida. El buffer vacío solo aparece en un estado
  // manipulado a mano; con muestras reales es inalcanzable.
  float baseline = 0.0f;
  if (!median(verification.validValues, verification.storedCount, &baseline) ||
      baseline < kMinValidWeightGrams || baseline > kMaxValidWeightGrams) {
    return BaselineVerdict::INVALID_BASELINE;
  }

  // Defensa adicional del plan: la mediana exige las mismas válidas mínimas.
  // Es inalcanzable con kMedianBufferSize >= 16, porque con muestras reales
  // storedCount es min(validCount, kMedianBufferSize) y el primer control ya
  // exige kMinValidReadings válidas. Solo protege un estado manipulado a mano.
  if (verification.storedCount < kMinValidReadings) {
    return BaselineVerdict::INSUFFICIENT_READINGS;
  }

  const unsigned firstIndex = verification.storedCount - kMinValidReadings;
  for (unsigned i = firstIndex; i + 1 < verification.storedCount; ++i) {
    if (std::fabs(verification.validValues[i + 1] -
                  verification.validValues[i]) > kSettlementMaxStepGrams) {
      return BaselineVerdict::UNSTABLE;
    }
  }

  *baselineOut = baseline;
  return BaselineVerdict::ACCEPTED;
}

// Texto del motivo del rechazo para el registro serie (RNF-4).
inline const char *baselineRejectionText(BaselineVerdict verdict) {
  switch (verdict) {
  case BaselineVerdict::ACCEPTED:
    return "aceptada";
  case BaselineVerdict::UNSTABLE:
    return "inestable";
  case BaselineVerdict::INSUFFICIENT_READINGS:
    return "lecturas_insuficientes";
  case BaselineVerdict::INVALID_BASELINE:
    return "linea_base_invalida";
  }
  return "motivo desconocido";
}

// --- Plausibilidad del incremento (RF-5, RF-6) ---

// Veredicto de una lectura del ciclo: PLAUSIBLE mientras el contador de
// lecturas consecutivas fuera del intervalo no alcance el umbral.
enum class PlausibilityVerdict { PLAUSIBLE, ABOVE_TOP, BELOW_FLOOR };

// Estado de tamaño fijo: solo el contador de lecturas consecutivas fuera del
// intervalo [suelo, tope].
struct PlausibilityState {
  unsigned consecutive;
};

// Tope de plausibilidad: el mayor entre kPlausibilityFactor por la cantidad
// solicitada y la cantidad más kPlausibilityMarginGrams.
inline float plausibilityTopGrams(float amountGrams) {
  const float factorTop = kPlausibilityFactor * amountGrams;
  const float marginTop = amountGrams + kPlausibilityMarginGrams;
  return factorTop > marginTop ? factorTop : marginTop;
}

// Deja el contador a cero: al iniciar el ciclo y en toda lectura inválida,
// porque RF-5 exige lecturas válidas consecutivas.
inline void resetPlausibility(PlausibilityState *state) {
  if (state == nullptr) {
    return;
  }
  state->consecutive = 0;
}

// Registra un incremento de una lectura válida del ciclo. Solo se invoca con
// lecturas válidas; un incremento estrictamente mayor que el tope o
// estrictamente menor que el suelo suma al contador y devuelve el cierre al
// llegar a kPlausibilityConsecutiveReadings. Una lectura dentro del intervalo
// reinicia el contador.
inline PlausibilityVerdict
recordPlausibilitySample(PlausibilityState *state, float incrementGrams,
                         float amountGrams) {
  if (state == nullptr) {
    return PlausibilityVerdict::PLAUSIBLE;
  }

  const float topGrams = plausibilityTopGrams(amountGrams);
  PlausibilityVerdict outside = PlausibilityVerdict::PLAUSIBLE;
  if (incrementGrams > topGrams) {
    outside = PlausibilityVerdict::ABOVE_TOP;
  } else if (incrementGrams < kPlausibilityFloorGrams) {
    outside = PlausibilityVerdict::BELOW_FLOOR;
  }

  if (outside == PlausibilityVerdict::PLAUSIBLE) {
    state->consecutive = 0;
    return PlausibilityVerdict::PLAUSIBLE;
  }

  ++state->consecutive;
  if (state->consecutive >= kPlausibilityConsecutiveReadings) {
    return outside;
  }
  return PlausibilityVerdict::PLAUSIBLE;
}

// Texto de la causa del cierre por plausibilidad para el registro serie.
inline const char *plausibilityCauseText(PlausibilityVerdict verdict) {
  switch (verdict) {
  case PlausibilityVerdict::PLAUSIBLE:
    return "incremento_plausible";
  case PlausibilityVerdict::ABOVE_TOP:
    return "plausibilidad_tope";
  case PlausibilityVerdict::BELOW_FLOOR:
    return "plausibilidad_suelo";
  }
  return "motivo desconocido";
}

// --- Compuerta de entrada (RF-1) ---

// Decisión de entrada de una orden de la API: la compuerta solo impide abrir
// una dispensación sin asentamiento; el resto de acciones no cambia.
enum class DispenseEntry {
  REST,
  DISPENSE,
  RESET_WIFI,
  REJECT_ORDER,
  REJECT_NO_SETTLEMENT
};

inline DispenseEntry decideDispenseEntry(OrderAction action, bool settled) {
  switch (action) {
  case OrderAction::REST:
    return DispenseEntry::REST;
  case OrderAction::DISPENSE:
    return settled ? DispenseEntry::DISPENSE
                   : DispenseEntry::REJECT_NO_SETTLEMENT;
  case OrderAction::RESET_WIFI:
    return DispenseEntry::RESET_WIFI;
  case OrderAction::INVALID_ORDER:
    return DispenseEntry::REJECT_ORDER;
  }
  return DispenseEntry::REST;
}

} // namespace dispensing

#endif // SCALE_GUARD_UTILS_H
