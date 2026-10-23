"""Pruebas de regresión de la generación automática de horarios WSAVA.

Cubre T11 de la Spec 011 (RF-3, RF-4, RNF-4): `auto_generar_horarios_wsava`
debe delegar en `nutrition_service.calculate_nutrition` como única fuente de
verdad, conservando el contrato externo (rer, mer, daily_grams, agua,
advertencias y horarios). Los valores esperados fijan la lógica unificada; si
alguien reintroduce una fórmula paralela en `schedule_service`, estas pruebas
fallan.
"""

import os
import sys
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi import HTTPException

from app.models import models
from app.schemas import schemas
from app.services import schedule_service
from app.services.nutrition_service import calculate_nutrition


def _crear_mascota(
    *,
    species: str,
    birth_date: date,
    weight: float,
    reproductive_status: bool,
) -> models.Pet:
    """Crea una mascota en memoria (sin persistirla) para el servicio."""
    return models.Pet(
        id=1,
        name="Mascota de prueba",
        species=species,
        birth_date=birth_date,
        weight=weight,
        reproductive_status=reproductive_status,
        user_id=1,
    )


class _DbMock:
    """Sesión SQLAlchemy simulada que devuelve la mascota y captura los horarios."""

    def __init__(self, mascota: models.Pet):
        self.db = MagicMock()
        self.schedule_query = MagicMock()

        pet_query = MagicMock()
        pet_query.filter.return_value.first.return_value = mascota

        def _query(model):
            if model is models.Pet:
                return pet_query
            if model is models.Schedule:
                return self.schedule_query
            return MagicMock()

        self.db.query.side_effect = _query

    @property
    def horarios_agregados(self):
        return [llamada.args[0] for llamada in self.db.add.call_args_list]


class TestAutoGenerarHorariosWsava(unittest.TestCase):
    """Regresión de valores y estructura del contrato del endpoint."""

    def _generar(self, mascota, req):
        db = _DbMock(mascota)
        resultado = schedule_service.auto_generar_horarios_wsava(
            db=db.db,
            pet_id=mascota.id,
            user_id=mascota.user_id,
            req=req,
        )
        return resultado, db

    def test_canino_adulto_castrado_usa_el_motor_unificado(self):
        mascota = _crear_mascota(
            species="perro",
            birth_date=date(2018, 1, 1),
            weight=12.5,
            reproductive_status=True,
        )
        req = schemas.AutoScheduleRequest(
            food_kcal_per_kg=4000.0,
            bcs=5,
            mcs="normal",
            activity_level="medium",
            meals_per_day=2,
        )

        resultado, db = self._generar(mascota, req)

        esperado = calculate_nutrition(
            species="canino",
            body_weight=12.5,
            caloric_density_kcal_per_kg=4000.0,
            bcs=5,
            mcs="normal",
            activity_level="medium",
            reproductive_status="castrado",
            life_stage="adulto",
            meals_per_day=2,
            snacks_kcal=0.0,
        )

        self.assertEqual(
            set(resultado.keys()),
            {
                "rer",
                "mer",
                "daily_grams",
                "water_min_ml",
                "water_max_ml",
                "warnings",
                "schedules",
            },
        )
        # Valores fijados con la lógica unificada (RER 70*BW^0.75 y factor 1.6).
        self.assertAlmostEqual(resultado["rer"], 465.35, places=2)
        self.assertAlmostEqual(resultado["mer"], 744.56, places=2)
        self.assertAlmostEqual(resultado["daily_grams"], 186.14, places=2)
        self.assertAlmostEqual(resultado["water_min_ml"], 550.0, places=1)
        self.assertAlmostEqual(resultado["water_max_ml"], 825.0, places=1)
        self.assertIn("±30%", resultado["warnings"][-1])

        # Trazabilidad directa contra el motor: los gramos son los mismos.
        self.assertAlmostEqual(
            resultado["daily_grams"], round(esperado["daily_ration_grams"], 2)
        )
        self.assertAlmostEqual(resultado["mer"], round(esperado["mer_kcal"], 2))

        self.assertEqual(
            [horario.time for horario in resultado["schedules"]],
            ["08:00", "20:00"],
        )
        self.assertEqual(
            [horario.amount for horario in resultado["schedules"]],
            [93.07, 93.07],
        )
        self.assertEqual(len(db.horarios_agregados), 2)
        db.schedule_query.filter.return_value.delete.assert_called_once()

    def test_felino_adulto_entero_usa_el_motor_unificado(self):
        mascota = _crear_mascota(
            species="gato",
            birth_date=date(2019, 5, 1),
            weight=4.0,
            reproductive_status=False,
        )
        req = schemas.AutoScheduleRequest(
            food_kcal_per_kg=3800.0,
            bcs=5,
            mcs="normal",
            activity_level="low",
            meals_per_day=4,
        )

        resultado, _ = self._generar(mascota, req)

        esperado = calculate_nutrition(
            species="felino",
            body_weight=4.0,
            caloric_density_kcal_per_kg=3800.0,
            bcs=5,
            mcs="normal",
            activity_level="low",
            reproductive_status="entero",
            life_stage="adulto",
            meals_per_day=4,
            snacks_kcal=0.0,
        )

        self.assertAlmostEqual(resultado["rer"], 197.99, places=2)
        self.assertAlmostEqual(resultado["mer"], 249.47, places=2)
        self.assertAlmostEqual(resultado["daily_grams"], 65.65, places=2)
        self.assertAlmostEqual(resultado["water_min_ml"], 176.0, places=1)
        self.assertAlmostEqual(resultado["water_max_ml"], 264.0, places=1)
        self.assertIn("±50%", resultado["warnings"][-1])
        self.assertAlmostEqual(
            resultado["daily_grams"], round(esperado["daily_ration_grams"], 2)
        )
        self.assertEqual(
            [horario.time for horario in resultado["schedules"]],
            ["07:00", "12:00", "17:00", "21:00"],
        )
        self.assertTrue(
            all(horario.amount == 16.41 for horario in resultado["schedules"])
        )

    def test_cachorro_canino_deriva_etapa_de_crecimiento(self):
        mascota = _crear_mascota(
            species="perro",
            birth_date=datetime.now().date() - timedelta(days=180),
            weight=8.0,
            reproductive_status=False,
        )
        req = schemas.AutoScheduleRequest(
            food_kcal_per_kg=4000.0,
            bcs=5,
            mcs="normal",
            activity_level="high",
            meals_per_day=3,
        )

        resultado, _ = self._generar(mascota, req)

        esperado = calculate_nutrition(
            species="canino",
            body_weight=8.0,
            caloric_density_kcal_per_kg=4000.0,
            bcs=5,
            mcs="normal",
            activity_level="high",
            reproductive_status="entero",
            life_stage="crecimiento",
            meals_per_day=3,
            snacks_kcal=0.0,
        )

        self.assertAlmostEqual(resultado["rer"], 332.98, places=2)
        self.assertAlmostEqual(resultado["mer"], 799.15, places=2)
        self.assertAlmostEqual(resultado["daily_grams"], 199.79, places=2)
        self.assertAlmostEqual(
            resultado["daily_grams"], round(esperado["daily_ration_grams"], 2)
        )
        self.assertEqual(
            [horario.time for horario in resultado["schedules"]],
            ["08:00", "14:00", "20:00"],
        )
        self.assertTrue(
            all(horario.amount == 66.6 for horario in resultado["schedules"])
        )

    def test_acepta_mcs_y_actividad_en_espanol_y_calcula_igual(self):
        """RF-2/RNF-4: el endpoint acepta los mismos sinónimos que el motor."""
        mascota = _crear_mascota(
            species="perro",
            birth_date=date(2018, 1, 1),
            weight=12.5,
            reproductive_status=True,
        )

        casos = [
            # (mcs en español, canónico, actividad en español, canónica, mer, gramos)
            ("normal", "normal", "Medio", "medium", 744.56, 186.14),
            ("Leve", "mild", "bajo", "low", 670.11, 167.53),
            ("MODERADA", "moderate", "Alto", "high", 848.80, 212.20),
            ("marcada", "marked", "alto", "high", 804.13, 201.03),
        ]

        for mcs_es, mcs_canon, act_es, act_canon, mer, gramos in casos:
            with self.subTest(mcs=mcs_es, activity_level=act_es):
                req = schemas.AutoScheduleRequest(
                    food_kcal_per_kg=4000.0,
                    bcs=5,
                    mcs=mcs_es,
                    activity_level=act_es,
                    meals_per_day=2,
                )

                resultado, _ = self._generar(mascota, req)

                esperado = calculate_nutrition(
                    species="canino",
                    body_weight=12.5,
                    caloric_density_kcal_per_kg=4000.0,
                    bcs=5,
                    mcs=mcs_canon,
                    activity_level=act_canon,
                    reproductive_status="castrado",
                    life_stage="adulto",
                    meals_per_day=2,
                    snacks_kcal=0.0,
                )

                self.assertAlmostEqual(resultado["mer"], mer, places=2)
                self.assertAlmostEqual(resultado["daily_grams"], gramos, places=2)
                self.assertAlmostEqual(
                    resultado["daily_grams"],
                    round(esperado["daily_ration_grams"], 2),
                )

    def test_rechaza_mcs_invalido(self):
        mascota = _crear_mascota(
            species="perro",
            birth_date=date(2018, 1, 1),
            weight=12.5,
            reproductive_status=True,
        )
        req = schemas.AutoScheduleRequest(
            food_kcal_per_kg=4000.0,
            bcs=5,
            mcs="severo",
            activity_level="medio",
            meals_per_day=2,
        )

        with self.assertRaises(HTTPException) as contexto:
            self._generar(mascota, req)

        self.assertEqual(contexto.exception.status_code, 400)
        self.assertIn("MCS inválido", contexto.exception.detail)

    def test_rechaza_actividad_invalida(self):
        mascota = _crear_mascota(
            species="perro",
            birth_date=date(2018, 1, 1),
            weight=12.5,
            reproductive_status=True,
        )
        req = schemas.AutoScheduleRequest(
            food_kcal_per_kg=4000.0,
            bcs=5,
            mcs="normal",
            activity_level="extremo",
            meals_per_day=2,
        )

        with self.assertRaises(HTTPException) as contexto:
            self._generar(mascota, req)

        self.assertEqual(contexto.exception.status_code, 400)
        self.assertIn("Nivel de actividad inválido", contexto.exception.detail)



if __name__ == "__main__":
    unittest.main()
