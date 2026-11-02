"""Vencimiento de la solicitud rápida: plazo, catálogo y descarte (spec 021).

T1 cubre las reglas puras de RF-1 y RF-9: el plazo de 15 minutos desde la
recepción en el servidor, con el límite inclusivo y sin la tolerancia de un
segundo que usan las órdenes de la spec 014, y la causa `solicitud_vencida` del
catálogo cerrado sin ampliar el catálogo de errores.

T2 cubre el descarte transaccional de RF-2, RF-9, RF-10 y RNF-5: la solicitud
vencida se marca consumida y deja exactamente un registro, sin crear orden, sin
tocar la cola y sin descontar stock.

T3 cubre el disparador periódico de RF-3, RNF-6 y RF-11: el ciclo de 30 s ya
existente descarta las vencidas entre el cierre de las órdenes y el encolado de
las comidas programadas, sin añadir tareas ni intervalos.

T4 cubre la consulta del dispositivo y la entrega de RF-3, RF-4, RF-5 y RF-11: el
barrido perezoso se limita al dispensador consultado, el diagnóstico no entrega
una vencida ni escribe, y la entrega nunca reclama una solicitud vencida.

T5 cubre la aceptación de una solicitud nueva y el reintento idempotente de RF-6
y RF-7: la aceptación descarta antes las vencidas de su dispensador, la reserva
caducada deja de bloquear el stock sin cambiar la cifra mostrada, y un
`operation_id` ya registrado responde antes que cualquier barrido, también para
una solicitud vencida.

T7 cierra la regresión: los dos casos límite que quedaban sin prueba —stock 0
con una vencida y el equipo reasignado que vence antes de la consulta— y la cota
de 60 s de RNF-6 sobre el ciclo de barrido que ya existe.

El reloj se inyecta como parámetro: no se lee el reloj real.
"""

import os
import sys
import threading
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from app.api.deps import get_current_user
from app.db.database import SessionLocal
from app.domain import catalogos, tiempo
from app.domain.catalogos import ErrorDominio
from app.main import app
from app.models import models
from app.services import activity_service, order_service
from app.services.background_tasks import background_schedules

from test_quick_dispense import (
    AHORA,
    MAC,
    STOCK_INICIAL,
    BaseDispensacionRapidaTests,
    _en_utc,
)

# Recepción una vez superado el plazo de 15 minutos respecto a `AHORA`. Con el
# reloj inyectado, la solicitud está vencida y solo espera su descarte.
RECIBIDA_VENCIDA = AHORA - tiempo.PLAZO_SOLICITUD_RAPIDA - timedelta(seconds=1)


class TestPlazoDeEntrega(unittest.TestCase):
    """RF-1, RNF-8: 15 minutos desde la recepción, límite inclusivo."""

    RECIBIDA_EN = datetime(2026, 10, 1, 12, 0, 0)

    def test_a_los_quince_minutos_exactos_sigue_vigente(self):
        # En el instante exacto del límite la solicitud sigue vigente (RF-1).
        ahora = self.RECIBIDA_EN + timedelta(minutes=15)
        self.assertFalse(tiempo.entrega_vencida(self.RECIBIDA_EN, ahora))

        # Un instante antes tampoco está vencida.
        self.assertFalse(
            tiempo.entrega_vencida(
                self.RECIBIDA_EN, ahora - timedelta(milliseconds=1)
            )
        )

    def test_un_segundo_despues_del_limite_esta_vencida(self):
        ahora = self.RECIBIDA_EN + timedelta(minutes=15, seconds=1)
        self.assertTrue(tiempo.entrega_vencida(self.RECIBIDA_EN, ahora))
        # Un milisegundo después del límite ya supera el plazo.
        self.assertTrue(
            tiempo.entrega_vencida(
                self.RECIBIDA_EN, self.RECIBIDA_EN + timedelta(minutes=15, milliseconds=1)
            )
        )

    def test_el_limite_es_la_recepcion_mas_quince_minutos(self):
        self.assertEqual(tiempo.PLAZO_SOLICITUD_RAPIDA, timedelta(minutes=15))
        self.assertEqual(
            tiempo.limite_de_entrega(self.RECIBIDA_EN),
            datetime(2026, 10, 1, 12, 15, 0),
        )
        # El límite no incluye la tolerancia de las órdenes (014 RF-20).
        self.assertEqual(
            tiempo.limite_de_entrega(self.RECIBIDA_EN),
            self.RECIBIDA_EN + tiempo.PLAZO_SOLICITUD_RAPIDA,
        )

    def test_no_aplica_la_tolerancia_de_un_segundo_de_las_ordenes(self):
        # Con la tolerancia de un segundo, `recibida + 15 min + 1 s` seguiría
        # vigente; el plazo de la solicitud rápida la excluye (RF-1).
        con_tolerancia = (
            self.RECIBIDA_EN + tiempo.PLAZO_SOLICITUD_RAPIDA + tiempo.TOLERANCIA
        )
        self.assertTrue(tiempo.entrega_vencida(self.RECIBIDA_EN, con_tolerancia))
        self.assertLess(
            tiempo.limite_de_entrega(self.RECIBIDA_EN),
            self.RECIBIDA_EN + tiempo.PLAZO_SOLICITUD_RAPIDA + tiempo.TOLERANCIA,
        )
        # La tolerancia sigue vigente solo para el plazo de las órdenes.
        self.assertFalse(
            tiempo.plazo_vencido(
                self.RECIBIDA_EN, self.RECIBIDA_EN + tiempo.PLAZO_ORDEN + tiempo.TOLERANCIA
            )
        )

    def test_compara_instantes_con_y_sin_zona_horaria(self):
        # La recepción guardada en UTC naive y `ahora` con zona son el mismo
        # instante cuando coinciden en UTC (RNF-8).
        ahora_con_zona = datetime(2026, 10, 1, 12, 15, 0, tzinfo=timezone.utc)
        self.assertFalse(
            tiempo.entrega_vencida(self.RECIBIDA_EN, ahora_con_zona)
        )
        self.assertTrue(
            tiempo.entrega_vencida(
                self.RECIBIDA_EN, ahora_con_zona + timedelta(seconds=1)
            )
        )

        # Una recepción con desplazamiento se normaliza a UTC antes de sumar
        # el plazo: 07:00 en UTC-05 son las 12:00 UTC.
        recibida_con_zona = datetime(
            2026, 10, 1, 7, 0, 0, tzinfo=timezone(timedelta(hours=-5))
        )
        self.assertEqual(
            tiempo.limite_de_entrega(recibida_con_zona),
            datetime(2026, 10, 1, 12, 15, 0),
        )
        self.assertFalse(
            tiempo.entrega_vencida(recibida_con_zona, ahora_con_zona)
        )
        self.assertTrue(
            tiempo.entrega_vencida(
                recibida_con_zona, datetime(2026, 10, 1, 12, 15, 1)
            )
        )


class TestCatalogoDeCausas(unittest.TestCase):
    """RF-9, RNF-7: causa nueva del servidor sin tocar el catálogo de errores."""

    CODIGO = "solicitud_vencida"

    def test_solicitud_vencida_tiene_etiqueta_fallo_y_origen_servidor(self):
        causa = catalogos.CAUSAS[self.CODIGO]
        self.assertEqual(causa.etiqueta, "Solicitud vencida")
        self.assertEqual(causa.resultado, catalogos.FALLO)
        self.assertEqual(causa.resultado, "failure")
        self.assertEqual(causa.origen, catalogos.ORIGEN_SERVIDOR)
        self.assertEqual(causa.origen, "servidor")
        self.assertTrue(catalogos.es_causa_valida(self.CODIGO))
        self.assertEqual(
            catalogos.etiqueta_causa(self.CODIGO), "Solicitud vencida"
        )

    def test_solicitud_vencida_no_es_motivo_de_reporte(self):
        self.assertNotIn(self.CODIGO, catalogos.MOTIVOS_REPORTE)
        self.assertFalse(catalogos.es_causa_de_reporte(self.CODIGO))
        with self.assertRaises(ErrorDominio) as contexto:
            catalogos.resultado_para_motivo(self.CODIGO)
        self.assertEqual(contexto.exception.code, "motivo_invalido")

    def test_el_catalogo_de_errores_no_cambia(self):
        # La 021 amplía el catálogo de causas, no el de errores: la causa no es
        # un código de rechazo de negocio (spec, «El catálogo de errores no
        # cambia»).
        self.assertNotIn(self.CODIGO, catalogos.MENSAJES_ERROR)
        with self.assertRaises(ValueError):
            ErrorDominio(self.CODIGO)
        # Los 16 códigos de error vigentes desde la 020 siguen siendo los mismos.
        self.assertEqual(len(catalogos.MENSAJES_ERROR), 16)


class BaseDescarteTests(BaseDispensacionRapidaTests):
    """Escenario de la 020 con solicitudes de recepción inyectada.

    Reutiliza el usuario, la mascota, el dispensador y el horario de la suite de
    la dispensación rápida; solo añade utilidades para crear solicitudes vencidas
    y ejecutar el descarte con una sesión nueva, como el barrido real.
    """

    def _crear_solicitud(
        self,
        recibida_en,
        cantidad=50.0,
        pet_id=None,
        operation_id=None,
        consumed_at=None,
    ):
        return self._guardar(
            models.ManualDispensingRequest(
                dispenser_id=self.dispensador.id,
                pet_id=self.mascota.id if pet_id is None else pet_id,
                amount=cantidad,
                operation_id=operation_id,
                requested_at=_en_utc(recibida_en),
                consumed_at=consumed_at,
            )
        )

    def _descartar(self, ahora=AHORA, dispenser_id=None):
        sesion = SessionLocal()
        try:
            return order_service.descartar_solicitudes_vencidas(
                sesion,
                ahora=_en_utc(ahora),
                dispenser_id=dispenser_id,
            )
        finally:
            sesion.close()

    def _solicitud(self):
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

    def _stock_reservado(self):
        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            return order_service._stock_reservado(sesion, dispensador)
        finally:
            sesion.close()

    def _registro_del_descarte(self):
        return [
            registro
            for registro in self._registros()
            if registro.cause == order_service.CAUSA_SOLICITUD_VENCIDA
        ]

    def _contexto(self, registro):
        return activity_service.contexto_desde_texto(registro.context)

    def _actualizar_dispensador(self, **valores):
        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            for campo, valor in valores.items():
                setattr(dispensador, campo, valor)
            sesion.commit()
        finally:
            sesion.close()

    def _reasignar(self, mascota):
        self._actualizar_dispensador(pet_id=mascota.id)

    def _eliminar_mascota(self, pet_id):
        """Borra la mascota y sus horarios, conservando las referencias del log."""
        sesion = SessionLocal()
        try:
            sesion.query(models.Schedule).filter(
                models.Schedule.pet_id == pet_id
            ).delete()
            mascota = sesion.query(models.Pet).filter(models.Pet.id == pet_id).first()
            if mascota is not None:
                sesion.delete(mascota)
            sesion.commit()
        finally:
            sesion.close()


class TestDescarte(BaseDescarteTests):
    """RF-2, RNF-8: descarte de la vencida sin orden, cola ni stock."""

    def test_descarta_la_solicitud_vencida_y_la_marca_consumida(self):
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=50.0)

        descartadas = self._descartar()

        self.assertEqual(descartadas, [solicitud.id])
        actual = self._solicitud()
        self.assertIsNotNone(actual.consumed_at)
        self.assertEqual(actual.consumed_at, _en_utc(AHORA))
        self.assertEqual(len(self._registro_del_descarte()), 1)

    def test_no_descarta_una_solicitud_en_el_limite_exacto(self):
        # En el instante exacto del límite la solicitud sigue vigente (RF-1).
        self._crear_solicitud(AHORA - tiempo.PLAZO_SOLICITUD_RAPIDA)

        self.assertEqual(self._descartar(), [])
        self.assertIsNone(self._solicitud().consumed_at)
        self.assertEqual(self._registro_del_descarte(), [])

    def test_el_descarte_no_crea_orden_ni_toca_la_cola_ni_el_stock(self):
        self._encolar()
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA)
        cola_antes = [
            (item.id, item.consumed_at, item.amount) for item in self._cola()
        ]
        ordenes_antes = self._ordenes()
        stock_antes = self._stock()

        self.assertEqual(self._descartar(), [solicitud.id])

        self.assertEqual(
            [(item.id, item.consumed_at, item.amount) for item in self._cola()],
            cola_antes,
            "El descarte no toca la cola de comidas programadas",
        )
        self.assertEqual(self._ordenes(), ordenes_antes)
        self.assertEqual(self._stock(), stock_antes)
        self.assertEqual(len(self._registro_del_descarte()), 1)

    def test_varias_vencidas_escriben_un_registro_cada_una(self):
        primera = self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=30.0)
        segunda = self._crear_solicitud(
            RECIBIDA_VENCIDA - timedelta(minutes=1), cantidad=40.0
        )

        descartadas = self._descartar()

        self.assertEqual(set(descartadas), {primera.id, segunda.id})
        self.assertEqual(
            sorted(r.requested_grams for r in self._registro_del_descarte()),
            [30.0, 40.0],
        )
        for solicitud in self._solicitudes():
            self.assertIsNotNone(solicitud.consumed_at)

    def test_una_vencida_con_orden_en_curso_se_descarta_sin_tocar_la_orden(self):
        order_id = self._crear_orden(AHORA - timedelta(minutes=1))
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA)

        self.assertEqual(self._descartar(), [solicitud.id])

        ordenes = self._ordenes()
        self.assertEqual(len(ordenes), 1)
        self.assertEqual(ordenes[0].id, order_id)
        self.assertEqual(ordenes[0].status, order_service.ESTADO_PENDIENTE)
        self.assertIsNone(ordenes[0].closed_at)
        self.assertEqual(len(self._registro_del_descarte()), 1)

    def test_una_vencida_con_el_dispensador_desactivado_se_descarta(self):
        self._actualizar_dispensador(is_active=False)
        self._crear_solicitud(RECIBIDA_VENCIDA)

        self.assertEqual(len(self._descartar()), 1)
        self.assertIsNotNone(self._solicitud().consumed_at)
        self.assertEqual(len(self._registro_del_descarte()), 1)

    def test_stock_cero_con_solicitud_vencida_la_descarta_y_sigue_sin_stock(self):
        # Caso límite de la spec: con el stock a 0 la vencida se descarta igual
        # para liberar su reserva, el stock sigue en 0 y la solicitud nueva se
        # rechaza por stock, no por la reserva caducada (RF-2, RF-6).
        self._fijar_stock(0)
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=50.0)

        self.assertEqual(self._descartar(), [solicitud.id])

        self.assertIsNotNone(
            self._solicitud().consumed_at, "La vencida se marca consumida"
        )
        registros = self._registro_del_descarte()
        self.assertEqual(len(registros), 1, "El descarte deja un único registro")
        self.assertEqual(registros[0].resulting_stock, 0.0)
        self.assertEqual(self._stock(), 0.0, "El descarte no toca el stock")
        self.assertEqual(self._stock_reservado(), 0.0)

        for cantidad in (0.5, 1, 50, 200):
            with self.subTest(cantidad=cantidad):
                with self.assertRaises(ErrorDominio) as contexto:
                    self._solicitar(cantidad)
                self.assertEqual(contexto.exception.code, "stock_insuficiente")
        self.assertEqual(len(self._solicitudes()), 1, "El rechazo no crea solicitud")
        self.assertEqual(self._ordenes(), [])


class TestRegistroDelDescarte(BaseDescarteTests):
    """RF-9, RNF-8: contenido del registro del descarte."""

    RECIBIDA = AHORA - timedelta(minutes=20)
    CANTIDAD = 50.0

    def setUp(self):
        super().setUp()
        self._crear_solicitud(self.RECIBIDA, cantidad=self.CANTIDAD)
        self._descartar()
        registros = self._registro_del_descarte()
        self.assertEqual(len(registros), 1)
        self.registro = registros[0]

    def test_usa_tipo_comida_dispensada_resultado_fallo_y_causa_vencida(self):
        self.assertEqual(self.registro.event_type, "feeding_dispensed")
        self.assertEqual(self.registro.event_type, order_service.EVENTO_DISPENSADO)
        self.assertEqual(self.registro.outcome, catalogos.FALLO)
        self.assertEqual(self.registro.cause, "solicitud_vencida")
        self.assertEqual(self.registro.cause, order_service.CAUSA_SOLICITUD_VENCIDA)
        self.assertEqual(
            self.registro.description, "Solicitud rápida vencida sin entregar"
        )
        self.assertEqual(
            self.registro.description,
            order_service.DESCRIPCION_SOLICITUD_VENCIDA,
        )

    def test_conserva_mascota_mac_parcial_y_gramos_solicitados(self):
        self.assertEqual(self.registro.pet_id, self.mascota.id)
        self.assertEqual(self.registro.pet_name, self.mascota.name)
        self.assertEqual(self.registro.user_id, self.usuario.id)
        self.assertEqual(self.registro.requested_grams, self.CANTIDAD)
        self.assertEqual(self.registro.created_at, _en_utc(AHORA))
        # El registro queda ligado al mismo dispensador que la solicitud, además
        # de la MAC parcial (RF-9).
        self.assertEqual(self.registro.dispenser_id, self.dispensador.id)
        self.assertEqual(
            self.registro.dispenser_id, self._solicitud().dispenser_id
        )

    def test_el_contexto_guarda_gramos_recepcion_y_limite(self):
        recibida_en = _en_utc(self.RECIBIDA)
        self.assertEqual(
            self._contexto(self.registro),
            {
                order_service.CLAVE_GRAMOS_RESERVADOS: self.CANTIDAD,
                order_service.CLAVE_RECIBIDA_EN: tiempo.a_texto_utc(recibida_en),
                order_service.CLAVE_LIMITE_ENTREGA: tiempo.a_texto_utc(
                    tiempo.limite_de_entrega(recibida_en)
                ),
            },
        )

    def test_los_datos_ausentes_quedan_como_no_disponible(self):
        self.assertIsNone(self.registro.order_id)
        self.assertIsNone(self.registro.measured_grams)
        self.assertIsNone(self.registro.discounted_grams)
        self.assertIsNone(self.registro.retry_count)

    def test_el_stock_resultante_es_el_stock_actual(self):
        self._actualizar_dispensador(current_food_grams=900.0)
        segunda = self._crear_solicitud(
            self.RECIBIDA - timedelta(minutes=1), cantidad=80.0
        )

        self.assertEqual(self._descartar(), [segunda.id])

        registro = [
            r for r in self._registro_del_descarte()
            if r.requested_grams == 80.0
        ][0]
        self.assertEqual(registro.resulting_stock, 900.0)
        self.assertEqual(self._stock(), 900.0)

    def test_no_guarda_la_mac_completa(self):
        self.assertEqual(self.registro.dispenser_mac_masked, "**:AB:1F")
        self.assertNotEqual(self.registro.dispenser_mac_masked, MAC)
        self.assertNotIn("AABBCCDDAB1F", self.registro.dispenser_mac_masked)

    def test_la_mascota_eliminada_tras_reasignar_queda_como_no_disponible(self):
        pet_id_original = self.mascota.id
        solicitud = self._crear_solicitud(
            self.RECIBIDA - timedelta(minutes=5),
            cantidad=60.0,
            pet_id=pet_id_original,
        )
        nueva = self._crear_mascota(self.otro_usuario, "Luna")
        self._reasignar(nueva)
        self._eliminar_mascota(pet_id_original)

        self.assertEqual(self._descartar(), [solicitud.id])

        registro = [
            r for r in self._registro_del_descarte()
            if r.requested_grams == 60.0
        ][0]
        self.assertEqual(registro.pet_id, pet_id_original)
        self.assertEqual(registro.pet_name, activity_service.NO_DISPONIBLE)
        self.assertEqual(registro.user_id, self.otro_usuario.id)

    def test_el_dispensador_reasignado_y_vencido_guarda_la_mascota_original(self):
        # Caso límite de la spec: si el vencimiento gana a la consulta, el
        # registro se escribe con la mascota guardada en la solicitud, no con la
        # que el equipo tiene asignada en ese momento (RF-9).
        original = self.mascota
        nueva = self._crear_mascota(self.otro_usuario, "Luna")
        cantidad = 70.0
        solicitud = self._crear_solicitud(
            self.RECIBIDA - timedelta(minutes=1),
            cantidad=cantidad,
            pet_id=original.id,
        )
        self._reasignar(nueva)

        self.assertEqual(self._descartar(), [solicitud.id])

        registro = [
            r for r in self._registro_del_descarte()
            if r.requested_grams == cantidad
        ][0]
        self.assertEqual(registro.pet_id, original.id)
        self.assertEqual(registro.pet_name, original.name)
        self.assertEqual(registro.user_id, self.usuario.id)
        self.assertNotEqual(registro.pet_id, nueva.id)
        self.assertNotEqual(registro.pet_name, nueva.name)
        self.assertNotEqual(registro.user_id, self.otro_usuario.id)
        self.assertEqual(
            registro.dispenser_id,
            self.dispensador.id,
            "El registro queda ligado al dispensador reasignado",
        )


class TestIdempotenciaDelDescarte(BaseDescarteTests):
    """RNF-5: una sola transición, un solo registro y una sola liberación."""

    def test_dos_barridos_seguidos_dejan_un_unico_registro(self):
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA)

        self.assertEqual(self._descartar(), [solicitud.id])
        self.assertEqual(self._descartar(), [])

        self.assertEqual(len(self._registro_del_descarte()), 1)
        self.assertIsNotNone(self._solicitud().consumed_at)

    def test_dos_sesiones_simultaneas_producen_una_sola_transicion(self):
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA)
        resultados = []
        errores = []
        barrera = threading.Barrier(2)
        datos_original = order_service._datos_de_la_mascota

        def datos_con_barrera(db, pet_id):
            datos = datos_original(db, pet_id)
            # Ambas sesiones ya superaron las comprobaciones y compiten por el
            # `UPDATE ... WHERE consumed_at IS NULL`, como dos barridos reales.
            barrera.wait(timeout=10)
            return datos

        def descartar():
            sesion = SessionLocal()
            try:
                resultados.append(
                    order_service.descartar_solicitudes_vencidas(
                        sesion, ahora=_en_utc(AHORA)
                    )
                )
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                sesion.close()

        with patch.object(
            order_service,
            "_datos_de_la_mascota",
            side_effect=datos_con_barrera,
        ):
            hilos = [threading.Thread(target=descartar) for _ in range(2)]
            for hilo in hilos:
                hilo.start()
            for hilo in hilos:
                hilo.join(timeout=20)

        self.assertEqual(errores, [], f"Los descartes simultáneos fallaron: {errores}")
        ganadoras = [r for r in resultados if r == [solicitud.id]]
        self.assertEqual(len(ganadoras), 1, f"Resultados: {resultados}")
        self.assertEqual(len(self._registro_del_descarte()), 1)
        self.assertIsNotNone(self._solicitud().consumed_at)


class TestFalloDeEscritura(BaseDescarteTests):
    """RF-10: sin marca ni registro parciales, sin frenar al resto."""

    def test_un_fallo_al_registrar_no_deja_marca_ni_registro(self):
        self._crear_solicitud(RECIBIDA_VENCIDA)

        with patch.object(
            order_service.activity_service,
            "registrar",
            side_effect=RuntimeError("fallo de escritura simulado"),
        ):
            self.assertEqual(self._descartar(), [])

        self.assertIsNone(self._solicitud().consumed_at)
        self.assertEqual(self._registro_del_descarte(), [])

    def test_la_solicitud_fallida_conserva_su_reserva(self):
        self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=50.0)
        reserva_antes = self._stock_reservado()

        with patch.object(
            order_service.activity_service,
            "registrar",
            side_effect=RuntimeError("fallo de escritura simulado"),
        ):
            self.assertEqual(self._descartar(), [])

        self.assertEqual(self._stock_reservado(), reserva_antes)
        self.assertEqual(self._stock_reservado(), STOCK_INICIAL - 50.0)

    def test_el_barrido_siguiente_descarta_la_solicitud_fallida(self):
        # RF-10: el fallo de escritura no deja marca ni registro y la solicitud
        # sigue reservando; el barrido siguiente, ya sin el fallo, la resuelve.
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=50.0)

        with patch.object(
            order_service.activity_service,
            "registrar",
            side_effect=RuntimeError("fallo de escritura simulado"),
        ):
            self.assertEqual(self._descartar(), [])

        self.assertIsNone(self._solicitud().consumed_at)
        self.assertEqual(self._registro_del_descarte(), [])
        self.assertEqual(self._stock_reservado(), STOCK_INICIAL - 50.0)

        # Sin el parche y con el mismo reloj, el reintento sí la descarta.
        self.assertEqual(self._descartar(), [solicitud.id])

        actual = self._solicitud()
        self.assertIsNotNone(actual.consumed_at)
        self.assertEqual(actual.consumed_at, _en_utc(AHORA))
        self.assertEqual(len(self._registro_del_descarte()), 1)
        self.assertEqual(self._stock_reservado(), STOCK_INICIAL)

    def test_el_fallo_de_una_no_impide_descartar_el_resto(self):
        fallida = self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=30.0)
        sana = self._crear_solicitud(
            RECIBIDA_VENCIDA - timedelta(minutes=1), cantidad=40.0
        )
        registrar_original = order_service.activity_service.registrar

        def registrar_con_fallo(db, **kwargs):
            if kwargs.get("requested_grams") == 30.0:
                raise RuntimeError("fallo de escritura simulado")
            return registrar_original(db, **kwargs)

        with patch.object(
            order_service.activity_service,
            "registrar",
            side_effect=registrar_con_fallo,
        ):
            descartadas = self._descartar()

        self.assertEqual(descartadas, [sana.id])
        solicitudes = {s.id: s for s in self._solicitudes()}
        self.assertIsNone(solicitudes[fallida.id].consumed_at)
        self.assertIsNotNone(solicitudes[sana.id].consumed_at)
        self.assertEqual(
            [r.requested_grams for r in self._registro_del_descarte()], [40.0]
        )


class TestBarridoPeriodico(BaseDescarteTests):
    """RF-3, RNF-6, RF-11: el ciclo de 30 s descarta entre cierre y encolado."""

    def _barrer(self, ahora=AHORA):
        sesion = SessionLocal()
        try:
            return background_schedules.ejecutar_barrido(
                sesion, ahora=_en_utc(ahora)
            )
        finally:
            sesion.close()

    def test_el_ciclo_descarta_las_vencidas(self):
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA)

        resultado = self._barrer()

        self.assertEqual(resultado["descartadas"], [solicitud.id])
        self.assertIsNotNone(self._solicitud().consumed_at)
        self.assertEqual(len(self._registro_del_descarte()), 1)
        self.assertEqual(self._ordenes(), [], "El descarte no crea órdenes")
        self.assertEqual(self._stock(), STOCK_INICIAL, "El descarte no toca el stock")

    def test_el_ciclo_devuelve_las_descartadas(self):
        primera = self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=30.0)
        segunda = self._crear_solicitud(
            RECIBIDA_VENCIDA - timedelta(minutes=1), cantidad=40.0
        )

        resultado = self._barrer()

        # El retorno conserva las claves del cierre y del encolado (RF-11) y
        # añade el identificador de cada solicitud descartada (RF-3).
        self.assertEqual(set(resultado), {"cerradas", "descartadas", "encoladas"})
        self.assertEqual(resultado["cerradas"], [])
        self.assertEqual(set(resultado["descartadas"]), {primera.id, segunda.id})
        self.assertEqual(len(resultado["encoladas"]), 1)

    def test_el_ciclo_no_descarta_una_solicitud_vigente(self):
        # En el límite exacto la solicitud sigue vigente y el ciclo la respeta.
        self._crear_solicitud(AHORA - tiempo.PLAZO_SOLICITUD_RAPIDA)

        resultado = self._barrer()

        self.assertEqual(resultado["descartadas"], [])
        self.assertIsNone(self._solicitud().consumed_at)
        self.assertEqual(self._registro_del_descarte(), [])

    def test_el_ciclo_conserva_el_cierre_y_el_encolado(self):
        # No regresión de la 014: el cierre y el encolado siguen ocurriendo en
        # el mismo ciclo y el descarte no altera su resultado (RF-11).
        self._encolar()
        order_id = self._crear_orden(AHORA - timedelta(minutes=10))
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA)
        cola_antes = [
            (item.id, item.consumed_at, item.amount) for item in self._cola()
        ]

        resultado = self._barrer()

        self.assertEqual(resultado["cerradas"], [order_id])
        self.assertEqual(resultado["descartadas"], [solicitud.id])
        self.assertEqual(resultado["encoladas"], [], "La ocurrencia ya estaba en la cola")

        ordenes = self._ordenes()
        self.assertEqual(len(ordenes), 1)
        self.assertEqual(ordenes[0].status, "closed")
        self.assertEqual(
            [(item.id, item.consumed_at, item.amount) for item in self._cola()],
            cola_antes,
            "El descarte no toca la cola de comidas programadas",
        )
        self.assertIsNotNone(self._solicitud().consumed_at)
        self.assertEqual(len(self._registro_del_descarte()), 1)
        self.assertEqual(self._stock(), STOCK_INICIAL)

    def test_el_barrido_respeta_la_cota_de_sesenta_segundos(self):
        # RNF-6: el descarte se resuelve en el siguiente ciclo del barrido
        # periódico que ya existe, y ese ciclo nunca tarda más de 60 s desde el
        # vencimiento. No hay temporizador propio del descarte.
        self.assertLessEqual(
            tiempo.INTERVALO_BARRIDO,
            timedelta(seconds=60),
            "RNF-6: el barrido no admite un margen mayor de 60 s",
        )
        self.assertEqual(tiempo.INTERVALO_BARRIDO, timedelta(seconds=30))

        # Instantes con zona UTC para que el margen no dependa de la hora local
        # del servidor (RNF-8).
        recibida_en = datetime(2026, 10, 1, 7, 0, 0, tzinfo=timezone.utc)
        limite = recibida_en + tiempo.PLAZO_SOLICITUD_RAPIDA
        solicitud = self._crear_solicitud(recibida_en, cantidad=50.0)

        # El ciclo que coincide con el límite todavía la considera vigente.
        self.assertEqual(self._barrer(ahora=limite)["descartadas"], [])
        self.assertIsNone(self._solicitud().consumed_at)

        # Un único ciclo después basta para descartarla: la cota no necesita
        # otro temporizador ni un segundo barrido.
        resultado = self._barrer(ahora=limite + tiempo.INTERVALO_BARRIDO)

        self.assertEqual(resultado["descartadas"], [solicitud.id])
        self.assertIsNotNone(self._solicitud().consumed_at)
        retraso = self._solicitud().consumed_at - _en_utc(limite)
        self.assertEqual(
            retraso,
            tiempo.INTERVALO_BARRIDO,
            "RNF-6: el descarte cae en el ciclo inmediatamente posterior",
        )
        self.assertLessEqual(retraso, timedelta(seconds=60))

        # El arranque sigue programando un único job, con el intervalo del
        # barrido: el descarte no añade un temporizador propio (RNF-2, RNF-6).
        from app import main as servidor

        with TestClient(app):
            trabajos = servidor.scheduler.get_jobs()

        self.assertEqual(len(trabajos), 1, "Un único job de barrido (RNF-2)")
        self.assertEqual(trabajos[0].trigger.interval, tiempo.INTERVALO_BARRIDO)


class TestConsultaDelDispositivo(BaseDescarteTests):
    """RF-3, RF-4, RF-5, RF-11: la consulta descarta su vencida y entrega.

    El barrido perezoso de la consulta usa el mismo instante que la entrega, de
    modo que el reloj decide el ganador y no el orden de llegada: en el límite
    exacto gana la entrega y un instante después gana el descarte.
    """

    MAC_AJENA = "0A:1B:2C:3D:4E:5F"

    def _consultar(self, ahora=AHORA, simular=False):
        sesion = SessionLocal()
        try:
            return order_service.entregar_orden(
                sesion, MAC, ahora=_en_utc(ahora), simular=simular
            )
        finally:
            sesion.close()

    def _crear_dispensador_ajeno(self):
        """Dispensador de otra mascota, con su MAC normalizada correcta."""
        mascota = self._crear_mascota(self.otro_usuario, "Luna")
        dispensador = self._guardar(
            models.Dispenser(
                mac_address=self.MAC_AJENA,
                mac_normalized="".join(
                    caracter for caracter in self.MAC_AJENA if caracter not in ":-. "
                ).upper(),
                pet_id=mascota.id,
                is_active=True,
                pending_dispensing=False,
                pending_wifi_reset=False,
                current_food_grams=STOCK_INICIAL,
            )
        )
        return dispensador, mascota

    def _crear_solicitud_ajena(self, dispensador, mascota, recibida_en, cantidad=40.0):
        return self._guardar(
            models.ManualDispensingRequest(
                dispenser_id=dispensador.id,
                pet_id=mascota.id,
                amount=cantidad,
                operation_id=f"op-ajena-{cantidad}",
                requested_at=_en_utc(recibida_en),
            )
        )

    def test_la_consulta_descarta_la_vencida_de_su_dispensador(self):
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA)

        respuesta = self._consultar()

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertIsNotNone(
            self._solicitud().consumed_at, "La vencida queda consumida sin orden"
        )
        self.assertEqual(self._solicitud().id, solicitud.id)
        self.assertEqual(self._ordenes(), [], "La consulta no entrega la vencida")
        self.assertEqual(len(self._registro_del_descarte()), 1)
        self.assertEqual(self._stock(), STOCK_INICIAL)

    def test_la_consulta_entrega_la_vigente_y_descarta_la_vencida(self):
        vencida = self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=30.0)
        vigente = self._crear_solicitud(AHORA - timedelta(minutes=1), cantidad=50.0)

        respuesta = self._consultar()

        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], 50.0)
        ordenes = self._ordenes()
        self.assertEqual(len(ordenes), 1, "Solo se entrega la vigente")
        self.assertEqual(ordenes[0].id, respuesta["order_id"])
        self.assertEqual(ordenes[0].requested_grams, 50.0)

        solicitudes = {s.id: s for s in self._solicitudes()}
        self.assertIsNotNone(solicitudes[vencida.id].consumed_at)
        self.assertIsNotNone(solicitudes[vigente.id].consumed_at)
        # La entrega de la vigente no escribe registro: solo el descarte deja uno.
        self.assertEqual(len(self._registro_del_descarte()), 1)
        self.assertEqual(len(self._registros()), 1)

    def test_la_consulta_no_descarta_las_vencidas_de_otro_dispensador(self):
        dispensador_ajeno, mascota_ajena = self._crear_dispensador_ajeno()
        ajena = self._crear_solicitud_ajena(
            dispensador_ajeno, mascota_ajena, RECIBIDA_VENCIDA, cantidad=40.0
        )

        respuesta = self._consultar()

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        solicitudes = {s.id: s for s in self._solicitudes()}
        self.assertIsNone(
            solicitudes[ajena.id].consumed_at,
            "El barrido perezoso solo alcanza al dispensador consultado",
        )
        self.assertEqual(self._registro_del_descarte(), [])
        self.assertEqual(self._ordenes(), [])

    def test_la_consulta_descarta_la_vencida_aunque_haya_una_orden_en_curso(self):
        # Caso límite de la spec: la vencida se descarta igual y no toca la
        # orden, aunque la orden en curso bloquee la dispensación (RF-3, RF-5).
        order_id = self._crear_orden(AHORA - timedelta(minutes=1))
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA)

        respuesta = self._consultar()

        # El barrido perezoso ocurre antes de evaluar la orden en curso: el
        # descarte se escribe aunque la consulta responda reposo por el bloqueo.
        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertIsNotNone(
            self._solicitud().consumed_at,
            "La vencida se descarta aunque haya una orden en curso",
        )
        self.assertEqual(self._solicitud().id, solicitud.id)

        ordenes = self._ordenes()
        self.assertEqual(len(ordenes), 1, "El descarte no crea órdenes")
        self.assertEqual(ordenes[0].id, order_id)
        self.assertEqual(ordenes[0].status, order_service.ESTADO_PENDIENTE)
        self.assertIsNone(ordenes[0].closed_at, "La orden en curso no se cierra")
        self.assertEqual(
            len(self._registro_del_descarte()), 1, "Solo el descarte escribe"
        )
        self.assertEqual(
            len(self._registros()), 1, "La orden en curso no deja un registro nuevo"
        )

    def test_la_consulta_descarta_la_vencida_con_el_dispensador_desactivado(self):
        # Caso límite de la spec: un equipo desactivado descarta su vencida y la
        # respuesta no dispensa esa solicitud (RF-3, RF-4).
        self._actualizar_dispensador(is_active=False)
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA)

        respuesta = self._consultar()

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertIsNotNone(
            self._solicitud().consumed_at,
            "La vencida se descarta aunque el dispensador esté desactivado",
        )
        self.assertEqual(self._solicitud().id, solicitud.id)
        self.assertEqual(self._ordenes(), [], "El desactivado no dispensa la vencida")
        self.assertEqual(len(self._registro_del_descarte()), 1)

    def test_la_consulta_en_el_limite_exacto_entrega_una_orden(self):
        # RF-1, RF-5: en el instante exacto del límite la solicitud sigue vigente.
        solicitud = self._crear_solicitud(AHORA - tiempo.PLAZO_SOLICITUD_RAPIDA)

        respuesta = self._consultar()

        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], 50.0)
        self.assertEqual(len(self._ordenes()), 1)
        self.assertIsNotNone(self._solicitud().consumed_at)
        self.assertEqual(self._solicitud().id, solicitud.id)
        self.assertEqual(self._registro_del_descarte(), [])

    def test_la_consulta_un_segundo_despues_del_limite_descarta_y_no_entrega(self):
        # RF-5: un instante después del límite gana el descarte aunque la
        # consulta llegue antes que el barrido periódico.
        solicitud = self._crear_solicitud(AHORA)

        respuesta = self._consultar(
            ahora=AHORA + tiempo.PLAZO_SOLICITUD_RAPIDA + timedelta(seconds=1)
        )

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertIsNotNone(self._solicitud().consumed_at)
        self.assertEqual(self._solicitud().id, solicitud.id)
        self.assertEqual(self._ordenes(), [])
        self.assertEqual(len(self._registro_del_descarte()), 1)

    def test_la_consulta_no_entrega_una_vencida_cuando_el_descarte_falla(self):
        # RF-10, RF-4: si el descarte no puede escribir, la consulta excluye la
        # vencida en memoria y responde reposo; el siguiente intento la resuelve.
        solicitud = self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=50.0)

        with patch.object(
            order_service.activity_service,
            "registrar",
            side_effect=RuntimeError("fallo de escritura simulado"),
        ):
            respuesta = self._consultar()

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertIsNone(self._solicitud().consumed_at)
        self.assertEqual(self._solicitud().id, solicitud.id)
        self.assertEqual(self._ordenes(), [])
        self.assertEqual(self._registro_del_descarte(), [])

    def test_la_consulta_de_diagnostico_no_entrega_una_vencida_y_responde_reposo(self):
        self._crear_solicitud(RECIBIDA_VENCIDA)

        respuesta = self._consultar(simular=True)

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        self.assertEqual(self._ordenes(), [])

    def test_la_consulta_de_diagnostico_no_escribe(self):
        vencida = self._crear_solicitud(RECIBIDA_VENCIDA, cantidad=30.0)
        vigente = self._crear_solicitud(AHORA - timedelta(minutes=1), cantidad=50.0)

        respuesta = self._consultar(simular=True)

        self.assertEqual(respuesta, {"serve": False, "amount": 0})
        solicitudes = {s.id: s for s in self._solicitudes()}
        self.assertIsNone(solicitudes[vencida.id].consumed_at, "El diagnóstico no descarta")
        self.assertIsNone(solicitudes[vigente.id].consumed_at, "El diagnóstico no consume")
        self.assertEqual(self._registros(), [], "El diagnóstico no escribe registros")
        self.assertEqual(self._ordenes(), [], "El diagnóstico no crea órdenes")

    def test_la_consulta_conserva_el_contrato_de_respuesta(self):
        self._crear_solicitud(AHORA - timedelta(minutes=1), cantidad=50.0)

        entrega = self._consultar()
        reposo = self._consultar()

        self.assertEqual(set(entrega), {"serve", "amount", "order_id"})
        self.assertEqual(reposo, {"serve": False, "amount": 0})

    def test_la_consulta_mantiene_la_prioridad_manual_sobre_la_cola(self):
        self._encolar()
        self._crear_solicitud(AHORA - timedelta(minutes=1), cantidad=50.0)

        respuesta = self._consultar()

        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], 50.0, "La solicitud manual va primero")
        cola = self._cola()
        self.assertEqual(len(cola), 1)
        self.assertIsNone(
            cola[0].consumed_at, "La comida programada sigue esperando su consulta"
        )


class TestAceptacionConReservaCaducada(BaseDescarteTests):
    """RF-6, RF-7: aceptar descarta antes; el reintento no barre ni escribe.

    La aceptación de una solicitud nueva dispara el barrido perezoso de su
    dispensador antes de evaluar el stock, así que la reserva de una vencida deja
    de bloquear en esa misma transacción. El reintento con el mismo
    `operation_id` responde antes que cualquier otra comprobación y no descarta
    nada.
    """

    def _marcar_recibida(self, solicitud_id, recibida_en):
        """Mueve la recepción de una solicitud para simular el paso del tiempo."""
        sesion = SessionLocal()
        try:
            solicitud = (
                sesion.query(models.ManualDispensingRequest)
                .filter(models.ManualDispensingRequest.id == solicitud_id)
                .first()
            )
            solicitud.requested_at = _en_utc(recibida_en)
            sesion.commit()
        finally:
            sesion.close()

    def _solicitudes_por_id(self):
        return {solicitud.id: solicitud for solicitud in self._solicitudes()}

    def test_la_aceptacion_descarta_antes_de_cerrar_vencidas(self):
        # RF-6: la aceptación barre las vencidas de su dispensador y solo después
        # cierra las órdenes vencidas. Sin esta ancla de orden, invertir ambas
        # llamadas en `solicitar_dispensacion_rapida` deja la suite en verde.
        llamadas = []

        def anotar(nombre):
            def efecto(*args, **kwargs):
                llamadas.append(nombre)
                return []

            return efecto

        with patch.object(
            order_service,
            "descartar_solicitudes_vencidas",
            side_effect=anotar("descartar"),
        ), patch.object(
            order_service,
            "cerrar_vencidas",
            side_effect=anotar("cerrar"),
        ):
            respuesta = self._solicitar(30, operation_id="op-orden")

        self.assertEqual(respuesta["status"], "pending")
        self.assertEqual(respuesta["requested_grams"], 30.0)
        self.assertEqual(
            llamadas,
            ["descartar", "cerrar"],
            "RF-6: el descarte de las vencidas va antes del cierre de las órdenes",
        )

    def test_la_aceptacion_descarta_antes_las_vencidas_del_dispensador(self):
        vencida = self._crear_solicitud(
            RECIBIDA_VENCIDA, cantidad=50.0, operation_id="op-vencida"
        )

        respuesta = self._solicitar(30, operation_id="op-nueva")

        self.assertEqual(respuesta["status"], "pending")
        self.assertEqual(respuesta["requested_grams"], 30.0)
        solicitudes = self._solicitudes_por_id()
        self.assertIsNotNone(
            solicitudes[vencida.id].consumed_at,
            "La aceptación descarta la vencida en la misma transacción",
        )
        nueva = [s for s in self._solicitudes() if s.operation_id == "op-nueva"][0]
        self.assertIsNone(nueva.consumed_at, "La solicitud nueva queda pendiente")
        self.assertEqual(len(self._registro_del_descarte()), 1)
        self.assertEqual(self._ordenes(), [], "La aceptación no crea órdenes")

    def test_la_reserva_caducada_ya_no_rechaza_una_solicitud_nueva(self):
        # Caso límite de la spec: stock 100 con una vencida de 100; la nueva de
        # 100 se acepta porque el descarte liberó la reserva antes del stock.
        self._fijar_stock(100)
        self._crear_solicitud(
            RECIBIDA_VENCIDA, cantidad=100.0, operation_id="op-vencida"
        )

        respuesta = self._solicitar(100, operation_id="op-nueva")

        self.assertEqual(respuesta["status"], "pending")
        self.assertEqual(respuesta["requested_grams"], 100.0)
        self.assertEqual(len(self._solicitudes()), 2)
        self.assertEqual(len(self._registro_del_descarte()), 1)

    def test_el_stock_mostrado_al_dueno_no_cambia(self):
        self._fijar_stock(100)
        self._crear_solicitud(
            RECIBIDA_VENCIDA, cantidad=100.0, operation_id="op-vencida"
        )
        stock_antes = self._stock()

        respuesta = self._solicitar(100, operation_id="op-nueva")

        self.assertEqual(stock_antes, 100.0)
        self.assertEqual(
            respuesta["stock_grams"],
            100.0,
            "La cifra de stock mostrada no se recalcula ni se altera (RF-6)",
        )
        self.assertEqual(self._stock(), stock_antes)

    def test_el_reintento_de_una_solicitud_vencida_devuelve_el_mismo_202_y_status(self):
        app.dependency_overrides[get_current_user] = lambda: self.usuario
        cuerpo = {"amount": 50, "operation_id": "op-reintento"}
        primera = self.client.post(
            f"/dispensers/{self.dispensador.id}/quick-dispense",
            json=cuerpo,
        )
        self.assertEqual(primera.status_code, 202)
        solicitud = self._solicitudes()[0]

        # El tiempo pasa: la solicitud queda vencida y se descarta.
        self._marcar_recibida(solicitud.id, RECIBIDA_VENCIDA)
        self.assertEqual(self._descartar(ahora=AHORA), [solicitud.id])

        repetida = self.client.post(
            f"/dispensers/{self.dispensador.id}/quick-dispense",
            json=cuerpo,
        )

        self.assertEqual(repetida.status_code, 202, "El reintento conserva el 202")
        self.assertEqual(repetida.json(), primera.json())
        self.assertEqual(repetida.json()["status"], "pending")
        self.assertEqual(len(self._solicitudes()), 1, "No se escribe otra solicitud")
        self.assertEqual(len(self._registro_del_descarte()), 1)

    def test_el_reintento_informa_el_stock_del_instante_del_reintento(self):
        self._solicitar(50, operation_id="op-stock")
        solicitud = self._solicitudes()[0]
        self._descartar(
            ahora=AHORA + tiempo.PLAZO_SOLICITUD_RAPIDA + timedelta(seconds=1)
        )
        self._fijar_stock(700)

        respuesta = self._solicitar(200, operation_id="op-stock")

        self.assertEqual(respuesta["status"], "pending")
        self.assertEqual(respuesta["requested_grams"], 50.0)
        self.assertEqual(
            respuesta["stock_grams"],
            700.0,
            "El reintento informa el stock del instante del reintento",
        )
        self.assertEqual(len(self._solicitudes()), 1)
        self.assertEqual(self._solicitudes()[0].id, solicitud.id)

    def test_el_reintento_no_descarta_otras_solicitudes_ni_escribe_segundo_registro(self):
        self._solicitar(50, operation_id="op-reintento")
        vencida = self._solicitudes()[0]
        self._descartar(
            ahora=AHORA + tiempo.PLAZO_SOLICITUD_RAPIDA + timedelta(seconds=1)
        )
        otra = self._crear_solicitud(
            RECIBIDA_VENCIDA, cantidad=30.0, operation_id="op-otra"
        )

        respuesta = self._solicitar(50, operation_id="op-reintento")

        self.assertEqual(respuesta["status"], "pending")
        self.assertEqual(len(self._solicitudes()), 2)
        self.assertEqual(len(self._registro_del_descarte()), 1, "Un único registro")
        solicitudes = self._solicitudes_por_id()
        self.assertIsNotNone(
            solicitudes[vencida.id].consumed_at,
            "El reintento no resucita la solicitud descartada",
        )
        self.assertIsNone(
            solicitudes[otra.id].consumed_at,
            "El reintento no descarta otras solicitudes del dispensador",
        )

    def test_el_reintento_no_crea_orden_ni_cubre_horarios_ni_reserva(self):
        vencida = self._crear_solicitud(
            RECIBIDA_VENCIDA, cantidad=50.0, operation_id="op-vencida"
        )
        reserva_antes = self._stock_reservado()

        respuesta = self._solicitar(50, operation_id="op-vencida")

        self.assertEqual(respuesta["status"], "pending")
        self.assertEqual(respuesta["requested_grams"], 50.0)
        self.assertEqual(self._cola(), [], "El reintento no cubre horarios")
        self.assertEqual(self._ordenes(), [], "El reintento no crea órdenes")
        self.assertEqual(self._registros(), [], "El reintento no escribe registros")
        self.assertEqual(len(self._solicitudes()), 1)
        self.assertEqual(self._solicitudes()[0].id, vencida.id)
        self.assertEqual(
            self._stock_reservado(),
            reserva_antes,
            "El reintento no reserva de nuevo",
        )

    def test_el_reintento_con_otro_identificador_crea_una_solicitud_nueva(self):
        self._fijar_stock(100)
        vencida = self._crear_solicitud(
            RECIBIDA_VENCIDA, cantidad=100.0, operation_id="op-vieja"
        )

        respuesta = self._solicitar(80, operation_id="op-nueva")

        self.assertEqual(respuesta["requested_grams"], 80.0)
        self.assertEqual(len(self._solicitudes()), 2)
        solicitudes = self._solicitudes_por_id()
        self.assertIsNotNone(solicitudes[vencida.id].consumed_at)
        nueva = [s for s in self._solicitudes() if s.operation_id == "op-nueva"][0]
        self.assertIsNone(nueva.consumed_at)
        self.assertEqual(len(self._registro_del_descarte()), 1)


if __name__ == "__main__":
    unittest.main()

