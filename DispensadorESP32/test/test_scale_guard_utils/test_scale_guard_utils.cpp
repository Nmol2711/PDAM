#include <unity.h>

#include <cmath>

#include "config/dispensing_utils.h"
#include "config/scale_guard_utils.h"

// Pruebas nativas de la lógica pura de la Spec 016: asentamiento de la celda,
// validación de la línea base, plausibilidad del incremento y compuerta de
// entrada. No dependen de hardware ni de Arduino (RNF-5).

using namespace dispensing;

void setUp(void) {}

void tearDown(void) {}

namespace {

// Muestra válida: respondió, sin saturar y con gramos dentro de 0-5000 g.
WeightSample validSample(float grams) {
  WeightSample sample;
  sample.responded = true;
  sample.raw = 1000;
  sample.grams = grams;
  return sample;
}

// Muestra no respondida: la 013 la clasifica como inválida.
WeightSample invalidSample() {
  WeightSample sample;
  sample.responded = false;
  sample.raw = 0;
  sample.grams = 0.0f;
  return sample;
}

SettlementState freshSettlement() {
  SettlementState state{};
  invalidateSettlement(&state);
  return state;
}

// Alimenta la racha con lecturas válidas idénticas y devuelve el último veredicto.
SettlementOutcome feedStable(SettlementState *state, unsigned count, float grams) {
  SettlementOutcome outcome = SettlementOutcome::IN_PROGRESS;
  for (unsigned i = 0; i < count; ++i) {
    outcome = recordSettlementSample(state, validSample(grams));
  }
  return outcome;
}

// Construye una ventana de verificación con las lecturas válidas indicadas,
// una cada kSamplePeriodMs desde el arranque (caben diez antes de los 2 s).
VerificationState verificationWith(const float *values, unsigned count) {
  VerificationState state;
  startVerification(&state, 0);
  for (unsigned i = 0; i < count; ++i) {
    recordVerificationSample(&state, validSample(values[i]),
                             static_cast<unsigned long>(i) * kSamplePeriodMs);
  }
  return state;
}

} // namespace

// --- Asentamiento: racha de 15 lecturas válidas (RF-1, RF-2, RNF-1) ---

void test_settlement_not_gained_with_fourteen_stable_readings(void) {
  SettlementState state = freshSettlement();
  const SettlementOutcome outcome = feedStable(&state, 14, 10.0f);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(outcome));
  TEST_ASSERT_FALSE(settlementGained(state));
  TEST_ASSERT_EQUAL_UINT(14, state.streak);
}

void test_settlement_gained_exactly_at_fifteen_readings(void) {
  SettlementState state = freshSettlement();
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(feedStable(&state, 14, 10.0f)));
  TEST_ASSERT_FALSE(settlementGained(state));

  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::GAINED),
                        static_cast<int>(recordSettlementSample(
                            &state, validSample(10.0f))));
  TEST_ASSERT_TRUE(settlementGained(state));

  // Ganado una sola vez: la siguiente válida no repite el aviso de ganancia.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(recordSettlementSample(
                            &state, validSample(10.0f))));
  TEST_ASSERT_TRUE(settlementGained(state));
}

void test_settlement_keeps_streak_with_step_of_one_gram_exact(void) {
  SettlementState state = freshSettlement();
  // Paso de exactamente 1,0 g entre cada dos lecturas válidas: se conserva.
  for (unsigned i = 0; i < 14; ++i) {
    TEST_ASSERT_EQUAL_INT(
        static_cast<int>(SettlementOutcome::IN_PROGRESS),
        static_cast<int>(recordSettlementSample(
            &state, validSample(static_cast<float>(i)))));
  }
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::GAINED),
                        static_cast<int>(recordSettlementSample(
                            &state, validSample(14.0f))));
  TEST_ASSERT_TRUE(settlementGained(state));
}

void test_settlement_breaks_streak_with_step_above_one_gram(void) {
  SettlementState state = freshSettlement();
  feedStable(&state, 14, 0.0f);
  TEST_ASSERT_EQUAL_UINT(14, state.streak);

  // 1,01 g supera la tolerancia: la racha se rompe y reinicia en 1.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(recordSettlementSample(
                            &state, validSample(1.01f))));
  TEST_ASSERT_EQUAL_UINT(1, state.streak);
  TEST_ASSERT_FALSE(settlementGained(state));

  // Desde la racha reiniciada hacen falta 14 lecturas más para ganarlo.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(feedStable(&state, 13, 1.01f)));
  TEST_ASSERT_FALSE(settlementGained(state));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::GAINED),
                        static_cast<int>(recordSettlementSample(
                            &state, validSample(1.01f))));
}

void test_isolated_invalid_reading_breaks_streak_without_removing_settlement(void) {
  SettlementState state = freshSettlement();
  feedStable(&state, 15, 10.0f);
  TEST_ASSERT_TRUE(settlementGained(state));

  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(recordSettlementSample(
                            &state, invalidSample())));
  TEST_ASSERT_TRUE(settlementGained(state));
  TEST_ASSERT_EQUAL_UINT(0, state.streak);

  // Con el asentamiento ya ganado, la racha nueva no repite el aviso.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(feedStable(&state, 15, 10.0f)));
  TEST_ASSERT_TRUE(settlementGained(state));
}

void test_three_consecutive_invalid_readings_remove_settlement(void) {
  SettlementState state = freshSettlement();
  feedStable(&state, 15, 10.0f);
  TEST_ASSERT_TRUE(settlementGained(state));

  recordSettlementSample(&state, invalidSample());
  recordSettlementSample(&state, invalidSample());
  TEST_ASSERT_TRUE(settlementGained(state));

  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::LOST),
                        static_cast<int>(recordSettlementSample(
                            &state, invalidSample())));
  TEST_ASSERT_FALSE(settlementGained(state));
}

void test_two_invalid_readings_then_valid_restart_invalid_counter(void) {
  SettlementState state = freshSettlement();
  feedStable(&state, 15, 10.0f);
  TEST_ASSERT_TRUE(settlementGained(state));

  recordSettlementSample(&state, invalidSample());
  recordSettlementSample(&state, invalidSample());
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveInvalid);

  // Una válida reinicia el contador de inválidas consecutivas.
  recordSettlementSample(&state, validSample(10.0f));
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveInvalid);

  recordSettlementSample(&state, invalidSample());
  recordSettlementSample(&state, invalidSample());
  TEST_ASSERT_TRUE(settlementGained(state));
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveInvalid);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::LOST),
                        static_cast<int>(recordSettlementSample(
                            &state, invalidSample())));
  TEST_ASSERT_FALSE(settlementGained(state));
}

void test_settlement_needs_fifteen_new_readings_after_loss(void) {
  SettlementState state = freshSettlement();
  feedStable(&state, 15, 10.0f);
  recordSettlementSample(&state, invalidSample());
  recordSettlementSample(&state, invalidSample());
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::LOST),
                        static_cast<int>(recordSettlementSample(
                            &state, invalidSample())));
  TEST_ASSERT_FALSE(settlementGained(state));

  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(feedStable(&state, 14, 10.0f)));
  TEST_ASSERT_FALSE(settlementGained(state));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::GAINED),
                        static_cast<int>(recordSettlementSample(
                            &state, validSample(10.0f))));
  TEST_ASSERT_TRUE(settlementGained(state));
}

void test_settlement_lost_after_top_closure_needs_fifteen_new_readings(void) {
  SettlementState state = freshSettlement();
  feedStable(&state, 15, 10.0f);
  TEST_ASSERT_TRUE(settlementGained(state));

  // El ciclo cierra por tope tras tres lecturas válidas consecutivas. La
  // distinción de la causa vive en la lógica pura; el consumidor (api_service)
  // solo ve el motivo del cierre y pasa su texto a invalidateSettlement.
  const float amount = 17.27f;
  const float aboveTop = plausibilityTopGrams(amount) + 0.01f;
  PlausibilityState plausibility{};
  resetPlausibility(&plausibility);
  recordPlausibilitySample(&plausibility, aboveTop, amount);
  recordPlausibilitySample(&plausibility, aboveTop, amount);
  const PlausibilityVerdict verdict =
      recordPlausibilitySample(&plausibility, aboveTop, amount);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::ABOVE_TOP),
                        static_cast<int>(verdict));

  const char *motivo = plausibilityCauseText(verdict);
  TEST_ASSERT_EQUAL_STRING("plausibilidad_tope", motivo);

  invalidateSettlement(&state);
  TEST_ASSERT_FALSE(settlementGained(state));
  TEST_ASSERT_EQUAL_UINT(0, state.streak);
  TEST_ASSERT_FALSE(state.hasPrevious);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveInvalid);

  // Ni con 14 lecturas nuevas: hacen falta 15 para volver a dispensar.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(feedStable(&state, 14, 10.0f)));
  TEST_ASSERT_FALSE(settlementGained(state));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::GAINED),
                        static_cast<int>(recordSettlementSample(
                            &state, validSample(10.0f))));
  TEST_ASSERT_TRUE(settlementGained(state));
}

void test_settlement_lost_after_floor_closure_needs_fifteen_new_readings(void) {
  SettlementState state = freshSettlement();
  // Base de 12 g: retirar la bandeja cruza el suelo de -10 g respecto de ella.
  feedStable(&state, 15, 12.0f);
  TEST_ASSERT_TRUE(settlementGained(state));

  const float amount = 20.0f;
  PlausibilityState plausibility{};
  resetPlausibility(&plausibility);
  recordPlausibilitySample(&plausibility, -10.01f, amount);
  recordPlausibilitySample(&plausibility, -10.01f, amount);
  const PlausibilityVerdict verdict =
      recordPlausibilitySample(&plausibility, -10.01f, amount);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::BELOW_FLOOR),
                        static_cast<int>(verdict));

  const char *motivo = plausibilityCauseText(verdict);
  TEST_ASSERT_EQUAL_STRING("plausibilidad_suelo", motivo);

  invalidateSettlement(&state);
  TEST_ASSERT_FALSE(settlementGained(state));
  TEST_ASSERT_EQUAL_UINT(0, state.streak);
  TEST_ASSERT_FALSE(state.hasPrevious);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(feedStable(&state, 14, 12.0f)));
  TEST_ASSERT_FALSE(settlementGained(state));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::GAINED),
                        static_cast<int>(recordSettlementSample(
                            &state, validSample(12.0f))));
  TEST_ASSERT_TRUE(settlementGained(state));
}

void test_invalidate_settlement_clears_even_a_complete_streak(void) {
  SettlementState state = freshSettlement();
  feedStable(&state, 15, 10.0f);
  TEST_ASSERT_TRUE(settlementGained(state));

  invalidateSettlement(&state);
  TEST_ASSERT_FALSE(settlementGained(state));
  TEST_ASSERT_EQUAL_UINT(0, state.streak);
  TEST_ASSERT_FALSE(state.hasPrevious);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutiveInvalid);

  // Aunque la racha estuviera completa, hacen falta 15 lecturas nuevas.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::IN_PROGRESS),
                        static_cast<int>(feedStable(&state, 14, 10.0f)));
  TEST_ASSERT_FALSE(settlementGained(state));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SettlementOutcome::GAINED),
                        static_cast<int>(recordSettlementSample(
                            &state, validSample(10.0f))));
}

void test_reading_out_of_range_counts_as_invalid_for_settlement(void) {
  SettlementState state = freshSettlement();
  feedStable(&state, 14, 10.0f);

  // Fuera de 0-5000 g y saturada: cuentan como inválidas y rompen la racha.
  recordSettlementSample(&state, validSample(5001.0f));
  TEST_ASSERT_EQUAL_UINT(0, state.streak);
  TEST_ASSERT_EQUAL_UINT(1, state.consecutiveInvalid);

  WeightSample saturated = validSample(10.0f);
  saturated.raw = kRawSaturationMax;
  recordSettlementSample(&state, saturated);
  TEST_ASSERT_EQUAL_UINT(2, state.consecutiveInvalid);
  TEST_ASSERT_FALSE(settlementGained(state));
}

// --- Línea base: mediana de todas las válidas y estabilidad de las últimas 5
// (RF-2, RF-3, RF-4) ---

void test_baseline_median_with_odd_number_of_valid_readings(void) {
  const float values[] = {10.0f, 11.0f, 12.0f, 13.0f, 14.0f};
  const VerificationState state = verificationWith(values, 5);

  float baseline = -1.0f;
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineVerdict::ACCEPTED),
                        static_cast<int>(assessBaseline(state, &baseline)));
  TEST_ASSERT_EQUAL_FLOAT(12.0f, baseline);
}

void test_baseline_median_with_even_number_of_valid_readings(void) {
  const float values[] = {10.0f, 11.0f, 12.0f, 13.0f, 14.0f, 15.0f};
  const VerificationState state = verificationWith(values, 6);

  float baseline = -1.0f;
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineVerdict::ACCEPTED),
                        static_cast<int>(assessBaseline(state, &baseline)));
  // Número par: promedio de los dos centrales.
  TEST_ASSERT_EQUAL_FLOAT(12.5f, baseline);
}

void test_baseline_median_uses_all_valid_readings_not_only_the_last_five(void) {
  // Un pico en la primera lectura no afecta a la mediana, que es la de todas
  // las válidas; la estabilidad solo mira las últimas cinco.
  const float values[] = {30.0f, 10.0f, 11.0f, 12.0f, 13.0f,
                          14.0f, 15.0f, 16.0f, 17.0f};
  const VerificationState state = verificationWith(values, 9);

  float baseline = -1.0f;
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineVerdict::ACCEPTED),
                        static_cast<int>(assessBaseline(state, &baseline)));
  TEST_ASSERT_EQUAL_FLOAT(14.0f, baseline);
}

void test_baseline_accepts_step_of_one_gram_exact(void) {
  const float values[] = {10.0f, 11.0f, 12.0f, 13.0f, 14.01f};
  const VerificationState state = verificationWith(values, 5);

  float baseline = -1.0f;
  // 14,01 - 13,00 = 1,01 g: supera la tolerancia y la base es inestable.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineVerdict::UNSTABLE),
                        static_cast<int>(assessBaseline(state, &baseline)));

  const float stable[] = {10.0f, 11.0f, 12.0f, 13.0f, 14.0f};
  const VerificationState stableState = verificationWith(stable, 5);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineVerdict::ACCEPTED),
                        static_cast<int>(assessBaseline(stableState, &baseline)));
}

void test_baseline_unstable_when_last_step_exceeds_one_gram(void) {
  const float values[] = {10.0f, 10.0f, 10.0f, 10.0f, 11.01f};
  const VerificationState state = verificationWith(values, 5);

  float baseline = -1.0f;
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineVerdict::UNSTABLE),
                        static_cast<int>(assessBaseline(state, &baseline)));
}

void test_baseline_insufficient_with_four_valid_readings(void) {
  const float values[] = {10.0f, 10.0f, 10.0f, 10.0f};
  const VerificationState state = verificationWith(values, 4);

  float baseline = -1.0f;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(BaselineVerdict::INSUFFICIENT_READINGS),
      static_cast<int>(assessBaseline(state, &baseline)));
}

void test_baseline_of_zero_grams_is_accepted(void) {
  const float values[] = {0.0f, 0.0f, 0.0f, 0.0f, 0.0f};
  const VerificationState state = verificationWith(values, 5);

  float baseline = -1.0f;
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineVerdict::ACCEPTED),
                        static_cast<int>(assessBaseline(state, &baseline)));
  TEST_ASSERT_EQUAL_FLOAT(0.0f, baseline);
}

void test_baseline_negative_readings_leave_window_insufficient(void) {
  // La 013 clasifica las lecturas negativas como inválidas, así que no entran
  // en la mediana; con cuatro válidas la ventana no reúne el mínimo y el
  // motivo es lecturas_insuficientes (RF-4).
  const float values[] = {10.0f, 10.0f, 10.0f, 10.0f};
  VerificationState state = verificationWith(values, 4);
  recordVerificationSample(&state, validSample(-3.0f), 4UL * kSamplePeriodMs);
  TEST_ASSERT_EQUAL_UINT(4, state.validCount);
  TEST_ASSERT_EQUAL_UINT(4, state.storedCount);

  float baseline = -1.0f;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(BaselineVerdict::INSUFFICIENT_READINGS),
      static_cast<int>(assessBaseline(state, &baseline)));
}

void test_baseline_invalid_when_buffer_is_empty_with_high_valid_count(void) {
  // Con muestras reales INVALID_BASELINE es inalcanzable: recordVerificationSample
  // solo guarda las lecturas que pasan isReadingValid, así que un validCount alto
  // siempre deja valores almacenados en 0-5000 g. Este estado se manipula a mano
  // para cubrir el caso defensivo de RF-3.
  VerificationState state{};
  startVerification(&state, 0);
  state.validCount = 5;
  state.storedCount = 0;

  float baseline = -1.0f;
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineVerdict::INVALID_BASELINE),
                        static_cast<int>(assessBaseline(state, &baseline)));
}

void test_baseline_invalid_when_median_is_out_of_range(void) {
  // Igual que el caso anterior: valores inyectados a mano fuera de 0-5000 g,
  // imposibles con recordVerificationSample. Es el caso defensivo de RF-3.
  VerificationState state{};
  startVerification(&state, 0);
  state.validCount = 5;
  state.storedCount = 5;
  for (unsigned i = 0; i < 5; ++i) {
    state.validValues[i] = 6000.0f;
  }

  float baseline = -1.0f;
  TEST_ASSERT_EQUAL_INT(static_cast<int>(BaselineVerdict::INVALID_BASELINE),
                        static_cast<int>(assessBaseline(state, &baseline)));
}

void test_baseline_rejection_texts_are_spanish(void) {
  TEST_ASSERT_EQUAL_STRING("inestable",
                           baselineRejectionText(BaselineVerdict::UNSTABLE));
  TEST_ASSERT_EQUAL_STRING(
      "lecturas_insuficientes",
      baselineRejectionText(BaselineVerdict::INSUFFICIENT_READINGS));
  TEST_ASSERT_EQUAL_STRING(
      "linea_base_invalida",
      baselineRejectionText(BaselineVerdict::INVALID_BASELINE));
}

// --- Plausibilidad del incremento (RF-5, RF-6) ---

void test_plausibility_top_of_seventeen_grams_is_three_times(void) {
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 51.81f, plausibilityTopGrams(17.27f));
}

void test_plausibility_top_of_one_hundred_grams_is_three_times(void) {
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 300.0f, plausibilityTopGrams(100.0f));
}

void test_plausibility_top_of_two_grams_uses_margin(void) {
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.0f, plausibilityTopGrams(2.0f));
}

void test_increment_equal_to_top_is_plausible(void) {
  const float amount = 17.27f;
  const float top = plausibilityTopGrams(amount);
  PlausibilityState state{};
  resetPlausibility(&state);

  for (unsigned i = 0; i < 3; ++i) {
    TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                          static_cast<int>(recordPlausibilitySample(
                              &state, top, amount)));
  }
  TEST_ASSERT_EQUAL_UINT(0, state.consecutive);
}

void test_increment_above_top_closes_on_third_consecutive(void) {
  const float amount = 17.27f;
  const float aboveTop = plausibilityTopGrams(amount) + 0.01f;
  PlausibilityState state{};
  resetPlausibility(&state);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(recordPlausibilitySample(
                            &state, aboveTop, amount)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(recordPlausibilitySample(
                            &state, aboveTop, amount)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::ABOVE_TOP),
                        static_cast<int>(recordPlausibilitySample(
                            &state, aboveTop, amount)));
}

void test_increment_at_floor_is_plausible(void) {
  PlausibilityState state{};
  resetPlausibility(&state);

  for (unsigned i = 0; i < 3; ++i) {
    TEST_ASSERT_EQUAL_INT(
        static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
        static_cast<int>(recordPlausibilitySample(&state, -10.0f, 20.0f)));
  }
  TEST_ASSERT_EQUAL_UINT(0, state.consecutive);
}

void test_increment_below_floor_closes_on_third_consecutive(void) {
  PlausibilityState state{};
  resetPlausibility(&state);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(recordPlausibilitySample(
                            &state, -10.01f, 20.0f)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(recordPlausibilitySample(
                            &state, -10.01f, 20.0f)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::BELOW_FLOOR),
                        static_cast<int>(recordPlausibilitySample(
                            &state, -10.01f, 20.0f)));
}

void test_valid_increment_inside_range_resets_the_counter(void) {
  const float amount = 20.0f;
  const float aboveTop = plausibilityTopGrams(amount) + 5.0f;
  PlausibilityState state{};
  resetPlausibility(&state);

  recordPlausibilitySample(&state, aboveTop, amount);
  recordPlausibilitySample(&state, aboveTop, amount);
  TEST_ASSERT_EQUAL_UINT(2, state.consecutive);

  // Una lectura dentro del intervalo reinicia el contador de consecutivas.
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(recordPlausibilitySample(
                            &state, 5.0f, amount)));
  TEST_ASSERT_EQUAL_UINT(0, state.consecutive);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(recordPlausibilitySample(
                            &state, aboveTop, amount)));
  TEST_ASSERT_EQUAL_UINT(1, state.consecutive);
}

void test_reset_plausibility_clears_the_counter(void) {
  const float amount = 20.0f;
  const float aboveTop = plausibilityTopGrams(amount) + 5.0f;
  PlausibilityState state{};
  resetPlausibility(&state);

  recordPlausibilitySample(&state, aboveTop, amount);
  recordPlausibilitySample(&state, aboveTop, amount);
  TEST_ASSERT_EQUAL_UINT(2, state.consecutive);

  resetPlausibility(&state);
  TEST_ASSERT_EQUAL_UINT(0, state.consecutive);

  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(recordPlausibilitySample(
                            &state, aboveTop, amount)));
}

void test_two_outside_one_invalid_then_outside_does_not_close(void) {
  // RF-5 exige tres lecturas VÁLIDAS consecutivas: una inválida en medio
  // reinicia el contador (resetPlausibility), así que no hay cierre.
  const float amount = 20.0f;
  const float aboveTop = plausibilityTopGrams(amount) + 5.0f;
  PlausibilityState state{};
  resetPlausibility(&state);

  recordPlausibilitySample(&state, aboveTop, amount);
  recordPlausibilitySample(&state, aboveTop, amount);

  resetPlausibility(&state); // lectura inválida en el ciclo

  TEST_ASSERT_EQUAL_INT(static_cast<int>(PlausibilityVerdict::PLAUSIBLE),
                        static_cast<int>(recordPlausibilitySample(
                            &state, aboveTop, amount)));
  TEST_ASSERT_EQUAL_UINT(1, state.consecutive);
}

void test_plausibility_cause_texts_are_spanish(void) {
  TEST_ASSERT_EQUAL_STRING(
      "incremento_plausible",
      plausibilityCauseText(PlausibilityVerdict::PLAUSIBLE));
  TEST_ASSERT_EQUAL_STRING("plausibilidad_tope",
                           plausibilityCauseText(PlausibilityVerdict::ABOVE_TOP));
  TEST_ASSERT_EQUAL_STRING("plausibilidad_suelo",
                           plausibilityCauseText(PlausibilityVerdict::BELOW_FLOOR));
}

// --- Compuerta de entrada (RF-1) ---

void test_gate_requires_settlement_only_for_dispense(void) {
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(DispenseEntry::REJECT_NO_SETTLEMENT),
      static_cast<int>(decideDispenseEntry(OrderAction::DISPENSE, false)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(DispenseEntry::DISPENSE),
      static_cast<int>(decideDispenseEntry(OrderAction::DISPENSE, true)));
}

void test_gate_does_not_change_other_actions(void) {
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(DispenseEntry::REST),
      static_cast<int>(decideDispenseEntry(OrderAction::REST, false)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(DispenseEntry::REST),
      static_cast<int>(decideDispenseEntry(OrderAction::REST, true)));

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(DispenseEntry::RESET_WIFI),
      static_cast<int>(decideDispenseEntry(OrderAction::RESET_WIFI, false)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(DispenseEntry::RESET_WIFI),
      static_cast<int>(decideDispenseEntry(OrderAction::RESET_WIFI, true)));

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(DispenseEntry::REJECT_ORDER),
      static_cast<int>(decideDispenseEntry(OrderAction::INVALID_ORDER, false)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(DispenseEntry::REJECT_ORDER),
      static_cast<int>(decideDispenseEntry(OrderAction::INVALID_ORDER, true)));
}

// --- Caso (d): factor de calibración cero, negativo, NaN o infinito ---

void test_invalid_calibration_factor_never_gains_settlement(void) {
  const float factors[] = {0.0f, -1.0f, NAN, INFINITY};
  for (unsigned f = 0; f < 4; ++f) {
    SettlementState state = freshSettlement();
    bool gained = false;
    for (unsigned i = 0; i < 40; ++i) {
      const WeightSample sample = makeSample(true, 1000, factors[f], -1.0f);
      TEST_ASSERT_FALSE(isReadingValid(sample));
      if (recordSettlementSample(&state, sample) ==
          SettlementOutcome::GAINED) {
        gained = true;
      }
    }
    TEST_ASSERT_FALSE(gained);
    TEST_ASSERT_FALSE(settlementGained(state));
    TEST_ASSERT_EQUAL_INT(
        static_cast<int>(DispenseEntry::REJECT_NO_SETTLEMENT),
        static_cast<int>(decideDispenseEntry(OrderAction::DISPENSE,
                                             settlementGained(state))));
  }
}

// --- Constantes nuevas y cotas de la 013 (RNF-3) ---

void test_new_constants_have_the_approved_values(void) {
  TEST_ASSERT_EQUAL_UINT(15, kSettlementReadings);
  TEST_ASSERT_EQUAL_FLOAT(1.0f, kSettlementMaxStepGrams);
  TEST_ASSERT_EQUAL_FLOAT(3.0f, kPlausibilityFactor);
  TEST_ASSERT_EQUAL_FLOAT(10.0f, kPlausibilityMarginGrams);
  TEST_ASSERT_EQUAL_FLOAT(-10.0f, kPlausibilityFloorGrams);
  TEST_ASSERT_EQUAL_UINT(3, kPlausibilityConsecutiveReadings);
}

void test_median_buffer_covers_every_valid_reading_of_the_window(void) {
  // El buffer de la 013 no es un anillo: la mediana debe seguir siendo la de
  // todas las válidas de la ventana de 2 s.
  TEST_ASSERT_TRUE(kMedianBufferSize >= 11);
  TEST_ASSERT_EQUAL_UINT(5, kMinValidReadings);
  TEST_ASSERT_EQUAL_UINT(3, kMaxConsecutiveInvalidReadings);
}

int main(int, char **) {
  UNITY_BEGIN();

  RUN_TEST(test_settlement_not_gained_with_fourteen_stable_readings);
  RUN_TEST(test_settlement_gained_exactly_at_fifteen_readings);
  RUN_TEST(test_settlement_keeps_streak_with_step_of_one_gram_exact);
  RUN_TEST(test_settlement_breaks_streak_with_step_above_one_gram);
  RUN_TEST(test_isolated_invalid_reading_breaks_streak_without_removing_settlement);
  RUN_TEST(test_three_consecutive_invalid_readings_remove_settlement);
  RUN_TEST(test_two_invalid_readings_then_valid_restart_invalid_counter);
  RUN_TEST(test_settlement_needs_fifteen_new_readings_after_loss);
  RUN_TEST(test_settlement_lost_after_top_closure_needs_fifteen_new_readings);
  RUN_TEST(test_settlement_lost_after_floor_closure_needs_fifteen_new_readings);
  RUN_TEST(test_invalidate_settlement_clears_even_a_complete_streak);
  RUN_TEST(test_reading_out_of_range_counts_as_invalid_for_settlement);

  RUN_TEST(test_baseline_median_with_odd_number_of_valid_readings);
  RUN_TEST(test_baseline_median_with_even_number_of_valid_readings);
  RUN_TEST(test_baseline_median_uses_all_valid_readings_not_only_the_last_five);
  RUN_TEST(test_baseline_accepts_step_of_one_gram_exact);
  RUN_TEST(test_baseline_unstable_when_last_step_exceeds_one_gram);
  RUN_TEST(test_baseline_insufficient_with_four_valid_readings);
  RUN_TEST(test_baseline_of_zero_grams_is_accepted);
  RUN_TEST(test_baseline_negative_readings_leave_window_insufficient);
  RUN_TEST(test_baseline_invalid_when_buffer_is_empty_with_high_valid_count);
  RUN_TEST(test_baseline_invalid_when_median_is_out_of_range);
  RUN_TEST(test_baseline_rejection_texts_are_spanish);

  RUN_TEST(test_plausibility_top_of_seventeen_grams_is_three_times);
  RUN_TEST(test_plausibility_top_of_one_hundred_grams_is_three_times);
  RUN_TEST(test_plausibility_top_of_two_grams_uses_margin);
  RUN_TEST(test_increment_equal_to_top_is_plausible);
  RUN_TEST(test_increment_above_top_closes_on_third_consecutive);
  RUN_TEST(test_increment_at_floor_is_plausible);
  RUN_TEST(test_increment_below_floor_closes_on_third_consecutive);
  RUN_TEST(test_valid_increment_inside_range_resets_the_counter);
  RUN_TEST(test_reset_plausibility_clears_the_counter);
  RUN_TEST(test_two_outside_one_invalid_then_outside_does_not_close);
  RUN_TEST(test_plausibility_cause_texts_are_spanish);

  RUN_TEST(test_gate_requires_settlement_only_for_dispense);
  RUN_TEST(test_gate_does_not_change_other_actions);

  RUN_TEST(test_invalid_calibration_factor_never_gains_settlement);

  RUN_TEST(test_new_constants_have_the_approved_values);
  RUN_TEST(test_median_buffer_covers_every_valid_reading_of_the_window);

  return UNITY_END();
}
