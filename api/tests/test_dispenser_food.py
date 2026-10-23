import unittest
from pydantic import ValidationError
from app.schemas.dispenser import DispenserRefillRequest
from app.services.dispenser_service import refill_dispenser, check_pending_task
from unittest.mock import MagicMock, patch

class TestDispenserFoodEstimation(unittest.TestCase):
    def test_refill_request_valid_amounts(self):
        req1 = DispenserRefillRequest(amount=100.0, unit="g")
        self.assertEqual(req1.amount, 100.0)

        req2 = DispenserRefillRequest(amount=2.5, unit="kg")
        self.assertEqual(req2.amount, 2.5)
        self.assertEqual(req2.unit, "kg")

    def test_refill_request_invalid_amounts(self):
        with self.assertRaises(ValidationError):
            DispenserRefillRequest(amount=0.0, unit="g")

        with self.assertRaises(ValidationError):
            DispenserRefillRequest(amount=-5.0, unit="g")

    def test_refill_dispenser_service_success_grams(self):
        db_mock = MagicMock()
        dispenser_mock = MagicMock()
        dispenser_mock.id = 1
        dispenser_mock.current_food_grams = 1000.0

        db_mock.query().filter().first.return_value = dispenser_mock

        refill_data = DispenserRefillRequest(amount=4500.0, unit="g")
        with patch("app.schemas.dispenser.Dispenser.model_validate", return_value=dispenser_mock):
            updated = refill_dispenser(db_mock, 1, refill_data)
            self.assertEqual(dispenser_mock.current_food_grams, 4500.0)
            db_mock.commit.assert_called_once()

    def test_refill_dispenser_service_success_kilograms(self):
        db_mock = MagicMock()
        dispenser_mock = MagicMock()
        dispenser_mock.id = 1
        dispenser_mock.current_food_grams = 1000.0

        db_mock.query().filter().first.return_value = dispenser_mock

        # 3.5 kg -> 3500.0 grams
        refill_data = DispenserRefillRequest(amount=3.5, unit="kg")
        with patch("app.schemas.dispenser.Dispenser.model_validate", return_value=dispenser_mock):
            updated = refill_dispenser(db_mock, 1, refill_data)
            self.assertEqual(dispenser_mock.current_food_grams, 3500.0)
            db_mock.commit.assert_called_once()

    def test_check_pending_task_discounts_food_automatically(self):
        db_mock = MagicMock()
        dispenser_mock = MagicMock()
        dispenser_mock.id = 1
        dispenser_mock.pet_id = 1
        dispenser_mock.is_active = True
        # El servicio consulta primero la orden de reseteo de WiFi (RF de la Spec 005).
        # En un MagicMock cualquier atributo no definido es verdadero, así que debe
        # declararse explícitamente como falso para simular un dispensador real.
        dispenser_mock.pending_wifi_reset = False
        dispenser_mock.pending_dispensing = True
        dispenser_mock.current_food_grams = 1000.0

        schedule_mock = MagicMock()
        schedule_mock.amount = 50.0

        db_mock.query().filter().first.side_effect = [dispenser_mock, schedule_mock]

        result = check_pending_task(db_mock, "AA:BB:CC:DD:EE:FF", test=False)
        self.assertTrue(result["serve"])
        self.assertEqual(result["amount"], 50.0)
        self.assertFalse(dispenser_mock.pending_dispensing)
        self.assertEqual(dispenser_mock.current_food_grams, 950.0)
        db_mock.commit.assert_called_once()
