#include <unity.h>

#include <cmath>
#include <cstring>

#include "config/dispensing_utils.h"

using namespace dispensing;

void setUp(void) {}

void tearDown(void) {}

// --- classifyOrder (RF-1, RF-2, RF-10) ---

void test_classify_order_reset_wifi_has_absolute_priority(void) {
  TEST_ASSERT_EQUAL_INT(static_cast<int>(OrderAction::RESET_WIFI),
                        static_cast<int>(classifyOrder(true, true, true, true, 100.0f)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(OrderAction::RESET_WIFI),
                        static_cast<int>(classifyOrder(true, false, false, false, 0.0f)));
}

void test_classify_order_rest_without_serve(void) {
  TEST_ASSERT_EQUAL_INT(static_cast<int>(OrderAction::REST),
                        static_cast<int>(classifyOrder(false, false, true, true, 50.0f)));
}

void test_classify_order_rest_with_zero_amount(void) {
  TEST_ASSERT_EQUAL_INT(static_cast<int>(OrderAction::REST),
                        static_cast<int>(classifyOrder(false, true, true, true, 0.0f)));
}

void test_classify_order_dispense_with_positive_amount(void) {
  TEST_ASSERT_EQUAL_INT(static_cast<int>(OrderAction::DISPENSE),
                        static_cast<int>(classifyOrder(false, true, true, true, 50.0f)));
}

void test_classify_order_invalid_when_amount_negative(void) {
  TEST_ASSERT_EQUAL_INT(static_cast<int>(OrderAction::INVALID_ORDER),
                        static_cast<int>(classifyOrder(false, true, true, true, -1.0f)));
}

void test_classify_order_invalid_when_amount_absent(void) {
  TEST_ASSERT_EQUAL_INT(static_cast<int>(OrderAction::INVALID_ORDER),
                        static_cast<int>(classifyOrder(false, true, false, true, 0.0f)));
}

void test_classify_order_invalid_when_amount_not_numeric(void) {
  TEST_ASSERT_EQUAL_INT(static_cast<int>(OrderAction::INVALID_ORDER),
                        static_cast<int>(classifyOrder(false, true, true, false, 0.0f)));
}

// --- isCalibrationFactorValid (RF-11) ---

void test_calibration_factor_accepts_positive_value(void) {
  TEST_ASSERT_TRUE(isCalibrationFactorValid(7050.0f));
  TEST_ASSERT_TRUE(isCalibrationFactorValid(1.0f));
}

void test_calibration_factor_rejects_zero_and_negative(void) {
  TEST_ASSERT_FALSE(isCalibrationFactorValid(0.0f));
  TEST_ASSERT_FALSE(isCalibrationFactorValid(-7050.0f));
}

void test_calibration_factor_rejects_nan_and_infinity(void) {
  TEST_ASSERT_FALSE(isCalibrationFactorValid(NAN));
  TEST_ASSERT_FALSE(isCalibrationFactorValid(INFINITY));
}

// --- convertRawToGrams / saturación (RF-6, RF-11) ---

void test_convert_raw_to_grams_applies_sign_and_factor(void) {
  TEST_ASSERT_EQUAL_FLOAT(1.0f, convertRawToGrams(-7050, 7050.0f, -1.0f));
  TEST_ASSERT_EQUAL_FLOAT(50.0f, convertRawToGrams(-352500, 7050.0f, -1.0f));
}

void test_convert_raw_to_grams_returns_nan_with_invalid_factor(void) {
  TEST_ASSERT_TRUE(std::isnan(convertRawToGrams(1000, 0.0f, -1.0f)));
  TEST_ASSERT_TRUE(std::isnan(convertRawToGrams(1000, -7050.0f, -1.0f)));
}

void test_is_raw_saturated_detects_both_extremes(void) {
  TEST_ASSERT_TRUE(isRawSaturated(-8388608L));
  TEST_ASSERT_TRUE(isRawSaturated(8388607L));
  TEST_ASSERT_FALSE(isRawSaturated(-8388607L));
  TEST_ASSERT_FALSE(isRawSaturated(8388606L));
  TEST_ASSERT_FALSE(isRawSaturated(0L));
}

// --- isReadingValid (RF-3, RF-6) ---

void test_reading_without_response_is_invalid(void) {
  WeightSample sample = makeSample(false, 1000, 7050.0f, -1.0f);
  TEST_ASSERT_FALSE(isReadingValid(sample));
}

void test_reading_with_negative_weight_is_invalid(void) {
  WeightSample sample;
  sample.responded = true;
  sample.raw = 1000;
  sample.grams = -0.1f;
  TEST_ASSERT_FALSE(isReadingValid(sample));
}

void test_reading_at_zero_grams_is_valid(void) {
  WeightSample sample = makeSample(true, 0, 7050.0f, -1.0f);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, sample.grams);
  TEST_ASSERT_TRUE(isReadingValid(sample));
}

void test_reading_at_max_range_is_valid(void) {
  WeightSample sample;
  sample.responded = true;
  sample.raw = 1000;
  sample.grams = 5000.0f;
  TEST_ASSERT_TRUE(isReadingValid(sample));
}

void test_reading_above_max_range_is_invalid(void) {
  WeightSample sample;
  sample.responded = true;
  sample.raw = 1000;
  sample.grams = 5000.1f;
  TEST_ASSERT_FALSE(isReadingValid(sample));
}

void test_reading_with_nan_weight_is_invalid(void) {
  WeightSample sample;
  sample.responded = true;
  sample.raw = 1000;
  sample.grams = NAN;
  TEST_ASSERT_FALSE(isReadingValid(sample));
}

void test_reading_with_saturated_raw_is_invalid(void) {
  WeightSample low;
  low.responded = true;
  low.raw = -8388608L;
  low.grams = 100.0f;
  TEST_ASSERT_FALSE(isReadingValid(low));

  WeightSample high;
  high.responded = true;
  high.raw = 8388607L;
  high.grams = 100.0f;
  TEST_ASSERT_FALSE(isReadingValid(high));
}

// --- median (RF-3) ---

void test_median_odd_returns_central_value_without_modifying_input(void) {
  float values[5] = {7.0f, 1.0f, 3.0f, 5.0f, 2.0f};
  float result = 0.0f;

  TEST_ASSERT_TRUE(median(values, 5, &result));
  TEST_ASSERT_EQUAL_FLOAT(3.0f, result);
  TEST_ASSERT_EQUAL_FLOAT(7.0f, values[0]);
  TEST_ASSERT_EQUAL_FLOAT(1.0f, values[1]);
  TEST_ASSERT_EQUAL_FLOAT(3.0f, values[2]);
  TEST_ASSERT_EQUAL_FLOAT(5.0f, values[3]);
  TEST_ASSERT_EQUAL_FLOAT(2.0f, values[4]);
}

void test_median_even_returns_average_of_central_values(void) {
  float values[4] = {4.0f, 1.0f, 3.0f, 2.0f};
  float result = 0.0f;

  TEST_ASSERT_TRUE(median(values, 4, &result));
  TEST_ASSERT_EQUAL_FLOAT(2.5f, result);
}

void test_median_single_value(void) {
  float values[1] = {7.5f};
  float result = 0.0f;

  TEST_ASSERT_TRUE(median(values, 1, &result));
  TEST_ASSERT_EQUAL_FLOAT(7.5f, result);
}

void test_median_rejects_invalid_arguments(void) {
  float values[2] = {1.0f, 2.0f};
  float result = 0.0f;

  TEST_ASSERT_FALSE(median(values, 0, &result));
  TEST_ASSERT_FALSE(median(nullptr, 2, &result));
  TEST_ASSERT_FALSE(median(values, 2, nullptr));
}

// --- targetGrams (RF-6, RF-7) ---

void test_target_grams_adds_amount_to_baseline(void) {
  TEST_ASSERT_EQUAL_FLOAT(62.5f, targetGrams(12.5f, 50.0f));
}

// --- formatDispenseLog (RF-12, RNF-5) ---

void test_format_dispense_log_complete_line(void) {
  DispenseResult result;
  result.requestedGrams = 50.0f;
  result.reason = DispenseReason::COMPLETED;
  result.baselineAvailable = true;
  result.baselineGrams = 12.3f;
  result.finalAvailable = true;
  result.finalGrams = 63.4f;
  result.incrementAvailable = true;
  result.incrementGrams = 51.1f;

  char buffer[160];

  formatDispenseLog(result, buffer, sizeof(buffer));
  TEST_ASSERT_EQUAL_STRING(
      "Despacho: solicitado=50.0 g, linea_base=12.3 g, peso_final=63.4 g, "
      "incremento=51.1 g, motivo=objetivo alcanzado",
      buffer);
}

void test_format_dispense_log_replaces_unavailable_values(void) {
  DispenseResult result;
  result.requestedGrams = 20.0f;
  result.reason = DispenseReason::SENSOR_UNAVAILABLE;
  result.baselineAvailable = false;
  result.baselineGrams = 0.0f;
  result.finalAvailable = false;
  result.finalGrams = 0.0f;
  result.incrementAvailable = false;
  result.incrementGrams = 0.0f;

  char buffer[160];

  formatDispenseLog(result, buffer, sizeof(buffer));
  TEST_ASSERT_EQUAL_STRING(
      "Despacho: solicitado=20.0 g, linea_base=no disponible, "
      "peso_final=no disponible, incremento=no disponible, "
      "motivo=sensor no disponible",
      buffer);
}

void test_format_dispense_log_includes_sensor_failure_reason(void) {
  DispenseResult result;
  result.requestedGrams = 50.0f;
  result.reason = DispenseReason::SENSOR_FAILURE;
  result.baselineAvailable = true;
  result.baselineGrams = 10.0f;
  result.finalAvailable = true;
  result.finalGrams = 25.0f;
  result.incrementAvailable = true;
  result.incrementGrams = 15.0f;

  char buffer[160];

  formatDispenseLog(result, buffer, sizeof(buffer));
  TEST_ASSERT_NOT_NULL(strstr(buffer, "fallo del sensor durante la dispensacion"));
  TEST_ASSERT_NOT_NULL(strstr(buffer, "solicitado=50.0 g"));
  TEST_ASSERT_NOT_NULL(strstr(buffer, "linea_base=10.0 g"));
  TEST_ASSERT_NOT_NULL(strstr(buffer, "peso_final=25.0 g"));
  TEST_ASSERT_NOT_NULL(strstr(buffer, "incremento=15.0 g"));
}

void test_format_dispense_log_rejects_invalid_buffer(void) {
  DispenseResult result;
  result.requestedGrams = 10.0f;
  result.reason = DispenseReason::INVALID_CONFIG;
  result.baselineAvailable = false;
  result.finalAvailable = false;
  result.incrementAvailable = false;

  // Buffer no usable: la función retorna sin escribir y sin fallar.
  formatDispenseLog(result, nullptr, 100);
  formatDispenseLog(result, nullptr, 0);

  char buffer[10];
  formatDispenseLog(result, buffer, 0);
}

// --- verificacion previa: ventana fija de 2 s (RF-3, RF-4, RNF-1, RNF-3) ---

namespace {

WeightSample validSample(float grams) {
  WeightSample sample;
  sample.responded = true;
  sample.raw = 1000;
  sample.grams = grams;
  return sample;
}

WeightSample invalidSample() {
  WeightSample sample;
  sample.responded = false;
  sample.raw = 0;
  sample.grams = 0.0f;
  return sample;
}

} // namespace

void test_start_verification_opens_fixed_window(void) {
  VerificationState state;
  startVerification(&state, 1234);

  TEST_ASSERT_EQUAL_UINT32(1234, state.startMs);
  TEST_ASSERT_EQUAL_UINT(0, state.validCount);
  TEST_ASSERT_EQUAL_UINT(0, state.storedCount);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveInvalid);
  TEST_ASSERT_FALSE(state.finished);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(VerificationOutcome::IN_PROGRESS),
                        static_cast<int>(state.outcome));
}

void test_verification_window_is_exactly_two_seconds(void) {
  VerificationState state;
  startVerification(&state, 0);

  // Diez muestras validas con valores distintos en 0, 200, ..., 1800 ms.
  for (unsigned i = 0; i < 10; ++i) {
    TEST_ASSERT_EQUAL_INT(
        static_cast<int>(VerificationOutcome::IN_PROGRESS),
        static_cast<int>(recordVerificationSample(&state, validSample(1.0f + i),
                                                  i * 200UL)));
  }

  // En 1999 ms aun no se cierra y la muestra entra en la ventana.
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, validSample(11.0f),
                                                1999UL)));

  // Al llamar en 2000 ms la ventana se cierra y la muestra NO se registra.
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::PASSED),
      static_cast<int>(recordVerificationSample(&state, validSample(100.0f),
                                                2000UL)));
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_UINT(11, state.validCount);
  TEST_ASSERT_EQUAL_UINT(11, state.storedCount);

  // Mediana de 1..11 es 6; si la muestra de 2000 ms (100) hubiera entrado,
  // la mediana seria otra.
  float baseline = 0.0f;
  TEST_ASSERT_TRUE(verificationBaseline(&state, &baseline));
  TEST_ASSERT_EQUAL_FLOAT(6.0f, baseline);
}

void test_verification_window_is_not_restarted_or_extended(void) {
  VerificationState state;
  startVerification(&state, 0);

  // Validas e invalidas intercaladas sin 3 consecutivas.
  recordVerificationSample(&state, validSample(10.0f), 0);
  recordVerificationSample(&state, invalidSample(), 100);
  recordVerificationSample(&state, validSample(20.0f), 200);
  recordVerificationSample(&state, invalidSample(), 300);
  recordVerificationSample(&state, validSample(30.0f), 400);
  recordVerificationSample(&state, validSample(40.0f), 600);
  recordVerificationSample(&state, validSample(50.0f), 800);

  // Una muestra valida posterior a 2 s no reabre ni extiende la ventana.
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::PASSED),
      static_cast<int>(recordVerificationSample(&state, validSample(1000.0f),
                                                2500UL)));
  TEST_ASSERT_EQUAL_UINT32(0, state.startMs);
  TEST_ASSERT_EQUAL_UINT(5, state.validCount);
  TEST_ASSERT_EQUAL_UINT(5, state.storedCount);
  TEST_ASSERT_TRUE(state.finished);

  // Ya cerrada, la ventana no admite mas muestras.
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::PASSED),
      static_cast<int>(recordVerificationSample(&state, validSample(2000.0f),
                                                2600UL)));
  TEST_ASSERT_EQUAL_UINT(5, state.validCount);
  TEST_ASSERT_EQUAL_UINT(5, state.storedCount);
}

void test_verification_passes_with_exactly_five_valid_readings(void) {
  VerificationState state;
  startVerification(&state, 0);

  for (unsigned i = 0; i < 5; ++i) {
    TEST_ASSERT_EQUAL_INT(
        static_cast<int>(VerificationOutcome::IN_PROGRESS),
        static_cast<int>(recordVerificationSample(&state, validSample(i * 10.0f),
                                                  i * 200UL)));
  }

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::PASSED),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 2000UL)));
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_UINT(5, state.validCount);
}

void test_verification_expires_with_four_valid_readings(void) {
  VerificationState state;
  startVerification(&state, 0);

  for (unsigned i = 0; i < 4; ++i) {
    recordVerificationSample(&state, validSample(i * 10.0f), i * 200UL);
  }

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::WINDOW_EXPIRED),
      static_cast<int>(recordVerificationSample(&state, validSample(40.0f),
                                                2000UL)));
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_UINT(4, state.validCount);
}

void test_verification_aborts_with_three_consecutive_invalid_readings(void) {
  VerificationState state;
  startVerification(&state, 0);

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 0)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 200)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::ABORTED_BY_INVALID),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 400)));

  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_UINT(3, state.consecutiveInvalid);
}

void test_valid_reading_resets_consecutive_invalid_counter(void) {
  VerificationState state;
  startVerification(&state, 0);

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 0)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 200)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, validSample(12.5f), 400)));
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveInvalid);

  // Despues de la valida hacen falta otras 3 invalidas consecutivas.
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 600)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 800)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::ABORTED_BY_INVALID),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 1000)));
  TEST_ASSERT_EQUAL_UINT(1, state.validCount);
}

void test_isolated_invalid_reading_keeps_accumulated_valid_values(void) {
  VerificationState state;
  startVerification(&state, 0);

  recordVerificationSample(&state, validSample(10.0f), 0);
  recordVerificationSample(&state, invalidSample(), 200);
  recordVerificationSample(&state, validSample(20.0f), 400);
  recordVerificationSample(&state, invalidSample(), 600);
  recordVerificationSample(&state, validSample(30.0f), 800);
  recordVerificationSample(&state, invalidSample(), 1000);
  recordVerificationSample(&state, validSample(40.0f), 1200);
  recordVerificationSample(&state, validSample(50.0f), 1400);
  recordVerificationSample(&state, validSample(60.0f), 1600);

  TEST_ASSERT_FALSE(state.finished);
  TEST_ASSERT_EQUAL_UINT(6, state.validCount);

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::PASSED),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 2000)));
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_UINT(6, state.validCount);
  TEST_ASSERT_EQUAL_UINT(6, state.storedCount);
}

void test_verification_baseline_is_median_of_window_values(void) {
  VerificationState state;
  startVerification(&state, 0);

  recordVerificationSample(&state, validSample(4.0f), 0);
  recordVerificationSample(&state, validSample(1.0f), 200);
  recordVerificationSample(&state, validSample(3.0f), 400);
  recordVerificationSample(&state, validSample(2.0f), 600);
  recordVerificationSample(&state, validSample(5.0f), 800);
  recordVerificationSample(&state, invalidSample(), 1000);
  recordVerificationSample(&state, validSample(6.0f), 1200);

  // Numero par de validas: promedio de los dos centrales (3 y 4).
  float baseline = 0.0f;
  TEST_ASSERT_TRUE(verificationBaseline(&state, &baseline));
  TEST_ASSERT_EQUAL_FLOAT(3.5f, baseline);
}

void test_verification_baseline_unavailable_without_valid_readings(void) {
  VerificationState state;
  startVerification(&state, 0);

  float baseline = 123.0f;
  TEST_ASSERT_FALSE(verificationBaseline(&state, &baseline));

  recordVerificationSample(&state, invalidSample(), 0);
  recordVerificationSample(&state, invalidSample(), 200);
  TEST_ASSERT_FALSE(verificationBaseline(&state, &baseline));

  TEST_ASSERT_FALSE(verificationBaseline(nullptr, &baseline));
  TEST_ASSERT_FALSE(verificationBaseline(&state, nullptr));
}

void test_record_after_finished_keeps_same_outcome_and_counters(void) {
  VerificationState state;
  startVerification(&state, 0);

  for (unsigned i = 0; i < 5; ++i) {
    recordVerificationSample(&state, validSample(i * 10.0f), i * 200UL);
  }

  recordVerificationSample(&state, invalidSample(), 2000);
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_UINT(5, state.validCount);
  TEST_ASSERT_EQUAL_UINT(5, state.storedCount);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveInvalid);

  const unsigned validBefore = state.validCount;
  const unsigned storedBefore = state.storedCount;
  const unsigned invalidBefore = state.consecutiveInvalid;

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::PASSED),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 2200)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::PASSED),
      static_cast<int>(recordVerificationSample(&state, validSample(7.0f), 2400)));

  TEST_ASSERT_EQUAL_UINT(validBefore, state.validCount);
  TEST_ASSERT_EQUAL_UINT(storedBefore, state.storedCount);
  TEST_ASSERT_EQUAL_UINT(invalidBefore, state.consecutiveInvalid);
}

void test_record_with_null_state_is_safe(void) {
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(nullptr, validSample(10.0f), 0)));
}

// --- giro por peso: objetivo, fallo de sensor y tiempo limite ---
// RF-6, RF-7, RF-8, RF-9, RNF-2, RNF-3

namespace {

// Objetivo de las pruebas: linea base 10 g + 50 g solicitados = 60 g.
constexpr float kTestBaseline = 10.0f;
constexpr float kTestAmount = 50.0f;

RotationOutcome recordValid(RotationState *state, float grams,
                            unsigned long nowMs) {
  return recordRotationSample(state, validSample(grams), nowMs, kTestBaseline,
                              kTestAmount);
}

RotationOutcome recordInvalid(RotationState *state, unsigned long nowMs) {
  return recordRotationSample(state, invalidSample(), nowMs, kTestBaseline,
                              kTestAmount);
}

} // namespace

void test_start_rotation_initializes_state(void) {
  RotationState state;
  startRotation(&state, 4321);

  TEST_ASSERT_EQUAL_UINT32(4321, state.startMs);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveInvalid);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveTarget);
  TEST_ASSERT_FALSE(state.hasLastValid);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, state.lastValidGrams);
  TEST_ASSERT_FALSE(state.finished);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(state.outcome));
}

void test_rotation_stops_after_three_consecutive_target_readings(void) {
  RotationState state;
  startRotation(&state, 0);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.5f, 0)));
  TEST_ASSERT_FALSE(state.finished);
  TEST_ASSERT_EQUAL_UINT(1, state.consecutiveTarget);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 61.0f, 200)));
  TEST_ASSERT_FALSE(state.finished);
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveTarget);

  // La igualdad exacta con el objetivo tambien cuenta (RF-7).
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TARGET_REACHED),
                        static_cast<int>(recordValid(&state, 60.0f, 400)));
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_UINT(3, state.consecutiveTarget);
}

void test_valid_reading_below_target_resets_target_counter(void) {
  RotationState state;
  startRotation(&state, 0);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.0f, 0)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.0f, 200)));
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveTarget);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 59.9f, 400)));
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveTarget);
  TEST_ASSERT_FALSE(state.finished);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.0f, 600)));
  TEST_ASSERT_EQUAL_UINT(1, state.consecutiveTarget);
}

void test_target_requires_three_consecutive_readings_after_interruption(void) {
  RotationState state;
  startRotation(&state, 0);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.0f, 0)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 61.0f, 200)));
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveTarget);

  // Una valida por debajo del objetivo rompe la racha.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 55.0f, 400)));
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveTarget);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.0f, 600)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.0f, 800)));
  TEST_ASSERT_FALSE(state.finished);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TARGET_REACHED),
                        static_cast<int>(recordValid(&state, 60.0f, 1000)));
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_UINT(3, state.consecutiveTarget);
}

void test_isolated_invalid_reading_does_not_stop_rotation(void) {
  RotationState state;
  startRotation(&state, 0);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.5f, 0)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.6f, 200)));
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveTarget);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordInvalid(&state, 400)));
  TEST_ASSERT_FALSE(state.finished);
  TEST_ASSERT_EQUAL_UINT(1, state.consecutiveInvalid);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveTarget);
  TEST_ASSERT_TRUE(state.hasLastValid);
  TEST_ASSERT_EQUAL_FLOAT(60.6f, state.lastValidGrams);

  // Tras la invalida aislada se exigen otras 3 validas consecutivas.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.7f, 600)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 60.8f, 800)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TARGET_REACHED),
                        static_cast<int>(recordValid(&state, 60.9f, 1000)));
}

void test_three_consecutive_invalid_readings_stop_rotation(void) {
  RotationState state;
  startRotation(&state, 0);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordInvalid(&state, 0)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordInvalid(&state, 200)));
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveInvalid);

  // Una valida intermedia reinicia el contador de invalidas.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 11.0f, 400)));
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveInvalid);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordInvalid(&state, 600)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordInvalid(&state, 800)));
  TEST_ASSERT_FALSE(state.finished);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::SENSOR_FAILURE),
                        static_cast<int>(recordInvalid(&state, 1000)));
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_UINT(3, state.consecutiveInvalid);
}

void test_rotation_stops_at_time_limit(void) {
  RotationState state;
  startRotation(&state, 1000);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 20.0f, 1000)));
  // A 29999 ms desde el inicio aun no vence el tope de giro.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 20.0f, 30999)));

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TIME_LIMIT),
                        static_cast<int>(recordValid(&state, 500.0f, 31000)));
  TEST_ASSERT_TRUE(state.finished);

  // La muestra tomada en el limite no se registra.
  TEST_ASSERT_EQUAL_FLOAT(20.0f, state.lastValidGrams);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveTarget);
}

void test_sample_exactly_at_time_limit_is_not_recorded(void) {
  RotationState state;
  startRotation(&state, 0);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TIME_LIMIT),
                        static_cast<int>(recordValid(&state, 60.0f, 30000)));
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_FALSE(state.hasLastValid);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, state.lastValidGrams);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveTarget);
}

void test_last_valid_weight_tracks_only_valid_readings(void) {
  RotationState state;
  startRotation(&state, 0);

  TEST_ASSERT_FALSE(state.hasLastValid);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, state.lastValidGrams);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordInvalid(&state, 0)));
  TEST_ASSERT_FALSE(state.hasLastValid);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 12.5f, 200)));
  TEST_ASSERT_TRUE(state.hasLastValid);
  TEST_ASSERT_EQUAL_FLOAT(12.5f, state.lastValidGrams);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordInvalid(&state, 400)));
  TEST_ASSERT_TRUE(state.hasLastValid);
  TEST_ASSERT_EQUAL_FLOAT(12.5f, state.lastValidGrams);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordValid(&state, 13.5f, 600)));
  TEST_ASSERT_EQUAL_FLOAT(13.5f, state.lastValidGrams);
}

void test_record_after_rotation_finished_keeps_outcome_and_state(void) {
  RotationState state;
  startRotation(&state, 0);

  recordValid(&state, 60.0f, 0);
  recordValid(&state, 60.0f, 200);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TARGET_REACHED),
                        static_cast<int>(recordValid(&state, 60.0f, 400)));
  TEST_ASSERT_TRUE(state.finished);

  const unsigned invalidBefore = state.consecutiveInvalid;
  const unsigned targetBefore = state.consecutiveTarget;
  const bool hasLastBefore = state.hasLastValid;
  const float lastBefore = state.lastValidGrams;

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TARGET_REACHED),
                        static_cast<int>(recordValid(&state, 99.0f, 600)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TARGET_REACHED),
                        static_cast<int>(recordInvalid(&state, 800)));

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TARGET_REACHED),
                        static_cast<int>(state.outcome));
  TEST_ASSERT_EQUAL_UINT(invalidBefore, state.consecutiveInvalid);
  TEST_ASSERT_EQUAL_UINT(targetBefore, state.consecutiveTarget);
  TEST_ASSERT_EQUAL(hasLastBefore, state.hasLastValid);
  TEST_ASSERT_EQUAL_FLOAT(lastBefore, state.lastValidGrams);
}

void test_record_rotation_with_null_state_is_safe(void) {
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(RotationOutcome::CONTINUE),
      static_cast<int>(recordRotationSample(nullptr, validSample(10.0f), 0,
                                            kTestBaseline, kTestAmount)));
}

void test_is_check_due_waits_the_full_interval(void) {
  TEST_ASSERT_FALSE(isCheckDue(0, 19999, 20000));
  TEST_ASSERT_TRUE(isCheckDue(0, 20000, 20000));
  TEST_ASSERT_TRUE(isCheckDue(1000, 21000, 20000));
  TEST_ASSERT_TRUE(isCheckDue(1000, 26250, 20000));
}

void test_is_check_due_tolerates_millis_rollover(void) {
  const unsigned long last = 0xFFFFFF00UL;
  const unsigned long now = 0x00000100UL;

  // La diferencia real es 512 ms aunque millis() haya dado la vuelta.
  TEST_ASSERT_TRUE(isCheckDue(last, now, 500));
  TEST_ASSERT_TRUE(isCheckDue(last, now, 512));
  TEST_ASSERT_FALSE(isCheckDue(last, now, 20000));
}

void test_time_limit_has_priority_over_invalid_readings_at_thirty_seconds(void) {
  RotationState state;
  startRotation(&state, 0);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordInvalid(&state, 29600)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::CONTINUE),
                        static_cast<int>(recordInvalid(&state, 29800)));
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveInvalid);

  // La tercera invalida coincide con el tope de giro: manda el tiempo limite.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TIME_LIMIT),
                        static_cast<int>(recordInvalid(&state, 30000)));
  TEST_ASSERT_TRUE(state.finished);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(RotationOutcome::TIME_LIMIT),
                        static_cast<int>(state.outcome));
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveInvalid);
}

// --- fillDispenseMeasurements: peso final, incremento y banderas (RF-12) ---

namespace {

RotationState rotationWithLastValid(float grams) {
  RotationState state;
  startRotation(&state, 0);
  state.hasLastValid = true;
  state.lastValidGrams = grams;
  return state;
}

} // namespace

void test_fill_measurements_with_baseline_and_last_valid_computes_increment(void) {
  DispenseResult result;
  result.requestedGrams = 50.0f;
  result.reason = DispenseReason::COMPLETED;
  result.baselineAvailable = false;
  result.baselineGrams = 0.0f;
  result.finalAvailable = false;
  result.finalGrams = 0.0f;
  result.incrementAvailable = false;
  result.incrementGrams = 0.0f;

  const RotationState rotation = rotationWithLastValid(63.5f);

  fillDispenseMeasurements(&result, true, 12.5f, rotation);

  TEST_ASSERT_TRUE(result.baselineAvailable);
  TEST_ASSERT_EQUAL_FLOAT(12.5f, result.baselineGrams);
  TEST_ASSERT_TRUE(result.finalAvailable);
  TEST_ASSERT_EQUAL_FLOAT(63.5f, result.finalGrams);
  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_EQUAL_FLOAT(51.0f, result.incrementGrams);
}

void test_fill_measurements_without_baseline_keeps_final_but_not_increment(void) {
  DispenseResult result;
  result.requestedGrams = 20.0f;
  result.reason = DispenseReason::SENSOR_UNAVAILABLE;
  result.baselineAvailable = true;
  result.baselineGrams = 99.0f;
  result.finalAvailable = false;
  result.finalGrams = 0.0f;
  result.incrementAvailable = true;
  result.incrementGrams = 99.0f;

  const RotationState rotation = rotationWithLastValid(40.0f);

  fillDispenseMeasurements(&result, false, 12.5f, rotation);

  TEST_ASSERT_FALSE(result.baselineAvailable);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, result.baselineGrams);
  TEST_ASSERT_TRUE(result.finalAvailable);
  TEST_ASSERT_EQUAL_FLOAT(40.0f, result.finalGrams);
  TEST_ASSERT_FALSE(result.incrementAvailable);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, result.incrementGrams);
}

void test_fill_measurements_without_last_valid_marks_final_and_increment_unavailable(
    void) {
  DispenseResult result;
  result.requestedGrams = 50.0f;
  result.reason = DispenseReason::SENSOR_FAILURE;
  result.baselineAvailable = false;
  result.baselineGrams = 0.0f;
  result.finalAvailable = true;
  result.finalGrams = 99.0f;
  result.incrementAvailable = true;
  result.incrementGrams = 99.0f;

  RotationState rotation;
  startRotation(&rotation, 0);

  fillDispenseMeasurements(&result, true, 10.0f, rotation);

  TEST_ASSERT_TRUE(result.baselineAvailable);
  TEST_ASSERT_EQUAL_FLOAT(10.0f, result.baselineGrams);
  TEST_ASSERT_FALSE(result.finalAvailable);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, result.finalGrams);
  TEST_ASSERT_FALSE(result.incrementAvailable);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, result.incrementGrams);
}

void test_fill_measurements_with_null_result_is_safe(void) {
  const RotationState rotation = rotationWithLastValid(63.5f);

  fillDispenseMeasurements(nullptr, true, 12.5f, rotation);

  TEST_ASSERT_TRUE(true);
}

void test_fill_measurements_does_not_change_requested_or_reason(void) {
  DispenseResult result;
  result.requestedGrams = 37.5f;
  result.reason = DispenseReason::NOT_REACHED;
  result.baselineAvailable = false;
  result.baselineGrams = 0.0f;
  result.finalAvailable = false;
  result.finalGrams = 0.0f;
  result.incrementAvailable = false;
  result.incrementGrams = 0.0f;

  const RotationState rotation = rotationWithLastValid(50.0f);

  fillDispenseMeasurements(&result, true, 10.0f, rotation);

  TEST_ASSERT_EQUAL_FLOAT(37.5f, result.requestedGrams);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(DispenseReason::NOT_REACHED),
                        static_cast<int>(result.reason));
}

// --- calibracion real con peso patron de ~206.8 g (RF-11) ---

void test_real_calibration_converts_raw_to_grams(void) {
  TEST_ASSERT_FLOAT_WITHIN(0.05f, 332.83f,
                           convertRawToGrams(160658, 482.7f, 1.0f));
  TEST_ASSERT_FLOAT_WITHIN(0.05f, 539.67f,
                           convertRawToGrams(260500, 482.7f, 1.0f));
}

void test_placeholder_calibration_makes_real_readings_invalid(void) {
  // Reproduccion del fallo reportado: con el factor placeholder 7050 y signo
  // -1, el RAW real de la bandeja vacia (160658) da un peso negativo y toda
  // lectura se rechaza, por lo que la verificacion aborta.
  const WeightSample sample = makeSample(true, 160658, 7050.0f, -1.0f);
  TEST_ASSERT_FLOAT_WITHIN(0.05f, -22.79f, sample.grams);
  TEST_ASSERT_FALSE(isReadingValid(sample));
}

void test_real_calibration_reading_is_valid(void) {
  const WeightSample sample = makeSample(true, 160658, 482.7f, 1.0f);
  TEST_ASSERT_TRUE(isReadingValid(sample));
}

void test_verification_passes_with_five_real_readings(void) {
  VerificationState state;
  startVerification(&state, 0);

  const WeightSample sample = makeSample(true, 160658, 482.7f, 1.0f);
  for (unsigned i = 0; i < 5; ++i) {
    TEST_ASSERT_EQUAL_INT(
        static_cast<int>(VerificationOutcome::IN_PROGRESS),
        static_cast<int>(
            recordVerificationSample(&state, sample, i * 200UL)));
  }

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::PASSED),
      static_cast<int>(recordVerificationSample(&state, invalidSample(), 2000)));

  float baseline = 0.0f;
  TEST_ASSERT_TRUE(verificationBaseline(&state, &baseline));
  TEST_ASSERT_FLOAT_WITHIN(0.05f, 332.83f, baseline);
}

void test_verification_aborts_with_three_placeholder_readings(void) {
  VerificationState state;
  startVerification(&state, 0);

  const WeightSample sample = makeSample(true, 160658, 7050.0f, -1.0f);
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, sample, 0)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::IN_PROGRESS),
      static_cast<int>(recordVerificationSample(&state, sample, 200)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(VerificationOutcome::ABORTED_BY_INVALID),
      static_cast<int>(recordVerificationSample(&state, sample, 400)));
  TEST_ASSERT_TRUE(state.finished);
}

void test_real_calibration_reaches_fifty_grams_target(void) {
  const float baseline = convertRawToGrams(160658, 482.7f, 1.0f);
  RotationState state;
  startRotation(&state, 0);

  const WeightSample sample = makeSample(true, 184793, 482.7f, 1.0f);
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(RotationOutcome::CONTINUE),
      static_cast<int>(
          recordRotationSample(&state, sample, 0, baseline, 50.0f)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(RotationOutcome::CONTINUE),
      static_cast<int>(
          recordRotationSample(&state, sample, 200, baseline, 50.0f)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(RotationOutcome::TARGET_REACHED),
      static_cast<int>(
          recordRotationSample(&state, sample, 400, baseline, 50.0f)));

  TEST_ASSERT_TRUE(state.hasLastValid);
  TEST_ASSERT_FLOAT_WITHIN(0.05f, 382.83f, state.lastValidGrams);
  TEST_ASSERT_FLOAT_WITHIN(0.05f, 50.0f, state.lastValidGrams - baseline);
}

void test_real_calibration_get_real_increment_for_known_weight(void) {
  const float baseline = convertRawToGrams(160658, 482.7f, 1.0f);
  const WeightSample loaded = makeSample(true, 260500, 482.7f, 1.0f);

  RotationState rotation;
  startRotation(&rotation, 0);
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(RotationOutcome::CONTINUE),
      static_cast<int>(
          recordRotationSample(&rotation, loaded, 0, baseline, 500.0f)));

  DispenseResult result;
  result.requestedGrams = 500.0f;
  result.reason = DispenseReason::NOT_REACHED;
  result.baselineAvailable = false;
  result.baselineGrams = 0.0f;
  result.finalAvailable = false;
  result.finalGrams = 0.0f;
  result.incrementAvailable = false;
  result.incrementGrams = 0.0f;

  fillDispenseMeasurements(&result, true, baseline, rotation);

  TEST_ASSERT_TRUE(result.incrementAvailable);
  TEST_ASSERT_FLOAT_WITHIN(0.05f, 206.80f, result.incrementGrams);
}

int main(int argc, char **argv) {
  UNITY_BEGIN();
  RUN_TEST(test_classify_order_reset_wifi_has_absolute_priority);
  RUN_TEST(test_classify_order_rest_without_serve);
  RUN_TEST(test_classify_order_rest_with_zero_amount);
  RUN_TEST(test_classify_order_dispense_with_positive_amount);
  RUN_TEST(test_classify_order_invalid_when_amount_negative);
  RUN_TEST(test_classify_order_invalid_when_amount_absent);
  RUN_TEST(test_classify_order_invalid_when_amount_not_numeric);
  RUN_TEST(test_calibration_factor_accepts_positive_value);
  RUN_TEST(test_calibration_factor_rejects_zero_and_negative);
  RUN_TEST(test_calibration_factor_rejects_nan_and_infinity);
  RUN_TEST(test_convert_raw_to_grams_applies_sign_and_factor);
  RUN_TEST(test_convert_raw_to_grams_returns_nan_with_invalid_factor);
  RUN_TEST(test_is_raw_saturated_detects_both_extremes);
  RUN_TEST(test_reading_without_response_is_invalid);
  RUN_TEST(test_reading_with_negative_weight_is_invalid);
  RUN_TEST(test_reading_at_zero_grams_is_valid);
  RUN_TEST(test_reading_at_max_range_is_valid);
  RUN_TEST(test_reading_above_max_range_is_invalid);
  RUN_TEST(test_reading_with_nan_weight_is_invalid);
  RUN_TEST(test_reading_with_saturated_raw_is_invalid);
  RUN_TEST(test_median_odd_returns_central_value_without_modifying_input);
  RUN_TEST(test_median_even_returns_average_of_central_values);
  RUN_TEST(test_median_single_value);
  RUN_TEST(test_median_rejects_invalid_arguments);
  RUN_TEST(test_target_grams_adds_amount_to_baseline);
  RUN_TEST(test_format_dispense_log_complete_line);
  RUN_TEST(test_format_dispense_log_replaces_unavailable_values);
  RUN_TEST(test_format_dispense_log_includes_sensor_failure_reason);
  RUN_TEST(test_format_dispense_log_rejects_invalid_buffer);
  RUN_TEST(test_start_verification_opens_fixed_window);
  RUN_TEST(test_verification_window_is_exactly_two_seconds);
  RUN_TEST(test_verification_window_is_not_restarted_or_extended);
  RUN_TEST(test_verification_passes_with_exactly_five_valid_readings);
  RUN_TEST(test_verification_expires_with_four_valid_readings);
  RUN_TEST(test_verification_aborts_with_three_consecutive_invalid_readings);
  RUN_TEST(test_valid_reading_resets_consecutive_invalid_counter);
  RUN_TEST(test_isolated_invalid_reading_keeps_accumulated_valid_values);
  RUN_TEST(test_verification_baseline_is_median_of_window_values);
  RUN_TEST(test_verification_baseline_unavailable_without_valid_readings);
  RUN_TEST(test_record_after_finished_keeps_same_outcome_and_counters);
  RUN_TEST(test_record_with_null_state_is_safe);
  RUN_TEST(test_start_rotation_initializes_state);
  RUN_TEST(test_rotation_stops_after_three_consecutive_target_readings);
  RUN_TEST(test_valid_reading_below_target_resets_target_counter);
  RUN_TEST(test_target_requires_three_consecutive_readings_after_interruption);
  RUN_TEST(test_isolated_invalid_reading_does_not_stop_rotation);
  RUN_TEST(test_three_consecutive_invalid_readings_stop_rotation);
  RUN_TEST(test_rotation_stops_at_time_limit);
  RUN_TEST(test_sample_exactly_at_time_limit_is_not_recorded);
  RUN_TEST(test_last_valid_weight_tracks_only_valid_readings);
  RUN_TEST(test_record_after_rotation_finished_keeps_outcome_and_state);
  RUN_TEST(test_record_rotation_with_null_state_is_safe);
  RUN_TEST(test_is_check_due_waits_the_full_interval);
  RUN_TEST(test_is_check_due_tolerates_millis_rollover);
  RUN_TEST(test_time_limit_has_priority_over_invalid_readings_at_thirty_seconds);
  RUN_TEST(test_fill_measurements_with_baseline_and_last_valid_computes_increment);
  RUN_TEST(test_fill_measurements_without_baseline_keeps_final_but_not_increment);
  RUN_TEST(test_fill_measurements_without_last_valid_marks_final_and_increment_unavailable);
  RUN_TEST(test_fill_measurements_with_null_result_is_safe);
  RUN_TEST(test_fill_measurements_does_not_change_requested_or_reason);
  RUN_TEST(test_real_calibration_converts_raw_to_grams);
  RUN_TEST(test_placeholder_calibration_makes_real_readings_invalid);
  RUN_TEST(test_real_calibration_reading_is_valid);
  RUN_TEST(test_verification_passes_with_five_real_readings);
  RUN_TEST(test_verification_aborts_with_three_placeholder_readings);
  RUN_TEST(test_real_calibration_reaches_fifty_grams_target);
  RUN_TEST(test_real_calibration_get_real_increment_for_known_weight);
  return UNITY_END();
}
