#include "dispensing_service.h"

#include <Arduino.h>

#include <cstddef>
#include <cstdint>

#include "../config/config.h"
#include "../drivers/hx711_driver.h"
#include "../drivers/servo_driver.h"

namespace dispensing {
namespace {

// Tamaño holgado para la línea de registro: tres campos de peso de hasta 31
// caracteres más el texto fijo y el motivo.
constexpr std::size_t kLogBufferSize = 256;

// Comprueba si ya se alcanzó un instante absoluto, respetando el desbordamiento
// de millis() mediante la resta sin signo.
bool reached(unsigned long nowMs, unsigned long targetMs) {
  return static_cast<long>(nowMs - targetMs) >= 0;
}

// Milisegundos que faltan para targetMs (0 si ya venció).
unsigned long remainingMs(unsigned long nowMs, unsigned long targetMs) {
  return static_cast<unsigned long>(static_cast<std::uint32_t>(targetMs) -
                                    static_cast<std::uint32_t>(nowMs));
}

// Espera acotada hasta un vencimiento absoluto. Usa delay(1) en el último tramo
// para no prolongar el giro más allá de la cota de seguridad.
void waitUntil(unsigned long targetMs) {
  while (!reached(millis(), targetMs)) {
    const unsigned long left = remainingMs(millis(), targetMs);
    delay(left > 5 ? 5 : 1);
  }
}

// Devuelve el vencimiento más cercano entre dos instantes absolutos.
unsigned long earlierDeadline(unsigned long firstMs, unsigned long secondMs) {
  return reached(firstMs, secondMs) ? secondMs : firstMs;
}

void logDispenseResult(const DispenseResult &result) {
  char buffer[kLogBufferSize];
  formatDispenseLog(result, buffer, sizeof(buffer));
  Serial.println(buffer);
}

// Muestra no respondida: se usa para cerrar una ventana o un giro por tiempo
// sin iniciar una lectura que pudiera exceder el plazo.
WeightSample unavailableSample(float factor, float sign) {
  return makeSample(false, 0, factor, sign);
}

// Diagnóstico de una ventana de verificación fallida. No imprime por muestra
// (se ejecuta solo al fallar) y no altera el contrato del servicio.
void logVerificationDiagnostics(unsigned samples, unsigned responded,
                                long lastRaw, float lastGrams, bool hasLast,
                                unsigned validCount,
                                unsigned consecutiveInvalid, float factor,
                                float sign) {
  if (hasLast) {
    Serial.printf(
        "Verificacion HX711: muestras=%u, respondidas=%u, validas=%u, "
        "invalidas_consecutivas=%u, ultimo_raw=%ld, ultimo_g=%.2f, "
        "factor=%.1f, signo=%+.1f\n",
        samples, responded, validCount, consecutiveInvalid, lastRaw, lastGrams,
        factor, sign);
  } else {
    Serial.printf(
        "Verificacion HX711: muestras=%u, respondidas=%u, validas=%u, "
        "invalidas_consecutivas=%u, ultimo_raw=sin_lectura, "
        "ultimo_g=sin_lectura, factor=%.1f, signo=%+.1f\n",
        samples, responded, validCount, consecutiveInvalid, factor, sign);
  }

  if (responded == 0) {
    Serial.println("Causa probable: el modulo HX711 no respondio (revise "
                   "alimentacion y cableado DT/SCK).");
  } else if (validCount == 0) {
    Serial.println("Causa probable: lecturas fuera de rango; revise la "
                   "calibracion (factor y signo) y el montaje.");
  } else {
    Serial.println(
        "Causa probable: ventana de verificacion sin lecturas validas "
        "suficientes.");
  }
}

} // namespace

DispenseResult dispenseWeight(float amountGrams) {
  DispenseResult result{};
  result.requestedGrams = amountGrams;
  result.reason = DispenseReason::SENSOR_UNAVAILABLE;
  result.baselineAvailable = false;
  result.baselineGrams = 0.0f;
  result.finalAvailable = false;
  result.finalGrams = 0.0f;
  result.incrementAvailable = false;
  result.incrementGrams = 0.0f;

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

  // La celda se inicializa una sola vez, ya validadas las entradas. main.cpp no
  // llama a initHx711().
  static bool hx711Initialized = false;
  if (!hx711Initialized) {
    initHx711();
    hx711Initialized = true;
  }

  const float factor = hx711CalibrationFactor;
  const float sign = hx711RawSign;

  // --- Ventana fija de verificación de 2 s, no reiniciable (RF-3, RF-4) ---
  VerificationState verification;
  startVerification(&verification, millis());
  const unsigned long verificationDeadline =
      verification.startMs + kVerificationWindowMs;
  unsigned long nextSampleMs = verification.startMs;
  VerificationOutcome verificationOutcome = VerificationOutcome::IN_PROGRESS;

  // Contadores de diagnóstico: solo lecturas reales intentadas, no las muestras
  // no respondidas que cierran la ventana.
  unsigned samples = 0;
  unsigned respondedCount = 0;
  long lastRaw = 0;
  float lastGrams = 0.0f;
  bool hasLastReading = false;

  while (true) {
    const unsigned long now = millis();

    // Vencimiento: se cierra con una muestra no respondida. La comprobación de
    // tiempo de recordVerificationSample ocurre antes de contar la muestra, así
    // que no altera el número de válidas ni extiende la ventana.
    if (reached(now, verificationDeadline)) {
      verificationOutcome = recordVerificationSample(
          &verification, unavailableSample(factor, sign), millis());
      break;
    }

    // No se inicia una lectura que pudiera terminar después del vencimiento.
    if (remainingMs(now, verificationDeadline) <= kReadTimeoutMs) {
      waitUntil(verificationDeadline);
      verificationOutcome = recordVerificationSample(
          &verification, unavailableSample(factor, sign), millis());
      break;
    }

    if (reached(now, nextSampleMs)) {
      long raw = 0;
      const bool responded = readHx711Raw(&raw, kReadTimeoutMs);
      const unsigned long sampleTimeMs = millis();
      const WeightSample sample = makeSample(responded, raw, factor, sign);

      ++samples;
      if (responded) {
        ++respondedCount;
        lastRaw = raw;
        lastGrams = sample.grams;
        hasLastReading = true;
      }

      verificationOutcome =
          recordVerificationSample(&verification, sample, sampleTimeMs);
      if (verificationOutcome != VerificationOutcome::IN_PROGRESS) {
        break;
      }

      nextSampleMs += kSamplePeriodMs;
    }

    const unsigned long wakeMs =
        earlierDeadline(nextSampleMs, verificationDeadline);
    if (!reached(millis(), wakeMs)) {
      waitUntil(wakeMs);
    }
  }

  if (verificationOutcome != VerificationOutcome::PASSED) {
    // RF-4: nunca dispensar a ciegas; el servo no llegó a arrancar.
    result.reason = DispenseReason::SENSOR_UNAVAILABLE;
    stopServo();
    logVerificationDiagnostics(samples, respondedCount, lastRaw, lastGrams,
                               hasLastReading, verification.validCount,
                               verification.consecutiveInvalid, factor, sign);
    logDispenseResult(result);
    return result;
  }

  float baseline = 0.0f;
  if (!verificationBaseline(&verification, &baseline)) {
    result.reason = DispenseReason::SENSOR_UNAVAILABLE;
    stopServo();
    logVerificationDiagnostics(samples, respondedCount, lastRaw, lastGrams,
                               hasLastReading, verification.validCount,
                               verification.consecutiveInvalid, factor, sign);
    logDispenseResult(result);
    return result;
  }

  result.baselineAvailable = true;
  result.baselineGrams = baseline;

  // --- Giro con objetivo sostenido y topes (RF-5 a RF-9, RNF-3) ---
  const unsigned long rotationStartMs = millis();
  startServo();
  RotationState rotation;
  startRotation(&rotation, rotationStartMs);
  const unsigned long rotationDeadline = rotation.startMs + kMaxRotationMs;
  nextSampleMs = rotation.startMs;
  RotationOutcome rotationOutcome = RotationOutcome::CONTINUE;

  while (true) {
    const unsigned long now = millis();

    // Cota estricta del giro: al vencer se cierra con una muestra no respondida
    // y el estado puro devuelve TIME_LIMIT sin registrar una lectura tardía.
    if (reached(now, rotationDeadline)) {
      rotationOutcome = recordRotationSample(
          &rotation, unavailableSample(factor, sign), millis(), baseline,
          amountGrams);
      break;
    }

    if (remainingMs(now, rotationDeadline) <= kReadTimeoutMs) {
      waitUntil(rotationDeadline);
      rotationOutcome = recordRotationSample(
          &rotation, unavailableSample(factor, sign), millis(), baseline,
          amountGrams);
      break;
    }

    if (reached(now, nextSampleMs)) {
      long raw = 0;
      const bool responded = readHx711Raw(&raw, kReadTimeoutMs);
      const unsigned long sampleTimeMs = millis();
      const WeightSample sample = makeSample(responded, raw, factor, sign);

      rotationOutcome = recordRotationSample(&rotation, sample, sampleTimeMs,
                                             baseline, amountGrams);
      if (rotationOutcome != RotationOutcome::CONTINUE) {
        break;
      }

      nextSampleMs += kSamplePeriodMs;
    }

    const unsigned long wakeMs = earlierDeadline(nextSampleMs, rotationDeadline);
    if (!reached(millis(), wakeMs)) {
      waitUntil(wakeMs);
    }
  }

  // Toda salida del bucle deja el servo detenido (idempotente).
  stopServo();

  switch (rotationOutcome) {
  case RotationOutcome::TARGET_REACHED:
    result.reason = DispenseReason::COMPLETED;
    break;
  case RotationOutcome::SENSOR_FAILURE:
    result.reason = DispenseReason::SENSOR_FAILURE;
    break;
  case RotationOutcome::TIME_LIMIT:
  case RotationOutcome::CONTINUE:
    result.reason = DispenseReason::NOT_REACHED;
    break;
  }

  fillDispenseMeasurements(&result, true, baseline, rotation);
  logDispenseResult(result);
  return result;
}

} // namespace dispensing
