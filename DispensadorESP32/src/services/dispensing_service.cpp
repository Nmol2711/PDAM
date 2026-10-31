#include "dispensing_service.h"

#include <Arduino.h>

#include <cstddef>

#include "../config/config.h"
#include "../config/dispensing_cycle.h"
#include "../drivers/hx711_driver.h"
#include "../drivers/servo_driver.h"

namespace dispensing {
namespace {

// Tamaño holgado para la línea de registro: tres campos de peso de hasta 31
// caracteres más el texto fijo y el motivo.
constexpr std::size_t kLogBufferSize = 256;

// --- Adaptadores Arduino del ciclo puro (RF-17) ---
// Los puertos no necesitan estado propio: cada adaptador llama al driver o al
// reloj del firmware, así que el contexto opaco queda nulo.

void startAdvanceAdapter(void *) { startServo(); }

void startReverseAdapter(void *) { reverseServo(); }

void stopAdapter(void *) { stopServo(); }

bool readRawAdapter(void *, long *rawOut, unsigned long timeoutMs) {
  return readHx711Raw(rawOut, timeoutMs);
}

unsigned long nowMsAdapter(void *) { return millis(); }

// Espera hasta un vencimiento absoluto en tramos cortos. El tiempo restante se
// recalcula antes de cada espera, de modo que nunca se duerme más allá del
// instante pedido ni se prolonga el giro por la granularidad de delay().
void waitUntilAdapter(void *, unsigned long deadlineMs) {
  while (!detail::deadlineReached(millis(), deadlineMs)) {
    const unsigned long leftMs = detail::remainingMs(millis(), deadlineMs);
    delay(leftMs > 5 ? 5 : 1);
  }
}

void logDispenseResult(const DispenseResult &result) {
  char buffer[kLogBufferSize];
  formatDispenseLog(result, buffer, sizeof(buffer));
  Serial.println(buffer);
}

// Diagnóstico de una ventana de verificación fallida. No imprime por muestra
// (se ejecuta solo al fallar) y no altera el contrato del servicio.
void logVerificationDiagnostics(const CycleDiagnostics &diagnostics,
                                float factor, float sign) {
  if (diagnostics.hasLastReading) {
    Serial.printf(
        "Verificacion HX711: muestras=%u, respondidas=%u, validas=%u, "
        "invalidas_consecutivas=%u, ultimo_raw=%ld, ultimo_g=%.2f, "
        "factor=%.1f, signo=%+.1f\n",
        diagnostics.samples, diagnostics.responded, diagnostics.valid,
        diagnostics.consecutiveInvalid, diagnostics.lastRaw,
        diagnostics.lastGrams, factor, sign);
  } else {
    Serial.printf(
        "Verificacion HX711: muestras=%u, respondidas=%u, validas=%u, "
        "invalidas_consecutivas=%u, ultimo_raw=sin_lectura, "
        "ultimo_g=sin_lectura, factor=%.1f, signo=%+.1f\n",
        diagnostics.samples, diagnostics.responded, diagnostics.valid,
        diagnostics.consecutiveInvalid, factor, sign);
  }

  if (diagnostics.responded == 0) {
    Serial.println("Causa probable: el modulo HX711 no respondio (revise "
                   "alimentacion y cableado DT/SCK).");
  } else if (diagnostics.valid == 0) {
    Serial.println("Causa probable: lecturas fuera de rango; revise la "
                   "calibracion (factor y signo) y el montaje.");
  } else {
    Serial.println(
        "Causa probable: ventana de verificacion sin lecturas validas "
        "suficientes.");
  }
}

// Motivo real del rechazo de la línea base (RF-3, RNF-4): una sola línea con el
// veredicto en español, las válidas de la ventana y la mediana observada.
void logBaselineRejection(const CycleDiagnostics &diagnostics) {
  if (diagnostics.hasBaseline) {
    Serial.printf("Linea base rechazada: motivo=%s, validas=%u, base=%.2f g\n",
                  baselineStatusText(diagnostics.baselineRejection),
                  diagnostics.valid, diagnostics.baselineGrams);
  } else {
    Serial.printf("Linea base rechazada: motivo=%s, validas=%u, "
                  "base=sin_calcular\n",
                  baselineStatusText(diagnostics.baselineRejection),
                  diagnostics.valid);
  }
}

// Cierre por plausibilidad (RF-5): una única línea en español con la causa real,
// el mayor incremento observado, la base y el tope. Nunca el diagnóstico de la
// ventana de verificación: en este camino sí hubo una base aceptada y volcarlo
// solo confundiría.
void logPlausibilityClosure(const CycleDiagnostics &diagnostics) {
  Serial.printf("Cierre por plausibilidad: motivo=%s, incremento_max=%.2f g, "
                "base=%.2f g, tope=%.2f g\n",
                plausibilityCauseText(diagnostics.plausibility),
                diagnostics.maxIncrementGrams, diagnostics.baselineGrams,
                diagnostics.topGrams);
}

} // namespace

DispenseResult dispenseWeight(float amountGrams) {
  // Las salidas tempranas no ejecutan el ciclo y dejan reintentos=0.
  DispenseResult result{};
  result.requestedGrams = amountGrams;

  // RF-11: sin factor positivo no se toca la celda ni el servo.
  if (!isCalibrationFactorValid(hx711CalibrationFactor)) {
    result.reason = DispenseReason::INVALID_CONFIG;
    logDispenseResult(result);
    return result;
  }

  // Cantidad no positiva o no numérica (NaN): tampoco se toca el hardware.
  if (!(amountGrams > 0.0f)) {
    result.reason = DispenseReason::INVALID_AMOUNT;
    logDispenseResult(result);
    return result;
  }

  // La celda se inicializa una sola vez desde el driver; el muestreo del
  // asentamiento y el ciclo comparten esa misma inicialización (Spec 016).
  ensureHx711Initialized();

  CyclePorts ports;
  ports.context = nullptr;
  ports.startAdvance = startAdvanceAdapter;
  ports.startReverse = startReverseAdapter;
  ports.stop = stopAdapter;
  ports.readRaw = readRawAdapter;
  ports.nowMs = nowMsAdapter;
  ports.waitUntil = waitUntilAdapter;

  // El ciclo puro conserva la ventana de verificación, la línea base, el avance,
  // el retroceso y la pausa de desatasco, y detiene el servo en toda salida.
  CycleDiagnostics diagnostics{};
  result = runDispenseCycle(ports, amountGrams, hx711CalibrationFactor,
                            hx711RawSign, &diagnostics);

  // Caminos de cierre sin una dispensación correcta (RF-3, RF-4 de la 013, RF-8,
  // RF-5):
  // - rechazo de la base: diagnóstico de la ventana más su motivo real;
  // - aborto por 3 inválidas: exactamente el diagnóstico de la 013, sin veredicto
  //   de base, porque es lo que distingue un sensor desconectado;
  // - cierre por plausibilidad: base aceptada y solo su línea, nunca el
  //   diagnóstico de la ventana.
  if (result.reason == DispenseReason::SENSOR_UNAVAILABLE &&
      diagnostics.plausibility != PlausibilityVerdict::PLAUSIBLE) {
    logPlausibilityClosure(diagnostics);
  } else if (result.reason == DispenseReason::SENSOR_UNAVAILABLE &&
             diagnostics.baselineRejection != BaselineStatus::ACCEPTED) {
    logVerificationDiagnostics(diagnostics, hx711CalibrationFactor,
                               hx711RawSign);
    if (diagnostics.baselineRejection != BaselineStatus::NOT_EVALUATED) {
      logBaselineRejection(diagnostics);
    }
  }

  // RF-12: una única línea final con el motivo y reintentos=N.
  logDispenseResult(result);
  return result;
}

} // namespace dispensing
