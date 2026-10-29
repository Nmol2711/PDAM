"""Entrega de orden, reporte, cierre atómico y descuento (spec 014, T4).

Cubre RF-1, RF-13 a RF-18, RF-20 a RF-24 y RNF-8 sobre `test.db`, con el reloj
del servidor inyectado como `ahora`: la entrega de la orden y el cierre se
prueban con instantes fijos para verificar el plazo sin depender del reloj real.

Se usa la aplicación completa (`TestClient`) para el contrato HTTP de
`POST /dispensers/reports` (200 con el cuerpo de §5.2 y 400 del catálogo, nunca
422) y los servicios con una sesión real para los casos que necesitan inyectar
el instante. Las comprobaciones de estado se hacen siempre con una sesión nueva
para no leer la caché de SQLAlchemy.
"""

import os
import sys
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.db.database import SessionLocal
from app.domain.catalogos import ErrorDominio
from app.main import app
from app.models import models
from app.schemas.reports import DispenserReportRequest
from app.services import order_service

# Dirección del dispensador del escenario. Se escribe con dos puntos y se
# normaliza en cada petición para comprobar también la normalización (RF-14).
MAC = "AA:BB:CC:DD:AB:1F"
MAC_NORMALIZADA = "AABBCCDDAB1F"

# Hora del servidor inyectada. Incluye zona para probar la conversión a UTC naive
# que exige RNF-8 al guardar la entrega, el cierre y el registro.
AHORA = datetime(2026, 10, 1, 12, 0, 0, tzinfo=timezone.utc)
AHORA_NAIVE = datetime(2026, 10, 1, 12, 0, 0)

# Límite exacto del plazo más la tolerancia, contado desde la entrega (RF-20).
LIMITE_DEL_PLAZO = AHORA_NAIVE + timedelta(minutes=5, seconds=1)

# Gramos solicitados por la orden que se entrega en cada escenario.
SOLICITADOS = 50.0

# Motivos de fallo del catálogo que el dispositivo puede declarar (RF-17).
MOTIVOS_DE_FALLO = [
    "objetivo_no_alcanzado",
    "atasco_no_resuelto",
    "sensor_no_disponible",
    "fallo_sensor_dispensacion",
    "orden_invalida",
]


class BaseOrdersTests(unittest.TestCase):
    """Escenario base: un usuario, su mascota, un dispensador y un horario."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario()
        self.mascota = self._crear_mascota(self.usuario)
        self.dispensador = self._crear_dispensador(self.mascota, MAC)
        self.horario = models.Schedule(time="08:00", amount=SOLICITADOS, pet_id=self.mascota.id)
        self._guardar(self.horario)

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
        """Vacía las tablas del escenario respetando las claves foráneas."""
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

    def _crear_usuario(self, email="dueno@orders.test"):
        return self._guardar(
            models.User(email=email, hashed_password="hash-de-prueba", is_active=True)
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

    def _crear_dispensador(
        self,
        mascota,
        mac_address,
        stock=1200.0,
        activo=True,
        pendiente=True,
        reset_wifi=False,
    ):
        return self._guardar(
            models.Dispenser(
                mac_address=mac_address,
                mac_normalized="".join(c for c in mac_address if c not in ":-. ").upper(),
                pet_id=mascota.id,
                is_active=activo,
                pending_dispensing=pendiente,
                pending_wifi_reset=reset_wifi,
                current_food_grams=stock,
            )
        )

    def _fijar_stock(self, gramos):
        sesion = SessionLocal()
        try:
            dispensador = sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first()
            dispensador.current_food_grams = gramos
            sesion.commit()
        finally:
            sesion.close()

    # --- Consultas de estado (siempre en sesión nueva) ----------------------

    def _dispensador_fresco(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first()
        finally:
            sesion.close()

    def _ordenes(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.DispensingOrder).order_by(
                models.DispensingOrder.id
            ).all()
        finally:
            sesion.close()

    def _orden(self, order_id):
        sesion = SessionLocal()
        try:
            return sesion.query(models.DispensingOrder).filter(
                models.DispensingOrder.id == order_id
            ).first()
        finally:
            sesion.close()

    def _logs(self, order_id=None):
        sesion = SessionLocal()
        try:
            consulta = sesion.query(models.ActivityLog)
            if order_id is not None:
                consulta = consulta.filter(models.ActivityLog.order_id == order_id)
            return consulta.order_by(models.ActivityLog.id).all()
        finally:
            sesion.close()

    # --- Acciones -----------------------------------------------------------

    def _entregar(self, mac=MAC, ahora=AHORA, simular=False):
        sesion = SessionLocal()
        try:
            return order_service.entregar_orden(
                sesion, mac, ahora=ahora, simular=simular
            )
        finally:
            sesion.close()

    def _reporte(self, **cambios):
        datos = {
            "mac": MAC,
            "order_id": getattr(self, "order_id", None),
            "motivo": "objetivo_alcanzado",
            "gramos_solicitados": SOLICITADOS,
            "gramos_medidos": 50.4,
            "reintentos": 0,
        }
        datos.update(cambios)
        return DispenserReportRequest(**datos)

    def _procesar(self, ahora=AHORA, **cambios):
        sesion = SessionLocal()
        try:
            return order_service.procesar_reporte(sesion, self._reporte(**cambios), ahora=ahora)
        finally:
            sesion.close()

    def _post(self, **cambios):
        datos = {
            "mac": MAC,
            "order_id": getattr(self, "order_id", None),
            "motivo": "objetivo_alcanzado",
            "gramos_solicitados": SOLICITADOS,
            "gramos_medidos": 50.4,
            "reintentos": 0,
        }
        datos.update(cambios)
        return self.client.post("/dispensers/reports", json=datos)


class TestEntregaDeOrden(BaseOrdersTests):
    """RF-13, RF-2, RNF-8: orden pendiente con hora del servidor y sin stock."""

    def test_entrega_crea_la_orden_pendiente_sin_descontar_stock(self):
        respuesta = self._entregar()

        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], SOLICITADOS)
        self.assertIsNotNone(respuesta["order_id"])

        ordenes = self._ordenes()
        self.assertEqual(len(ordenes), 1, "La entrega debe crear una única orden")
        orden = ordenes[0]

        self.assertEqual(orden.id, respuesta["order_id"])
        self.assertEqual(orden.status, "pending")
        self.assertEqual(orden.requested_grams, SOLICITADOS)
        self.assertEqual(orden.pet_id, self.mascota.id)
        self.assertEqual(orden.pet_name, self.mascota.name)
        self.assertEqual(orden.dispenser_id, self.dispensador.id)
        self.assertEqual(orden.user_id, self.usuario.id)
        self.assertEqual(orden.dispenser_mac_masked, "**:AB:1F")
        # RNF-8: la hora es la del servidor (la inyectada) y se guarda en UTC naive.
        self.assertEqual(orden.delivered_at, AHORA_NAIVE)
        self.assertIsNone(orden.closed_at)
        self.assertIsNone(orden.outcome)

        # RF-13: entregar no toca el stock; el descuento ocurre solo al cerrar.
        self.assertEqual(self._dispensador_fresco().current_food_grams, 1200.0)
        self.assertEqual(self._logs(), [], "La entrega no escribe registros")

    def test_entrega_baja_la_bandera_pendiente_para_no_repetir_la_orden(self):
        self._entregar()
        respuesta = self._entregar()

        self.assertFalse(respuesta["serve"])
        self.assertEqual(respuesta["amount"], 0)
        self.assertEqual(len(self._ordenes()), 1)

    def test_dispensador_no_registrado_responde_404_sin_registro(self):
        with self.assertRaises(HTTPException) as contexto:
            self._entregar(mac="0A:1B:2C:3D:4E:5F")

        self.assertEqual(contexto.exception.status_code, 404)
        self.assertEqual(self._ordenes(), [])
        self.assertEqual(self._logs(), [], "RF-2: el 404 no escribe registro")

    def test_reset_wifi_tiene_prioridad_absoluta(self):
        sesion = SessionLocal()
        try:
            dispensador = sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first()
            dispensador.pending_wifi_reset = True
            dispensador.is_active = False
            sesion.commit()
        finally:
            sesion.close()

        respuesta = self._entregar()

        self.assertEqual(
            respuesta, {"serve": False, "amount": 0, "reset_wifi": True}
        )
        self.assertEqual(self._ordenes(), [], "El reseteo no crea orden")
        self.assertFalse(
            self._dispensador_fresco().pending_wifi_reset,
            "La bandera de reseteo se consume al entregarse",
        )

    def test_reposo_sin_dispensacion_no_crea_orden(self):
        sesion = SessionLocal()
        try:
            dispensador = sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first()
            dispensador.pending_dispensing = False
            sesion.commit()
        finally:
            sesion.close()

        self.assertEqual(self._entregar(), {"serve": False, "amount": 0})
        self.assertEqual(self._ordenes(), [])

    def test_el_put_ya_no_acepta_la_bandera_heredada(self):
        # T5, opción (a): la bandera `pending_dispensing` sale del contrato de
        # actualización. Un cliente antiguo que la envíe no recibe 422, pero el
        # servidor la ignora; solo se consume si ya estaba puesta en la base.
        from app.api.deps import get_current_user
        from app.schemas.dispenser import DispenserUpdate

        self.assertNotIn("pending_dispensing", DispenserUpdate.model_fields)

        sesion = SessionLocal()
        try:
            dispensador = sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first()
            dispensador.pending_dispensing = False
            sesion.commit()
        finally:
            sesion.close()

        usuario = models.User(
            id=self.usuario.id,
            email=self.usuario.email,
            hashed_password="hash-de-prueba",
            is_active=True,
        )
        app.dependency_overrides[get_current_user] = lambda: usuario

        respuesta = self.client.put(
            f"/dispensers/{self.dispensador.id}",
            json={"pending_dispensing": True, "pet_id": self.mascota.id},
        )

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertFalse(
            self._dispensador_fresco().pending_dispensing,
            "El campo extra del cliente no modifica la bandera heredada",
        )

    def test_check_taks_entrega_order_id_y_no_descuenta(self):
        # Ruta efectiva del endpoint real que consulta el firmware (sin barra
        # inicial en el decorador, igual que el resto de `check-taks`).
        respuesta = self.client.get(f"/dispenserscheck-taks/{MAC}")

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        cuerpo = respuesta.json()
        self.assertTrue(cuerpo["serve"])
        self.assertEqual(cuerpo["amount"], SOLICITADOS)
        self.assertIsNotNone(cuerpo["order_id"], "RF-13: la orden viaja al firmware")
        self.assertEqual(len(self._ordenes()), 1)
        self.assertEqual(
            self._dispensador_fresco().current_food_grams,
            1200.0,
            "La consulta del hardware no descuenta stock",
        )

    def test_check_taks_test_diagnostico_no_crea_orden_ni_descuenta(self):
        respuesta = self.client.get(f"/dispenserscheck-taks-test/{MAC}")

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertTrue(respuesta.json()["serve"])
        self.assertEqual(respuesta.json()["amount"], SOLICITADOS)
        self.assertEqual(self._ordenes(), [], "El diagnóstico no crea órdenes")
        self.assertEqual(self._dispensador_fresco().current_food_grams, 1200.0)

    def test_dispensador_desactivado_no_dispensa_ni_crea_orden(self):
        self._fijar_stock(1200.0)
        sesion = SessionLocal()
        try:
            dispensador = sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first()
            dispensador.is_active = False
            sesion.commit()
        finally:
            sesion.close()

        self.assertEqual(self._entregar(), {"serve": False, "amount": 0})
        self.assertEqual(self._ordenes(), [])

    def test_modo_simulado_no_crea_orden_ni_consume_banderas(self):
        primera = self._entregar(simular=True)
        segunda = self._entregar(simular=True)

        self.assertTrue(primera["serve"])
        self.assertEqual(primera["amount"], SOLICITADOS)
        self.assertNotIn("order_id", primera)
        self.assertEqual(primera, segunda, "El modo simulado no escribe nada")
        self.assertEqual(self._ordenes(), [])
        self.assertTrue(self._dispensador_fresco().pending_dispensing)


    def test_el_indice_unico_impide_dos_ordenes_pendientes_del_mismo_dispensador(self):
        # RNF-3: la base es la última red; el índice parcial solo afecta a las
        # órdenes pendientes y deja intactas las cerradas.
        from sqlalchemy.exc import IntegrityError

        self._entregar()

        sesion = SessionLocal()
        try:
            sesion.add(
                models.DispensingOrder(
                    user_id=self.usuario.id,
                    pet_id=self.mascota.id,
                    pet_name=self.mascota.name,
                    dispenser_id=self.dispensador.id,
                    dispenser_mac_masked="**:AB:1F",
                    requested_grams=SOLICITADOS,
                    delivered_at=AHORA_NAIVE,
                    status="pending",
                )
            )
            with self.assertRaises(IntegrityError):
                sesion.commit()
        finally:
            sesion.rollback()
            sesion.close()

        ordenes = self._ordenes()
        self.assertEqual(len(ordenes), 1, "Solo puede quedar una orden pendiente")
        self.assertEqual(ordenes[0].status, "pending")

    def test_una_orden_cerrada_no_cuenta_para_el_indice_parcial(self):
        # La cláusula `WHERE status='pending'` permite varias órdenes cerradas
        # del mismo dispensador.
        primera = self._entregar()["order_id"]
        sesion = SessionLocal()
        try:
            sesion.query(models.DispensingOrder).filter(
                models.DispensingOrder.id == primera
            ).update({"status": "closed"}, synchronize_session=False)
            # Se vuelve a armar la bandera heredada para tener una segunda fuente
            # de comida; el índice ya no bloquea porque la orden está cerrada.
            sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).update({"pending_dispensing": True}, synchronize_session=False)
            sesion.commit()
        finally:
            sesion.close()

        segunda = self._entregar()
        self.assertTrue(segunda["serve"])
        self.assertEqual(len(self._ordenes()), 2)


class TestCierrePorReporte(BaseOrdersTests):
    """RF-15, RF-16, RF-17, RF-24, RF-23: resultado del reporte y descuento."""

    def setUp(self):
        super().setUp()
        self.order_id = self._entregar()["order_id"]

    def _assert_sin_descuento(self, respuesta, causa):
        self.assertEqual(respuesta["outcome"], "failure")
        self.assertEqual(respuesta["cause"], causa)
        self.assertEqual(respuesta["discounted_grams"], 0.0)
        self.assertEqual(self._dispensador_fresco().current_food_grams, 1200.0)

        orden = self._orden(self.order_id)
        self.assertEqual(orden.status, "closed")
        self.assertEqual(orden.outcome, "failure")
        self.assertEqual(orden.cause, causa)
        self.assertIsNone(
            orden.discounted_grams,
            "Sin descuento no se guarda un valor de descuento",
        )

        logs = self._logs(self.order_id)
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].discounted_grams, None)
        return logs[0]

    def test_exito_descuenta_lo_medido_y_guarda_medidos_y_descontados(self):
        respuesta = self._procesar(gramos_medidos=50.4)

        self.assertEqual(respuesta["order_id"], self.order_id)
        self.assertEqual(respuesta["outcome"], "success")
        self.assertEqual(respuesta["cause"], "objetivo_alcanzado")
        self.assertEqual(respuesta["requested_grams"], SOLICITADOS)
        self.assertEqual(respuesta["measured_grams"], 50.4)
        self.assertEqual(respuesta["discounted_grams"], 50.4)
        self.assertEqual(respuesta["resulting_stock"], 1149.6)
        self.assertFalse(respuesta["ya_cerrada"])

        orden = self._orden(self.order_id)
        self.assertEqual(orden.status, "closed")
        self.assertEqual(orden.outcome, "success")
        self.assertEqual(orden.cause, "objetivo_alcanzado")
        # RF-15: medidos y descontados en columnas distintas.
        self.assertEqual(orden.measured_grams, 50.4)
        self.assertEqual(orden.discounted_grams, 50.4)
        self.assertEqual(orden.resulting_stock, 1149.6)
        self.assertEqual(orden.closed_at, AHORA_NAIVE)

        self.assertAlmostEqual(self._dispensador_fresco().current_food_grams, 1149.6)
        self.assertEqual(len(self._logs(self.order_id)), 1)

    def test_medidos_mayores_que_los_solicitados_descuentan_lo_medido(self):
        respuesta = self._procesar(gramos_medidos=60.0)

        self.assertEqual(respuesta["outcome"], "success")
        self.assertEqual(respuesta["discounted_grams"], 60.0)
        self.assertEqual(respuesta["resulting_stock"], 1140.0)

    def test_los_solicitados_del_reporte_no_se_usan_para_comparar(self):
        # RF-15: prevalece el valor guardado en la orden; los del reporte solo se
        # auditan en el contexto. Se envía un solicitado del reporte **mayor** que
        # los medidos (100 frente a 50): si se comparara contra él, el cierre sería
        # `entrega_incompleta` en lugar de éxito.
        respuesta = self._procesar(gramos_solicitados=100.0, gramos_medidos=50.0)

        self.assertEqual(respuesta["outcome"], "success")
        self.assertEqual(respuesta["requested_grams"], SOLICITADOS)
        self.assertIn('"solicitados_reporte": 100.0', self._logs(self.order_id)[0].context)

    def test_medidos_mayores_que_el_stock_descuentan_todo_el_disponible(self):
        self._fijar_stock(100.0)

        respuesta = self._procesar(gramos_medidos=150.0)

        self.assertEqual(respuesta["outcome"], "success")
        self.assertEqual(respuesta["discounted_grams"], 100.0)
        self.assertEqual(respuesta["resulting_stock"], 0.0)
        self.assertEqual(self._dispensador_fresco().current_food_grams, 0.0)
        self.assertIn('"faltante": 50.0', self._logs(self.order_id)[0].context)

    def test_stock_en_cero_descuenta_cero_y_refleja_el_faltante(self):
        self._fijar_stock(0.0)

        respuesta = self._procesar(gramos_medidos=50.0)

        self.assertEqual(respuesta["outcome"], "success")
        self.assertEqual(respuesta["discounted_grams"], 0.0)
        self.assertEqual(respuesta["resulting_stock"], 0.0)
        self.assertIn('"faltante": 50.0', self._logs(self.order_id)[0].context)

    def test_medidos_menores_que_los_solicitados_cierra_entrega_incompleta(self):
        respuesta = self._procesar(gramos_medidos=40.0)

        log = self._assert_sin_descuento(respuesta, "entrega_incompleta")
        self.assertEqual(respuesta["measured_grams"], 40.0)
        self.assertIn('"medidos": 40.0', log.context)
        self.assertIn('"solicitados_reporte": 50.0', log.context)

    def test_objetivo_alcanzado_sin_medidos_no_acredita_el_objetivo(self):
        respuesta = self._procesar(gramos_medidos=None)

        log = self._assert_sin_descuento(respuesta, "entrega_incompleta")
        self.assertIsNone(respuesta["measured_grams"])
        # RF-24: el dato ausente se registra como «no disponible», no se omite.
        self.assertIn('"medidos": "no disponible"', log.context)

    def test_cada_motivo_de_fallo_cierra_con_su_causa_y_sin_descuento(self):
        for motivo in MOTIVOS_DE_FALLO:
            with self.subTest(motivo=motivo):
                self._limpiar_base_de_datos()
                self.usuario = self._crear_usuario()
                self.mascota = self._crear_mascota(self.usuario)
                self.dispensador = self._crear_dispensador(self.mascota, MAC)
                self.horario = self._guardar(
                    models.Schedule(time="08:00", amount=SOLICITADOS, pet_id=self.mascota.id)
                )
                self.order_id = self._entregar()["order_id"]

                respuesta = self._procesar(motivo=motivo, gramos_medidos=3.0)

                log = self._assert_sin_descuento(respuesta, motivo)
                self.assertIn('"medidos": 3.0', log.context)

    def test_orden_invalida_sin_gramos_solicitados_ni_medidos(self):
        respuesta = self._procesar(
            motivo="orden_invalida", gramos_solicitados=None, gramos_medidos=None
        )

        log = self._assert_sin_descuento(respuesta, "orden_invalida")
        self.assertIn('"solicitados_reporte": "no disponible"', log.context)
        self.assertIn('"medidos": "no disponible"', log.context)

    def test_el_registro_guarda_orden_solicitados_medidos_stock_y_reintentos(self):
        respuesta = self._procesar(gramos_medidos=50.4, reintentos=2)

        self.assertEqual(respuesta["outcome"], "success")
        logs = self._logs(self.order_id)
        self.assertEqual(len(logs), 1)
        log = logs[0]

        # RF-3, RF-24: campos obligatorios del registro.
        self.assertEqual(log.event_type, "feeding_dispensed")
        self.assertEqual(log.outcome, "success")
        self.assertEqual(log.cause, "objetivo_alcanzado")
        self.assertEqual(log.description, "Comida dispensada")
        self.assertEqual(log.user_id, self.usuario.id)
        self.assertEqual(log.pet_id, self.mascota.id)
        self.assertEqual(log.pet_name, self.mascota.name)
        self.assertEqual(log.dispenser_id, self.dispensador.id)
        self.assertEqual(log.dispenser_mac_masked, "**:AB:1F")
        self.assertEqual(log.order_id, self.order_id)
        self.assertEqual(log.requested_grams, SOLICITADOS)
        self.assertEqual(log.measured_grams, 50.4)
        self.assertEqual(log.discounted_grams, 50.4)
        self.assertEqual(log.resulting_stock, 1149.6)
        self.assertEqual(log.retry_count, 2)
        self.assertEqual(log.created_at, AHORA_NAIVE)
        self.assertNotIn(MAC, log.context)
        self.assertNotIn("AABBCCDDAB1F", log.context)

    def test_el_stock_resultante_nunca_supera_la_capacidad(self):
        self._fijar_stock(5000.0)

        respuesta = self._procesar(gramos_medidos=50.0)

        self.assertEqual(respuesta["resulting_stock"], 4950.0)
        self.assertEqual(self._dispensador_fresco().current_food_grams, 4950.0)

    def test_un_stock_de_partida_fuera_de_rango_rechaza_el_cierre_sin_cambios(self):
        # RF-22: ninguna operación distinta del reabastecimiento puede dejar el
        # stock fuera del intervalo; se rechaza con `stock_fuera_de_rango`.
        self._fijar_stock(6000.0)

        with self.assertRaises(ErrorDominio) as contexto:
            self._procesar(gramos_medidos=50.0)

        self.assertEqual(contexto.exception.code, "stock_fuera_de_rango")
        self.assertEqual(self._dispensador_fresco().current_food_grams, 6000.0)
        self.assertEqual(self._orden(self.order_id).status, "pending")
        self.assertEqual(self._logs(), [], "El rechazo no escribe registro (RF-2)")

    def test_el_stock_no_se_toma_del_reporte(self):
        # RF-23: el stock es del servidor; un valor del cliente se ignora.
        sesion = SessionLocal()
        try:
            respuesta = order_service.procesar_reporte(
                sesion,
                DispenserReportRequest(
                    mac=MAC,
                    order_id=self.order_id,
                    motivo="objetivo_alcanzado",
                    gramos_medidos=50.0,
                    current_food_grams=0,
                    mensaje_extra="ignorado",
                ),
                ahora=AHORA,
            )
        finally:
            sesion.close()

        self.assertEqual(respuesta["discounted_grams"], 50.0)
        self.assertEqual(self._dispensador_fresco().current_food_grams, 1150.0)


class TestIdempotenciaYTardanza(BaseOrdersTests):
    """RF-18, RF-20: duplicados y cierre tardío con un único cierre."""

    def setUp(self):
        super().setUp()
        self.order_id = self._entregar()["order_id"]

    def test_un_segundo_reporte_devuelve_ya_cerrada_sin_nuevo_log_ni_descuento(self):
        primera = self._procesar(gramos_medidos=50.4)
        segunda = self._procesar(gramos_medidos=999.0, motivo="objetivo_no_alcanzado")

        self.assertFalse(primera["ya_cerrada"])
        self.assertTrue(segunda["ya_cerrada"], "RF-18: el duplicado se marca cerrado")
        self.assertEqual(segunda["outcome"], "success", "Prevalece el primer cierre")
        self.assertEqual(segunda["cause"], "objetivo_alcanzado")
        self.assertEqual(segunda["measured_grams"], 50.4)
        self.assertEqual(segunda["discounted_grams"], 50.4)
        self.assertEqual(len(self._logs(self.order_id)), 1)
        self.assertAlmostEqual(self._dispensador_fresco().current_food_grams, 1149.6)

    def test_duplicado_identico_del_mismo_reporte(self):
        primera = self._procesar()
        segunda = self._procesar()

        self.assertEqual(primera, segunda | {"ya_cerrada": False})
        self.assertEqual(len(self._logs(self.order_id)), 1)

    def test_reporte_en_el_limite_exacto_del_plazo_sigue_dentro(self):
        respuesta = self._procesar(
            ahora=LIMITE_DEL_PLAZO, gramos_medidos=50.0
        )

        self.assertEqual(respuesta["outcome"], "success")
        self.assertFalse(respuesta["ya_cerrada"])
        self.assertEqual(self._dispensador_fresco().current_food_grams, 1150.0)

    def test_reporte_tardio_cierra_orden_cerrada_sin_descuento(self):
        respuesta = self._procesar(
            ahora=LIMITE_DEL_PLAZO + timedelta(milliseconds=1), gramos_medidos=50.0
        )

        self.assertEqual(respuesta["outcome"], "failure")
        self.assertEqual(respuesta["cause"], "orden_cerrada")
        self.assertTrue(respuesta["ya_cerrada"])
        self.assertEqual(respuesta["discounted_grams"], 0.0)
        self.assertEqual(self._dispensador_fresco().current_food_grams, 1200.0)

        logs = self._logs(self.order_id)
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].cause, "orden_cerrada")
        self.assertIn('"medidos": 50.0', logs[0].context)

    def test_un_tardio_tras_otro_tardio_no_duplica_el_registro(self):
        self._procesar(ahora=LIMITE_DEL_PLAZO + timedelta(seconds=10))
        segunda = self._procesar(ahora=LIMITE_DEL_PLAZO + timedelta(seconds=20))

        self.assertTrue(segunda["ya_cerrada"])
        self.assertEqual(segunda["cause"], "orden_cerrada")
        self.assertEqual(len(self._logs(self.order_id)), 1)


class TestRechazosDelReporte(BaseOrdersTests):
    """RF-2, RF-14, RF-21: MAC, motivo y orden en el orden definido."""

    def setUp(self):
        super().setUp()
        # El endpoint no permite inyectar el reloj: la orden se entrega con la
        # hora real del servidor para que el reporte quede dentro del plazo.
        self.order_id = self._entregar(ahora=None)["order_id"]

    def _assert_400(self, respuesta, codigo):
        self.assertEqual(
            respuesta.status_code,
            400,
            f"Se esperaba 400 {codigo}. Cuerpo: {respuesta.text}",
        )
        detalle = respuesta.json()["detail"]
        self.assertEqual(detalle["code"], codigo)
        self.assertTrue(detalle["message"].strip())
        return detalle

    def test_mac_no_registrada_responde_400_sin_registro(self):
        respuesta = self._post(mac="0A:1B:2C:3D:4E:5F")

        self._assert_400(respuesta, "mac_no_registrada")
        self.assertEqual(self._logs(), [], "RF-21: sin registro")
        self.assertEqual(self._orden(self.order_id).status, "pending")

    def test_la_mac_se_normaliza_antes_de_buscarla(self):
        respuesta = self._post(mac="aa-bb-cc-dd-ab-1f")

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(respuesta.json()["outcome"], "success")

    def test_motivo_invalido_responde_400_sin_registro_y_la_orden_sigue_pendiente(self):
        for motivo in ("motivo_inventado", "", None, "entrega_incompleta", "sin_reporte"):
            with self.subTest(motivo=repr(motivo)):
                respuesta = self._post(motivo=motivo)

                self._assert_400(respuesta, "motivo_invalido")
                self.assertEqual(self._logs(), [], "RF-21: sin registro")
                self.assertEqual(self._orden(self.order_id).status, "pending")
                self.assertEqual(self._dispensador_fresco().current_food_grams, 1200.0)

    def test_un_stock_de_partida_fuera_de_rango_responde_400_stock_fuera_de_rango(self):
        # RF-22: la variante HTTP del rechazo de dominio. El stock de partida
        # 6000 g sale del intervalo y el cierre se rechaza sin escribir nada.
        self._fijar_stock(6000.0)

        respuesta = self._post(gramos_medidos=50.0)

        self._assert_400(respuesta, "stock_fuera_de_rango")
        self.assertEqual(self._logs(), [], "El rechazo no escribe registro")
        self.assertEqual(self._orden(self.order_id).status, "pending")
        self.assertEqual(self._dispensador_fresco().current_food_grams, 6000.0)

    def test_orden_desconocida_responde_400_con_registro_de_fallo(self):
        respuesta = self._post(order_id=999999)

        self._assert_400(respuesta, "orden_desconocida")
        logs = self._logs()
        self.assertEqual(len(logs), 1, "RF-21: la orden desconocida sí se registra")
        log = logs[0]
        self.assertEqual(log.event_type, "feeding_dispensed")
        self.assertEqual(log.outcome, "failure")
        self.assertEqual(log.cause, "orden_desconocida")
        self.assertEqual(log.dispenser_id, self.dispensador.id)
        self.assertEqual(log.dispenser_mac_masked, "**:AB:1F")
        self.assertEqual(self._dispensador_fresco().current_food_grams, 1200.0)
        self.assertEqual(self._orden(self.order_id).status, "pending")

    def test_orden_de_otro_dispensador_es_desconocida(self):
        otra_mascota = self._crear_mascota(self.usuario, "Nina")
        otro_dispensador = self._crear_dispensador(
            otra_mascota, "0A:1B:2C:3D:4E:5F", pendiente=True
        )
        sesion = SessionLocal()
        try:
            orden_ajena = models.DispensingOrder(
                user_id=self.usuario.id,
                pet_id=otra_mascota.id,
                pet_name=otra_mascota.name,
                dispenser_id=otro_dispensador.id,
                dispenser_mac_masked="**:4E:5F",
                requested_grams=SOLICITADOS,
                delivered_at=AHORA_NAIVE,
                status="pending",
            )
            sesion.add(orden_ajena)
            sesion.commit()
            sesion.refresh(orden_ajena)
            orden_ajena_id = orden_ajena.id
        finally:
            sesion.close()

        respuesta = self._post(order_id=orden_ajena_id)

        self._assert_400(respuesta, "orden_desconocida")
        self.assertEqual(self._orden(orden_ajena_id).status, "pending")

    def test_la_orden_de_la_mac_se_valida_despues_del_motivo(self):
        # Orden desconocida y motivo inválido a la vez: gana `motivo_invalido`
        # porque el orden de comprobación es MAC → motivo → orden (RF-21).
        respuesta = self._post(order_id=999999, motivo="motivo_inventado")

        self._assert_400(respuesta, "motivo_invalido")
        self.assertEqual(self._logs(), [])

    def test_ningun_reporte_de_negocio_responde_422(self):
        casos = [
            {},
            {"mac": None},
            {"mac": MAC, "order_id": None, "motivo": None},
            {"mac": MAC, "order_id": "no-es-un-id", "motivo": "objetivo_alcanzado"},
            {"mac": MAC, "order_id": {"id": 1}, "motivo": "objetivo_alcanzado"},
            {"mac": MAC, "order_id": self.order_id, "motivo": ["objetivo_alcanzado"]},
            {
                "mac": MAC,
                "order_id": self.order_id,
                "motivo": "objetivo_alcanzado",
                "gramos_medidos": "no-numerico",
            },
            {
                "mac": MAC,
                "order_id": self.order_id,
                "motivo": "objetivo_alcanzado",
                "gramos_solicitados": {"valor": 50},
                "gramos_medidos": [50],
            },
            {
                "mac": MAC,
                "order_id": self.order_id,
                "motivo": "objetivo_alcanzado",
                "gramos_medidos": "50.4",
                "reintentos": "dos",
            },
        ]

        for caso in casos:
            with self.subTest(caso=caso):
                respuesta = self.client.post("/dispensers/reports", json=caso)
                self.assertNotEqual(
                    respuesta.status_code,
                    422,
                    f"RF-14: ningún reporte responde 422. Cuerpo: {respuesta.text}",
                )
                self.assertIn(respuesta.status_code, (200, 400))


class TestAtomicidadDelCierre(BaseOrdersTests):
    """RF-1: si el registro falla no queda descuento ni cierre; el reintento cierra."""

    def setUp(self):
        super().setUp()
        self.order_id = self._entregar(ahora=None)["order_id"]

    def test_fallo_al_escribir_el_log_revierte_y_devuelve_500(self):
        with patch.object(
            order_service.activity_service,
            "registrar",
            side_effect=RuntimeError("fallo de escritura del registro"),
        ):
            respuesta = self._post(gramos_medidos=50.4)

        self.assertEqual(
            respuesta.status_code,
            500,
            f"RF-1: un fallo de escritura responde 5xx. Cuerpo: {respuesta.text}",
        )

        orden = self._orden(self.order_id)
        self.assertEqual(orden.status, "pending", "No queda cierre")
        self.assertIsNone(orden.outcome)
        self.assertIsNone(orden.closed_at)
        self.assertIsNone(orden.discounted_grams)
        self.assertEqual(
            self._dispensador_fresco().current_food_grams,
            1200.0,
            "No queda descuento",
        )
        self.assertEqual(self._logs(self.order_id), [])

    def test_el_reintento_tras_el_500_cierra_una_sola_vez(self):
        with patch.object(
            order_service.activity_service,
            "registrar",
            side_effect=RuntimeError("fallo de escritura del registro"),
        ):
            self._post(gramos_medidos=50.4)

        respuesta = self._post(gramos_medidos=50.4)

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        cuerpo = respuesta.json()
        self.assertFalse(cuerpo["ya_cerrada"])
        self.assertEqual(cuerpo["outcome"], "success")
        self.assertAlmostEqual(self._dispensador_fresco().current_food_grams, 1149.6)
        self.assertEqual(len(self._logs(self.order_id)), 1, "Un único registro")

        # Un tercer envío ya es duplicado y no vuelve a descontar.
        ultimo = self._post(gramos_medidos=50.4)
        self.assertTrue(ultimo.json()["ya_cerrada"])
        self.assertAlmostEqual(self._dispensador_fresco().current_food_grams, 1149.6)


class TestContratoDeLaRespuesta(BaseOrdersTests):
    """RF-14, RF-18, RF-20: cuerpo de §5.2 y endpoints sin token."""

    def setUp(self):
        super().setUp()
        self.order_id = self._entregar(ahora=None)["order_id"]

    def test_el_reporte_no_requiere_token(self):
        respuesta = self.client.post(
            "/dispensers/reports",
            json={
                "mac": MAC,
                "order_id": self.order_id,
                "motivo": "objetivo_alcanzado",
                "gramos_solicitados": 50.0,
                "gramos_medidos": 50.4,
                "reintentos": 0,
            },
        )

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(
            respuesta.json(),
            {
                "order_id": self.order_id,
                "outcome": "success",
                "cause": "objetivo_alcanzado",
                "requested_grams": 50.0,
                "measured_grams": 50.4,
                "discounted_grams": 50.4,
                "resulting_stock": 1149.6,
                "ya_cerrada": False,
            },
        )

    def test_el_cuerpo_del_duplicado_conserva_el_resultado(self):
        self._post()
        respuesta = self._post(gramos_medidos=10.0)

        self.assertEqual(respuesta.status_code, 200)
        cuerpo = respuesta.json()
        self.assertTrue(cuerpo["ya_cerrada"])
        self.assertEqual(cuerpo["outcome"], "success")
        self.assertEqual(cuerpo["measured_grams"], 50.4)


class TestAjustesDeCierreDeT4(BaseOrdersTests):
    """Cierres de T4: «no disponible», números finitos, 500 genérico y cuerpo JSON.

    Son ajustes aprobados en la revisión de T4; no cambian el contrato de la
    entrega ni del reporte, solo completan RF-24 y el rechazo sin 422.
    """

    def setUp(self):
        super().setUp()
        self.order_id = None

    def _reiniciar_escenario(self, ahora=AHORA):
        """Deja una orden pendiente nueva, sin arrastrar la de la prueba anterior."""
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario()
        self.mascota = self._crear_mascota(self.usuario)
        self.dispensador = self._crear_dispensador(self.mascota, MAC)
        self.horario = self._guardar(
            models.Schedule(time="08:00", amount=SOLICITADOS, pet_id=self.mascota.id)
        )
        self.order_id = self._entregar(ahora=ahora)["order_id"]

    # --- RF-24: todo dato ausente se registra como «no disponible» ----------

    def test_reintentos_ausente_se_registra_como_no_disponible(self):
        self._reiniciar_escenario()

        respuesta = self._procesar(gramos_medidos=50.4, reintentos=None)

        self.assertEqual(respuesta["outcome"], "success")
        log = self._logs(self.order_id)[0]
        self.assertIsNone(log.retry_count)
        self.assertIn('"reintentos": "no disponible"', log.context)

    def test_reintentos_ausente_en_orden_desconocida_se_registra(self):
        datos = {
            "mac": MAC,
            "order_id": 999999,
            "motivo": "objetivo_alcanzado",
            "gramos_medidos": 10.0,
        }

        respuesta = self.client.post("/dispensers/reports", json=datos)

        self.assertEqual(respuesta.status_code, 400, respuesta.text)
        logs = self._logs()
        self.assertEqual(len(logs), 1)
        self.assertIsNone(logs[0].retry_count)
        self.assertIn('"reintentos": "no disponible"', logs[0].context)

    # --- Números no finitos y negativos ------------------------------------

    def test_los_valores_no_finitos_se_tratan_como_ausentes(self):
        no_finitos = [
            float("nan"),
            float("inf"),
            float("-inf"),
            "1e999",
            "-1e999",
            "NaN",
            "Infinity",
        ]

        for valor in no_finitos:
            with self.subTest(valor=repr(valor)):
                self._reiniciar_escenario()

                respuesta = self._procesar(gramos_medidos=valor)

                self.assertEqual(
                    respuesta["outcome"],
                    "failure",
                    "Un valor no finito no puede acreditar el objetivo",
                )
                self.assertEqual(respuesta["cause"], "entrega_incompleta")
                self.assertIsNone(respuesta["measured_grams"])
                log = self._logs(self.order_id)[0]
                self.assertIn('"medidos": "no disponible"', log.context)
                self.assertEqual(
                    self._dispensador_fresco().current_food_grams,
                    1200.0,
                    "Sin una medida válida no hay descuento",
                )

    def test_los_medidos_negativos_no_descuentan_ni_acreditan_el_objetivo(self):
        self._reiniciar_escenario()

        respuesta = self._procesar(gramos_medidos=-5.0)

        self.assertEqual(respuesta["outcome"], "failure")
        self.assertEqual(respuesta["cause"], "entrega_incompleta")
        self.assertEqual(respuesta["measured_grams"], -5.0)
        self.assertIsNone(self._orden(self.order_id).discounted_grams)
        self.assertIn('"medidos": -5.0', self._logs(self.order_id)[0].context)
        self.assertEqual(self._dispensador_fresco().current_food_grams, 1200.0)

    def test_reintentos_no_finitos_se_tratan_como_ausentes(self):
        self._reiniciar_escenario()

        self._procesar(gramos_medidos=50.4, reintentos="1e999")

        self.assertIsNone(self._logs(self.order_id)[0].retry_count)

    # --- 500 sin detalles internos -----------------------------------------

    def test_el_500_de_la_entrega_no_filtra_el_detalle_de_la_excepcion(self):
        with patch.object(
            order_service,
            "_crear_orden_pendiente",
            side_effect=RuntimeError("detalle interno del servidor"),
        ):
            with self.assertRaises(HTTPException) as contexto:
                self._entregar()

        self.assertEqual(contexto.exception.status_code, 500)
        self.assertEqual(contexto.exception.detail, order_service.MENSAJE_ERROR_ENTREGA)
        self.assertNotIn("detalle interno", contexto.exception.detail)

    # --- Cuerpos que no son un objeto JSON ---------------------------------

    def test_cuerpos_que_no_son_objeto_json_responden_400_del_catalogo(self):
        peticiones = [
            ("lista", self.client.post("/dispensers/reports", json=[])),
            ("cadena", self.client.post("/dispensers/reports", json="texto")),
            ("número", self.client.post("/dispensers/reports", json=42)),
            ("nulo", self.client.post("/dispensers/reports", content=b"null")),
            ("vacío", self.client.post("/dispensers/reports", content=b"")),
        ]

        for nombre, respuesta in peticiones:
            with self.subTest(cuerpo=nombre):
                self.assertEqual(
                    respuesta.status_code,
                    400,
                    f"El cuerpo {nombre} no puede responder 422. {respuesta.text}",
                )
                detalle = respuesta.json()["detail"]
                self.assertEqual(detalle["code"], "motivo_invalido")
                self.assertTrue(detalle["message"].strip())
                self.assertEqual(self._logs(), [], "El rechazo no escribe registro")

    def test_un_objeto_json_sigue_cerrando_la_orden(self):
        # El endpoint no permite inyectar el reloj: la orden se entrega con la
        # hora real del servidor para que el reporte quede dentro del plazo.
        self._reiniciar_escenario(ahora=None)

        respuesta = self._post(gramos_medidos=50.4)

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(respuesta.json()["outcome"], "success")


if __name__ == "__main__":
    unittest.main()
