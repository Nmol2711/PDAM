"""Pruebas unitarias del motor de cálculo nutricional WSAVA.

Cubre RF-3 de la Spec 011: funciones puras para RER, MER con factores
correctores, rango de variabilidad fisiológica, evaluación del límite de snacks
al 10% del MER con recálculo de ración principal, y conversión ponderal a gramos.

Las funciones probadas viven en `app/services/nutrition_service.py` y no tienen
efectos secundarios (RNF-1: determinismo).
"""

import sys
from pathlib import Path

import pytest

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.services.nutrition_service import (
    calculate_daily_ration_grams,
    calculate_mer,
    calculate_rer,
    evaluate_snacks,
    get_variability_range,
)


# ---------------------------------------------------------------------------
# calculate_rer
# ---------------------------------------------------------------------------


class TestCalculateRer:
    """RF-3: RER = 70 * BW^0.75 (Requerimiento de Energía en Reposo)."""

    def test_rer_known_weight(self):
        assert calculate_rer(10.0) == pytest.approx(393.6389276332444)

    def test_rer_unit_weight(self):
        assert calculate_rer(1.0) == pytest.approx(70.0)

    def test_rer_positive_fractional_weight(self):
        assert calculate_rer(12.5) == pytest.approx(465.3508909826865)

    def test_rer_zero_weight_raises(self):
        with pytest.raises(ValueError):
            calculate_rer(0.0)

    def test_rer_negative_weight_raises(self):
        with pytest.raises(ValueError):
            calculate_rer(-5.0)


# ---------------------------------------------------------------------------
# calculate_mer (factores correctores WSAVA)
# ---------------------------------------------------------------------------


class TestCalculateMerBaseFactors:
    """Factores base MER por especie, estatus reproductivo y etapa de vida.

    Para aislar el factor base, se fijan actividad=medium, bcs=5 y mcs=normal
    (multiplicadores neutros de 1.0) y se usa rer=100 para leer el factor.
    """

    def test_canino_adulto_entero(self):
        assert calculate_mer(100.0, "canino", "entero", "adulto", "medium", 5, "normal") == pytest.approx(180.0)

    def test_canino_adulto_castrado(self):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "medium", 5, "normal") == pytest.approx(160.0)

    def test_canino_adulto_esterilizado(self):
        assert calculate_mer(100.0, "canino", "esterilizado", "adulto", "medium", 5, "normal") == pytest.approx(160.0)

    def test_canino_crecimiento(self):
        assert calculate_mer(100.0, "canino", "entero", "crecimiento", "medium", 5, "normal") == pytest.approx(200.0)

    def test_felino_adulto_entero(self):
        assert calculate_mer(100.0, "felino", "entero", "adulto", "medium", 5, "normal") == pytest.approx(140.0)

    def test_felino_adulto_castrado(self):
        assert calculate_mer(100.0, "felino", "castrado", "adulto", "medium", 5, "normal") == pytest.approx(120.0)

    def test_felino_crecimiento(self):
        assert calculate_mer(100.0, "felino", "entero", "crecimiento", "medium", 5, "normal") == pytest.approx(250.0)


class TestCalculateMerActivityFactors:
    """Factor de actividad: low=0.9, medium=1.0, high=1.2."""

    def test_low_activity_reduces_mer(self):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "low", 5, "normal") == pytest.approx(144.0)

    def test_medium_activity_neutral(self):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "medium", 5, "normal") == pytest.approx(160.0)

    def test_high_activity_increases_mer(self):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "high", 5, "normal") == pytest.approx(192.0)


class TestCalculateMerBcsFactors:
    """Factor de condición corporal: bcs<=3 -> 1.2, 4..6 -> 1.0, bcs>=7 -> 0.8."""

    @pytest.mark.parametrize("bcs", [1, 2, 3])
    def test_low_bcs_increases_mer(self, bcs):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "medium", bcs, "normal") == pytest.approx(192.0)

    @pytest.mark.parametrize("bcs", [4, 5, 6])
    def test_ideal_bcs_neutral(self, bcs):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "medium", bcs, "normal") == pytest.approx(160.0)

    @pytest.mark.parametrize("bcs", [7, 8, 9])
    def test_high_bcs_reduces_mer(self, bcs):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "medium", bcs, "normal") == pytest.approx(128.0)


class TestCalculateMerMcsFactors:
    """Factor de masa muscular: normal/mild -> 1.0, moderate -> 0.95, marked -> 0.9."""

    @pytest.mark.parametrize("mcs", ["normal", "mild"])
    def test_normal_mild_neutral(self, mcs):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "medium", 5, mcs) == pytest.approx(160.0)

    def test_moderate_reduces_mer(self):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "medium", 5, "moderate") == pytest.approx(152.0)

    def test_marked_reduces_mer(self):
        assert calculate_mer(100.0, "canino", "castrado", "adulto", "medium", 5, "marked") == pytest.approx(144.0)


class TestCalculateMerCombined:
    """Combinación de factores correctores aplicados de forma multiplicativa."""

    def test_full_realistic_example(self):
        rer = calculate_rer(10.0)
        mer = calculate_mer(rer, "canino", "castrado", "adulto", "medium", 5, "normal")
        assert mer == pytest.approx(629.8222842131911)

    def test_combined_high_activity_underweight_moderate_mcs(self):
        rer = calculate_rer(10.0)
        mer = calculate_mer(rer, "canino", "castrado", "adulto", "high", 3, "moderate")
        assert mer == pytest.approx(861.5968848036454)

    def test_combined_feline_low_activity_overweight_marked_mcs(self):
        rer = calculate_rer(10.0)
        mer = calculate_mer(rer, "felino", "entero", "adulto", "low", 8, "marked")
        assert mer == pytest.approx(357.1092351488793)

    def test_deterministic_same_input_same_output(self):
        first = calculate_mer(250.0, "felino", "esterilizado", "adulto", "medium", 5, "normal")
        second = calculate_mer(250.0, "felino", "esterilizado", "adulto", "medium", 5, "normal")
        assert first == second


class TestCalculateMerInvalidInputs:
    """Entradas fuera de los whitelists levantan ValueError explícito."""

    @pytest.mark.parametrize("species", ["ave", "conejo", "", "CANINO_FALSO"])
    def test_invalid_species_raises(self, species):
        with pytest.raises(ValueError):
            calculate_mer(100.0, species, "castrado", "adulto", "medium", 5, "normal")

    @pytest.mark.parametrize("status", ["preñada", "lactante", ""])
    def test_invalid_reproductive_status_raises(self, status):
        with pytest.raises(ValueError):
            calculate_mer(100.0, "canino", status, "adulto", "medium", 5, "normal")

    @pytest.mark.parametrize("stage", ["senior", "juvenil", ""])
    def test_invalid_life_stage_raises(self, stage):
        with pytest.raises(ValueError):
            calculate_mer(100.0, "canino", "castrado", stage, "medium", 5, "normal")

    @pytest.mark.parametrize("activity", ["extremo", "sedentario", ""])
    def test_invalid_activity_raises(self, activity):
        with pytest.raises(ValueError):
            calculate_mer(100.0, "canino", "castrado", "adulto", activity, 5, "normal")

    @pytest.mark.parametrize("mcs", ["severo", "excelente", ""])
    def test_invalid_mcs_raises(self, mcs):
        with pytest.raises(ValueError):
            calculate_mer(100.0, "canino", "castrado", "adulto", "medium", 5, mcs)


# ---------------------------------------------------------------------------
# get_variability_range
# ---------------------------------------------------------------------------


class TestVariabilityRange:
    """RF-3: variabilidad fisiológica ±30% perros, ±50% gatos."""

    def test_canino_variability(self):
        assert get_variability_range("canino", 100.0) == pytest.approx((70.0, 130.0))

    def test_felino_variability(self):
        assert get_variability_range("felino", 100.0) == pytest.approx((50.0, 150.0))

    def test_canino_zero_mer(self):
        assert get_variability_range("canino", 0.0) == pytest.approx((0.0, 0.0))

    def test_returns_tuple_of_two_floats(self):
        result = get_variability_range("canino", 300.0)
        assert isinstance(result, tuple)
        assert len(result) == 2
        assert result[0] < result[1]

    @pytest.mark.parametrize("species", ["ave", "", "felino_falso"])
    def test_invalid_species_raises(self, species):
        with pytest.raises(ValueError):
            get_variability_range(species, 100.0)


# ---------------------------------------------------------------------------
# evaluate_snacks
# ---------------------------------------------------------------------------


class TestEvaluateSnacks:
    """RF-3: límite de snacks al 10% del MER con alerta/bloqueo y recálculo."""

    def test_snacks_below_limit_no_alert(self):
        result = evaluate_snacks(1000.0, 50.0)
        assert result["snack_limit_kcal"] == pytest.approx(100.0)
        assert result["exceeds_limit"] is False
        assert result["final_ration_kcal"] == pytest.approx(950.0)

    def test_snacks_at_limit_not_exceeding(self):
        result = evaluate_snacks(1000.0, 100.0)
        assert result["exceeds_limit"] is False
        assert result["final_ration_kcal"] == pytest.approx(900.0)

    def test_snacks_above_limit_alert(self):
        result = evaluate_snacks(1000.0, 100.1)
        assert result["exceeds_limit"] is True
        assert result["final_ration_kcal"] == pytest.approx(899.9)

    def test_snacks_greater_than_mer_clamps_ration_to_zero(self):
        result = evaluate_snacks(1000.0, 1500.0)
        assert result["exceeds_limit"] is True
        assert result["final_ration_kcal"] == 0.0

    def test_zero_snacks_keeps_full_mer(self):
        result = evaluate_snacks(800.0, 0.0)
        assert result["exceeds_limit"] is False
        assert result["final_ration_kcal"] == pytest.approx(800.0)

    def test_returns_expected_keys(self):
        result = evaluate_snacks(500.0, 20.0)
        assert set(result.keys()) == {
            "snack_limit_kcal",
            "snacks_kcal",
            "exceeds_limit",
            "final_ration_kcal",
        }


# ---------------------------------------------------------------------------
# calculate_daily_ration_grams
# ---------------------------------------------------------------------------


class TestDailyRationGrams:
    """RF-3: conversión ponderal de kcal a gramos con división segura."""

    def test_ration_grams_typical(self):
        assert calculate_daily_ration_grams(600.0, 4000.0) == pytest.approx(150.0)

    def test_ration_grams_density_1000(self):
        assert calculate_daily_ration_grams(600.0, 1000.0) == pytest.approx(600.0)

    def test_zero_ration_returns_zero(self):
        assert calculate_daily_ration_grams(0.0, 4000.0) == 0.0

    def test_zero_density_is_safe(self):
        assert calculate_daily_ration_grams(600.0, 0.0) == 0.0

    def test_negative_density_is_safe(self):
        assert calculate_daily_ration_grams(600.0, -4000.0) == 0.0


# ---------------------------------------------------------------------------
# Flujo integral (determinismo end-to-end)
# ---------------------------------------------------------------------------


class TestEndToEndPipeline:
    """Integración de las funciones puras en el flujo completo de dosificación."""

    def test_full_pipeline_dog_with_snacks(self):
        rer = calculate_rer(12.5)
        mer = calculate_mer(rer, "canino", "castrado", "adulto", "medium", 5, "normal")
        snacks = evaluate_snacks(mer, 40.0)
        grams = calculate_daily_ration_grams(
            snacks["final_ration_kcal"], 3800.0
        )
        assert mer == pytest.approx(465.3508909826865 * 1.6)
        assert snacks["exceeds_limit"] is False
        assert grams > 0
        assert grams == pytest.approx(snacks["final_ration_kcal"] / (3800.0 / 1000.0))

    def test_full_pipeline_cat_snacks_over_limit(self):
        rer = calculate_rer(4.0)
        mer = calculate_mer(rer, "felino", "esterilizado", "adulto", "medium", 5, "normal")
        snacks = evaluate_snacks(mer, mer * 0.5)
        assert snacks["exceeds_limit"] is True
        assert snacks["final_ration_kcal"] == pytest.approx(mer * 0.5)
        assert snacks["final_ration_kcal"] > 0


if __name__ == "__main__":
    pytest.main([__file__])
