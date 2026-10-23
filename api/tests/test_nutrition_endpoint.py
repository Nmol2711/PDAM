"""Pruebas de integración del endpoint REST de dosificación nutricional.

Cubre RF-4 de la Spec 011: el endpoint ``POST /nutrition/calculate`` procesa
peticiones válidas e inválidas y devuelve exactamente los mismos resultados
sincronizados que genera el motor WSAVA del servicio (RNF-1: determinismo).

Usa `TestClient` de FastAPI para ejercitar la ruta completa: validación Pydantic
(RF-1/RF-2), llamada al servicio (RF-3) y serialización de la respuesta.
"""

import os
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from app.main import app
from app.services import nutrition_service

client = TestClient(app)


def _valid_payload(**overrides):
    """Devuelve un payload válido base para las pruebas del endpoint."""
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


EXPECTED_KEYS = {
    "species",
    "body_weight",
    "meals_per_day",
    "rer_kcal",
    "mer_kcal",
    "variability_min_kcal",
    "variability_max_kcal",
    "snack_limit_kcal",
    "snacks_kcal",
    "exceeds_snack_limit",
    "final_ration_kcal",
    "daily_ration_grams",
    "ration_per_meal_grams",
}


class TestNutritionCalculateValidRequests:
    """RF-4: peticiones válidas devuelven 200 con el cálculo completo."""

    def test_valid_request_returns_200_and_complete_result(self):
        response = client.post("/nutrition/calculate", json=_valid_payload())

        assert response.status_code == 200
        data = response.json()
        assert set(data.keys()) == EXPECTED_KEYS

    def test_valid_request_matches_known_wsaVA_values(self):
        """Perro 12.5 kg, castrado, adulto, actividad media, BCS 5, MCS normal."""
        response = client.post("/nutrition/calculate", json=_valid_payload())

        assert response.status_code == 200
        data = response.json()
        assert data["rer_kcal"] == pytest.approx(465.3508909826865)
        assert data["mer_kcal"] == pytest.approx(744.5614255722985)
        assert data["variability_min_kcal"] == pytest.approx(521.1929979006089)
        assert data["variability_max_kcal"] == pytest.approx(967.9298532439881)
        assert data["snack_limit_kcal"] == pytest.approx(74.45614255722985)
        assert data["exceeds_snack_limit"] is False
        assert data["final_ration_kcal"] == pytest.approx(744.5614255722985)
        assert data["daily_ration_grams"] == pytest.approx(186.14035639307463)
        assert data["ration_per_meal_grams"] == pytest.approx(93.07017819653731)

    def test_endpoint_matches_service_result_exactly(self):
        """El resultado HTTP es idéntico al generado por el servicio (RF-4)."""
        payload = _valid_payload(snacks_kcal=40.0)
        response = client.post("/nutrition/calculate", json=payload)

        expected = nutrition_service.calculate_nutrition(
            species="canino",
            body_weight=12.5,
            caloric_density_kcal_per_kg=4000.0,
            bcs=5,
            mcs="normal",
            activity_level="medium",
            reproductive_status="castrado",
            life_stage="adulto",
            meals_per_day=2,
            snacks_kcal=40.0,
        )

        assert response.status_code == 200
        data = response.json()
        for key, value in expected.items():
            assert data[key] == pytest.approx(value), f"Campo {key!r} divergente"

    def test_species_synonym_normalizes_in_response(self):
        response = client.post(
            "/nutrition/calculate", json=_valid_payload(species="perro")
        )

        assert response.status_code == 200
        assert response.json()["species"] == "canino"

    def test_cat_variability_is_50_percent(self):
        response = client.post(
            "/nutrition/calculate",
            json=_valid_payload(species="gato", reproductive_status="esterilizado"),
        )

        assert response.status_code == 200
        data = response.json()
        mer = data["mer_kcal"]
        assert data["variability_min_kcal"] == pytest.approx(mer * 0.5)
        assert data["variability_max_kcal"] == pytest.approx(mer * 1.5)


class TestNutritionCalculateSnacks:
    """RF-3: evaluación del límite de snacks al 10% del MER con recálculo."""

    def test_snacks_below_limit_does_not_exceed(self):
        response = client.post(
            "/nutrition/calculate", json=_valid_payload(snacks_kcal=50.0)
        )

        assert response.status_code == 200
        data = response.json()
        assert data["exceeds_snack_limit"] is False
        assert data["final_ration_kcal"] == pytest.approx(data["mer_kcal"] - 50.0)

    def test_snacks_above_limit_flags_exceedance_and_recalculates(self):
        mer = 744.5614255722985
        response = client.post(
            "/nutrition/calculate", json=_valid_payload(snacks_kcal=mer * 0.2)
        )

        assert response.status_code == 200
        data = response.json()
        assert data["exceeds_snack_limit"] is True
        assert data["final_ration_kcal"] == pytest.approx(mer - (mer * 0.2))


class TestNutritionCalculateInvalidRequests:
    """RF-1/RF-2: peticiones inválidas son rechazadas con 422 y mensajes en español."""

    def _assert_rejected(self, payload, fragment):
        response = client.post("/nutrition/calculate", json=payload)
        assert response.status_code == 422, response.text
        detail = response.json()["detail"]
        assert isinstance(detail, list)
        messages = " | ".join(err["msg"] for err in detail).lower()
        assert fragment.lower() in messages, messages

    def test_missing_body_weight_rejected(self):
        payload = _valid_payload()
        del payload["body_weight"]
        self._assert_rejected(payload, "peso corporal")

    def test_zero_body_weight_rejected(self):
        self._assert_rejected(_valid_payload(body_weight=0), "peso corporal")

    def test_negative_body_weight_rejected(self):
        self._assert_rejected(_valid_payload(body_weight=-1), "peso corporal")

    def test_non_numeric_body_weight_rejected(self):
        self._assert_rejected(_valid_payload(body_weight="abc"), "número")

    def test_zero_caloric_density_rejected(self):
        self._assert_rejected(
            _valid_payload(caloric_density_kcal_per_kg=0), "densidad calórica"
        )

    def test_out_of_range_meals_rejected(self):
        for meals in (0, 7, -1):
            self._assert_rejected(
                _valid_payload(meals_per_day=meals), "comidas diarias"
            )

    def test_out_of_range_bcs_rejected(self):
        for bcs in (0, 10, -1):
            self._assert_rejected(_valid_payload(bcs=bcs), "bcs")

    def test_invalid_species_rejected(self):
        self._assert_rejected(_valid_payload(species="ave"), "especie")

    def test_invalid_mcs_rejected(self):
        self._assert_rejected(_valid_payload(mcs="severo"), "mcs")

    def test_invalid_activity_rejected(self):
        self._assert_rejected(_valid_payload(activity_level="extremo"), "actividad")

    def test_invalid_reproductive_status_rejected(self):
        self._assert_rejected(
            _valid_payload(reproductive_status="preñada"), "reproductivo"
        )

    def test_invalid_life_stage_rejected(self):
        self._assert_rejected(_valid_payload(life_stage="senior"), "etapa de vida")

    def test_negative_snacks_rejected(self):
        self._assert_rejected(_valid_payload(snacks_kcal=-1), "snacks")


if __name__ == "__main__":
    pytest.main([__file__])
