"""Vencimiento de órdenes pendientes (spec 014, T5; RF-19, RF-40, RNF-3).

Cubre el barrido de vencimientos con el reloj del servidor inyectado como
`ahora`: las fronteras se prueban al milisegundo (límite exacto, 1 ms antes y
1 ms después), el cierre queda garantizado dentro de los 60 s con el barrido de
30 s y nunca se descuenta stock. El escenario de firmware antiguo (RF-40) es el
mismo camino: la orden se cierra por plazo sin exigir reporte.

La exclusión mutua con el reporte (RNF-3) se prueba con hilos reales y sesiones
distintas, igual que en `test_orders_concurrency.py`.
"""

import os
import sys
import threading
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi.testclient import TestClient

from app.db.database import SessionLocal
from app.domain.tiempo import INTERVALO_BARRIDO, PLAZO_ORDEN, TOLERANCIA
from app.main import app
from app.models import models
from app.schemas.reports import DispenserReportRequest
from app.services import order_service
from app.services.background_tasks import background_schedules

MAC = "AA:BB:CC:DD:AB:1F"
MAC_NORMALIZADA = "AABBCCDDAB1F"

# Entrega de la orden del escenario. Se usa con zona para comprobar que el
# barrido guarda en UTC naive (RNF-8).
AHORA = datetime(2026, 10, 1, 12, 0, 0, tzinfo=timezone.utc)
AHORA_NAIVE = datetime(2026, 10, 1, 12, 0, 0)

# Límite exacto del plazo más la tolerancia de 1 s (RF-19, RF-20).
LIMITE_DEL_PLAZO = AHORA_NAIVE + PLAZO_ORDEN + TOLERANCIA

SOLICITADOS = 50.0
STOCK_INICIAL = 1200.0

DESCRIPCION_SIN_REPORTE = "Comida dispensada sin reporte del dispositivo"


class BaseVencimientoTests(unittest.TestCase):
    """Un usuario, su mascota, un dispensador con stock y un horario."""

    def setUp(self):
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario()
        self.mascota = self._crear_mascota(self.usuario)
        self.dispensador = self._crear_dispensador(self.mascota, MAC)
        self.horario = self._guardar(
            models.Schedule(time="08:00", amount=SOLICITADOS, pet_id=self.mascota.id)
        )

    def tearDown(self):
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

    def _crear_usuario(self, email="dueno@vencimiento.test"):
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

    def _crear_dispensador(self, mascota, mac_address, stock=STOCK_INICIAL, activo=True):
        return self._guardar(
            models.Dispenser(
                mac_address=mac_address,
                mac_normalized=MAC_NORMALIZADA,
                pet_id=mascota.id,
                is_active=activo,
                # La bandera heredada queda desactivada: el escenario de T5 se
                # resuelve con órdenes y cola, nunca con el booleano.
                pending_dispensing=False,
                pending_wifi_reset=False,
                current_food_grams=stock,
            )
        )

    def _crear_orden(
        self,
        entregada_en=AHORA_NAIVE,
        solicitados=SOLICITADOS,
        estado="pending",
        dispenser_id=None,
    ):
        """Crea una orden directamente para aislar el barrido de la entrega."""
        sesion = SessionLocal()
        try:
            orden = models.DispensingOrder(
                user_id=self.usuario.id,
                pet_id=self.mascota.id,
                pet_name=self.mascota.name,
                dispenser_id=dispenser_id or self.dispensador.id,
                dispenser_mac_masked="**:AB:1F",
                requested_grams=solicitados,
                delivered_at=entregada_en,
                status=estado,
            )
            sesion.add(orden)
            sesion.commit()
            sesion.refresh(orden)
            return orden.id
        finally:
            sesion.close()

    # --- Acciones -----------------------------------------------------------

    def _cerrar_vencidas(self, ahora=LIMITE_DEL_PLAZO, dispenser_id=None):
        sesion = SessionLocal()
        try:
            return order_service.cerrar_vencidas(
                sesion, ahora=ahora, dispenser_id=dispenser_id
            )
        finally:
            sesion.close()

    def _procesar(self, order_id, ahora=LIMITE_DEL_PLAZO + timedelta(seconds=1), medidos=50.0):
        sesion = SessionLocal()
        try:
            return order_service.procesar_reporte(
                sesion,
                DispenserReportRequest(
                    mac=MAC,
                    order_id=order_id,
                    motivo="objetivo_alcanzado",
                    gramos_solicitados=SOLICITADOS,
                    gramos_medidos=medidos,
                    reintentos=0,
                ),
                ahora=ahora,
            )
        finally:
            sesion.close()

    # --- Consultas de estado (siempre en sesión nueva) ----------------------

    def _orden(self, order_id):
        sesion = SessionLocal()
        try:
            return sesion.query(models.DispensingOrder).filter(
                models.DispensingOrder.id == order_id
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

    def _logs(self, order_id=None):
        sesion = SessionLocal()
        try:
            consulta = sesion.query(models.ActivityLog)
            if order_id is not None:
                consulta = consulta.filter(models.ActivityLog.order_id == order_id)
            return consulta.order_by(models.ActivityLog.id).all()
        finally:
            sesion.close()

    def _stock(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first().current_food_grams
        finally:
            sesion.close()

    def _assert_sin_descuento(self):
        self.assertEqual(
            self._stock(), STOCK_INICIAL, "RF-19: el vencimiento no toca el stock"
        )


class TestFronterasDelVencimiento(BaseVencimientoTests):
    """RF-19: nunca antes del límite; en el límite tampoco; después sí."""

    def test_no_cierra_una_orden_cuyo_plazo_mas_1_s_no_ha_vencido(self):
        order_id = self._crear_orden()

        cerradas = self._cerrar_vencidas(ahora=LIMITE_DEL_PLAZO)

        self.assertEqual(
            cerradas, [], "RF-19: en el límite exacto la tolerancia sigue vigente"
        )
        self.assertEqual(self._orden(order_id).status, "pending")
        self.assertEqual(self._logs(), [], "Sin cierre no hay registro")
        self._assert_sin_descuento()

    def test_no_cierra_un_milisegundo_antes_del_limite(self):
        order_id = self._crear_orden()

        cerradas = self._cerrar_vencidas(
            ahora=LIMITE_DEL_PLAZO - timedelta(milliseconds=1)
        )

        self.assertEqual(cerradas, [])
        self.assertEqual(self._orden(order_id).status, "pending")

    def test_cierra_un_milisegundo_despues_del_limite(self):
        order_id = self._crear_orden()
        instante = LIMITE_DEL_PLAZO + timedelta(milliseconds=1)

        cerradas = self._cerrar_vencidas(ahora=instante)

        self.assertEqual(cerradas, [order_id])

        orden = self._orden(order_id)
        self.assertEqual(orden.status, "closed")
        self.assertEqual(orden.outcome, "failure")
        self.assertEqual(orden.cause, "sin_reporte")
        self.assertEqual(orden.closed_at, instante)
        self.assertIsNone(orden.measured_grams)
        self.assertIsNone(orden.discounted_grams)
        self.assertIsNone(orden.retry_count)

        logs = self._logs(order_id)
        self.assertEqual(len(logs), 1, "RF-19: un único registro de cierre")
        log = logs[0]
        self.assertEqual(log.event_type, "feeding_dispensed")
        self.assertEqual(log.outcome, "failure")
        self.assertEqual(log.cause, "sin_reporte")
        self.assertEqual(log.description, DESCRIPCION_SIN_REPORTE)
        self.assertEqual(log.order_id, order_id)
        self.assertEqual(log.requested_grams, SOLICITADOS)
        self.assertIsNone(log.measured_grams)
        self.assertIsNone(log.discounted_grams)
        self.assertIsNone(log.retry_count)
        self.assertEqual(log.created_at, instante)
        self.assertEqual(orden.log_id, log.id)
        # RF-24: todo dato ausente se registra como «no disponible».
        self.assertIn('"medidos": "no disponible"', log.context)
        self.assertIn('"reintentos": "no disponible"', log.context)
        self._assert_sin_descuento()

    def test_el_cierre_ocurre_dentro_de_60_s_con_el_barrido_de_30_s(self):
        order_id = self._crear_orden()

        # Cadencia real del job: un barrido cada 30 s desde la entrega.
        primer_barrido = AHORA_NAIVE + INTERVALO_BARRIDO * 10  # 300 s < 301 s
        segundo_barrido = AHORA_NAIVE + INTERVALO_BARRIDO * 11  # 330 s > 301 s

        self.assertEqual(self._cerrar_vencidas(ahora=primer_barrido), [])
        self.assertEqual(self._orden(order_id).status, "pending")

        self.assertEqual(self._cerrar_vencidas(ahora=segundo_barrido), [order_id])

        cerrada_en = self._orden(order_id).closed_at
        self.assertEqual(cerrada_en, segundo_barrido)
        self.assertLessEqual(
            cerrada_en - LIMITE_DEL_PLAZO,
            timedelta(seconds=60),
            "RF-19: el cierre no puede tardar más de 60 s desde el vencimiento",
        )
        # Estructura que garantiza la cota: un barrido cada 30 s.
        self.assertEqual(INTERVALO_BARRIDO, timedelta(seconds=30))
        self.assertEqual(PLAZO_ORDEN, timedelta(minutes=5))
        self.assertEqual(TOLERANCIA, timedelta(seconds=1))


class TestAlcanceDelBarrido(BaseVencimientoTests):
    """RF-19, RF-40: solo vencidas, sin descuento y con firmware antiguo."""

    def test_solo_cierra_las_ordenes_vencidas(self):
        vencida = self._crear_orden(entregada_en=AHORA_NAIVE - timedelta(minutes=10))

        # El índice único parcial impide dos órdenes pendientes del mismo
        # dispensador, así que la orden vigente se crea para otro dispensador.
        otra_mascota = self._crear_mascota(self.usuario, "Nina")
        otro_dispensador = self._guardar(
            models.Dispenser(
                mac_address="0A:1B:2C:3D:4E:5F",
                mac_normalized="0A1B2C3D4E5F",
                pet_id=otra_mascota.id,
                is_active=True,
                pending_dispensing=False,
                pending_wifi_reset=False,
                current_food_grams=STOCK_INICIAL,
            )
        )
        vigente = self._crear_orden(
            entregada_en=AHORA_NAIVE, dispenser_id=otro_dispensador.id
        )

        cerradas = self._cerrar_vencidas(ahora=LIMITE_DEL_PLAZO)

        self.assertEqual(cerradas, [vencida])
        self.assertEqual(self._orden(vencida).status, "closed")
        self.assertEqual(self._orden(vigente).status, "pending")
        self.assertEqual(self._logs(vigente), [])

    def test_el_barrido_es_idempotente(self):
        order_id = self._crear_orden()
        despues = LIMITE_DEL_PLAZO + timedelta(seconds=30)

        primera = self._cerrar_vencidas(ahora=despues)
        segunda = self._cerrar_vencidas(ahora=despues + timedelta(seconds=30))

        self.assertEqual(primera, [order_id])
        self.assertEqual(segunda, [], "RNF-3: no hay segundo cierre")
        self.assertEqual(len(self._logs(order_id)), 1)

    def test_no_cierra_ordenes_ya_cerradas(self):
        order_id = self._crear_orden(estado="closed")

        self.assertEqual(self._cerrar_vencidas(), [])
        self.assertEqual(self._logs(), [])

    def test_firmware_antiguo_cierra_por_plazo_sin_reporte_ni_descuento(self):
        # RF-40: un firmware sin reporte no ejecuta `POST /dispensers/reports`;
        # el barrido cierra la orden igualmente, sin exigir ningún reporte.
        order_id = self._crear_orden()

        self.assertEqual(self._cerrar_vencidas(), [])

        cerradas = self._cerrar_vencidas(ahora=LIMITE_DEL_PLAZO + timedelta(seconds=1))

        self.assertEqual(cerradas, [order_id])
        self.assertEqual(self._orden(order_id).cause, "sin_reporte")
        self.assertEqual(len(self._logs(order_id)), 1)
        self._assert_sin_descuento()

    def test_el_barrido_puede_limitarse_a_un_dispensador(self):
        order_id = self._crear_orden()
        despues = LIMITE_DEL_PLAZO + timedelta(milliseconds=1)

        self.assertEqual(
            self._cerrar_vencidas(ahora=despues, dispenser_id=self.dispensador.id + 999),
            [],
        )
        self.assertEqual(self._orden(order_id).status, "pending")

        self.assertEqual(
            self._cerrar_vencidas(ahora=despues, dispenser_id=self.dispensador.id),
            [order_id],
        )


class TestExclusionMutuaConElReporte(BaseVencimientoTests):
    """RNF-3: una sola transición entre el reporte y el barrido."""

    def test_un_reporte_dentro_del_plazo_no_se_duplica_al_vencer(self):
        order_id = self._crear_orden()

        cierre = self._procesar(order_id, ahora=LIMITE_DEL_PLAZO, medidos=50.0)

        self.assertFalse(cierre["ya_cerrada"])
        self.assertEqual(cierre["outcome"], "success")

        self.assertEqual(
            self._cerrar_vencidas(ahora=LIMITE_DEL_PLAZO + timedelta(seconds=1)), []
        )
        self.assertEqual(len(self._logs(order_id)), 1)
        self.assertAlmostEqual(self._stock(), STOCK_INICIAL - 50.0)

    def test_el_barrido_cierra_y_el_reporte_tardio_devuelve_ya_cerrada(self):
        order_id = self._crear_orden()
        self._cerrar_vencidas(ahora=LIMITE_DEL_PLAZO + timedelta(milliseconds=1))

        respuesta = self._procesar(order_id, medidos=50.0)

        self.assertTrue(respuesta["ya_cerrada"], "RF-18: prevalece el cierre del barrido")
        self.assertEqual(respuesta["outcome"], "failure")
        self.assertEqual(respuesta["cause"], "sin_reporte")
        self.assertEqual(respuesta["discounted_grams"], 0.0)
        self.assertEqual(len(self._logs(order_id)), 1)
        self._assert_sin_descuento()

    def test_un_reporte_tardio_deja_la_orden_cerrada_y_el_barrido_no_duplica(self):
        order_id = self._crear_orden()
        self._procesar(order_id, ahora=LIMITE_DEL_PLAZO + timedelta(seconds=10))

        self.assertEqual(self._cerrar_vencidas(ahora=LIMITE_DEL_PLAZO + timedelta(seconds=20)), [])

        self.assertEqual(self._orden(order_id).cause, "orden_cerrada")
        self.assertEqual(len(self._logs(order_id)), 1)
        self._assert_sin_descuento()

    def test_reporte_y_barrido_simultaneos_producen_un_unico_registro(self):
        order_id = self._crear_orden()
        instante = LIMITE_DEL_PLAZO + timedelta(seconds=5)
        errores = []
        resultados = []
        barrera = threading.Barrier(2)

        def reportar():
            sesion = SessionLocal()
            try:
                barrera.wait(timeout=10)
                resultados.append(
                    order_service.procesar_reporte(
                        sesion,
                        DispenserReportRequest(
                            mac=MAC,
                            order_id=order_id,
                            motivo="objetivo_alcanzado",
                            gramos_solicitados=SOLICITADOS,
                            gramos_medidos=50.0,
                            reintentos=0,
                        ),
                        ahora=instante,
                    )
                )
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                sesion.close()

        def barrer():
            sesion = SessionLocal()
            try:
                barrera.wait(timeout=10)
                resultados.append(
                    {"cerradas": order_service.cerrar_vencidas(sesion, ahora=instante)}
                )
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                sesion.close()

        hilos = [threading.Thread(target=reportar), threading.Thread(target=barrer)]
        for hilo in hilos:
            hilo.start()
        for hilo in hilos:
            hilo.join(timeout=20)

        self.assertEqual(errores, [], f"El cierre simultáneo no debe fallar: {errores}")
        self.assertEqual(len(resultados), 2)

        logs = self._logs(order_id)
        self.assertEqual(len(logs), 1, "RNF-3: un único cierre y un único registro")
        self.assertIn(logs[0].cause, {"sin_reporte", "orden_cerrada"})
        self.assertEqual(self._orden(order_id).status, "closed")
        self._assert_sin_descuento()


class TestBarridoProgramado(unittest.TestCase):
    """RNF-3: un único job de 30 s que cierra y después encola."""

    def test_el_job_ejecuta_primero_el_cierre_y_despues_el_encolado(self):
        llamadas = []
        db = MagicMock()

        with patch.object(
            order_service, "cerrar_vencidas", side_effect=lambda *a, **k: llamadas.append("cerrar") or []
        ), patch.object(
            order_service, "encolar_comida", side_effect=lambda *a, **k: llamadas.append("encolar") or []
        ):
            background_schedules.ejecutar_barrido(db)

        self.assertEqual(
            llamadas,
            ["cerrar", "encolar"],
            "RF-19, RF-25: primero se cierran los vencimientos y después se encola",
        )

    def test_el_arranque_programa_un_unico_job_cada_30_s(self):
        from app import main

        with TestClient(app):
            trabajos = main.scheduler.get_jobs()

            self.assertEqual(len(trabajos), 1, "Un único job de barrido (RNF-3)")
            trabajo = trabajos[0]
            self.assertEqual(trabajo.trigger.interval, INTERVALO_BARRIDO)
            self.assertEqual(trabajo.max_instances, 1)
            self.assertTrue(trabajo.coalesce)

    def test_la_tarea_programada_cierra_la_sesion(self):
        from app import main

        sesion = MagicMock()
        with patch.object(main, "SessionLocal", return_value=sesion), patch.object(
            main, "ejecutar_barrido"
        ) as barrido:
            main.execute_cron_task()

        barrido.assert_called_once()
        sesion.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
