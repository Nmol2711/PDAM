"""Dispensación rápida manual: reglas puras y servicio (spec 020, T1-T2).

Cubre cantidad, stock, estado, orden en curso, propiedad, cobertura de
ocurrencias, atomicidad y contrato HTTP. El reloj se inyecta como `ahora`; las
comprobaciones se hacen con sesiones nuevas.
"""

import os
import sys
import threading
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.api.deps import get_current_user
from app.db.database import SessionLocal
from app.domain import dispensado_rapido
from app.domain.catalogos import ErrorDominio
from app.domain.tiempo import PLAZO_ORDEN
from app.main import app
from app.models import models
from app.services import order_service

MAC = "AA:BB:CC:DD:AB:1F"
MAC_NORMALIZADA = "AABBCCDDAB1F"
HORA_PROGRAMADA = "08:00"
AHORA = datetime(2026, 10, 1, 8, 0, 10)
STOCK_INICIAL = 1200.0
GRAMOS_HORARIO = 40.0

# Distingue «no indicar operation_id» (se genera uno único) de enviar `None`,
# que debe rechazarse como operación ausente (RF-14).
AUTO = object()


def _en_utc(instante_local: datetime) -> datetime:
    """Hora local del servidor al UTC naive que usan los servicios."""
    return instante_local.astimezone(timezone.utc).replace(tzinfo=None)


class TestCantidadRapida(unittest.TestCase):
    """RF-2: cantidad numérica, mayor que 0 y máximo 200 g."""

    def test_acepta_los_limites_y_los_textos_numericos(self):
        for valor, esperado in (
            (1, 1.0),
            (50, 50.0),
            (200, 200.0),
            ("50", 50.0),
            (" 50.5 ", 50.5),
        ):
            with self.subTest(valor=repr(valor)):
                self.assertEqual(
                    dispensado_rapido.normalizar_cantidad_rapida(valor), esperado
                )

    def test_rechaza_cero_negativos_y_mayores_que_el_limite(self):
        for valor in (0, -1, -0.1, 200.1, 5000, "0", "-5", "200.01"):
            with self.subTest(valor=repr(valor)):
                with self.assertRaises(ErrorDominio) as contexto:
                    dispensado_rapido.normalizar_cantidad_rapida(valor)
                self.assertEqual(contexto.exception.code, "cantidad_rapida_invalida")

    def test_rechaza_valores_que_no_son_numeros_reales(self):
        for valor in (
            None,
            "",
            "   ",
            "abc",
            True,
            False,
            float("nan"),
            float("inf"),
            float("-inf"),
            "1e999",
            [],
            {},
        ):
            with self.subTest(valor=repr(valor)):
                with self.assertRaises(ErrorDominio) as contexto:
                    dispensado_rapido.normalizar_cantidad_rapida(valor)
                self.assertEqual(contexto.exception.code, "cantidad_rapida_invalida")


class TestOperationId(unittest.TestCase):
    """RF-14: identificador obligatorio, sin espacios y de hasta 128 caracteres."""

    def test_acepta_un_identificador_valido(self):
        for valor in (
            "op-1",
            "8f14e45fceea167a5a36dedd4bea2543",
            "a" * 128,
        ):
            with self.subTest(valor=repr(valor)):
                self.assertEqual(
                    dispensado_rapido.normalizar_operation_id(valor), valor
                )

    def test_recorta_los_espacios_externos_y_devuelve_el_texto_limpio(self):
        self.assertEqual(dispensado_rapido.normalizar_operation_id(" op-1 "), "op-1")
        self.assertEqual(dispensado_rapido.normalizar_operation_id("\top-1\n"), "op-1")

    def test_rechaza_un_identificador_ausente_o_que_no_es_cadena(self):
        for valor in (None, "", 0, 123, True, [], {}):
            with self.subTest(valor=repr(valor)):
                with self.assertRaises(ErrorDominio) as contexto:
                    dispensado_rapido.normalizar_operation_id(valor)
                self.assertEqual(contexto.exception.code, "operacion_invalida")

    def test_rechaza_un_identificador_de_solo_espacios(self):
        for valor in (" ", "   ", "\t", "\n", " \t\n "):
            with self.subTest(valor=repr(valor)):
                with self.assertRaises(ErrorDominio) as contexto:
                    dispensado_rapido.normalizar_operation_id(valor)
                self.assertEqual(contexto.exception.code, "operacion_invalida")

    def test_rechaza_un_identificador_con_espacios_internos(self):
        for valor in ("op 1", "op\t1", "op\n1", "a\u00a0b"):
            with self.subTest(valor=repr(valor)):
                with self.assertRaises(ErrorDominio) as contexto:
                    dispensado_rapido.normalizar_operation_id(valor)
                self.assertEqual(contexto.exception.code, "operacion_invalida")

    def test_rechaza_un_identificador_mas_largo_que_128(self):
        for valor in ("a" * 129, "a" * 500):
            with self.subTest(longitud=len(valor)):
                with self.assertRaises(ErrorDominio) as contexto:
                    dispensado_rapido.normalizar_operation_id(valor)
                self.assertEqual(contexto.exception.code, "operacion_invalida")


class TestStockReservado(unittest.TestCase):
    """RF-3, RNF-9: stock actual menos las solicitudes pendientes, acotado a 0."""

    def test_sin_pendientes_devuelve_el_stock_actual(self):
        self.assertEqual(dispensado_rapido.stock_reservado(1200.0, []), 1200.0)
        self.assertEqual(dispensado_rapido.stock_reservado(1200, ()), 1200.0)

    def test_resta_la_suma_de_las_cantidades_pendientes(self):
        self.assertEqual(
            dispensado_rapido.stock_reservado(1200.0, [50.0, 30.5]), 1119.5
        )
        self.assertEqual(dispensado_rapido.stock_reservado(100.0, (25, 25)), 50.0)
        self.assertEqual(dispensado_rapido.stock_reservado(50.0, [50.0]), 0.0)

    def test_nunca_devuelve_un_stock_negativo(self):
        self.assertEqual(dispensado_rapido.stock_reservado(10.0, [50.0]), 0.0)
        self.assertEqual(dispensado_rapido.stock_reservado(0.0, [0.5]), 0.0)
        self.assertEqual(dispensado_rapido.stock_reservado(0.0, []), 0.0)

    def test_acepta_cualquier_iterable_de_pendientes(self):
        pendientes = (cantidad for cantidad in (10.0, 20.0))
        self.assertEqual(dispensado_rapido.stock_reservado(100.0, pendientes), 70.0)


class TestCodigoRechazo(unittest.TestCase):
    """RF-3 a RF-5: precedencia stock reservado, desactivado y orden en curso."""

    def test_solicitud_valida_no_tiene_codigo(self):
        self.assertIsNone(
            dispensado_rapido.codigo_rechazo(
                cantidad=50.0,
                stock_reservado=1200.0,
                activo=True,
                orden_en_curso=False,
            )
        )

    def test_la_cantidad_igual_al_stock_reservado_se_acepta(self):
        self.assertIsNone(
            dispensado_rapido.codigo_rechazo(
                cantidad=50.0,
                stock_reservado=50.0,
                activo=True,
                orden_en_curso=False,
            )
        )

    def test_el_stock_reservado_tiene_prioridad_sobre_el_estado_y_la_orden(self):
        self.assertEqual(
            dispensado_rapido.codigo_rechazo(
                cantidad=51.0,
                stock_reservado=50.0,
                activo=False,
                orden_en_curso=True,
            ),
            "stock_insuficiente",
        )

    def test_el_dispensador_desactivado_tiene_prioridad_sobre_la_orden(self):
        self.assertEqual(
            dispensado_rapido.codigo_rechazo(
                cantidad=50.0,
                stock_reservado=1200.0,
                activo=False,
                orden_en_curso=True,
            ),
            "dispensador_desactivado",
        )

    def test_la_orden_en_curso_es_el_ultimo_rechazo(self):
        self.assertEqual(
            dispensado_rapido.codigo_rechazo(
                cantidad=50.0,
                stock_reservado=1200.0,
                activo=True,
                orden_en_curso=True,
            ),
            "dispensacion_en_curso",
        )

    def test_el_stock_reservado_cero_rechaza_cualquier_cantidad(self):
        self.assertEqual(
            dispensado_rapido.codigo_rechazo(
                cantidad=1.0,
                stock_reservado=0.0,
                activo=True,
                orden_en_curso=False,
            ),
            "stock_insuficiente",
        )


class TestVentanaDeCoincidencia(unittest.TestCase):
    """RF-7: la ventana es `(ahora − 10 min, ahora]`."""

    AHORA = datetime(2026, 10, 1, 8, 0, 10)

    def test_incluye_la_ocurrencia_del_instante_exacto(self):
        self.assertTrue(
            dispensado_rapido.en_ventana_coincidencia(self.AHORA, self.AHORA)
        )

    def test_excluye_el_limite_exacto_de_diez_minutos(self):
        limite = self.AHORA - timedelta(minutes=10)
        self.assertFalse(
            dispensado_rapido.en_ventana_coincidencia(limite, self.AHORA)
        )

    def test_incluye_un_segundo_despues_del_limite(self):
        dentro = self.AHORA - timedelta(minutes=10) + timedelta(seconds=1)
        self.assertTrue(
            dispensado_rapido.en_ventana_coincidencia(dentro, self.AHORA)
        )

    def test_excluye_el_futuro(self):
        futuro = self.AHORA + timedelta(seconds=1)
        self.assertFalse(
            dispensado_rapido.en_ventana_coincidencia(futuro, self.AHORA)
        )

    def test_devuelve_la_ocurrencia_del_horario_en_la_ventana(self):
        ocurrencias = dispensado_rapido.ocurrencias_en_ventana(
            "08:00", self.AHORA
        )
        self.assertEqual(ocurrencias, [datetime(2026, 10, 1, 8, 0)])

    def test_cubre_la_ventana_que_cruza_medianoche(self):
        ahora = datetime(2026, 10, 1, 0, 3, 0)
        ocurrencias = dispensado_rapido.ocurrencias_en_ventana("23:55", ahora)
        self.assertEqual(ocurrencias, [datetime(2026, 9, 30, 23, 55)])

    def test_un_horario_invalido_no_produce_ocurrencias(self):
        for valor in (None, "", "abc", "25:00", "08", []):
            with self.subTest(valor=repr(valor)):
                self.assertEqual(
                    dispensado_rapido.ocurrencias_en_ventana(valor, self.AHORA),
                    [],
                )


class BaseDispensacionRapidaTests(unittest.TestCase):
    """Un usuario, su mascota, un dispensador activo y un horario."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario()
        self.otro_usuario = self._crear_usuario("otro@rapida.test")
        self.mascota = self._crear_mascota(self.usuario)
        self.dispensador = self._crear_dispensador(self.mascota, MAC)
        self.horario = self._guardar(
            models.Schedule(
                time=HORA_PROGRAMADA,
                amount=GRAMOS_HORARIO,
                pet_id=self.mascota.id,
            )
        )

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
                models.ManualDispensingRequest,
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

    def _crear_usuario(self, email="dueno@rapida.test"):
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
                pending_dispensing=False,
                pending_wifi_reset=False,
                current_food_grams=stock,
            )
        )

    def _crear_orden(self, entregada_en, solicitados=50.0, mac=MAC):
        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.mac_address == mac)
                .first()
            )
            orden = models.DispensingOrder(
                user_id=self.usuario.id,
                pet_id=dispensador.pet_id,
                pet_name=self.mascota.name,
                dispenser_id=dispensador.id,
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

    def _fijar_stock(self, gramos):
        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            dispensador.current_food_grams = gramos
            sesion.commit()
        finally:
            sesion.close()

    # --- Acciones -----------------------------------------------------------

    def _solicitar(self, cantidad=50.0, ahora=AHORA, usuario=None, operation_id=AUTO):
        """Solicita la dispensación con un `operation_id` único por defecto."""
        if operation_id is AUTO:
            operation_id = f"op-{uuid4().hex}"
        sesion = SessionLocal()
        try:
            return order_service.solicitar_dispensacion_rapida(
                db=sesion,
                dispenser_id=self.dispensador.id,
                cantidad=cantidad,
                operation_id=operation_id,
                user_id=(usuario or self.usuario).id,
                ahora=_en_utc(ahora),
            )
        finally:
            sesion.close()

    def _encolar(self, ahora=AHORA):
        sesion = SessionLocal()
        try:
            return order_service.encolar_comida(sesion, ahora=_en_utc(ahora))
        finally:
            sesion.close()

    def _entregar(self, ahora=AHORA):
        sesion = SessionLocal()
        try:
            return order_service.entregar_orden(sesion, MAC, ahora=_en_utc(ahora))
        finally:
            sesion.close()

    # --- Consultas ----------------------------------------------------------

    def _solicitudes(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.ManualDispensingRequest).all()
        finally:
            sesion.close()

    def _cola(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.DispensingQueue).all()
        finally:
            sesion.close()

    def _ordenes(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.DispensingOrder).all()
        finally:
            sesion.close()

    def _registros(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.ActivityLog).all()
        finally:
            sesion.close()


class TestSolicitudRapida(BaseDispensacionRapidaTests):
    """RF-1 a RF-7: validación, creación y cobertura."""

    def test_acepta_la_solicitud_y_no_crea_orden_todavia(self):
        respuesta = self._solicitar(50)
        self.assertEqual(respuesta["status"], "pending")
        self.assertEqual(respuesta["requested_grams"], 50.0)
        self.assertEqual(len(self._solicitudes()), 1)
        self.assertEqual(self._ordenes(), [])

    def test_cubre_una_ocurrencia_que_todavia_no_estaba_encolada(self):
        self._solicitar(50)
        cola = self._cola()
        self.assertEqual(len(cola), 1)
        self.assertIsNotNone(cola[0].consumed_at)
        self.assertEqual(cola[0].amount, GRAMOS_HORARIO)

        self._encolar(ahora=AHORA + timedelta(seconds=20))
        self.assertEqual(len(self._cola()), 1)
        self.assertIsNotNone(self._cola()[0].consumed_at)

    def test_cubre_una_ocurrencia_que_ya_estaba_en_la_cola(self):
        self._encolar()
        self.assertIsNone(self._cola()[0].consumed_at)
        self._solicitar(50)
        self.assertIsNotNone(self._cola()[0].consumed_at)

    def test_la_ocurrencia_cubierta_no_se_entrega(self):
        self._solicitar(50)
        respuesta = self._entregar()
        self.assertTrue(respuesta["serve"])
        self.assertEqual(respuesta["amount"], 50.0)
        self.assertEqual(self._entregar()["serve"], False)

    def test_un_horario_fuera_de_la_ventana_no_se_cubre(self):
        self.horario.time = "07:00"
        sesion = SessionLocal()
        try:
            sesion.merge(self.horario)
            sesion.commit()
        finally:
            sesion.close()

        self._solicitar(50)
        self.assertEqual(self._cola(), [])
        self.assertEqual(len(self._solicitudes()), 1)

    def test_el_limite_exacto_de_diez_minutos_queda_fuera(self):
        self._solicitar(50, ahora=datetime(2026, 10, 1, 8, 10, 0))
        self.assertEqual(self._cola(), [])

    def test_cubre_varias_ocurrencias_de_la_ventana(self):
        self._guardar(
            models.Schedule(time="07:55", amount=30.0, pet_id=self.mascota.id)
        )
        self._solicitar(50)
        cola = self._cola()
        self.assertEqual(len(cola), 2)
        self.assertTrue(all(item.consumed_at is not None for item in cola))

    def test_sin_horarios_solo_crea_la_solicitud(self):
        self.horario.time = "12:00"
        sesion = SessionLocal()
        try:
            sesion.merge(self.horario)
            sesion.commit()
        finally:
            sesion.close()

        self._solicitar(50)
        self.assertEqual(self._cola(), [])
        self.assertEqual(len(self._solicitudes()), 1)

    def test_la_cantidad_invalida_no_crea_nada(self):
        for valor in (0, -10, 200.1, "abc", None, float("nan")):
            with self.subTest(valor=repr(valor)):
                with self.assertRaises(ErrorDominio) as contexto:
                    self._solicitar(valor)
                self.assertEqual(contexto.exception.code, "cantidad_rapida_invalida")
                self.assertEqual(self._solicitudes(), [])
                self.assertEqual(self._cola(), [])

    def test_la_cantidad_igual_al_stock_se_acepta(self):
        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            dispensador.current_food_grams = 50
            sesion.commit()
        finally:
            sesion.close()

        self._solicitar(50)
        self.assertEqual(len(self._solicitudes()), 1)

    def test_la_cantidad_mayor_que_el_stock_se_rechaza(self):
        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            dispensador.current_food_grams = 40
            sesion.commit()
        finally:
            sesion.close()

        with self.assertRaises(ErrorDominio) as contexto:
            self._solicitar(50)
        self.assertEqual(contexto.exception.code, "stock_insuficiente")
        self.assertEqual(self._solicitudes(), [])

    def test_stock_cero_rechaza_cualquier_cantidad(self):
        sesion = SessionLocal()
        try:
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            dispensador.current_food_grams = 0
            sesion.commit()
        finally:
            sesion.close()

        for cantidad in (0.5, 1, 50, 200):
            with self.subTest(cantidad=cantidad):
                with self.assertRaises(ErrorDominio) as contexto:
                    self._solicitar(cantidad)
                self.assertEqual(contexto.exception.code, "stock_insuficiente")
        self.assertEqual(self._solicitudes(), [])

    def test_dispensador_desactivado_se_rechaza(self):
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

        with self.assertRaises(ErrorDominio) as contexto:
            self._solicitar(50)
        self.assertEqual(contexto.exception.code, "dispensador_desactivado")

    def test_una_orden_en_curso_rechaza_la_solicitud(self):
        self._crear_orden(AHORA)
        with self.assertRaises(ErrorDominio) as contexto:
            self._solicitar(50)
        self.assertEqual(contexto.exception.code, "dispensacion_en_curso")
        self.assertEqual(self._solicitudes(), [])

    def test_una_orden_vencida_se_cierra_y_la_solicitud_continua(self):
        self._crear_orden(AHORA - PLAZO_ORDEN - timedelta(seconds=2))
        self._solicitar(50)
        self.assertEqual(len(self._solicitudes()), 1)
        orden = self._ordenes()[0]
        self.assertEqual(orden.status, "closed")
        self.assertEqual(orden.cause, "sin_reporte")

    def test_una_mascota_ajena_responde_404_sin_crear_nada(self):
        with self.assertRaises(HTTPException) as contexto:
            self._solicitar(50, usuario=self.otro_usuario)
        self.assertEqual(contexto.exception.status_code, 404)
        self.assertEqual(self._solicitudes(), [])

    def test_un_dispensador_inexistente_responde_404(self):
        sesion = SessionLocal()
        try:
            with self.assertRaises(HTTPException) as contexto:
                order_service.solicitar_dispensacion_rapida(
                    db=sesion,
                    dispenser_id=999999,
                    cantidad=50,
                    operation_id=uuid4().hex,
                    user_id=self.usuario.id,
                    ahora=_en_utc(AHORA),
                )
        finally:
            sesion.close()
        self.assertEqual(contexto.exception.status_code, 404)

    def test_un_fallo_en_la_cobertura_revierte_la_solicitud(self):
        with patch.object(
            order_service,
            "_cubrir_ocurrencias_programadas",
            side_effect=RuntimeError("fallo de prueba"),
        ):
            with self.assertRaises(HTTPException) as contexto:
                self._solicitar(50)
        self.assertEqual(contexto.exception.status_code, 500)
        self.assertEqual(self._solicitudes(), [])
        self.assertEqual(self._cola(), [])

    def test_un_fallo_a_mitad_de_la_cobertura_revierte_la_ocurrencia(self):
        """RNF-5: la ocurrencia vuelve a quedar pendiente tras el rollback."""
        self._encolar()
        self.assertIsNone(self._cola()[0].consumed_at)

        with patch.object(
            order_service,
            "_consumir_ocurrencia",
            side_effect=RuntimeError("fallo de prueba"),
        ):
            with self.assertRaises(HTTPException) as contexto:
                self._solicitar(50)

        self.assertEqual(contexto.exception.status_code, 500)
        self.assertEqual(self._solicitudes(), [])
        cola = self._cola()
        self.assertEqual(len(cola), 1)
        self.assertIsNone(cola[0].consumed_at)

    def test_una_orden_que_aparece_al_escribir_revierte_la_solicitud(self):
        """RF-5, RNF-5: la segunda comprobación corre bajo el bloqueo de escritura."""
        with patch.object(
            order_service, "_hay_orden_en_curso", side_effect=[False, True]
        ):
            with self.assertRaises(ErrorDominio) as contexto:
                self._solicitar(50)

        self.assertEqual(contexto.exception.code, "dispensacion_en_curso")
        self.assertEqual(self._solicitudes(), [])
        self.assertEqual(self._cola(), [])

    def test_la_clave_unica_ganada_por_otra_peticion_devuelve_su_solicitud(self):
        """RF-14: una carrera que pierde el `flush` responde la solicitud ganadora."""
        existente = self._guardar(
            models.ManualDispensingRequest(
                dispenser_id=self.dispensador.id,
                pet_id=self.mascota.id,
                amount=50.0,
                operation_id="op-carrera",
                requested_at=_en_utc(AHORA),
            )
        )

        # La primera búsqueda no ve la fila, como en una carrera real; la segunda
        # (tras el `IntegrityError`) sí la encuentra.
        with patch.object(
            order_service,
            "_solicitud_por_operacion",
            side_effect=[None, existente],
        ):
            respuesta = self._solicitar(200, operation_id="op-carrera")

        self.assertEqual(respuesta["requested_grams"], 50.0)
        self.assertEqual(len(self._solicitudes()), 1)

    def test_la_solicitud_y_la_cobertura_no_escriben_eventos(self):
        """RF-7, RNF-8: la cobertura no deja rastro visible por ocurrencia."""
        self._solicitar(50)
        self.assertEqual(len(self._solicitudes()), 1)
        self.assertEqual(self._cola()[0].consumed_at is not None, True)
        self.assertEqual(self._registros(), [])

    def test_el_endpoint_acepta_la_solicitud_y_su_reintento(self):
        app.dependency_overrides[get_current_user] = lambda: self.usuario
        cuerpo = {"amount": 50, "operation_id": "op-endpoint"}
        respuesta = self.client.post(
            f"/dispensers/{self.dispensador.id}/quick-dispense",
            json=cuerpo,
        )
        self.assertEqual(respuesta.status_code, 202)
        self.assertEqual(respuesta.json()["status"], "pending")
        self.assertEqual(len(self._solicitudes()), 1)

        repetida = self.client.post(
            f"/dispensers/{self.dispensador.id}/quick-dispense",
            json=cuerpo,
        )
        self.assertEqual(repetida.status_code, 202)
        self.assertEqual(repetida.json(), respuesta.json())
        self.assertEqual(len(self._solicitudes()), 1)

    def test_el_endpoint_rechaza_con_el_codigo_del_catalogo(self):
        app.dependency_overrides[get_current_user] = lambda: self.usuario
        casos = (
            ({"amount": 0, "operation_id": "op-1"}, "cantidad_rapida_invalida"),
            ({"amount": 200.1, "operation_id": "op-2"}, "cantidad_rapida_invalida"),
            ({"amount": "abc", "operation_id": "op-3"}, "cantidad_rapida_invalida"),
            ({"operation_id": "op-4"}, "cantidad_rapida_invalida"),
            ({"amount": 50}, "operacion_invalida"),
            ({}, "operacion_invalida"),
            ({"amount": 50, "operation_id": ""}, "operacion_invalida"),
            ({"amount": 50, "operation_id": "op 5"}, "operacion_invalida"),
        )
        for cuerpo, codigo in casos:
            with self.subTest(cuerpo=repr(cuerpo)):
                respuesta = self.client.post(
                    f"/dispensers/{self.dispensador.id}/quick-dispense",
                    json=cuerpo,
                )
                self.assertEqual(respuesta.status_code, 400)
                self.assertEqual(respuesta.json()["detail"]["code"], codigo)
        self.assertEqual(self._solicitudes(), [])

    def test_el_endpoint_rechaza_un_cuerpo_no_objeto(self):
        app.dependency_overrides[get_current_user] = lambda: self.usuario
        for cuerpo in (["no", "es", "objeto"], "texto", 50, None):
            with self.subTest(cuerpo=repr(cuerpo)):
                respuesta = self.client.post(
                    f"/dispensers/{self.dispensador.id}/quick-dispense",
                    json=cuerpo,
                )
                self.assertEqual(respuesta.status_code, 400)
                self.assertEqual(
                    respuesta.json()["detail"]["code"], "operacion_invalida"
                )
        self.assertEqual(self._solicitudes(), [])

    def test_el_endpoint_exige_autenticacion(self):
        respuesta = self.client.post(
            f"/dispensers/{self.dispensador.id}/quick-dispense",
            json={"amount": 50, "operation_id": "op-sin-sesion"},
        )
        self.assertEqual(respuesta.status_code, 401)


class TestReservaDeStock(BaseDispensacionRapidaTests):
    """RF-3, RNF-9: dos pendientes no pueden sumar más que el stock actual."""

    def test_una_solicitud_de_200_con_stock_300_se_acepta(self):
        self._fijar_stock(300)
        respuesta = self._solicitar(200)
        self.assertEqual(respuesta["requested_grams"], 200.0)
        self.assertEqual(len(self._solicitudes()), 1)

    def test_dos_solicitudes_de_200_con_stock_300_rechazan_la_segunda(self):
        self._fijar_stock(300)
        self._solicitar(200, operation_id="op-primera")

        with self.assertRaises(ErrorDominio) as contexto:
            self._solicitar(200, operation_id="op-segunda")

        self.assertEqual(contexto.exception.code, "stock_insuficiente")
        self.assertEqual(len(self._solicitudes()), 1)
        self.assertIsNotNone(self._cola()[0].consumed_at)

    def test_el_rechazo_por_reserva_no_crea_ni_cubre(self):
        self._fijar_stock(300)
        self._solicitar(200, operation_id="op-primera")

        with self.assertRaises(ErrorDominio):
            self._solicitar(100.5, operation_id="op-segunda")

        self.assertEqual(len(self._solicitudes()), 1)
        self.assertEqual(len(self._cola()), 1)

    def test_la_solicitud_que_cabe_justo_en_la_reserva_se_acepta(self):
        self._fijar_stock(300)
        self._solicitar(200)
        self._solicitar(100)

        self.assertEqual(len(self._solicitudes()), 2)
        with self.assertRaises(ErrorDominio) as contexto:
            self._solicitar(0.5)
        self.assertEqual(contexto.exception.code, "stock_insuficiente")


class TestConcurrenciaDeReserva(BaseDispensacionRapidaTests):
    """RF-3, RNF-5: dos solicitudes simultáneas no reservan más que el stock.

    La barrera se coloca dentro de la comprobación previa de stock, de modo que
    las dos sesiones superan esa lectura antes de escribir. La comprobación que
    decide es la que corre después del `flush`, bajo el bloqueo de escritura.
    """

    def test_dos_solicitudes_simultaneas_de_200_rechazan_exactamente_una(self):
        self._fijar_stock(300)
        aceptadas = []
        rechazadas = []
        errores = []
        barrera = threading.Barrier(2)
        reserva_original = order_service._stock_reservado

        def reserva_con_barrera(db, dispensador):
            # Ambas sesiones calculan la reserva previa (stock 300, sin
            # pendientes) y esperan aquí antes de continuar hacia la escritura.
            valor = reserva_original(db, dispensador)
            barrera.wait(timeout=10)
            return valor

        def solicitar(operacion):
            sesion = SessionLocal()
            try:
                aceptadas.append(
                    order_service.solicitar_dispensacion_rapida(
                        db=sesion,
                        dispenser_id=self.dispensador.id,
                        cantidad=200.0,
                        operation_id=operacion,
                        user_id=self.usuario.id,
                        ahora=_en_utc(AHORA),
                    )
                )
            except ErrorDominio as error:
                rechazadas.append(error.code)
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                sesion.close()

        with patch.object(
            order_service, "_stock_reservado", side_effect=reserva_con_barrera
        ):
            hilos = [
                threading.Thread(target=solicitar, args=(f"op-stock-{indice}",))
                for indice in range(2)
            ]
            for hilo in hilos:
                hilo.start()
            for hilo in hilos:
                hilo.join(timeout=20)

        self.assertEqual(errores, [], f"Las solicitudes simultáneas fallaron: {errores}")
        self.assertEqual(len(aceptadas), 1, "Solo una solicitud puede reservar 200 g")
        self.assertEqual(rechazadas, ["stock_insuficiente"])

        solicitudes = self._solicitudes()
        self.assertEqual(len(solicitudes), 1)
        self.assertIsNone(solicitudes[0].consumed_at)
        self.assertEqual(solicitudes[0].amount, 200.0)


class TestConsumoDeOcurrencia(BaseDispensacionRapidaTests):
    """RF-7: cubrir una ocurrencia que ya desapareció no bloquea la solicitud."""

    def test_una_ocurrencia_inexistente_no_se_rechaza(self):
        from types import SimpleNamespace

        sesion = SessionLocal()
        try:
            order_service._consumir_ocurrencia(
                sesion,
                SimpleNamespace(id=999999),
                _en_utc(AHORA),
            )
        finally:
            sesion.close()


class TestIdempotencia(BaseDispensacionRapidaTests):
    """RF-14: el mismo `operation_id` devuelve la misma solicitud pendiente."""

    def test_el_mismo_identificador_no_crea_otra_solicitud(self):
        primera = self._solicitar(50, operation_id="op-repetida")
        segunda = self._solicitar(50, operation_id="op-repetida")

        self.assertEqual(segunda, primera)
        self.assertEqual(primera["status"], "pending")
        self.assertEqual(len(self._solicitudes()), 1)

    def test_el_reintento_no_vuelve_a_cubrir_horarios(self):
        self._solicitar(50, operation_id="op-cobertura")
        cola = self._cola()
        self.assertEqual(len(cola), 1)
        marca = cola[0].consumed_at
        self.assertIsNotNone(marca)

        self._solicitar(50, operation_id="op-cobertura")

        cola = self._cola()
        self.assertEqual(len(cola), 1)
        self.assertEqual(cola[0].consumed_at, marca)

    def test_el_reintento_no_valida_la_cantidad_ni_el_stock(self):
        self._solicitar(50, operation_id="op-sin-stock")
        self._fijar_stock(0)

        respuesta = self._solicitar(200, operation_id="op-sin-stock")

        self.assertEqual(respuesta["requested_grams"], 50.0)
        self.assertEqual(len(self._solicitudes()), 1)
        self.assertEqual(len(self._cola()), 1)

    def test_identificadores_distintos_crean_solicitudes_distintas(self):
        self._fijar_stock(300)
        self._solicitar(50, operation_id="op-a")
        self._solicitar(50, operation_id="op-b")

        self.assertEqual(len(self._solicitudes()), 2)

    def test_un_identificador_invalido_no_crea_ni_cubre(self):
        for operation_id in (None, "", "   ", "op 1", "a" * 129):
            with self.subTest(operation_id=repr(operation_id)):
                with self.assertRaises(ErrorDominio) as contexto:
                    self._solicitar(50, operation_id=operation_id)
                self.assertEqual(contexto.exception.code, "operacion_invalida")
        self.assertEqual(self._solicitudes(), [])
        self.assertEqual(self._cola(), [])

    def test_un_identificador_invalido_tiene_prioridad_sobre_el_404(self):
        """RF-14 antes que RF-15: el cuerpo se valida antes de buscar dueño."""
        sesion = SessionLocal()
        try:
            with self.assertRaises(ErrorDominio) as contexto:
                order_service.solicitar_dispensacion_rapida(
                    db=sesion,
                    dispenser_id=999999,
                    cantidad=50,
                    operation_id="",
                    user_id=self.otro_usuario.id,
                    ahora=_en_utc(AHORA),
                )
        finally:
            sesion.close()
        self.assertEqual(contexto.exception.code, "operacion_invalida")


class TestConcurrenciaDeSolicitud(BaseDispensacionRapidaTests):
    """RNF-5 y RF-7: dos solicitudes simultáneas cubren una sola ocurrencia.

    Las dos sesiones leen el dispensador antes de competir, igual que dos
    peticiones reales simultáneas. La clave única de `dispensing_queue` y su
    `IntegrityError` resuelto dejan una única ocurrencia, consumida, sin
    duplicarla ni perderla.
    """

    def test_dos_solicitudes_simultaneas_no_duplican_la_ocurrencia(self):
        resultados = []
        errores = []
        barrera = threading.Barrier(2)
        buscar_original = order_service._dispensador_del_usuario

        def buscar_con_barrera(db, dispenser_id, user_id):
            encontrado = buscar_original(db, dispenser_id, user_id)
            barrera.wait(timeout=10)
            return encontrado

        def solicitar(operacion):
            sesion = SessionLocal()
            try:
                resultados.append(
                    order_service.solicitar_dispensacion_rapida(
                        db=sesion,
                        dispenser_id=self.dispensador.id,
                        cantidad=50.0,
                        operation_id=operacion,
                        user_id=self.usuario.id,
                        ahora=_en_utc(AHORA),
                    )
                )
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                sesion.close()

        with patch.object(
            order_service,
            "_dispensador_del_usuario",
            side_effect=buscar_con_barrera,
        ):
            hilos = [
                threading.Thread(target=solicitar, args=(f"op-hilo-{indice}",))
                for indice in range(2)
            ]
            for hilo in hilos:
                hilo.start()
            for hilo in hilos:
                hilo.join(timeout=20)

        self.assertEqual(errores, [], f"Las solicitudes simultáneas fallaron: {errores}")
        self.assertEqual(len(resultados), 2)
        self.assertTrue(all(r["status"] == "pending" for r in resultados))
        self.assertEqual(len(self._solicitudes()), 2)
        self.assertEqual(self._ordenes(), [])

        cola = self._cola()
        self.assertEqual(len(cola), 1, "La ocurrencia no se duplica")
        self.assertIsNotNone(cola[0].consumed_at, "La ocurrencia queda cubierta")


if __name__ == "__main__":
    unittest.main()
