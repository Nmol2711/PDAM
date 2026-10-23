"""Prueba de contrato compartida backend<->frontend del motor nutricional WSAVA.

Cubre RF-4 de la Spec 011: el backend y la aplicacion movil deben aplicar
exactamente las mismas formulas y tablas. Ambas suites (`pytest` y
`flutter test`) consumen el MISMO fixture
`specs/011-refactorizacion-modular-nutricion-y-specs/fixtures/nutrition_contract_cases.json`;
si una formula o tabla se altera en un solo lado, al menos una de las dos suites
falla.

El fixture se localiza subiendo desde este archivo hasta la raiz del
repositorio (no se duplica en `api/`), y los valores numericos se comparan con la
tolerancia decimal declarada en el propio fixture (``tolerance``), la misma que
usa la prueba Dart.
"""

import json
import sys
from pathlib import Path

import pytest

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.services.nutrition_service import calculate_nutrition

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_PATH = (
    REPO_ROOT
    / "specs"
    / "011-refactorizacion-modular-nutricion-y-specs"
    / "fixtures"
    / "nutrition_contract_cases.json"
)

FLOAT_FIELDS = (
    "rer_kcal",
    "mer_kcal",
    "variability_min_kcal",
    "variability_max_kcal",
    "snack_limit_kcal",
    "final_ration_kcal",
    "daily_ration_grams",
    "ration_per_meal_grams",
)

BOOL_FIELDS = ("exceeds_snack_limit",)


def _load_fixture():
    assert FIXTURE_PATH.is_file(), f"No se encontro el fixture compartido: {FIXTURE_PATH}"
    with FIXTURE_PATH.open(encoding="utf-8") as fixture_file:
        return json.load(fixture_file)


FIXTURE = _load_fixture()
TOLERANCE = FIXTURE["tolerance"]
CASES = FIXTURE["cases"]


def test_fixture_covers_required_scenarios():
    """El fixture debe cubrir especies, etapas, BCS/MCS y snacks bajo/sobre limite."""
    ids = {case["id"] for case in CASES}
    assert len(CASES) >= 6
    assert any(case["input"]["species"] == "canino" for case in CASES)
    assert any(case["input"]["species"] == "felino" for case in CASES)
    assert any(case["input"]["life_stage"] == "crecimiento" for case in CASES)
    assert any(case["input"]["bcs"] <= 3 for case in CASES)
    assert any(case["input"]["bcs"] >= 7 for case in CASES)
    assert any(case["input"]["mcs"] == "moderate" for case in CASES)
    assert any(case["input"]["mcs"] == "marked" for case in CASES)
    assert any(case["expected"]["exceeds_snack_limit"] is True for case in CASES)
    assert any(case["expected"]["exceeds_snack_limit"] is False for case in CASES)
    assert "canino_adulto_snacks_en_el_limite" in ids


@pytest.mark.parametrize("case", CASES, ids=[case["id"] for case in CASES])
def test_calculate_nutrition_matches_shared_fixture(case):
    """El motor Python reproduce exactamente los valores esperados del contrato."""
    result = calculate_nutrition(**case["input"])
    expected = case["expected"]

    assert result["species"] == case["input"]["species"]
    assert result["body_weight"] == case["input"]["body_weight"]
    assert result["meals_per_day"] == case["input"]["meals_per_day"]

    for field in FLOAT_FIELDS:
        assert field in expected, f"Falta '{field}' en el caso {case['id']}"
        assert result[field] == pytest.approx(
            expected[field], rel=0.0, abs=TOLERANCE
        ), f"Divergencia en '{field}' para el caso {case['id']}"

    for field in BOOL_FIELDS:
        assert field in expected, f"Falta '{field}' en el caso {case['id']}"
        assert result[field] is expected[field], (
            f"Divergencia en '{field}' para el caso {case['id']}"
        )
