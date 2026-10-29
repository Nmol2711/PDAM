"""Stock y reabastecimiento del dispensador (specs 012 y 014).

Desde la spec 014 la cantidad que entra y la capacidad se validan en el
servicio, no en el esquema de Pydantic: un rechazo de negocio responde 400 con un
código del catálogo (`cantidad_invalida` o `supera_capacidad`) y nunca 422. El
registro de cada reabastecimiento se prueba en `test_refill_logs.py`; aquí se
comprueba el cálculo del stock con un doble de la base de datos.

La entrega de la orden de dispensación ya no descuenta stock (RF-13): solo crea
la orden pendiente y devuelve su identificador.
"""

import os
import sys
import unittest

from datetime import date
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.domain.stock import CAPACIDAD_MAXIMA_GRAMOS, normalizar_gramos
from app.models import models
from app.models.models import Base
from app.schemas.dispenser import DispenserRefillRequest
from app.services import dispenser_service
from app.services.dispenser_service import check_pending_task, refill_dispenser

MAC = "AA:BB:CC:DD:EE:FF"


def _sesion_con_dispensador(stock: float):
    """Sesión SQLite en memoria con un dispensador real para probar el stock."""
    motor = create_engine("sqlite://")
    Base.metadata.create_all(motor)
    sesion = sessionmaker(bind=motor)()

    usuario = models.User(email="refill@test.com", hashed_password="hash")
    sesion.add(usuario)
    sesion.flush()
    mascota = models.Pet(
        name="Milo",
        species="perro",
        birth_date=date(2023, 1, 1),
        weight=5.5,
        reproductive_status=False,
        user_id=usuario.id,
    )
    sesion.add(mascota)
    sesion.flush()
    dispensador = models.Dispenser(
        mac_address=MAC,
        mac_normalized="AABBCCDDEEFF",
        pet_id=mascota.id,
        is_active=True,
        pending_dispensing=False,
        pending_wifi_reset=False,
        current_food_grams=stock,
    )
    sesion.add(dispensador)
    sesion.commit()
    sesion.refresh(dispensador)
    return sesion, dispensador, motor


class TestDispenserRefillContract(unittest.TestCase):
    def test_refill_request_valid_amounts(self):
        req1 = DispenserRefillRequest(amount=100.0, unit="g")
        self.assertEqual(req1.amount, 100.0)

        req2 = DispenserRefillRequest(amount=2.5, unit="kg")
        self.assertEqual(req2.amount, 2.5)
        self.assertEqual(req2.unit, "kg")

    def test_refill_request_acepta_la_idempotencia_y_el_origen(self):
        req = DispenserRefillRequest(
            amount=500.0,
            unit="g",
            operation_id="refill-1",
            origen="sincronizacion_sin_conexion",
        )
        self.assertEqual(req.operation_id, "refill-1")
        self.assertEqual(req.origen, "sincronizacion_sin_conexion")

    def test_refill_request_no_valida_la_cantidad_en_el_esquema(self):
        # La cantidad se valida en el servicio para que el rechazo sea un 400 del
        # catálogo y nunca un 422 del esquema (RF-12).
        self.assertEqual(DispenserRefillRequest(amount=0).amount, 0)
        self.assertEqual(DispenserRefillRequest(amount=-5.0).amount, -5.0)
        self.assertEqual(DispenserRefillRequest(amount="mucho").amount, "mucho")
        self.assertIsNone(DispenserRefillRequest().amount)

    def test_normalizar_gramos_convierte_y_rechaza_las_cantidades_invalidas(self):
        from app.domain.catalogos import ErrorDominio

        self.assertEqual(normalizar_gramos(500.0, "g"), 500.0)
        self.assertEqual(normalizar_gramos(2.5, "kg"), 2500.0)
        self.assertEqual(normalizar_gramos("250", "g"), 250.0)

        for invalida in (0, -5.0, "mucho", None, True, float("nan")):
            with self.subTest(cantidad=invalida):
                with self.assertRaises(ErrorDominio) as contexto:
                    normalizar_gramos(invalida, "g")
                self.assertEqual(contexto.exception.code, "cantidad_invalida")


class TestDispenserRefillService(unittest.TestCase):
    def tearDown(self):
        if hasattr(self, "_sesion"):
            self._sesion.close()
        if hasattr(self, "_motor"):
            self._motor.dispose()

    def _abrir(self, stock):
        self._sesion, self._dispensador, self._motor = _sesion_con_dispensador(stock)
        return self._sesion, self._dispensador

    def test_refill_dispenser_service_success_grams(self):
        db, dispensador = self._abrir(1000.0)

        respuesta = refill_dispenser(
            db, dispensador.id, DispenserRefillRequest(amount=500.0, unit="g")
        )

        self.assertEqual(respuesta.current_food_grams, 1500.0)
        db.refresh(dispensador)
        self.assertEqual(dispensador.current_food_grams, 1500.0)

    def test_refill_dispenser_allows_exact_capacity(self):
        db, dispensador = self._abrir(1000.0)

        respuesta = refill_dispenser(
            db, dispensador.id, DispenserRefillRequest(amount=4000.0, unit="g")
        )

        self.assertEqual(respuesta.current_food_grams, CAPACIDAD_MAXIMA_GRAMOS)
        db.refresh(dispensador)
        self.assertEqual(dispensador.current_food_grams, CAPACIDAD_MAXIMA_GRAMOS)

    def test_refill_dispenser_rejects_exceeding_capacity(self):
        # RF-12: el rechazo usa el código del catálogo y deja el stock intacto; el
        # registro de fallo se escribe en su propia transacción, que aquí se dobla.
        from fastapi import HTTPException

        db, dispensador = self._abrir(4900.0)

        refill_data = DispenserRefillRequest(amount=200.0, unit="g")
        with patch.object(dispenser_service.activity_service, "registrar_rechazo") as rechazo:
            with self.assertRaises(HTTPException) as contexto:
                refill_dispenser(db, dispensador.id, refill_data)

        self.assertEqual(contexto.exception.status_code, 400)
        self.assertEqual(
            contexto.exception.detail,
            {
                "code": "supera_capacidad",
                "message": "La cantidad supera la capacidad máxima de 5000 g del dispensador.",
            },
        )
        db.refresh(dispensador)
        self.assertEqual(dispensador.current_food_grams, 4900.0)
        self.assertEqual(rechazo.call_args.kwargs["cause"], "supera_capacidad")

    def test_refill_dispenser_rejects_amount_above_capacity(self):
        from fastapi import HTTPException

        db, dispensador = self._abrir(200.0)

        refill_data = DispenserRefillRequest(amount=5001.0, unit="g")
        with patch.object(dispenser_service.activity_service, "registrar_rechazo"):
            with self.assertRaises(HTTPException) as contexto:
                refill_dispenser(db, dispensador.id, refill_data)

        self.assertEqual(contexto.exception.status_code, 400)
        self.assertEqual(contexto.exception.detail["code"], "supera_capacidad")
        db.refresh(dispensador)
        self.assertEqual(dispensador.current_food_grams, 200.0)

    def test_refill_dispenser_rejects_zero_and_negative_amounts(self):
        from fastapi import HTTPException

        for cantidad in (0.0, -5.0):
            with self.subTest(cantidad=cantidad):
                db, dispensador, motor = _sesion_con_dispensador(1000.0)
                try:
                    refill_data = DispenserRefillRequest(amount=cantidad, unit="g")

                    with patch.object(
                        dispenser_service.activity_service, "registrar_rechazo"
                    ) as rechazo:
                        with self.assertRaises(HTTPException) as contexto:
                            refill_dispenser(db, dispensador.id, refill_data)

                    self.assertEqual(contexto.exception.status_code, 400)
                    self.assertEqual(
                        contexto.exception.detail["code"], "cantidad_invalida"
                    )
                    db.refresh(dispensador)
                    self.assertEqual(dispensador.current_food_grams, 1000.0)
                    self.assertEqual(
                        rechazo.call_args.kwargs["cause"], "cantidad_invalida"
                    )
                finally:
                    db.close()
                    motor.dispose()

    def test_refill_dispenser_not_found(self):
        from fastapi import HTTPException

        db_mock = MagicMock()
        db_mock.query().filter().first.return_value = None

        refill_data = DispenserRefillRequest(amount=500.0, unit="g")
        with self.assertRaises(HTTPException) as context:
            refill_dispenser(db_mock, 99, refill_data)

        self.assertEqual(context.exception.status_code, 404)

    def test_refill_dispenser_service_success_kilograms(self):
        db, dispensador = self._abrir(1000.0)

        # 3.5 kg -> 3500.0 grams, sumados a los 1000 g existentes
        respuesta = refill_dispenser(
            db, dispensador.id, DispenserRefillRequest(amount=3.5, unit="kg")
        )

        self.assertEqual(respuesta.current_food_grams, 4500.0)
        db.refresh(dispensador)
        self.assertEqual(dispensador.current_food_grams, 4500.0)

    def test_check_pending_task_creates_the_order_without_discounting_stock(self):
        # RF-13 (spec 014): entregar la orden ya no descuenta stock; solo crea la
        # orden pendiente con la hora del servidor y devuelve su identificador.
        from app.models import models

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
        dispenser_mock.mac_address = "AA:BB:CC:DD:EE:FF"

        schedule_mock = MagicMock()
        schedule_mock.amount = 50.0

        pet_mock = MagicMock()
        pet_mock.name = "Milo"
        pet_mock.user_id = 7

        # T5: antes de la bandera heredada el servicio mira las órdenes pendientes
        # y la cola de comidas en espera. Con el mock ambos conjuntos están vacíos,
        # así que la entrega sigue saliendo por la bandera como en T4.
        db_mock.query().filter().order_by().all.return_value = []
        db_mock.query().filter().order_by().first.return_value = None

        db_mock.query().filter().first.side_effect = [dispenser_mock, schedule_mock, pet_mock]

        result = check_pending_task(db_mock, "AA:BB:CC:DD:EE:FF", test=False)
        self.assertTrue(result["serve"])
        self.assertEqual(result["amount"], 50.0)
        self.assertIn("order_id", result)
        self.assertFalse(dispenser_mock.pending_dispensing)

        # El stock no se toca al entregar: el descuento ocurre al cerrar la orden.
        self.assertEqual(dispenser_mock.current_food_grams, 1000.0)

        ordenes = [
            llamada.args[0]
            for llamada in db_mock.add.call_args_list
            if isinstance(llamada.args[0], models.DispensingOrder)
        ]
        self.assertEqual(len(ordenes), 1, "La entrega crea una única orden")
        orden = ordenes[0]
        self.assertEqual(orden.status, "pending")
        self.assertEqual(orden.requested_grams, 50.0)
        self.assertEqual(orden.pet_id, 1)
        self.assertEqual(orden.pet_name, "Milo")
        self.assertEqual(orden.user_id, 7)
        self.assertIsNotNone(orden.delivered_at, "La entrega lleva la hora del servidor")
        db_mock.commit.assert_called_once()


if __name__ == "__main__":
    unittest.main()
