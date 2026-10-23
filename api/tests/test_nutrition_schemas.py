import sys
from pathlib import Path

import pytest
from pydantic import ValidationError

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.schemas.nutrition_schemas import NutritionCalculationRequest


def _valid_payload(**overrides):
    """Devuelve un payload válido base para las pruebas de validación."""
    payload = {
        "species": "canino",
        "body_weight": 12.5,
        "caloric_density_kcal_per_kg": 4000.0,
        "bcs": 5,
        "mcs": "normal",
        "activity_level": "medio",
        "reproductive_status": "castrado",
        "life_stage": "adulto",
        "meals_per_day": 2,
    }
    payload.update(overrides)
    return payload


def _error_messages(exc: ValidationError) -> str:
    """Une todos los mensajes de error en un único texto para las aserciones."""
    return " | ".join(err["msg"] for err in exc.errors())


class TestValidPayloads:
    """Un payload válido debe construirse sin errores y normalizar los valores de texto."""

    def test_valid_payload_builds_without_error(self):
        request = NutritionCalculationRequest(**_valid_payload())
        assert request.body_weight == 12.5
        assert request.meals_per_day == 2
        assert request.bcs == 5

    def test_species_synonyms_normalize_to_canonical(self):
        for raw, expected in [
            ("canino", "canino"),
            ("perro", "canino"),
            ("dog", "canino"),
            ("felino", "felino"),
            ("gato", "felino"),
            ("cat", "felino"),
            ("CANINO", "canino"),
            (" Perro ", "canino"),
        ]:
            request = NutritionCalculationRequest(**_valid_payload(species=raw))
            assert request.species == expected, f"species={raw!r} -> {expected!r}"

    def test_mcs_synonyms_normalize_to_canonical(self):
        for raw, expected in [
            ("normal", "normal"),
            ("leve", "mild"),
            ("mild", "mild"),
            ("moderada", "moderate"),
            ("moderate", "moderate"),
            ("marcada", "marked"),
            ("marked", "marked"),
        ]:
            request = NutritionCalculationRequest(**_valid_payload(mcs=raw))
            assert request.mcs == expected, f"mcs={raw!r} -> {expected!r}"

    def test_activity_synonyms_normalize_to_canonical(self):
        for raw, expected in [
            ("bajo", "low"),
            ("low", "low"),
            ("medio", "medium"),
            ("medium", "medium"),
            ("alto", "high"),
            ("high", "high"),
        ]:
            request = NutritionCalculationRequest(**_valid_payload(activity_level=raw))
            assert request.activity_level == expected, f"activity_level={raw!r} -> {expected!r}"

    def test_reproductive_status_accepted_values(self):
        for raw in ["entero", "castrado", "esterilizado"]:
            request = NutritionCalculationRequest(**_valid_payload(reproductive_status=raw))
            assert request.reproductive_status == raw

    def test_life_stage_accepted_values(self):
        for raw, expected in [("crecimiento", "crecimiento"), ("adulto", "adulto")]:
            request = NutritionCalculationRequest(**_valid_payload(life_stage=raw))
            assert request.life_stage == expected

    def test_snacks_kcal_optional_defaults_to_zero(self):
        request = NutritionCalculationRequest(**_valid_payload())
        assert request.snacks_kcal == 0.0

    def test_snacks_kcal_positive_accepted(self):
        request = NutritionCalculationRequest(**_valid_payload(snacks_kcal=45.5))
        assert request.snacks_kcal == 45.5


class TestBodyWeightValidation:
    """RF-1: BW debe ser numérico y estrictamente mayor a 0, con mensajes en español."""

    def test_missing_body_weight_returns_spanish_message(self):
        payload = _valid_payload()
        del payload["body_weight"]
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**payload)
        messages = _error_messages(exc_info.value)
        assert "peso corporal" in messages.lower()
        assert "obligatorio" in messages

    def test_none_body_weight_returns_spanish_message(self):
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**_valid_payload(body_weight=None))
        messages = _error_messages(exc_info.value)
        assert "peso corporal" in messages.lower()
        assert "obligatorio" in messages

    @pytest.mark.parametrize("bw", [0, -1, -12.5])
    def test_zero_or_negative_body_weight_is_rejected(self, bw):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(body_weight=bw))

    @pytest.mark.parametrize("bw", ["abc", "", "   ", "12.5kg"])
    def test_non_numeric_body_weight_returns_spanish_message(self, bw):
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**_valid_payload(body_weight=bw))
        messages = _error_messages(exc_info.value)
        assert "peso corporal" in messages.lower()
        assert "debe ser un número" in messages


class TestCaloricDensityValidation:
    """RF-1: la densidad calórica debe ser estrictamente mayor a 0, con mensajes en español."""

    def test_missing_caloric_density_returns_spanish_message(self):
        payload = _valid_payload()
        del payload["caloric_density_kcal_per_kg"]
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**payload)
        messages = _error_messages(exc_info.value)
        assert "densidad calórica" in messages.lower()
        assert "obligatoria" in messages

    def test_none_caloric_density_returns_spanish_message(self):
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**_valid_payload(caloric_density_kcal_per_kg=None))
        messages = _error_messages(exc_info.value)
        assert "densidad calórica" in messages.lower()
        assert "obligatoria" in messages

    @pytest.mark.parametrize("density", [0, -1, -4000.0])
    def test_zero_or_negative_density_is_rejected(self, density):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(caloric_density_kcal_per_kg=density))

    @pytest.mark.parametrize("density", ["abc", "", "4000kcal"])
    def test_non_numeric_density_returns_spanish_message(self, density):
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**_valid_payload(caloric_density_kcal_per_kg=density))
        messages = _error_messages(exc_info.value)
        assert "densidad calórica" in messages.lower()
        assert "debe ser un número" in messages


class TestMealsPerDayValidation:
    """RF-1: comidas diarias entre 1 y 6, con mensajes en español."""

    @pytest.mark.parametrize("meals", [0, -1, 7, 10])
    def test_out_of_range_meals_are_rejected(self, meals):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(meals_per_day=meals))

    @pytest.mark.parametrize("meals", [1, 6])
    def test_boundary_meals_are_accepted(self, meals):
        request = NutritionCalculationRequest(**_valid_payload(meals_per_day=meals))
        assert request.meals_per_day == meals

    def test_missing_meals_returns_spanish_message(self):
        payload = _valid_payload()
        del payload["meals_per_day"]
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**payload)
        messages = _error_messages(exc_info.value)
        assert "comidas diarias" in messages.lower()
        assert "obligatorias" in messages

    def test_none_meals_returns_spanish_message(self):
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**_valid_payload(meals_per_day=None))
        messages = _error_messages(exc_info.value)
        assert "comidas diarias" in messages.lower()
        assert "obligatorias" in messages

    @pytest.mark.parametrize("meals", ["abc", "2.5", ""])
    def test_non_numeric_meals_returns_spanish_message(self, meals):
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**_valid_payload(meals_per_day=meals))
        messages = _error_messages(exc_info.value)
        assert "comidas diarias" in messages.lower()
        assert "número entero" in messages


class TestBcsValidation:
    """RF-2: BCS entre 1 y 9, con mensajes en español."""

    @pytest.mark.parametrize("bcs", [0, -1, 10, 99])
    def test_out_of_range_bcs_is_rejected(self, bcs):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(bcs=bcs))

    @pytest.mark.parametrize("bcs", [1, 9])
    def test_boundary_bcs_is_accepted(self, bcs):
        request = NutritionCalculationRequest(**_valid_payload(bcs=bcs))
        assert request.bcs == bcs

    def test_missing_bcs_returns_spanish_message(self):
        payload = _valid_payload()
        del payload["bcs"]
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**payload)
        messages = _error_messages(exc_info.value)
        assert "bcs" in messages.lower()
        assert "obligatorio" in messages

    def test_none_bcs_returns_spanish_message(self):
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**_valid_payload(bcs=None))
        messages = _error_messages(exc_info.value)
        assert "bcs" in messages.lower()
        assert "obligatorio" in messages

    @pytest.mark.parametrize("bcs", ["abc", "5.5", ""])
    def test_non_numeric_bcs_returns_spanish_message(self, bcs):
        with pytest.raises(ValidationError) as exc_info:
            NutritionCalculationRequest(**_valid_payload(bcs=bcs))
        messages = _error_messages(exc_info.value)
        assert "bcs" in messages.lower()
        assert "número entero" in messages


class TestMcsValidation:
    """RF-2: MCS dentro de los valores permitidos."""

    @pytest.mark.parametrize("mcs", ["", "severo", "excelente", "none", 123])
    def test_invalid_mcs_is_rejected(self, mcs):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(mcs=mcs))


class TestActivityValidation:
    """RF-2: nivel de actividad dentro de los valores permitidos."""

    @pytest.mark.parametrize("activity", ["", "extremo", "sedentario", "none", 123])
    def test_invalid_activity_is_rejected(self, activity):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(activity_level=activity))


class TestReproductiveStatusValidation:
    """RF-2: estatus reproductivo dentro de los valores permitidos."""

    @pytest.mark.parametrize("status", ["", "preñada", "lactante", "none", 123])
    def test_invalid_reproductive_status_is_rejected(self, status):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(reproductive_status=status))


class TestLifeStageValidation:
    """RF-2: etapa de vida dentro de los valores permitidos."""

    @pytest.mark.parametrize("stage", ["", "senior", "juvenil", "none", 123])
    def test_invalid_life_stage_is_rejected(self, stage):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(life_stage=stage))


class TestSpeciesValidation:
    """RF-2: especie canino/perro o felino/gato."""

    @pytest.mark.parametrize("species", ["", "ave", "conejo", "none", 123])
    def test_invalid_species_is_rejected(self, species):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(species=species))


class TestSnacksValidation:
    """Los snacks opcionales, si se proveen, no pueden ser negativos."""

    @pytest.mark.parametrize("snacks", [-1, -0.5])
    def test_negative_snacks_are_rejected(self, snacks):
        with pytest.raises(ValidationError):
            NutritionCalculationRequest(**_valid_payload(snacks_kcal=snacks))


if __name__ == "__main__":
    pytest.main([__file__])
