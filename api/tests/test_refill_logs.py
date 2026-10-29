"""Reabastecimiento idempotente y sus registros (spec 014, T6).

Cubre RF-11, RF-12 y RF-22: el reabastecimiento aceptado escribe
`dispenser_refilled` con resultado éxito, gramos añadidos, stock resultante y
origen; el sincronizado usa la hora de la sincronización y el origen
`sincronizacion_sin_conexion`; el doble `operation_id` no duplica el incremento
ni el registro; y los rechazos responden 400 con `cantidad_invalida` o
`supera_capacidad`, dejan el stock intacto y escriben su registro de fallo en una
sesión independiente, nunca con 422.

Se usa la aplicación completa (`TestClient`) para el contrato HTTP y los
servicios con una sesión real para los casos que necesitan inyectar el instante
de la sincronización. Las comprobaciones de estado se hacen con una sesión nueva.
"""

import os
import sys
import unittest
from datetime import date, datetime, timezone
from pathlib import Path
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.api.deps import get_current_user
from app.db.database import SessionLocal
from app.main import app
from app.models import models
from app.schemas.dispenser import DispenserRefillRequest
from app.services import activity_service, dispenser_service

MAC = "AA:BB:CC:DD:AB:1F"
MAC_NORMALIZADA = "AABBCCDDAB1F"
MAC_ENMASCARADA = "**:AB:1F"

EMAIL = "dueno@refill.test"
SECRETO = "clave-wifi-y-token-que-no-debe-registrarse"

STOCK_INICIAL = 1000.0
AHORA = datetime(2026, 10, 1, 12, 0, 0, tzinfo=timezone.utc)
AHORA_NAIVE = datetime(2026, 10, 1, 12, 0, 0)
AHORA_SINCRONIZACION = datetime(2026, 10, 2, 14, 30, 0, tzinfo=timezone.utc)
AHORA_SINCRONIZACION_NAIVE = datetime(2026, 10, 2, 14, 30, 0)


class BaseRefillTests(unittest.TestCase):
    """Un usuario, su mascota y un dispensador con `STOCK_INICIAL` gramos."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario()
        self.mascota = self._crear_mascota(self.usuario)
        self.dispensador = self._crear_dispensador(self.mascota, MAC, STOCK_INICIAL)

    def tearDown(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()

    # --- Escenario ----------------------------------------------------------

    def _guardar(self, entidad):
        sesion = SessionLocal()
        try:
            sesion.add(entidad)
            sesion.commit()
            sesion.refresh(entidad)
            return entidad
        finally:
            sesion.close()

    def _limpiar_base_de_datos(self):
        sesion = SessionLocal()
        try:
            for modelo in (
                models.DispensingQueue,
                models.DispensingOrder,
                models.RefillOperation,
                models.ActivityLog,
                models.Dispenser,
                models.Schedule,
                models.Pet,
                models.User,
            ):
                sesion.query(modelo).delete()
            sesion.commit()
        finally:
            sesion.close()

    def _crear_usuario(self, email=EMAIL):
        return self._guardar(
            models.User(email=email, hashed_password=SECRETO, is_active=True)
        )

    def _crear_mascota(self, usuario, nombre="Milo"):
        return self._guardar(
            models.Pet(
                name=nombre,
                species="perro",
                birth_date=date(2023, 1, 1),
                weight=5.5,
                reproductive_status=False,
                user_id=usuario.id,
            )
        )

    def _crear_dispensador(self, mascota, mac_address, stock, mac_normalizada=None):
        return self._guardar(
            models.Dispenser(
                mac_address=mac_address,
                mac_normalized=mac_normalizada or MAC_NORMALIZADA,
                pet_id=mascota.id,
                is_active=True,
                pending_dispensing=False,
                pending_wifi_reset=False,
                current_food_grams=stock,
            )
        )

    # --- Acciones -----------------------------------------------------------

    def _peticion(self, **cambios):
        datos = {"amount": 500.0, "unit": "g"}
        datos.update(cambios)
        return DispenserRefillRequest(**datos)

    def _reabastecer(
        self,
        ahora=AHORA,
        usuario=None,
        dispensador=None,
        sesion=None,
        **cambios,
    ):
        """Llama al servicio; la sesión se cierra solo si la abre la prueba."""
        propia = sesion is None
        sesion = sesion or SessionLocal()
        try:
            return dispenser_service.refill_dispenser(
                sesion,
                (dispensador or self.dispensador).id,
                self._peticion(**cambios),
                user_id=(usuario or self.usuario).id,
                ahora=ahora,
            )
        finally:
            if propia:
                sesion.close()

    def _post(self, cuerpo, dispensador=None):
        app.dependency_overrides[get_current_user] = lambda: self.usuario
        return self.client.post(
            f"/dispensers/{(dispensador or self.dispensador).id}/refill",
            json=cuerpo,
        )

    # --- Consultas de estado (siempre en sesión nueva) ----------------------

    def _stock(self, dispensador=None):
        sesion = SessionLocal()
        try:
            return (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == (dispensador or self.dispensador).id)
                .first()
                .current_food_grams
            )
        finally:
            sesion.close()

    def _logs(self, dispensador=None):
        sesion = SessionLocal()
        try:
            consulta = sesion.query(models.ActivityLog)
            if dispensador is not None:
                consulta = consulta.filter(
                    models.ActivityLog.dispenser_id == dispensador.id
                )
            return consulta.order_by(models.ActivityLog.id).all()
        finally:
            sesion.close()

    def _operaciones(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.RefillOperation).all()
        finally:
            sesion.close()

    # --- Aserciones ---------------------------------------------------------

    def assert_sin_datos_sensibles(self, *valores_prohibidos):
        """Ningún registro expone credenciales, correo ni la MAC completa (RNF-1)."""
        for log in self._logs():
            texto = " ".join(
                filter(
                    None,
                    [
                        log.description or "",
                        log.context or "",
                        log.pet_name or "",
                        log.dispenser_mac_masked or "",
                    ],
                )
            )
            for prohibido in valores_prohibidos:
                self.assertNotIn(
                    prohibido,
                    texto,
                    f"El registro {log.id} expone un dato que no puede guardar",
                )
            for prohibido in ("ssid", "password", "token", "secret", "secret_key"):
                self.assertNotIn(prohibido, texto.lower())

    def assert_catalogo(self, respuesta, codigo):
        self.assertEqual(respuesta.status_code, 400, respuesta.text)
        detalle = respuesta.json()["detail"]
        self.assertEqual(detalle["code"], codigo)
        self.assertTrue(detalle["message"].strip(), "El rechazo lleva mensaje visible")


class TestReabastecimientoAceptado(BaseRefillTests):
    """RF-11, RF-22, RF-23: incremento del servidor y un único registro."""

    def test_reabastecimiento_con_conexion_registra_origen_servidor(self):
        self._reabastecer(amount=500.0, unit="g")

        self.assertEqual(self._stock(), 1500.0)
        logs = self._logs()
        self.assertEqual(len(logs), 1, "El reabastecimiento aceptado deja un registro")
        log = logs[0]

        self.assertEqual(log.event_type, "dispenser_refilled")
        self.assertEqual(log.outcome, "success")
        self.assertIsNone(log.cause)
        self.assertEqual(log.description.strip(), "Dispensador reabastecido")
        self.assertEqual(log.user_id, self.usuario.id)
        self.assertEqual(log.pet_id, self.mascota.id)
        self.assertEqual(log.pet_name, self.mascota.name)
        self.assertEqual(log.dispenser_id, self.dispensador.id)
        self.assertEqual(log.dispenser_mac_masked, MAC_ENMASCARADA)
        self.assertEqual(log.resulting_stock, 1500.0)
        self.assertEqual(log.created_at, AHORA_NAIVE, "La hora es la del servidor")

        self.assertIn('"gramos_anadidos": 500.0', log.context)
        self.assertIn('"stock_resultante": 1500.0', log.context)
        self.assertIn('"origen": "servidor"', log.context)

        self.assert_sin_datos_sensibles(
            EMAIL, "AA:BB:CC:DD:AB:1F", MAC_NORMALIZADA, SECRETO
        )

    def test_reabastecimiento_en_kilogramos_registra_los_gramos(self):
        self._reabastecer(amount=1.5, unit="kg")

        self.assertEqual(self._stock(), 2500.0)
        self.assertIn('"gramos_anadidos": 1500.0', self._logs()[0].context)

    def test_reabastecimiento_sincronizado_usa_la_hora_de_la_sincronizacion(self):
        self._reabastecer(
            amount=500.0,
            operation_id="refill-offline-1",
            origen="sincronizacion_sin_conexion",
            ahora=AHORA_SINCRONIZACION,
        )

        self.assertEqual(self._stock(), 1500.0)
        log = self._logs()[0]
        self.assertEqual(
            log.created_at,
            AHORA_SINCRONIZACION_NAIVE,
            "El registro usa la hora de la sincronización, no la del móvil",
        )
        self.assertIn('"origen": "sincronizacion_sin_conexion"', log.context)

    def test_un_origen_desconocido_se_registra_como_servidor(self):
        # El origen solo admite los dos valores del catálogo; no hay código de
        # error para él, así que se normaliza al valor por defecto sin inventar
        # un rechazo ni un valor libre en el contexto (RNF-7).
        self._reabastecer(amount=500.0, origen="inventado")

        self.assertIn('"origen": "servidor"', self._logs()[0].context)

    def test_el_limite_de_capacidad_exacto_se_acepta(self):
        sesion = SessionLocal()
        try:
            dispensador = sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first()
            dispensador.current_food_grams = 4000.0
            sesion.commit()
        finally:
            sesion.close()

        self._reabastecer(amount=1000.0)

        self.assertEqual(self._stock(), 5000.0)
        self.assertEqual(self._logs()[0].outcome, "success")

    def test_el_operation_id_es_opcional_con_conexion(self):
        self._reabastecer(amount=100.0)
        self._reabastecer(amount=100.0)

        self.assertEqual(self._stock(), 1200.0)
        self.assertEqual(len(self._logs()), 2, "Sin operation_id no hay idempotencia")
        self.assertEqual(self._operaciones(), [])


class TestIdempotenciaDelReabastecimiento(BaseRefillTests):
    """RF-11: el mismo `operation_id` se aplica una sola vez."""

    def test_el_doble_operation_id_no_duplica_ni_registra_dos_veces(self):
        self._reabastecer(
            amount=500.0,
            operation_id="refill-offline-1",
            origen="sincronizacion_sin_conexion",
        )
        segundo = self._reabastecer(
            amount=500.0,
            operation_id="refill-offline-1",
            origen="sincronizacion_sin_conexion",
        )

        self.assertEqual(self._stock(), 1500.0, "El stock solo sube una vez")
        self.assertEqual(len(self._logs()), 1, "Un único registro")
        operaciones = self._operaciones()
        self.assertEqual(len(operaciones), 1)
        self.assertEqual(operaciones[0].operation_id, "refill-offline-1")
        self.assertEqual(operaciones[0].grams, 500.0)
        self.assertEqual(operaciones[0].log_id, self._logs()[0].id)
        self.assertEqual(
            float(segundo.current_food_grams),
            1500.0,
            "El reintento recibe el stock autoritativo del servidor",
        )

    def test_el_doble_operation_id_no_duplica_aunque_cambie_la_cantidad(self):
        self._reabastecer(amount=500.0, operation_id="refill-2")
        self._reabastecer(amount=900.0, operation_id="refill-2")

        self.assertEqual(self._stock(), 1500.0)
        self.assertEqual(len(self._logs()), 1)

    def test_el_operation_id_es_idempotente_por_usuario(self):
        segundo_usuario = self._crear_usuario("otro@refill.test")
        mascota = self._crear_mascota(segundo_usuario, "Nina")
        dispensador = self._crear_dispensador(
            mascota, "11:22:33:44:55:66", 2000.0, mac_normalizada="112233445566"
        )

        self._reabastecer(amount=500.0, operation_id="refill-compartido")
        self._reabastecer(
            amount=500.0,
            operation_id="refill-compartido",
            usuario=segundo_usuario,
            dispensador=dispensador,
        )

        self.assertEqual(self._stock(), 1500.0)
        self.assertEqual(self._stock(dispensador), 2500.0)
        self.assertEqual(len(self._logs()), 2, "Cada usuario aplica su operación")

    def test_el_endpoint_reintentado_con_el_mismo_operation_id_no_duplica(self):
        cuerpo = {
            "amount": 500,
            "unit": "g",
            "operation_id": "refill-endpoint",
            "origen": "sincronizacion_sin_conexion",
        }

        primera = self._post(cuerpo)
        segunda = self._post(cuerpo)

        self.assertEqual(primera.status_code, 200, primera.text)
        self.assertEqual(segunda.status_code, 200, segunda.text)
        self.assertEqual(primera.json()["current_food_grams"], 1500.0)
        self.assertEqual(
            segunda.json()["current_food_grams"],
            1500.0,
            "El reintento recibe el stock del servidor sin volver a sumar",
        )
        self.assertEqual(len(self._logs()), 1)
        self.assertEqual(len(self._operaciones()), 1)


class TestRechazosDelReabastecimiento(BaseRefillTests):
    """RF-12, RF-22: 400 del catálogo, stock intacto y registro de fallo."""

    def _assert_rechazo(self, codigo, stock_esperado=STOCK_INICIAL, **cambios):
        with self.assertRaises(HTTPException) as contexto:
            self._reabastecer(**cambios)

        self.assertEqual(contexto.exception.status_code, 400)
        self.assertEqual(contexto.exception.detail["code"], codigo)
        self.assertTrue(contexto.exception.detail["message"].strip())
        self.assertEqual(self._stock(), stock_esperado, "El stock queda intacto")
        self.assertEqual(self._operaciones(), [], "Un rechazo no se aplica")

        logs = self._logs()
        self.assertEqual(len(logs), 1, "El rechazo deja un único registro de fallo")
        log = logs[0]
        self.assertEqual(log.event_type, "dispenser_refilled")
        self.assertEqual(log.outcome, "failure")
        self.assertEqual(log.cause, codigo)
        self.assertEqual(log.resulting_stock, stock_esperado)
        self.assertEqual(log.dispenser_mac_masked, MAC_ENMASCARADA)
        self.assert_sin_datos_sensibles(
            EMAIL, "AA:BB:CC:DD:AB:1F", MAC_NORMALIZADA, SECRETO
        )
        return log

    def test_cantidad_cero_responde_400_cantidad_invalida(self):
        log = self._assert_rechazo("cantidad_invalida", amount=0)
        self.assertIn('"cantidad_intentada": 0.0', log.context)

    def test_cantidad_negativa_responde_400_cantidad_invalida(self):
        log = self._assert_rechazo("cantidad_invalida", amount=-25.0)
        self.assertIn('"cantidad_intentada": -25.0', log.context)

    def test_cantidad_no_numerica_responde_400_cantidad_invalida(self):
        log = self._assert_rechazo("cantidad_invalida", amount="mucho")
        self.assertIn('"cantidad_intentada": "no disponible"', log.context)

    def test_cantidad_ausente_responde_400_cantidad_invalida(self):
        self._assert_rechazo("cantidad_invalida", amount=None)

    def test_superar_la_capacidad_responde_400_supera_capacidad(self):
        log = self._assert_rechazo("supera_capacidad", amount=4500.0)
        self.assertIn('"cantidad_intentada": 4500.0', log.context)
        self.assertIn('"stock_resultante": 1000.0', log.context)

    def test_una_sola_cantidad_mayor_que_la_capacidad_tambien_se_rechaza(self):
        self._assert_rechazo("supera_capacidad", amount=5001.0)

    def test_el_registro_de_fallo_persiste_en_una_sesion_independiente(self):
        # RF-12: el registro se escribe en una transacción aparte para que
        # sobreviva a la reversión de la operación rechazada.
        sesion = SessionLocal()
        try:
            with self.assertRaises(HTTPException):
                self._reabastecer(amount=0, sesion=sesion)
            sesion.rollback()
        finally:
            sesion.close()

        logs = self._logs()
        self.assertEqual(len(logs), 1, "El registro sobrevive al rollback")
        self.assertEqual(logs[0].cause, "cantidad_invalida")

    def test_los_rechazos_nunca_responden_422(self):
        casos = [
            ("cero", {"amount": 0}),
            ("negativa", {"amount": -5}),
            ("texto", {"amount": "mucho"}),
            ("nula", {"amount": None}),
            ("sin cantidad", {"unit": "g"}),
            ("capacidad", {"amount": 6000}),
        ]

        for nombre, cuerpo in casos:
            with self.subTest(caso=nombre):
                respuesta = self._post(cuerpo)
                self.assertNotEqual(
                    respuesta.status_code, 422, f"{nombre} no puede responder 422"
                )
                esperado = (
                    "supera_capacidad"
                    if nombre == "capacidad"
                    else "cantidad_invalida"
                )
                self.assert_catalogo(respuesta, esperado)

        self.assertEqual(
            self._stock(), STOCK_INICIAL, "Ningún rechazo modifica el stock"
        )
        self.assertEqual(
            len(self._logs()), len(casos), "Cada rechazo deja su registro"
        )

    def test_un_cuerpo_que_no_es_objeto_json_responde_400(self):
        for cuerpo in ([], "texto", 42):
            with self.subTest(cuerpo=cuerpo):
                respuesta = self._post(cuerpo)
                self.assertEqual(respuesta.status_code, 400, respuesta.text)
                self.assertEqual(
                    respuesta.json()["detail"]["code"], "cantidad_invalida"
                )
        self.assertEqual(self._stock(), STOCK_INICIAL)

    def test_un_fallo_al_escribir_el_registro_no_aplica_el_stock(self):
        with patch.object(
            activity_service,
            "registrar",
            side_effect=RuntimeError("fallo de escritura del registro"),
        ):
            with self.assertRaises(HTTPException) as contexto:
                self._reabastecer(amount=500.0, operation_id="refill-3")

        self.assertEqual(contexto.exception.status_code, 500)
        self.assertNotIn("fallo de escritura", str(contexto.exception.detail))
        self.assertEqual(self._stock(), STOCK_INICIAL, "No hay incremento parcial")
        self.assertEqual(self._logs(), [])
        self.assertEqual(self._operaciones(), [])
