"""Entrega prioritaria, reporte, evento y stock de la dispensación rápida (T3).

La solicitud manual se entrega antes que cualquier comida programada en espera,
se reclama una sola vez y reutiliza el cierre de la spec 014: evento
`feeding_dispensed`, descuento acotado y `sin_reporte` cuando no hay reporte.
"""

import os
import sys
import threading
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi import HTTPException

from app.db.database import SessionLocal
from app.domain.tiempo import PLAZO_ORDEN, PLAZO_SOLICITUD_RAPIDA
from app.models import models
from app.schemas.reports import DispenserReportRequest
from app.services import order_service, pet_service

from test_quick_dispense import (
    AHORA,
    GRAMOS_HORARIO,
    MAC,
    STOCK_INICIAL,
    BaseDispensacionRapidaTests,
    _en_utc,
)


class TestEntregaRapida(BaseDispensacionRapidaTests):
    """RF-8 a RF-10: prioridad, reclamación, evento y cierre."""

    def _crear_espera_programada(self, hora="07:50", gramos=30.0):
        from app.models import models as m

        sesion = SessionLocal()
        try:
            item = m.DispensingQueue(
                dispenser_id=self.dispensador.id,
                pet_id=self.mascota.id,
                schedule_id=self.horario.id,
                amount=gramos,
                scheduled_for=_en_utc(datetime(2026, 10, 1, 7, 50)),
                consumed_at=None,
            )
            sesion.add(item)
            sesion.commit()
            sesion.refresh(item)
            return item.id
        finally:
            sesion.close()

    def _reportar(
        self,
        order_id,
        medidos,
        ahora=AHORA,
        motivo="objetivo_alcanzado",
        solicitados=50.0,
    ):
        sesion = SessionLocal()
        try:
            return order_service.procesar_reporte(
                sesion,
                DispenserReportRequest(
                    mac=MAC,
                    order_id=order_id,
                    motivo=motivo,
                    gramos_solicitados=solicitados,
                    gramos_medidos=medidos,
                    reintentos=0,
                ),
                ahora=_en_utc(ahora),
            )
        finally:
            sesion.close()

    def _stock(self):
        sesion = SessionLocal()
        try:
            return (
                sesion.query(models.Dispenser.current_food_grams)
                .filter(models.Dispenser.id == self.dispensador.id)
                .scalar()
            )
        finally:
            sesion.close()

    def test_la_solicitud_manual_se_entrega_antes_que_la_programada(self):
        self._crear_espera_programada()
        self._solicitar(50)

        respuesta = self._entregar()

        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], 50.0)
        self.assertEqual(len(self._ordenes()), 1)
        self.assertEqual(self._ordenes()[0].requested_grams, 50.0)

        # La siguiente consulta entrega la comida programada que quedó en espera.
        self._reportar(respuesta["order_id"], medidos=50.0)
        siguiente = self._entregar(ahora=AHORA + timedelta(seconds=10))
        self.assertTrue(siguiente["serve"])
        self.assertEqual(siguiente["amount"], 30.0)

    def test_dos_solicitudes_se_entregan_en_orden_de_llegada(self):
        self._solicitar(20, ahora=AHORA)
        self._solicitar(30, ahora=AHORA + timedelta(seconds=1))

        primera = self._entregar()
        self._reportar(primera["order_id"], medidos=20.0)
        segunda = self._entregar(ahora=AHORA + timedelta(seconds=2))

        self.assertEqual(primera["amount"], 20.0)
        self.assertEqual(segunda["amount"], 30.0)

    def test_una_solicitud_se_reclama_una_sola_vez(self):
        self._solicitar(50)
        self._entregar()
        self.assertEqual(len(self._ordenes()), 1)
        self.assertFalse(self._entregar()["serve"])

    def test_dos_consultas_simultaneas_crean_una_sola_orden(self):
        self._solicitar(50)
        resultados = []
        barrera = threading.Barrier(2)

        def consultar():
            sesion = SessionLocal()
            try:
                barrera.wait(timeout=5)
                resultados.append(
                    order_service.entregar_orden(
                        sesion, MAC, ahora=_en_utc(AHORA + timedelta(seconds=5))
                    )
                )
            finally:
                sesion.close()

        hilos = [threading.Thread(target=consultar) for _ in range(2)]
        for hilo in hilos:
            hilo.start()
        for hilo in hilos:
            hilo.join(timeout=10)

        activas = [r for r in resultados if r.get("serve")]
        self.assertEqual(len(activas), 1)
        self.assertEqual(len(self._ordenes()), 1)
        self.assertEqual(len(self._solicitudes()), 1)
        self.assertIsNotNone(self._solicitudes()[0].consumed_at)

    def test_el_reporte_escribe_el_evento_y_descuenta_el_stock(self):
        self._solicitar(50)
        order_id = self._entregar()["order_id"]

        resultado = self._reportar(order_id, medidos=50.0)

        self.assertEqual(resultado["outcome"], "success")
        self.assertEqual(resultado["cause"], "objetivo_alcanzado")
        self.assertEqual(self._stock(), STOCK_INICIAL - 50.0)

        registros = self._registros()
        self.assertEqual(len(registros), 1)
        registro = registros[0]
        self.assertEqual(registro.event_type, "feeding_dispensed")
        self.assertEqual(registro.outcome, "success")
        self.assertEqual(registro.cause, "objetivo_alcanzado")
        self.assertEqual(registro.requested_grams, 50.0)
        self.assertEqual(registro.measured_grams, 50.0)
        self.assertEqual(registro.discounted_grams, 50.0)
        self.assertEqual(registro.order_id, order_id)

    def test_una_entrega_incompleta_no_descuenta_stock(self):
        self._solicitar(50)
        order_id = self._entregar()["order_id"]

        resultado = self._reportar(order_id, medidos=30.0)

        self.assertEqual(resultado["outcome"], "failure")
        self.assertEqual(resultado["cause"], "entrega_incompleta")
        self.assertEqual(self._stock(), STOCK_INICIAL)
        self.assertEqual(len(self._registros()), 1)

    def test_sin_reporte_cierra_por_plazo_sin_descontar(self):
        self._solicitar(50)
        order_id = self._entregar()["order_id"]

        sesion = SessionLocal()
        try:
            order_service.cerrar_vencidas(
                sesion,
                ahora=_en_utc(AHORA + PLAZO_ORDEN + timedelta(seconds=2)),
                dispenser_id=self.dispensador.id,
            )
        finally:
            sesion.close()

        sesion = SessionLocal()
        try:
            orden = (
                sesion.query(models.DispensingOrder)
                .filter(models.DispensingOrder.id == order_id)
                .first()
            )
        finally:
            sesion.close()

        self.assertEqual(orden.status, "closed")
        self.assertEqual(orden.cause, "sin_reporte")
        self.assertEqual(self._stock(), STOCK_INICIAL)
        registros = self._registros()
        self.assertEqual(len(registros), 1)
        self.assertEqual(registros[0].cause, "sin_reporte")

    def test_el_dispensador_desactivado_no_entrega_la_solicitud(self):
        self._solicitar(50)
        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            dispensador.is_active = False
            sesion.commit()
        finally:
            sesion.close()

        self.assertFalse(self._entregar()["serve"])
        self.assertEqual(self._ordenes(), [])

        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            dispensador.is_active = True
            sesion.commit()
        finally:
            sesion.close()

        self.assertTrue(self._entregar()["serve"])
        self.assertEqual(len(self._ordenes()), 1)

    def test_el_modo_simulado_no_escribe_nada(self):
        self._solicitar(50)
        sesion = SessionLocal()
        try:
            respuesta = order_service.entregar_orden(
                sesion,
                MAC,
                ahora=_en_utc(AHORA),
                simular=True,
            )
        finally:
            sesion.close()

        self.assertEqual(respuesta, {"serve": True, "amount": 50.0})
        self.assertEqual(self._ordenes(), [])
        self.assertIsNone(self._solicitudes()[0].consumed_at)


class TestCicloDeVidaSolicitud(BaseDispensacionRapidaTests):
    """RF-9, RF-10 y RF-16: reasignación, cascada, espera y tope de 200 g.

    La solicitud manual conserva el ciclo de la spec 014: se entrega como una
    orden normal, su cierre escribe el evento y solo descuenta stock si el cierre
    es exitoso. Una solicitud de la mascota anterior se descarta al intentar
    entregarse, sin orden ni evento.
    """

    def _reasignar(self, mascota):
        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            dispensador.pet_id = mascota.id
            sesion.commit()
        finally:
            sesion.close()

    def _solicitud_fresca(self):
        sesion = SessionLocal()
        try:
            return (
                sesion.query(models.ManualDispensingRequest)
                .order_by(models.ManualDispensingRequest.id)
                .first()
            )
        finally:
            sesion.close()

    def _stock(self):
        sesion = SessionLocal()
        try:
            return (
                sesion.query(models.Dispenser.current_food_grams)
                .filter(models.Dispenser.id == self.dispensador.id)
                .scalar()
            )
        finally:
            sesion.close()

    def _reportar(self, order_id, medidos, motivo="objetivo_alcanzado", solicitados=200.0):
        sesion = SessionLocal()
        try:
            return order_service.procesar_reporte(
                sesion,
                DispenserReportRequest(
                    mac=MAC,
                    order_id=order_id,
                    motivo=motivo,
                    gramos_solicitados=solicitados,
                    gramos_medidos=medidos,
                    reintentos=0,
                ),
                ahora=_en_utc(AHORA),
            )
        finally:
            sesion.close()

    def test_la_solicitud_de_la_mascota_anterior_se_descarta_sin_orden_ni_evento(
        self,
    ):
        self._solicitar(50)
        nueva_mascota = self._crear_mascota(self.usuario, "Luna")
        self._reasignar(nueva_mascota)

        respuesta = self._entregar()

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertEqual(self._ordenes(), [])
        self.assertEqual(self._registros(), [])

        solicitud = self._solicitud_fresca()
        self.assertIsNotNone(
            solicitud.consumed_at, "La solicitud descartada queda consumida"
        )

        # La siguiente consulta ya no la sirve.
        self.assertEqual(self._entregar(), {"serve": False, "amount": 0})
        self.assertEqual(self._ordenes(), [])
        self.assertEqual(self._registros(), [])

    def test_tras_descartar_la_ajena_se_entrega_la_solicitud_vigente(self):
        self._solicitar(50, operation_id="op-mascota-anterior")
        nueva_mascota = self._crear_mascota(self.usuario, "Luna")
        self._reasignar(nueva_mascota)

        self._solicitar(30, operation_id="op-mascota-nueva")
        respuesta = self._entregar()

        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], 30.0)
        ordenes = self._ordenes()
        self.assertEqual(len(ordenes), 1)
        self.assertEqual(ordenes[0].pet_id, nueva_mascota.id)
        self.assertEqual(ordenes[0].pet_name, "Luna")
        self.assertEqual(self._registros(), [])

    def test_eliminar_el_dispensador_borra_la_solicitud_sin_orden_ni_evento(self):
        self._solicitar(50)

        sesion = SessionLocal()
        try:
            sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).delete(synchronize_session=False)
            sesion.commit()
        finally:
            sesion.close()

        self.assertEqual(self._solicitudes(), [], "La FK en cascada borra la solicitud")
        self.assertEqual(self._ordenes(), [])
        self.assertEqual(self._registros(), [])

    def test_la_baja_de_la_mascota_con_dispensador_responde_409(self):
        """RF-16: la baja se rechaza sin borrar la solicitud ni escribir evento.

        El dispensador está vinculado a la mascota, así que la baja responde 409
        `pet_has_dispenser`; desvincularlo es un paso previo explícito. La
        solicitud pendiente y el historial quedan intactos.
        """
        self._solicitar(50)
        self.assertEqual(len(self._solicitudes()), 1)

        sesion = SessionLocal()
        try:
            with self.assertRaises(HTTPException) as contexto:
                pet_service.eliminar_mascota(
                    sesion, self.mascota.id, self.usuario.id
                )
        finally:
            sesion.close()

        self.assertEqual(contexto.exception.status_code, 409)
        self.assertEqual(contexto.exception.detail["code"], "pet_has_dispenser")
        self.assertEqual(
            len(self._solicitudes()), 1, "La solicitud pendiente no se borra"
        )
        self.assertIsNone(self._solicitudes()[0].consumed_at)
        self.assertEqual(self._registros(), [], "La baja rechazada no escribe evento")

    def test_una_solicitud_sin_consulta_se_entrega_antes_del_plazo(self):
        self._solicitar(50)

        sesion = SessionLocal()
        try:
            cerradas = order_service.cerrar_vencidas(
                sesion,
                ahora=_en_utc(AHORA + timedelta(days=1)),
                dispenser_id=self.dispensador.id,
            )
        finally:
            sesion.close()

        # El cierre de órdenes de la 014 no toca la solicitud rápida ("no vence").
        self.assertEqual(cerradas, [])
        self.assertEqual(self._ordenes(), [])
        self.assertEqual(self._registros(), [])
        solicitud = self._solicitud_fresca()
        self.assertIsNotNone(solicitud, "La solicitud no se borra")
        self.assertIsNone(solicitud.consumed_at)

        respuesta = self._entregar(ahora=AHORA + timedelta(minutes=10))

        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], 50.0)

    def test_una_solicitud_sin_consulta_vence_y_ya_no_se_entrega(self):
        # La 021 sustituye el caso límite de la 020 «equipo que nunca consulta:
        # queda pendiente sin vencimiento»: pasados los 15 minutos la consulta
        # descarta la solicitud vencida y no dispensa (RF-1, RF-4).
        self._solicitar(50)

        respuesta = self._entregar(
            ahora=AHORA + PLAZO_SOLICITUD_RAPIDA + timedelta(seconds=1)
        )

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertEqual(self._ordenes(), [], "Una vencida no crea orden")
        self.assertIsNotNone(self._solicitud_fresca().consumed_at)
        registros = self._registros()
        self.assertEqual(len(registros), 1)
        self.assertEqual(registros[0].cause, "solicitud_vencida")

    def test_objetivo_no_alcanzado_en_200_g_no_descuenta_stock(self):
        self._solicitar(200)
        order_id = self._entregar()["order_id"]
        self.assertEqual(self._ordenes()[0].requested_grams, 200.0)

        respuesta = self._reportar(order_id, medidos=150.0, motivo="objetivo_no_alcanzado")

        self.assertEqual(respuesta["outcome"], "failure")
        self.assertEqual(respuesta["cause"], "objetivo_no_alcanzado")
        self.assertEqual(respuesta["discounted_grams"], 0.0)
        self.assertEqual(self._stock(), STOCK_INICIAL)

        registros = self._registros()
        self.assertEqual(len(registros), 1)
        self.assertEqual(registros[0].event_type, "feeding_dispensed")
        self.assertEqual(registros[0].outcome, "failure")
        self.assertEqual(registros[0].cause, "objetivo_no_alcanzado")
        self.assertEqual(registros[0].requested_grams, 200.0)
        self.assertIsNone(registros[0].discounted_grams)

    def test_medidos_menores_en_200_g_cierran_entrega_incompleta(self):
        self._solicitar(200)
        order_id = self._entregar()["order_id"]

        respuesta = self._reportar(
            order_id, medidos=199.5, motivo="objetivo_alcanzado"
        )

        self.assertEqual(respuesta["outcome"], "failure")
        self.assertEqual(respuesta["cause"], "entrega_incompleta")
        self.assertEqual(respuesta["discounted_grams"], 0.0)
        self.assertEqual(self._stock(), STOCK_INICIAL)

        registros = self._registros()
        self.assertEqual(len(registros), 1)
        self.assertEqual(registros[0].event_type, "feeding_dispensed")
        self.assertEqual(registros[0].cause, "entrega_incompleta")
        self.assertEqual(registros[0].measured_grams, 199.5)
        self.assertIsNone(registros[0].discounted_grams)


if __name__ == "__main__":
    unittest.main()
