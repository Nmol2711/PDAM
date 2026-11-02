#ifndef DISPENSING_CYCLE_H
#define DISPENSING_CYCLE_H

#include <cstdint>

#include "dispensing_utils.h"
#include "scale_guard_utils.h"

// Ciclo completo de dispensado por peso como unidad pura (Spec 013).
// Cabecera sin <Arduino.h>: el servo, la celda, el reloj y la espera se inyectan
// como punteros a función, de modo que RF-17 se verifica en el entorno nativo con
// un servo simulado (decisión 20 del plan). No imprime ni inicializa hardware.

namespace dispensing {

// Fase del ciclo de motor. El avance empuja el alimento; el retroceso y la pausa
// forman el reintento de desatasco (RF-15).
enum class MotorPhase { ADVANCE, REVERSE, PAUSE };

// Puertos del ciclo: contexto opaco y seis operaciones. Sin memoria dinámica ni
// métodos virtuales.
struct CyclePorts {
  void *context;
  void (*startAdvance)(void *context);
  void (*startReverse)(void *context);
  void (*stop)(void *context);
  bool (*readRaw)(void *context, long *rawOut, unsigned long timeoutMs);
  unsigned long (*nowMs)(void *context);
  void (*waitUntil)(void *context, unsigned long deadlineMs);
};

// Veredicto de la línea base al cerrar la ventana de verificación, con un valor
// «sin veredicto» para el aborto por 3 lecturas inválidas consecutivas: en ese
// camino la base no llega a evaluarse (RF-4 de la 013, RF-8). Los otros cuatro
// valores son los de BaselineVerdict de scale_guard_utils.h; se nombran aquí
// porque NOT_EVALUATED no existe en el veredicto puro (Spec 016).
enum class BaselineStatus {
  NOT_EVALUATED,
  ACCEPTED,
  UNSTABLE,
  INSUFFICIENT_READINGS,
  INVALID_BASELINE
};

// Texto en español del estado de la línea base para el registro serie (RNF-4).
// Los cuatro veredictos reales delegan en baselineRejectionText() para no
// duplicar sus textos.
inline const char *baselineStatusText(BaselineStatus status) {
  switch (status) {
  case BaselineStatus::ACCEPTED:
    return baselineRejectionText(BaselineVerdict::ACCEPTED);
  case BaselineStatus::UNSTABLE:
    return baselineRejectionText(BaselineVerdict::UNSTABLE);
  case BaselineStatus::INSUFFICIENT_READINGS:
    return baselineRejectionText(BaselineVerdict::INSUFFICIENT_READINGS);
  case BaselineStatus::INVALID_BASELINE:
    return baselineRejectionText(BaselineVerdict::INVALID_BASELINE);
  case BaselineStatus::NOT_EVALUATED:
    return "sin_veredicto";
  }
  return "sin_veredicto";
}

// Diagnóstico de la ventana de verificación, para que el servicio lo imprima
// como hasta ahora cuando no se supera (RF-4).
struct CycleDiagnostics {
  unsigned samples;            // lecturas realmente intentadas
  unsigned responded;          // lecturas con respuesta de la celda
  unsigned valid;              // lecturas válidas de la ventana
  unsigned consecutiveInvalid; // inválidas consecutivas al cerrar la ventana
  long lastRaw;                // último valor en bruto respondido
  float lastGrams;             // últimos gramos respondidos
  bool hasLastReading;         // false si nunca respondió
  BaselineStatus baselineRejection; // veredicto de la base; NOT_EVALUATED si la
                                    // ventana se abortó por inválidas
  bool hasBaseline;            // mediana de todas las válidas calculable
  float baselineGrams;         // mediana de todas las válidas (solo log)
  PlausibilityVerdict plausibility; // cierre por plausibilidad; PLAUSIBLE si el
                                    // ciclo no se cerró por incremento imposible
  float topGrams;              // tope de plausibilidad de la orden (solo log)
  float maxIncrementGrams;     // mayor incremento observado del ciclo de motor,
                               // incluido un ciclo íntegramente negativo (solo log)
};

// Límites del ciclo de motor. Los valores por defecto son exactamente las
// constantes aprobadas (kMotorBudgetMs y kMaxStallRetries), que siguen siendo la
// única fuente de los valores de producción (RNF-7).
//
// Punto de inyección exclusivo para pruebas: con los umbrales aprobados las
// ramas de «no retroceder» (sin reintentos disponibles o sin presupuesto para el
// reintento) solo se alcanzan tras 30 s de ciclo, de modo que sin él quedarían
// sin cobertura. El servicio llama a runDispenseCycle sin este parámetro, así que
// producción conserva el comportamiento idéntico; nunca debe usarse para
// cambiarlo. Las pruebas solo lo reducen, nunca lo amplían por encima de
// kMotorBudgetMs.
struct CycleLimits {
  unsigned long motorBudgetMs = kMotorBudgetMs;
  unsigned maxRetries = kMaxStallRetries;
};

namespace detail {

// Un vencimiento absoluto se alcanza cuando el instante actual lo iguala o lo
// supera. La resta se hace en 32 bits para tolerar el desbordamiento de millis().
inline bool deadlineReached(unsigned long nowMs, unsigned long deadlineMs) {
  const std::uint32_t diff =
      static_cast<std::uint32_t>(nowMs) - static_cast<std::uint32_t>(deadlineMs);
  return diff < 0x80000000UL;
}

// Milisegundos que faltan para el vencimiento (0 si ya venció).
inline unsigned long remainingMs(unsigned long nowMs,
                                 unsigned long deadlineMs) {
  return static_cast<unsigned long>(static_cast<std::uint32_t>(deadlineMs) -
                                    static_cast<std::uint32_t>(nowMs));
}

// Devuelve el vencimiento más cercano entre dos instantes absolutos.
inline unsigned long earlierDeadline(unsigned long firstMs,
                                     unsigned long secondMs) {
  return deadlineReached(firstMs, secondMs) ? secondMs : firstMs;
}

// Formas parametrizadas del presupuesto de motor, equivalentes a
// motorBudgetRemainingMs() e isMotorBudgetExhausted() de dispensing_utils.h pero
// con el presupuesto del ciclo: así el bucle y la decisión de desatasco usan
// CycleLimits y las constantes aprobadas solo aportan el valor por defecto.
inline unsigned long budgetRemainingMs(unsigned long startMs,
                                       unsigned long nowMs,
                                       unsigned long budgetMs) {
  const unsigned long elapsed = elapsedMs(startMs, nowMs);
  return elapsed >= budgetMs ? 0 : budgetMs - elapsed;
}

inline bool budgetExhausted(unsigned long startMs, unsigned long nowMs,
                            unsigned long budgetMs) {
  return elapsedMs(startMs, nowMs) >= budgetMs;
}

// Muestra no respondida: cierra una ventana o un ciclo por tiempo sin iniciar
// una lectura que pudiera exceder el plazo.
inline WeightSample unavailableSample(float factor, float sign) {
  return makeSample(false, 0, factor, sign);
}

// Traslada el veredicto puro de la línea base al estado del diagnóstico.
inline BaselineStatus baselineStatusOf(BaselineVerdict verdict) {
  switch (verdict) {
  case BaselineVerdict::ACCEPTED:
    return BaselineStatus::ACCEPTED;
  case BaselineVerdict::UNSTABLE:
    return BaselineStatus::UNSTABLE;
  case BaselineVerdict::INSUFFICIENT_READINGS:
    return BaselineStatus::INSUFFICIENT_READINGS;
  case BaselineVerdict::INVALID_BASELINE:
    return BaselineStatus::INVALID_BASELINE;
  }
  return BaselineStatus::NOT_EVALUATED;
}

} // namespace detail

// Alimenta la mediana móvil y el máximo observado sin evaluar atascos.
// En retroceso y pausa se sigue midiendo el peso (RF-6 y definición de máximo
// observado), pero el tornillo no empuja y el progreso no se interpreta
// (decisión 23).
inline void feedMovingMedian(StallState *state, const WeightSample &sample) {
  if (state == nullptr || !pushMovingMedian(&state->median, sample)) {
    return;
  }
  float medianGrams = 0.0f;
  if (movingMedianValue(&state->median, &medianGrams)) {
    updateMaxObserved(&state->observedMax, medianGrams);
  }
}

// Decisión de desatasco con el tope de reintentos del ciclo. Solo el contador se
// parametriza: el presupuesto mínimo sigue en decideStallAction() para no
// duplicar la regla aprobada (RF-15, RF-16).
inline StallAction decideStallAction(unsigned retriesDone,
                                     unsigned long remainingBudgetMs,
                                     const CycleLimits &limits) {
  if (retriesDone >= limits.maxRetries) {
    return StallAction::GIVE_UP;
  }
  return decideStallAction(retriesDone, remainingBudgetMs);
}

// Ejecuta el ciclo completo: valida las entradas, verifica la celda durante 2 s,
// acepta la línea base solo con 5 válidas y paso de 1 g como máximo entre las
// últimas 5, avanza, mide en las tres fases, cierra por incremento imposible
// antes que por objetivo o atasco, resuelve atascos dentro del presupuesto de
// motor y detiene el servo en toda salida (RF-5 a RF-9, RF-12, RF-14 a RF-17,
// RNF-1, RNF-3; RF-2 a RF-8 de la 016).
inline DispenseResult runDispenseCycle(const CyclePorts &ports,
                                       float amountGrams, float factor,
                                       float sign,
                                       CycleDiagnostics *diagnostics,
                                       const CycleLimits &limits =
                                           CycleLimits{}) {
  DispenseResult result{};
  result.requestedGrams = amountGrams;
  result.reason = DispenseReason::SENSOR_UNAVAILABLE;
  result.baselineAvailable = false;
  result.baselineGrams = 0.0f;
  result.finalAvailable = false;
  result.finalGrams = 0.0f;
  result.incrementAvailable = false;
  result.incrementGrams = 0.0f;
  result.retryCount = 0;

  if (diagnostics != nullptr) {
    *diagnostics = CycleDiagnostics{};
  }

  // RF-11: sin factor positivo no se toca la celda ni el servo.
  if (!isCalibrationFactorValid(factor)) {
    result.reason = DispenseReason::INVALID_CONFIG;
    return result;
  }

  // Cantidad no positiva o no numérica (NaN): tampoco se toca el hardware
  // (RF-2, RF-17).
  if (!(amountGrams > 0.0f)) {
    result.reason = DispenseReason::INVALID_AMOUNT;
    return result;
  }

  // Sin los puertos necesarios no hay ciclo posible; el servo no se toca.
  if (ports.startAdvance == nullptr || ports.startReverse == nullptr ||
      ports.stop == nullptr || ports.readRaw == nullptr ||
      ports.nowMs == nullptr || ports.waitUntil == nullptr) {
    result.reason = DispenseReason::INVALID_CONFIG;
    return result;
  }

  // --- Ventana fija de verificación de 2 s, no reiniciable (RF-3, RF-4) ---
  VerificationState verification;
  startVerification(&verification, ports.nowMs(ports.context));
  const unsigned long verificationDeadlineMs =
      verification.startMs + kVerificationWindowMs;
  unsigned long nextSampleMs = verification.startMs;
  // Solo se conserva para la guarda del aborto por inválidas: sobre la ventana
  // agotada por tiempo decide assessBaseline (Spec 016).
  VerificationOutcome verificationOutcome = VerificationOutcome::IN_PROGRESS;

  while (true) {
    const unsigned long now = ports.nowMs(ports.context);

    // Vencimiento: se cierra con una muestra no respondida, que no altera el
    // número de válidas ni extiende la ventana.
    if (detail::deadlineReached(now, verificationDeadlineMs)) {
      verificationOutcome = recordVerificationSample(
          &verification, detail::unavailableSample(factor, sign),
          ports.nowMs(ports.context));
      break;
    }

    // No se inicia una lectura que pudiera terminar después del vencimiento.
    if (detail::remainingMs(now, verificationDeadlineMs) <= kReadTimeoutMs) {
      ports.waitUntil(ports.context, verificationDeadlineMs);
      verificationOutcome = recordVerificationSample(
          &verification, detail::unavailableSample(factor, sign),
          ports.nowMs(ports.context));
      break;
    }

    if (detail::deadlineReached(now, nextSampleMs)) {
      long raw = 0;
      const bool responded = ports.readRaw(ports.context, &raw, kReadTimeoutMs);
      const unsigned long sampleTimeMs = ports.nowMs(ports.context);
      const WeightSample sample = makeSample(responded, raw, factor, sign);

      if (diagnostics != nullptr) {
        ++diagnostics->samples;
        if (responded) {
          ++diagnostics->responded;
          diagnostics->lastRaw = raw;
          diagnostics->lastGrams = sample.grams;
          diagnostics->hasLastReading = true;
        }
      }

      verificationOutcome =
          recordVerificationSample(&verification, sample, sampleTimeMs);
      if (verificationOutcome != VerificationOutcome::IN_PROGRESS) {
        break;
      }

      nextSampleMs += kSamplePeriodMs;
    }

    const unsigned long wakeMs =
        detail::earlierDeadline(nextSampleMs, verificationDeadlineMs);
    if (!detail::deadlineReached(ports.nowMs(ports.context), wakeMs)) {
      ports.waitUntil(ports.context, wakeMs);
    }
  }

  if (diagnostics != nullptr) {
    diagnostics->valid = verification.validCount;
    diagnostics->consecutiveInvalid = verification.consecutiveInvalid;
  }

  // Guarda previa obligatoria (RF-4 de la 013, RF-8): el break del bucle de
  // verificación no distingue el motivo y cae aquí, así que una ventana abortada
  // por 3 inválidas consecutivas no evalúa la línea base. Sin esta guarda,
  // assessBaseline aceptaría la base de una ventana abortada en cuanto hubiera 5
  // válidas ya guardadas. El cierre es el de la 013 y no produce veredicto.
  if (verificationOutcome == VerificationOutcome::ABORTED_BY_INVALID) {
    ports.stop(ports.context);
    result.reason = DispenseReason::SENSOR_UNAVAILABLE;
    return result;
  }

  // RF-4 de la 013 y RF-2, RF-3, RF-4 de la 016: nunca dispensar a ciegas. Esta
  // evaluación sustituye a la comprobación `verificationOutcome != PASSED` de la
  // 013 y exige, además de 5 válidas, una mediana en rango y un paso de 1 g como
  // máximo entre las últimas 5 válidas. Desde el ciclo solo son alcanzables
  // UNSTABLE e INSUFFICIENT_READINGS; INVALID_BASELINE es defensivo.
  float baseline = 0.0f;
  const BaselineVerdict verdict = assessBaseline(verification, &baseline);

  if (diagnostics != nullptr) {
    diagnostics->baselineRejection = detail::baselineStatusOf(verdict);
    // Mediana de todas las válidas solo para el log del servicio: se muestra
    // aunque el veredicto la rechace, para que el operador vea con qué base se
    // decidió. No interviene en la decisión.
    diagnostics->hasBaseline =
        verificationBaseline(&verification, &diagnostics->baselineGrams);
  }

  if (verdict != BaselineVerdict::ACCEPTED) {
    ports.stop(ports.context);
    result.reason = DispenseReason::SENSOR_UNAVAILABLE;
    return result;
  }

  // --- Ciclo de motor con presupuesto absoluto (RF-5, RF-8, RNF-3) ---
  // El presupuesto se cuenta desde el primer arranque del avance e incluye
  // retrocesos y pausas.
  const unsigned long budgetStartMs = ports.nowMs(ports.context);
  ports.startAdvance(ports.context);

  RotationState rotation;
  startRotation(&rotation, budgetStartMs);
  StallState stall;
  startAdvance(&stall, budgetStartMs);

  // Contador de plausibilidad del incremento en cero al abrir el ciclo de motor
  // (RF-5). El estado es de tamaño fijo y no reserva memoria (RNF-4).
  PlausibilityState plausibility;
  resetPlausibility(&plausibility);
  // Mayor incremento observado del ciclo. Arranca con el primer incremento válido
  // (bandera hasIncrement) y no con cero, de modo que un ciclo íntegramente
  // negativo informe del menos negativo y no de un 0 que nunca se midió. Solo
  // alimenta el log: no interviene en ninguna decisión.
  float maxIncrementGrams = 0.0f;
  bool hasIncrement = false;

  const unsigned long budgetDeadlineMs = budgetStartMs + limits.motorBudgetMs;
  MotorPhase phase = MotorPhase::ADVANCE;
  unsigned long phaseDeadlineMs = 0;
  nextSampleMs = budgetStartMs;
  DispenseReason reason = DispenseReason::NOT_REACHED;

  while (true) {
    const unsigned long now = ports.nowMs(ports.context);

    // Cota estricta del ciclo de motor: avances, retrocesos y pausas.
    if (detail::budgetExhausted(budgetStartMs, now, limits.motorBudgetMs)) {
      reason = budgetExhaustedReason(stall.stallPending);
      break;
    }

    // Transiciones de la secuencia de desatasco (RF-15).
    if (phase == MotorPhase::REVERSE &&
        detail::deadlineReached(now, phaseDeadlineMs)) {
      ports.stop(ports.context);
      phase = MotorPhase::PAUSE;
      phaseDeadlineMs = now + kPauseMs;
    } else if (phase == MotorPhase::PAUSE &&
               detail::deadlineReached(now, phaseDeadlineMs)) {
      // El reintento se cuenta al reanudar el avance (RF-12, decisión 21).
      ports.startAdvance(ports.context);
      resumeAdvanceAfterRetry(&stall, now);
      phase = MotorPhase::ADVANCE;
      phaseDeadlineMs = 0;
      nextSampleMs = now;
    }

    const unsigned long budgetLeftMs = detail::budgetRemainingMs(
        budgetStartMs, now, limits.motorBudgetMs);

    // Muestreo cada 200 ms con vencimientos absolutos, en las tres fases
    // (RNF-1). No se inicia una lectura que pudiera cruzar el presupuesto.
    if (budgetLeftMs > kReadTimeoutMs &&
        detail::deadlineReached(now, nextSampleMs)) {
      long raw = 0;
      const bool responded = ports.readRaw(ports.context, &raw, kReadTimeoutMs);
      const unsigned long sampleTimeMs = ports.nowMs(ports.context);
      const WeightSample sample = makeSample(responded, raw, factor, sign);

      // RF-5 y RF-6: la plausibilidad del incremento se evalúa en las tres fases
      // y antes del objetivo y del atasco, de modo que el cierre por incremento
      // imposible gana a ambos. Una lectura inválida reinicia el contador porque
      // RF-5 exige tres lecturas VÁLIDAS consecutivas.
      PlausibilityVerdict plausibilityVerdict = PlausibilityVerdict::PLAUSIBLE;
      if (isReadingValid(sample)) {
        const float incrementGrams = sample.grams - baseline;
        // El primer incremento válido fija el máximo aunque sea negativo; los
        // siguientes solo lo elevan si son mayores.
        if (!hasIncrement || incrementGrams > maxIncrementGrams) {
          maxIncrementGrams = incrementGrams;
          hasIncrement = true;
        }
        plausibilityVerdict = recordPlausibilitySample(
            &plausibility, incrementGrams, amountGrams);
      } else {
        resetPlausibility(&plausibility);
      }

      if (plausibilityVerdict != PlausibilityVerdict::PLAUSIBLE) {
        if (diagnostics != nullptr) {
          diagnostics->plausibility = plausibilityVerdict;
          diagnostics->topGrams = plausibilityTopGrams(amountGrams);
          diagnostics->maxIncrementGrams = maxIncrementGrams;
        }
        // El peso final se conserva para el log serie; el reporte lo omitirá
        // porque el motivo es SENSOR_UNAVAILABLE (RF-7).
        rotation.hasLastValid = true;
        rotation.lastValidGrams = sample.grams;
        reason = DispenseReason::SENSOR_UNAVAILABLE;
        break;
      }

      // El objetivo y el fallo del sensor se comprueban en las tres fases
      // (RF-7, RF-9) y el objetivo tiene prioridad sobre el atasco (RF-14).
      const RotationOutcome rotationOutcome = recordRotationSample(
          &rotation, sample, sampleTimeMs, baseline, amountGrams);

      if (rotationOutcome == RotationOutcome::TARGET_REACHED) {
        reason = DispenseReason::COMPLETED;
        break;
      }
      if (rotationOutcome == RotationOutcome::SENSOR_FAILURE) {
        // RF-9 y RF-17: sin retroceso ni reanudación.
        reason = DispenseReason::SENSOR_FAILURE;
        break;
      }
      if (rotationOutcome == RotationOutcome::TIME_LIMIT) {
        reason = budgetExhaustedReason(stall.stallPending);
        break;
      }

      if (phase == MotorPhase::ADVANCE) {
        // La detección de atasco solo se evalúa en avance (RF-14, decisión 23).
        if (recordAdvanceSample(&stall, sample, sampleTimeMs) ==
            StallOutcome::STALL_DECLARED) {
          const StallAction action = decideStallAction(
              stall.retries,
              detail::budgetRemainingMs(budgetStartMs, sampleTimeMs,
                                        limits.motorBudgetMs),
              limits);
          if (action == StallAction::GIVE_UP) {
            // RF-16: sin reintentos o sin presupuesto para el reintento.
            reason = DispenseReason::STALL_UNRESOLVED;
            break;
          }
          ports.startReverse(ports.context);
          phase = MotorPhase::REVERSE;
          phaseDeadlineMs = sampleTimeMs + kReverseMs;
        }
      } else {
        // Retroceso y pausa siguen midiendo, sin declarar atasco (RF-6).
        feedMovingMedian(&stall, sample);
      }

      nextSampleMs += kSamplePeriodMs;
    }

    // Espera hasta el próximo vencimiento, nunca más allá del presupuesto ni del
    // final de la fase en curso.
    unsigned long wakeMs = budgetDeadlineMs;
    if (budgetLeftMs > kReadTimeoutMs) {
      wakeMs = detail::earlierDeadline(nextSampleMs, wakeMs);
    }
    if (phase != MotorPhase::ADVANCE) {
      wakeMs = detail::earlierDeadline(phaseDeadlineMs, wakeMs);
    }
    if (!detail::deadlineReached(ports.nowMs(ports.context), wakeMs)) {
      ports.waitUntil(ports.context, wakeMs);
    }
  }

  // Toda salida del ciclo deja el servo detenido (RF-9, RF-12, RNF-3).
  ports.stop(ports.context);

  result.reason = reason;
  fillDispenseMeasurements(&result, true, baseline, rotation);
  result.retryCount = stall.retries;
  return result;
}

} // namespace dispensing

#endif // DISPENSING_CYCLE_H
