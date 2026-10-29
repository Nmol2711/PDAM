"""Comidas en espera y cola de dispensación (spec 014, T5; RF-25).

La comida programada no se pierde: se encola una sola vez por ocurrencia y se
entrega en la siguiente consulta del dispositivo cuando ya no hay una orden
pendiente dentro de su plazo y el dispensador está activo. La cola no se
consume mientras exista esa orden, mientras el dispensador esté desactivado ni
en la consulta que cierra una orden vencida; el elemento espera y se entrega en
la consulta siguiente.

El reloj se inyecta como `ahora` en todas las llamadas y las comprobaciones se
hacen con sesiones nuevas para no leer la caché de SQLAlchemy.
"""

import os
import sys
import threading
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from app.db.database import SessionLocal
from app.domain.tiempo import PLAZO_ORDEN, TOLERANCIA
from app.models import models
from app.schemas.dispenser import DispenserUpdate
from app.schemas.reports import DispenserReportRequest
from app.services import dispenser_service, order_service

MAC = "AA:BB:CC:DD:AB:1F"
MAC_NORMALIZADA = "AABBCCDDAB1F"


def _en_utc(instante_local: datetime) -> datetime:
    """Convierte una hora local del servidor al UTC naive que usan los servicios.

    Las pruebas escriben las horas como las vería una persona en el servidor
    (08:00 de la mañana); el servicio recibe UTC y el horario se interpreta en la
    zona local. Así las pruebas son deterministas en cualquier zona horaria y
    fallan si el horario se compara contra UTC.
    """
    return instante_local.astimezone(timezone.utc).replace(tzinfo=None)


# Hora programada del horario del escenario y hora local del servidor con la que
# se ejecuta el barrido (dentro de la ventana de la ocurrencia de las 08:00).
HORA_PROGRAMADA = "08:00"
AHORA = datetime(2026, 10, 1, 8, 0, 10)

GRAMOS_ESPERA = 40.0
GRAMOS_ORDEN = 50.0
STOCK_INICIAL = 1200.0


class BaseColaTests(unittest.TestCase):
    """Un usuario, su mascota, un dispensador activo y un horario."""

    def setUp(self):
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario()
        self.mascota = self._crear_mascota(self.usuario)
        self.dispensador = self._crear_dispensador(self.mascota, MAC)
        self.horario = self._guardar(
            models.Schedule(
                time=HORA_PROGRAMADA, amount=GRAMOS_ESPERA, pet_id=self.mascota.id
            )
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

    def _crear_usuario(self, email="dueno@cola.test"):
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

    def _crear_dispensador(self, mascota, mac_address, activo=True, stock=STOCK_INICIAL):
        return self._guardar(
            models.Dispenser(
                mac_address=mac_address,
                mac_normalized=MAC_NORMALIZADA,
                pet_id=mascota.id,
                is_active=activo,
                # El escenario de la cola no usa la bandera heredada.
                pending_dispensing=False,
                pending_wifi_reset=False,
                current_food_grams=stock,
            )
        )

    def _crear_orden(self, entregada_en, solicitados=GRAMOS_ORDEN):
        """Orden pendiente que ya está en curso (bloquea la entrega, RF-25)."""
        sesion = SessionLocal()
        try:
            orden = models.DispensingOrder(
                user_id=self.usuario.id,
                pet_id=self.mascota.id,
                pet_name=self.mascota.name,
                dispenser_id=self.dispensador.id,
                dispenser_mac_masked="**:AB:1F",
                requested_grams=solicitados,
                delivered_at=_en_utc(entregada_en),
                status="pending",
            )
            sesion.add(orden)
            sesion.commit()
            sesion.refresh(orden)
            return orden.id
        finally:
            sesion.close()

    # --- Acciones -----------------------------------------------------------

    def _encolar(self, ahora=AHORA):
        sesion = SessionLocal()
        try:
            return order_service.encolar_comida(sesion, ahora=_en_utc(ahora))
        finally:
            sesion.close()

    def _encolar_con_zona(self, ahora_utc, zona):
        """Encola con un desplazamiento explícito del servidor (RF-25)."""
        sesion = SessionLocal()
        try:
            return order_service.encolar_comida(sesion, ahora=ahora_utc, zona=zona)
        finally:
            sesion.close()

    def _cambiar_hora_del_horario(self, hora):
        """Cambia la hora de la programación del escenario base."""
        sesion = SessionLocal()
        try:
            horario = sesion.query(models.Schedule).filter(
                models.Schedule.id == self.horario.id
            ).first()
            horario.time = hora
            sesion.commit()
        finally:
            sesion.close()

    def _entregar(self, ahora=AHORA):
        sesion = SessionLocal()
        try:
            return order_service.entregar_orden(sesion, MAC, ahora=_en_utc(ahora))
        finally:
            sesion.close()

    def _reportar(self, order_id, ahora, medidos):
        sesion = SessionLocal()
        try:
            return order_service.procesar_reporte(
                sesion,
                DispenserReportRequest(
                    mac=MAC,
                    order_id=order_id,
                    motivo="objetivo_alcanzado",
                    gramos_solicitados=GRAMOS_ORDEN,
                    gramos_medidos=medidos,
                    reintentos=0,
                ),
                ahora=_en_utc(ahora),
            )
        finally:
            sesion.close()

    def _activar(self, activo):
        sesion = SessionLocal()
        try:
            dispenser_service.update_dispenser(
                db=sesion,
                dispenser_id=self.dispensador.id,
                dispenser_update=DispenserUpdate(is_active=activo),
            )
        finally:
            sesion.close()

    # --- Consultas de estado (siempre en sesión nueva) ----------------------

    def _cola(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.DispensingQueue).order_by(
                models.DispensingQueue.scheduled_for, models.DispensingQueue.id
            ).all()
        finally:
            sesion.close()

    def _esperando(self):
        return [item for item in self._cola() if item.consumed_at is None]

    def _ordenes(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.DispensingOrder).order_by(
                models.DispensingOrder.id
            ).all()
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


class TestEncoladoDeLaComidaProgramada(BaseColaTests):
    """RF-25: la ocurrencia se encola una sola vez y no se pierde."""

    def test_encola_la_ocurrencia_programada_en_la_ventana(self):
        insertadas = self._encolar(AHORA)

        cola = self._cola()
        self.assertEqual(len(insertadas), 1)
        self.assertEqual(len(cola), 1)
        item = cola[0]
        self.assertEqual(item.dispenser_id, self.dispensador.id)
        self.assertEqual(item.pet_id, self.mascota.id)
        self.assertEqual(item.schedule_id, self.horario.id)
        self.assertEqual(item.amount, GRAMOS_ESPERA)
        self.assertEqual(item.scheduled_for, datetime(2026, 10, 1, 8, 0))
        self.assertIsNone(item.consumed_at, "La ocurrencia espera su turno")

    def test_no_duplica_la_misma_ocurrencia(self):
        self._encolar(AHORA)
        insertadas = self._encolar(AHORA + timedelta(seconds=20))

        self.assertEqual(insertadas, [], "La ocurrencia ya estaba encolada")
        self.assertEqual(len(self._cola()), 1)

    def test_no_encola_antes_de_la_hora_programada(self):
        self.assertEqual(self._encolar(datetime(2026, 10, 1, 7, 59, 50)), [])
        self.assertEqual(self._cola(), [])

    def test_no_encola_fuera_de_la_ventana_de_la_ocurrencia(self):
        self.assertEqual(self._encolar(datetime(2026, 10, 1, 8, 11, 0)), [])
        self.assertEqual(self._cola(), [])

    def test_la_ocurrencia_del_dia_siguiente_es_independiente(self):
        self._encolar(AHORA)
        self._encolar(datetime(2026, 10, 2, 8, 0, 5))

        cola = self._cola()
        self.assertEqual(len(cola), 2)
        self.assertEqual(
            [item.scheduled_for for item in cola],
            [datetime(2026, 10, 1, 8, 0), datetime(2026, 10, 2, 8, 0)],
        )

    def test_un_dispensador_desactivado_tambien_encola(self):
        self._activar(False)

        self.assertEqual(len(self._encolar(AHORA)), 1)
        self.assertEqual(len(self._esperando()), 1, "RF-25: la comida no se descarta")

    def test_un_horario_sin_dispensador_no_se_encola(self):
        otra_mascota = self._crear_mascota(self.usuario, "Nina")
        self._guardar(
            models.Schedule(time="08:00", amount=30.0, pet_id=otra_mascota.id)
        )

        self.assertEqual(len(self._encolar(AHORA)), 1)
        self.assertEqual(
            [item.pet_id for item in self._cola()],
            [self.mascota.id],
            "Solo se encola lo que tiene dispensador al que entregarse",
        )

    def test_el_encolado_no_crea_ordenes_por_si_solo(self):
        self._encolar(AHORA)

        self.assertEqual(len(self._esperando()), 1)
        self.assertEqual(
            self._ordenes(),
            [],
            "La orden de dispensación se crea solo al entregarla al dispositivo",
        )


class TestHoraLocalDelServidor(BaseColaTests):
    """El horario se interpreta en la hora local del servidor (RF-25).

    Las pruebas escriben las horas locales y las convierten a UTC antes de llamar
    al servicio. En un servidor con desplazamiento distinto de cero fallan si el
    horario se compara contra la hora UTC, que es el defecto que corrigió T5.
    """

    def test_la_ocurrencia_se_calcula_en_la_hora_local_vigente(self):
        # A las 00:05 locales del 1 de octubre el instante UTC puede ser otro
        # día. La ocurrencia de las 00:00 debe encontrarse igualmente.
        self._guardar(
            models.Schedule(time="00:00", amount=25.0, pet_id=self.mascota.id)
        )

        insertadas = self._encolar(datetime(2026, 10, 1, 0, 5, 0))

        self.assertEqual(len(insertadas), 1)
        self.assertEqual(
            [item.scheduled_for for item in self._cola()],
            [datetime(2026, 10, 1, 0, 0)],
        )

    def test_la_ocurrencia_que_cruza_medianoche_se_encola(self):
        self._guardar(
            models.Schedule(time="23:59", amount=25.0, pet_id=self.mascota.id)
        )

        insertadas = self._encolar(datetime(2026, 10, 1, 0, 5, 0))

        self.assertEqual(len(insertadas), 1)
        self.assertEqual(
            [item.scheduled_for for item in self._cola()],
            [datetime(2026, 9, 30, 23, 59)],
        )

    def test_un_horario_que_coincide_con_utc_pero_no_con_la_hora_local_no_se_encola(self):
        # El desplazamiento se inyecta para no depender de la zona del equipo:
        # con el servidor en UTC-05, el barrido de las 12:00 UTC corre a las
        # 07:00 locales. Un horario «12:00» coincide con la hora UTC pero no con
        # la local y no debe encolarse; solo la ocurrencia local de las 07:00.
        zona = timezone(timedelta(hours=-5))
        self._cambiar_hora_del_horario("07:00")
        horario_utc = self._guardar(
            models.Schedule(time="12:00", amount=25.0, pet_id=self.mascota.id)
        )

        insertadas = self._encolar_con_zona(
            datetime(2026, 10, 1, 12, 0, 10), zona
        )

        self.assertEqual(len(insertadas), 1)
        self.assertEqual(
            [item.schedule_id for item in self._cola()],
            [self.horario.id],
            "Solo se encola la ocurrencia de la hora local",
        )
        self.assertNotIn(horario_utc.id, [item.schedule_id for item in self._cola()])
        self.assertEqual(
            [item.scheduled_for for item in self._cola()],
            [datetime(2026, 10, 1, 7, 0)],
        )

    def test_la_hora_local_del_servidor_acepta_cualquier_desplazamiento(self):
        # La misma hora UTC produce horas de pared distintas según la zona del
        # servidor: +02:00 adelanta el reloj y -05:00 lo atrasa (RF-25).
        casos = [
            (timezone(timedelta(hours=2)), "10:00", datetime(2026, 10, 1, 10, 0)),
            (timezone(timedelta(hours=-5)), "03:00", datetime(2026, 10, 1, 3, 0)),
        ]

        for indice, (zona, hora, ocurrencia) in enumerate(casos):
            with self.subTest(zona=zona.tzname(None)):
                self._limpiar_base_de_datos()
                self.usuario = self._crear_usuario()
                self.mascota = self._crear_mascota(self.usuario)
                self.dispensador = self._crear_dispensador(self.mascota, MAC)
                self.horario = self._guardar(
                    models.Schedule(
                        time=hora, amount=GRAMOS_ESPERA, pet_id=self.mascota.id
                    )
                )

                insertadas = self._encolar_con_zona(
                    datetime(2026, 10, 1, 8, 0, 10), zona
                )

                self.assertEqual(len(insertadas), 1, f"caso {indice}: {zona}")
                self.assertEqual(
                    [item.scheduled_for for item in self._cola()], [ocurrencia]
                )


class TestConcurrenciaDeEntrega(BaseColaTests):
    """Dos consultas simultáneas del dispositivo (RF-25).

    La reclamación de la ocurrencia es un `UPDATE ... WHERE consumed_at IS NULL`
    con `rowcount`: una sola consulta sirve la comida, crea una única orden
    pendiente y consume la ocurrencia una sola vez.
    """

    def test_dos_consultas_simultaneas_no_duplican_la_entrega(self):
        self._encolar(AHORA)
        resultados = []
        errores = []
        barrera = threading.Barrier(2)
        consulta_original = order_service._dispensador_por_mac

        def consultar_con_barrera(db, mac):
            # Las dos sesiones ya leyeron el dispensador antes de competir por
            # la ocurrencia, igual que dos consultas reales simultáneas.
            encontrado = consulta_original(db, mac)
            barrera.wait(timeout=10)
            return encontrado

        def entregar():
            sesion = SessionLocal()
            try:
                resultados.append(
                    order_service.entregar_orden(
                        sesion, MAC, ahora=_en_utc(AHORA)
                    )
                )
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                sesion.close()

        with patch.object(
            order_service, "_dispensador_por_mac", side_effect=consultar_con_barrera
        ):
            hilos = [threading.Thread(target=entregar) for _ in range(2)]
            for hilo in hilos:
                hilo.start()
            for hilo in hilos:
                hilo.join(timeout=20)

        self.assertEqual(errores, [], f"Las consultas simultáneas fallaron: {errores}")
        self.assertEqual(len(resultados), 2)

        servidas = [resultado for resultado in resultados if resultado["serve"]]
        reposo = [resultado for resultado in resultados if not resultado["serve"]]
        self.assertEqual(len(servidas), 1, "Una sola consulta sirve la comida")
        self.assertEqual(reposo, [{"serve": False, "amount": 0}])

        self.assertEqual(len(self._ordenes()), 1, "Se crea una única orden pendiente")
        self.assertEqual(self._esperando(), [], "La ocurrencia queda consumida")
        cola = self._cola()
        self.assertEqual(len(cola), 1)
        self.assertIsNotNone(cola[0].consumed_at)

    def test_dos_consultas_simultaneas_no_duplican_la_bandera_heredada(self):
        # La bandera ya no se acepta en la actualización, pero una base anterior
        # puede conservarla puesta: su consumo también es atómico.
        sesion = SessionLocal()
        try:
            dispensador = sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first()
            dispensador.pending_dispensing = True
            sesion.commit()
        finally:
            sesion.close()

        resultados = []
        errores = []
        barrera = threading.Barrier(2)
        consulta_original = order_service._dispensador_por_mac

        def consultar_con_barrera(db, mac):
            encontrado = consulta_original(db, mac)
            barrera.wait(timeout=10)
            return encontrado

        def entregar():
            sesion = SessionLocal()
            try:
                resultados.append(
                    order_service.entregar_orden(
                        sesion, MAC, ahora=_en_utc(AHORA)
                    )
                )
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                sesion.close()

        with patch.object(
            order_service, "_dispensador_por_mac", side_effect=consultar_con_barrera
        ):
            hilos = [threading.Thread(target=entregar) for _ in range(2)]
            for hilo in hilos:
                hilo.start()
            for hilo in hilos:
                hilo.join(timeout=20)

        self.assertEqual(errores, [], f"Las consultas simultáneas fallaron: {errores}")
        self.assertEqual(len(resultados), 2)
        self.assertEqual(
            len([resultado for resultado in resultados if resultado["serve"]]),
            1,
            "Una sola consulta consume la bandera heredada",
        )
        self.assertEqual(len(self._ordenes()), 1)
        self.assertEqual(self._esperando(), [])

        sesion = SessionLocal()
        try:
            bandera = sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first().pending_dispensing
        finally:
            sesion.close()
        self.assertFalse(bandera)


class TestEntregaDeLaComidaEnEspera(BaseColaTests):
    """RF-25: entrega al cerrar, al vencer y al reactivarse."""

    def test_sin_comida_en_espera_responde_reposo(self):
        self.assertEqual(self._entregar(AHORA), {"serve": False, "amount": 0})
        self.assertEqual(self._ordenes(), [])

    def test_con_orden_pendiente_en_plazo_no_entrega_y_conserva_la_cola(self):
        orden_id = self._crear_orden(datetime(2026, 10, 1, 8, 0, 0))
        self._encolar(AHORA)

        respuesta = self._entregar(AHORA)

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertEqual(len(self._ordenes()), 1, "No se crea una segunda orden")
        self.assertEqual(self._ordenes()[0].id, orden_id)
        esperando = self._esperando()
        self.assertEqual(len(esperando), 1, "La cola no se consume (RF-25)")
        self.assertIsNone(esperando[0].consumed_at)

    def test_al_cerrar_la_orden_se_entrega_la_comida_en_espera(self):
        orden_id = self._crear_orden(datetime(2026, 10, 1, 8, 0, 0))
        self._encolar(AHORA)
        self._entregar(AHORA)

        cierre = self._reportar(orden_id, datetime(2026, 10, 1, 8, 1, 0), medidos=55.0)
        self.assertEqual(cierre["outcome"], "success")
        stock_tras_cierre = self._stock()
        self.assertAlmostEqual(stock_tras_cierre, STOCK_INICIAL - 55.0)

        respuesta = self._entregar(datetime(2026, 10, 1, 8, 1, 5))

        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], GRAMOS_ESPERA)
        self.assertNotEqual(respuesta["order_id"], orden_id)

        ordenes = self._ordenes()
        self.assertEqual(len(ordenes), 2)
        nueva = [orden for orden in ordenes if orden.id == respuesta["order_id"]][0]
        self.assertEqual(nueva.status, "pending")
        self.assertEqual(nueva.requested_grams, GRAMOS_ESPERA)
        self.assertEqual(nueva.delivered_at, _en_utc(datetime(2026, 10, 1, 8, 1, 5)))
        self.assertIsNone(nueva.closed_at)

        esperando = self._esperando()
        self.assertEqual(esperando, [], "La ocurrencia se consume al entregarse")
        self.assertEqual(len(self._cola()), 1, "La fila se conserva como consumida")
        self.assertEqual(
            self._cola()[0].consumed_at, _en_utc(datetime(2026, 10, 1, 8, 1, 5))
        )
        self.assertAlmostEqual(
            self._stock(),
            stock_tras_cierre,
            "RF-13: entregar la espera no descuenta stock",
        )

    def test_al_vencer_la_consulta_cierra_la_orden_y_la_cola_sigue_esperando(self):
        limite = datetime(2026, 10, 1, 8, 0, 0) + PLAZO_ORDEN + TOLERANCIA
        orden_id = self._crear_orden(datetime(2026, 10, 1, 8, 0, 0))
        self._encolar(AHORA)

        respuesta = self._entregar(limite + timedelta(milliseconds=1))

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        orden = [o for o in self._ordenes() if o.id == orden_id][0]
        self.assertEqual(orden.status, "closed")
        self.assertEqual(orden.cause, "sin_reporte")
        self.assertEqual(len(self._esperando()), 1, "La cola sigue esperando")
        self.assertAlmostEqual(self._stock(), STOCK_INICIAL)

        # Al vencer la orden anterior, la siguiente consulta entrega la espera.
        entrega = self._entregar(limite + timedelta(seconds=2))

        self.assertTrue(entrega["serve"])
        self.assertEqual(entrega["amount"], GRAMOS_ESPERA)
        self.assertEqual(self._esperando(), [])

    def test_un_dispensador_desactivado_no_consume_la_cola(self):
        self._activar(False)
        self._encolar(AHORA)

        respuesta = self._entregar(AHORA)

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertEqual(self._ordenes(), [])
        self.assertEqual(len(self._esperando()), 1, "La comida espera la reactivación")

    def test_un_dispensador_desactivado_no_dispensa_al_vencer_su_orden_pendiente(self):
        """RF-25: el vencimiento libera el bloqueo, no habilita la dispensación."""
        limite = datetime(2026, 10, 1, 8, 0, 0) + PLAZO_ORDEN + TOLERANCIA
        orden_id = self._crear_orden(datetime(2026, 10, 1, 8, 0, 0))
        self._encolar(AHORA)
        self._activar(False)

        # La orden ya está fuera del plazo y el dispensador, desactivado.
        respuesta = self._entregar(limite + timedelta(seconds=2))

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        orden = [o for o in self._ordenes() if o.id == orden_id][0]
        self.assertEqual(orden.status, "closed")
        self.assertEqual(orden.cause, "sin_reporte")
        self.assertEqual(len(self._ordenes()), 1, "No se crea una orden nueva")
        esperando = self._esperando()
        self.assertEqual(len(esperando), 1, "La ocurrencia sigue sin consumir")
        self.assertIsNone(esperando[0].consumed_at)
        self.assertAlmostEqual(self._stock(), STOCK_INICIAL)

        # Cerrada la orden, el dispensador sigue desactivado: la consulta
        # siguiente no dispensa ni consume la espera; solo la reactivación lo hará.
        siguiente = self._entregar(limite + timedelta(seconds=3))

        self.assertEqual(siguiente, {"serve": False, "amount": 0})
        self.assertEqual(len(self._ordenes()), 1, "Sigue sin crearse una orden nueva")
        self.assertEqual(len(self._esperando()), 1, "La ocurrencia se conserva")

    def test_al_reactivarse_se_entrega_la_comida_en_espera(self):
        self._activar(False)
        self._encolar(AHORA)
        self._entregar(AHORA)

        self._activar(True)
        respuesta = self._entregar(AHORA + timedelta(minutes=2))

        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], GRAMOS_ESPERA)
        self.assertEqual(self._esperando(), [])
        self.assertEqual(len(self._ordenes()), 1)

    def test_la_reactivacion_no_dispensa_si_hay_otra_orden_pendiente(self):
        self._activar(False)
        self._encolar(AHORA)
        self._crear_orden(datetime(2026, 10, 1, 8, 0, 5))
        self._activar(True)

        respuesta = self._entregar(AHORA + timedelta(seconds=10))

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertEqual(len(self._esperando()), 1, "La cola espera a que cierre la orden")

    def test_la_espera_se_entrega_en_orden_de_llegada(self):
        primer_horario = self._guardar(
            models.Schedule(time="07:58", amount=30.0, pet_id=self.mascota.id)
        )
        self._encolar(AHORA)
        self.assertEqual(
            [item.schedule_id for item in self._esperando()],
            [primer_horario.id, self.horario.id],
        )

        primera = self._entregar(AHORA)
        self.assertEqual(primera["amount"], 30.0)

        self._reportar(primera["order_id"], datetime(2026, 10, 1, 8, 1, 0), medidos=30.0)
        segunda = self._entregar(datetime(2026, 10, 1, 8, 1, 5))

        self.assertTrue(segunda["serve"])
        self.assertEqual(segunda["amount"], GRAMOS_ESPERA)
        self.assertEqual(self._esperando(), [])

    def test_la_ocurrencia_no_se_reencola_tras_entregarse(self):
        self._encolar(AHORA)
        entrega = self._entregar(AHORA)
        self.assertTrue(entrega["serve"])

        self.assertEqual(
            self._encolar(AHORA + timedelta(seconds=10)),
            [],
            "La ocurrencia ya consumida no vuelve a encolarse",
        )
        self.assertEqual(len(self._cola()), 1)


if __name__ == "__main__":
    unittest.main()
