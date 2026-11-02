#include "scale_guard_service.h"

#include <Arduino.h>

#include "../config/config.h"
#include "../config/dispensing_utils.h"
#include "../config/scale_guard_utils.h"
#include "../drivers/hx711_driver.h"

namespace guard {
namespace {

// Único estado de asentamiento del firmware: tamaño fijo y sin memoria dinámica.
dispensing::SettlementState settlementState;

// Instante del último intento de muestreo, en millis().
unsigned long lastSampleMs = 0;

// Motivo de la pérdida, derivado de la misma muestra que la provocó: un paso
// mayor que el umbral (lectura válida) o tres inválidas consecutivas.
const char *settlementLossText(const dispensing::WeightSample &sample) {
  return dispensing::isReadingValid(sample)
             ? "paso entre lecturas mayor que el umbral configurado"
             : "3 lecturas invalidas consecutivas";
}

} // namespace

void initScaleGuard() {
  ensureHx711Initialized();

  // Caso (d): con factor cero, NaN o infinito la celda nunca produce lecturas
  // válidas y no se ganará el asentamiento. Una sola línea nombra la causa; no
  // se toma ninguna decisión aquí.
  if (!dispensing::isCalibrationFactorValid(hx711CalibrationFactor)) {
    Serial.println("Aviso: factor de calibracion no finito o no positivo; la "
                   "celda no producira lecturas validas y no se ganara el "
                   "asentamiento.");
  }

  dispensing::invalidateSettlement(&settlementState);
}

void updateSettlement() {
  const unsigned long nowMs = millis();

  // Una lectura como máximo por periodo. El instante se fija antes del sondeo
  // para que el bloqueo de readHx711Raw no adelante la muestra siguiente.
  if (dispensing::elapsedMs(lastSampleMs, nowMs) < kSamplePeriodMs) {
    return;
  }
  lastSampleMs = nowMs;

  long raw = 0;
  const bool responded = readHx711Raw(&raw, kReadTimeoutMs);
  const dispensing::WeightSample sample =
      dispensing::makeSample(responded, raw, hx711CalibrationFactor,
                             hx711RawSign);

  switch (dispensing::recordSettlementSample(&settlementState, sample)) {
  case dispensing::SettlementOutcome::GAINED:
    Serial.printf("Asentamiento alcanzado: %u lecturas consecutivas con paso "
                  "<= %.1f g\n",
                  kSettlementReadings,
                  static_cast<double>(kSettlementMaxStepGrams));
    break;
  case dispensing::SettlementOutcome::LOST:
    Serial.printf("Asentamiento perdido: %s\n", settlementLossText(sample));
    break;
  case dispensing::SettlementOutcome::IN_PROGRESS:
    break;
  }
}

bool settlementGained() { return dispensing::settlementGained(settlementState); }

void invalidateSettlement(const char *motivo) {
  dispensing::invalidateSettlement(&settlementState);
  if (motivo != nullptr) {
    Serial.printf("Asentamiento invalidado: %s\n", motivo);
  }
}

} // namespace guard
