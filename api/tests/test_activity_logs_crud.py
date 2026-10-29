"""Registros de mascotas y dispensadores (spec 014, T6).

Cubre RF-2 a RF-10, RF-22 y RNF-1: crear, modificar y eliminar una mascota o un
dispensador, y el reseteo de WiFi, escriben su registro con tipo, resultado,
causa, mascota, MAC parcial, descripción y contexto **en la misma transacción**
que el cambio de estado. `pet_updated` y `dispenser_updated` guardan solo los
nombres de los campos modificados, sin valores antiguos ni nuevos, y ningún
contexto contiene SSID, credenciales, tokens, correos ni la MAC completa.

El caso límite de la mascota eliminada se comprueba con un dispensador
desvinculado y una orden pendiente: la orden conserva su referencia, cierra por
plazo como `sin_reporte`, no descuenta stock y no se emiten órdenes nuevas. Si la
mascota aún tiene un dispensador vinculado, la eliminación se rechaza con 409
`pet_has_dispenser` y no deja ni borrado ni registro parciales.
"""

import json
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

from app.db.database import SessionLocal
from app.domain.tiempo import PLAZO_ORDEN, TOLERANCIA
from app.main import app
from app.models import models
from app.schemas.dispenser import DispenserCreate, DispenserUpdate
from app.schemas.schemas import PetCreate, PetUpdate
from app.services import activity_service, dispenser_service, order_service, pet_service
from app.services.mac_service import mask_mac

MAC = "AA:BB:CC:DD:AB:1F"
MAC_NORMALIZADA = "AABBCCDDAB1F"
MAC_ENMASCARADA = "**:AB:1F"
OTRA_MAC = "11:22:33:44:55:66"

EMAIL = "dueno@crud.test"
EMAIL_AJENO = "ajeno@crud.test"
SECRETO = "secreto-wifi-y-token-que-no-debe-registrarse"
LLAVE_QR = "llave-qr-del-hardware"

AHORA = datetime(2026, 10, 1, 12, 0, 0, tzinfo=timezone.utc)
AHORA_NAIVE = datetime(2026, 10, 1, 12, 0, 0)
STOCK_INICIAL = 1200.0


class BaseCrudLogsTests(unittest.TestCase):
    """Un usuario con su mascota, sin dispensador, en `test.db`."""

    def setUp(self):
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario()
        self.mascota = self._crear_mascota(self.usuario)

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

    def _crear_dispensador(self, mascota=None, mac=MAC, stock=STOCK_INICIAL):
        return self._guardar(
            models.Dispenser(
                mac_address=mac,
                mac_normalized="".join(
                    caracter for caracter in mac if caracter not in ":-. "
                ).upper(),
                pet_id=(mascota or self.mascota).id,
                is_active=True,
                pending_dispensing=False,
                pending_wifi_reset=False,
                current_food_grams=stock,
            )
        )

    def _crear_orden_pendiente(self, dispensador, entregada_en=AHORA_NAIVE, solicitados=50.0):
        orden = models.DispensingOrder(
            user_id=self.usuario.id,
            pet_id=self.mascota.id,
            pet_name=self.mascota.name,
            dispenser_id=dispensador.id,
            dispenser_mac_masked=MAC_ENMASCARADA,
            requested_grams=solicitados,
            delivered_at=entregada_en,
            status="pending",
        )
        return self._guardar(orden)

    # --- Acciones -----------------------------------------------------------

    def _crear_mascota_por_servicio(self, usuario=None, nombre="Nina"):
        sesion = SessionLocal()
        try:
            return pet_service.crear_mascota(
                sesion,
                PetCreate(
                    name=nombre,
                    species="gato",
                    birth_date=date(2024, 5, 1),
                    weight=4.2,
                    reproductive_status=True,
                ),
                (usuario or self.usuario).id,
            )
        finally:
            sesion.close()

    def _actualizar_mascota(self, datos, usuario=None, pet_id=None):
        sesion = SessionLocal()
        try:
            return pet_service.actualizar_mascota(
                sesion,
                pet_id or self.mascota.id,
                datos,
                usuario.id if usuario is not None else self.usuario.id,
            )
        finally:
            sesion.close()

    def _eliminar_mascota(self, usuario=None, pet_id=None):
        sesion = SessionLocal()
        try:
            return pet_service.eliminar_mascota(
                sesion,
                pet_id or self.mascota.id,
                usuario.id if usuario is not None else self.usuario.id,
            )
        finally:
            sesion.close()

    def _crear_dispensador_por_servicio(self, mascota=None, mac=MAC):
        sesion = SessionLocal()
        try:
            return dispenser_service.create_new_dispenser(
                sesion,
                DispenserCreate(mac_address=mac, pet_id=(mascota or self.mascota).id),
                user_id=self.usuario.id,
            )
        finally:
            sesion.close()

    def _actualizar_dispensador(self, datos, dispensador=None):
        sesion = SessionLocal()
        try:
            return dispenser_service.update_dispenser(
                sesion,
                (dispensador or self.dispensador).id,
                datos,
                user_id=self.usuario.id,
            )
        finally:
            sesion.close()

    def _eliminar_dispensador(self, mascota=None):
        sesion = SessionLocal()
        try:
            return dispenser_service.delete_dispenser(
                sesion,
                (mascota or self.mascota).id,
                user_id=self.usuario.id,
            )
        finally:
            sesion.close()

    def _resetear_wifi(self, dispensador=None):
        sesion = SessionLocal()
        try:
            return dispenser_service.reset_wifi_credentials(
                sesion, (dispensador or self.dispensador).id, user_id=self.usuario.id
            )
        finally:
            sesion.close()

    def _cerrar_vencidas(self, ahora):
        sesion = SessionLocal()
        try:
            return order_service.cerrar_vencidas(sesion, ahora=ahora)
        finally:
            sesion.close()

    # --- Consultas de estado (siempre en sesión nueva) ----------------------

    def _logs(self, tipo=None):
        sesion = SessionLocal()
        try:
            consulta = sesion.query(models.ActivityLog)
            if tipo is not None:
                consulta = consulta.filter(models.ActivityLog.event_type == tipo)
            return consulta.order_by(models.ActivityLog.id).all()
        finally:
            sesion.close()

    def _existe(self, modelo, identificador):
        sesion = SessionLocal()
        try:
            return (
                sesion.query(modelo).filter(modelo.id == identificador).first()
                is not None
            )
        finally:
            sesion.close()

    def _tips(self, modelo, identificador, campo):
        """Valor de `campo` leído en una sesión nueva."""
        sesion = SessionLocal()
        try:
            fila = sesion.query(modelo).filter(modelo.id == identificador).first()
            return None if fila is None else getattr(fila, campo)
        finally:
            sesion.close()

    # --- Aserciones ---------------------------------------------------------

    def _campos_modificados(self, log):
        """Conjunto de nombres de campos del contexto del registro."""
        return _campos_de_contexto(log)

    def assert_log_base(self, log, *, tipo, resultado="success", causa=None):
        """Campos obligatorios de un registro (RF-3)."""
        self.assertEqual(log.event_type, tipo)
        self.assertEqual(log.outcome, resultado)
        self.assertEqual(log.cause, causa)
        self.assertTrue(log.description.strip(), "La descripción no puede estar vacía")
        self.assertIsNotNone(log.created_at, "El registro lleva la hora del servidor")
        self.assertIsNotNone(log.user_id, "El registro tiene propietario")

    def assert_sin_datos_sensibles(self, *prohibidos):
        """Ningún registro expone credenciales, correo ni la MAC completa (RNF-1)."""
        prohibidos = prohibidos or (
            EMAIL,
            EMAIL_AJENO,
            MAC,
            MAC_NORMALIZADA,
            SECRETO,
            LLAVE_QR,
        )
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
            for prohibido in prohibidos:
                self.assertNotIn(
                    prohibido,
                    texto,
                    f"El registro {log.id} ({log.event_type}) expone un dato prohibido",
                )
            for palabra in ("ssid", "password", "token", "secret_key", "credencial"):
                self.assertNotIn(
                    palabra,
                    texto.lower(),
                    f"El registro {log.id} ({log.event_type}) menciona un secreto",
                )


def _campos_de_contexto(log):
    """Nombres de campos modificados guardados en el contexto del registro."""
    datos = json.loads(log.context or "{}")
    return set(datos.get("campos_modificados") or [])


class TestRegistrosDeMascotas(BaseCrudLogsTests):
    """RF-4, RF-5, RF-6: creación, modificación y eliminación de mascotas."""

    def test_crear_mascota_escribe_pet_created(self):
        mascota = self._crear_mascota_por_servicio(nombre="Nina")

        logs = self._logs()
        self.assertEqual(len(logs), 1)
        log = logs[0]

        self.assert_log_base(log, tipo="pet_created")
        self.assertEqual(log.user_id, self.usuario.id)
        self.assertEqual(log.pet_id, mascota.id)
        self.assertEqual(log.pet_name, "Nina")
        self.assertIsNone(log.dispenser_id)
        self.assertIsNone(log.dispenser_mac_masked)
        self.assertIn('"mascota": "Nina"', log.context)
        self.assertNotIn(EMAIL, log.context)
        self.assert_sin_datos_sensibles()

    def test_modificar_mascota_escribe_solo_los_nombres_de_los_campos(self):
        self._actualizar_mascota(PetUpdate(name="Nina", weight=7.5))

        logs = self._logs()
        self.assertEqual(len(logs), 1)
        log = logs[0]

        self.assert_log_base(log, tipo="pet_updated")
        self.assertEqual(log.pet_id, self.mascota.id)
        self.assertEqual(log.pet_name, "Nina", "Se guarda la instantánea de la mascota")

        campos = self._campos_modificados(log)
        self.assertEqual(campos, {"name", "weight"})
        for valor in ("Nina", "Milo", "7.5", "5.5"):
            self.assertNotIn(
                valor, log.context, "El contexto no guarda valores del cambio"
            )
        self.assert_sin_datos_sensibles()

    def test_modificar_un_solo_campo_registra_un_unico_nombre(self):
        self._actualizar_mascota(PetUpdate(weight=6.0))

        log = self._logs()[0]
        self.assertEqual(self._campos_modificados(log), {"weight"})
        self.assertNotIn("6.0", log.context)

    def test_eliminar_mascota_conserva_la_referencia_de_los_historicos(self):
        # Una mascota con registros previos: tras borrarla, todos sus históricos
        # siguen ligados a su identificador (RF-6, RF-27).
        mascota = self._crear_mascota_por_servicio(nombre="Nina")
        self._actualizar_mascota(PetUpdate(weight=6.0), pet_id=mascota.id)
        self._eliminar_mascota(pet_id=mascota.id)

        self.assertFalse(self._existe(models.Pet, mascota.id))

        logs = self._logs()
        self.assertEqual(
            [log.event_type for log in logs],
            ["pet_created", "pet_updated", "pet_deleted"],
        )

        borrado = logs[-1]
        self.assert_log_base(borrado, tipo="pet_deleted")
        self.assertEqual(borrado.pet_id, mascota.id)
        self.assertEqual(borrado.pet_name, mascota.name)
        for log in logs:
            self.assertEqual(
                log.pet_id,
                mascota.id,
                "El histórico conserva la mascota eliminada (RF-6, RF-27)",
            )
        self.assert_sin_datos_sensibles()

    def test_eliminar_mascota_con_dispensador_vinculado_responde_conflicto(self):
        # La relación 1-a-1 exige desvincular el dispensador antes de borrar la
        # mascota. El conflicto es un rechazo de negocio (409), no un 500, y la
        # operación rechazada no deja ni borrado ni registro.
        self._crear_dispensador()

        with self.assertRaises(HTTPException) as contexto:
            self._eliminar_mascota()

        self.assertEqual(contexto.exception.status_code, 409)
        self.assertEqual(contexto.exception.detail["code"], "pet_has_dispenser")
        self.assertTrue(contexto.exception.detail["message"].strip())
        self.assertTrue(self._existe(models.Pet, self.mascota.id))
        self.assertEqual(self._logs(), [], "Una operación no confirmada no registra")

    def test_eliminar_mascota_y_dispensador_con_orden_pendiente(self):
        # Caso límite de la spec: mascota eliminada y dispensador desvinculado con
        # orden pendiente. La orden conserva sus referencias, cierra por plazo como
        # `sin_reporte`, no descuenta stock y no se emiten órdenes nuevas.
        dispensador = self._crear_dispensador()
        orden = self._crear_orden_pendiente(dispensador)

        self.assertTrue(self._eliminar_dispensador())
        self._eliminar_mascota()

        self.assertFalse(self._existe(models.Dispenser, dispensador.id))
        self.assertFalse(self._existe(models.Pet, self.mascota.id))

        tipos = [log.event_type for log in self._logs()]
        self.assertEqual(tipos, ["dispenser_unlinked", "pet_deleted"])

        self.assertEqual(
            self._tips(models.DispensingOrder, orden.id, "pet_id"),
            self.mascota.id,
            "La orden conserva la mascota aunque ya no exista",
        )
        self.assertEqual(
            self._tips(models.DispensingOrder, orden.id, "dispenser_id"),
            dispensador.id,
        )

        cerradas = self._cerrar_vencidas(AHORA + PLAZO_ORDEN + 2 * TOLERANCIA)
        self.assertEqual(len(cerradas), 1, "El vencimiento no requiere el dispensador")

        self.assertEqual(
            self._tips(models.DispensingOrder, orden.id, "cause"), "sin_reporte"
        )
        self.assertEqual(
            self._tips(models.DispensingOrder, orden.id, "discounted_grams"), None
        )
        cierre = self._logs(tipo="feeding_dispensed")[0]
        self.assertEqual(cierre.pet_id, self.mascota.id)
        self.assertEqual(cierre.pet_name, self.mascota.name)
        # El dispensador ya no existe, así que la MAC se toma de la instantánea
        # que guardó la orden. Esa instantánea ya viene enmascarada y el registro
        # debe conservarla tal cual, sin volver a enmascararla (RF-3, RNF-1).
        self.assertEqual(cierre.dispenser_mac_masked, MAC_ENMASCARADA)

        sesion = SessionLocal()
        try:
            with self.assertRaises(HTTPException) as contexto:
                order_service.entregar_orden(sesion, MAC, ahora=AHORA)
        finally:
            sesion.close()
        self.assertEqual(
            contexto.exception.status_code,
            404,
            "Sin dispensador registrado no se emiten órdenes nuevas",
        )
        self.assertEqual(
            len(self._logs(tipo="feeding_dispensed")), 1, "No hay una segunda orden"
        )
        self.assert_sin_datos_sensibles()

    def test_la_escritura_del_registro_falla_y_la_mascota_no_se_crea(self):
        with patch.object(
            activity_service, "registrar", side_effect=RuntimeError("disco lleno")
        ):
            with self.assertRaises(RuntimeError):
                self._crear_mascota_por_servicio(nombre="Nina")

        sesion = SessionLocal()
        try:
            self.assertEqual(
                sesion.query(models.Pet).filter(models.Pet.name == "Nina").count(),
                0,
                "La creación se revierte con su registro (RF-2)",
            )
        finally:
            sesion.close()
        self.assertEqual(self._logs(), [])

    def test_la_escritura_del_registro_falla_y_la_modificacion_no_se_aplica(self):
        peso_anterior = self._tips(models.Pet, self.mascota.id, "weight")

        with patch.object(
            activity_service, "registrar", side_effect=RuntimeError("disco lleno")
        ):
            with self.assertRaises(RuntimeError):
                self._actualizar_mascota(PetUpdate(weight=9.9, name="Nina"))

        self.assertEqual(
            self._tips(models.Pet, self.mascota.id, "weight"),
            peso_anterior,
            "La modificación se revierte con su registro (RF-2)",
        )
        self.assertEqual(
            self._tips(models.Pet, self.mascota.id, "name"), "Milo"
        )
        self.assertEqual(self._logs(), [])

    def test_la_escritura_del_registro_falla_y_la_mascota_no_se_elimina(self):
        with patch.object(
            activity_service, "registrar", side_effect=RuntimeError("disco lleno")
        ):
            with self.assertRaises(RuntimeError):
                self._eliminar_mascota()

        self.assertTrue(
            self._existe(models.Pet, self.mascota.id),
            "El borrado se revierte con su registro (RF-2, RF-6)",
        )
        self.assertEqual(self._logs(), [])

    def test_una_modificacion_rechazada_no_registra(self):
        ajeno = self._crear_usuario(EMAIL_AJENO)
        mascota_ajena = self._crear_mascota(ajeno, "Pelota")

        with self.assertRaises(HTTPException) as contexto:
            self._actualizar_mascota(PetUpdate(weight=9.0), usuario=self.usuario, pet_id=mascota_ajena.id)

        self.assertEqual(contexto.exception.status_code, 404)
        self.assertEqual(self._logs(), [], "Un rechazo previo no escribe registro")


class TestRegistrosDeDispensadores(BaseCrudLogsTests):
    """RF-7, RF-8, RF-9, RF-10, RF-22: vínculo, cambios, desvínculo y WiFi."""

    def setUp(self):
        super().setUp()
        self.dispensador = self._crear_dispensador()

    def test_vincular_dispensador_escribe_dispenser_linked(self):
        mascota_sin_dispensador = self._crear_mascota(self.usuario, "Nina")
        self.dispensador = self._crear_dispensador_por_servicio(
            mascota_sin_dispensador, mac=OTRA_MAC
        )

        log = self._logs(tipo="dispenser_linked")[0]
        self.assert_log_base(log, tipo="dispenser_linked")
        self.assertEqual(log.user_id, self.usuario.id)
        self.assertEqual(log.pet_id, mascota_sin_dispensador.id)
        self.assertEqual(log.pet_name, "Nina")
        self.assertEqual(log.dispenser_id, self.dispensador.id)
        self.assertEqual(log.dispenser_mac_masked, mask_mac(OTRA_MAC))
        self.assertIn('"mascota": "Nina"', log.context)
        self.assertIn(f'"mac": "{mask_mac(OTRA_MAC)}"', log.context)
        self.assert_sin_datos_sensibles(OTRA_MAC, "112233445566")

    def test_vincular_un_dispensador_ya_registrado_no_escribe_registro(self):
        with self.assertRaises(HTTPException) as contexto:
            self._crear_dispensador_por_servicio()

        self.assertEqual(contexto.exception.status_code, 409)
        self.assertEqual(self._logs(), [])

    def test_modificar_dispensador_escribe_solo_los_nombres_de_los_campos(self):
        self._actualizar_dispensador(
            DispenserUpdate(is_active=False, current_food_grams=900.0)
        )

        log = self._logs()[0]
        self.assert_log_base(log, tipo="dispenser_updated")
        self.assertEqual(log.pet_id, self.mascota.id)
        self.assertEqual(log.dispenser_id, self.dispensador.id)
        self.assertEqual(log.dispenser_mac_masked, MAC_ENMASCARADA)
        self.assertEqual(
            self._campos_modificados(log),
            {"is_active"},
            "El stock del cliente no es un campo que se modifique por esta vía (RF-23)",
        )
        for valor in ("900", "false", "False", MAC, MAC_NORMALIZADA):
            self.assertNotIn(valor, log.context)
        self.assert_sin_datos_sensibles()

    def test_cambiar_la_mac_registra_el_nombre_del_campo_y_no_la_direccion(self):
        self._actualizar_dispensador(DispenserUpdate(mac_address=OTRA_MAC))

        log = self._logs()[0]
        self.assertEqual(self._campos_modificados(log), {"mac_address"})
        self.assertEqual(log.dispenser_mac_masked, mask_mac(OTRA_MAC))
        for prohibido in (OTRA_MAC, MAC, "112233445566", MAC_NORMALIZADA):
            self.assertNotIn(prohibido, log.context)
        self.assert_sin_datos_sensibles(OTRA_MAC, "112233445566")

    def test_un_stock_enviado_por_el_cliente_se_ignora_sin_error(self):
        # RF-23: el stock solo lo calcula el servidor. El campo se sigue
        # aceptando por compatibilidad, pero no cambia nada ni produce error.
        for valor in (900.0, 6000.0, 0.0):
            with self.subTest(stock_enviado=valor):
                respuesta = self._actualizar_dispensador(
                    DispenserUpdate(current_food_grams=valor)
                )

                self.assertEqual(respuesta.current_food_grams, STOCK_INICIAL)
                self.assertEqual(
                    self._tips(
                        models.Dispenser, self.dispensador.id, "current_food_grams"
                    ),
                    STOCK_INICIAL,
                    "El stock del servidor no cambia con el valor del cliente",
                )

        log = self._logs()[0]
        self.assertEqual(log.event_type, "dispenser_updated")
        self.assertEqual(self._campos_modificados(log), set())
        for valor in ("900", "6000"):
            self.assertNotIn(valor, log.context)

    def test_desvincular_dispensador_escribe_dispenser_unlinked(self):
        self.assertTrue(self._eliminar_dispensador())

        log = self._logs()[0]
        self.assert_log_base(log, tipo="dispenser_unlinked")
        self.assertEqual(log.pet_id, self.mascota.id)
        self.assertEqual(log.pet_name, self.mascota.name)
        self.assertEqual(log.dispenser_id, self.dispensador.id)
        self.assertEqual(log.dispenser_mac_masked, MAC_ENMASCARADA)
        self.assertIn(f'"mac": "{MAC_ENMASCARADA}"', log.context)
        self.assert_sin_datos_sensibles()

    def test_la_escritura_del_registro_falla_y_el_dispensador_sigue_vinculado(self):
        with patch.object(
            activity_service, "registrar", side_effect=RuntimeError("disco lleno")
        ):
            resultado = self._eliminar_dispensador()

        self.assertFalse(resultado, "El borrado no se confirma sin su registro")
        self.assertTrue(self._existe(models.Dispenser, self.dispensador.id))
        self.assertEqual(self._logs(), [])

    def test_la_escritura_del_registro_falla_y_la_modificacion_no_se_aplica(self):
        with patch.object(
            activity_service, "registrar", side_effect=RuntimeError("disco lleno")
        ):
            with self.assertRaises(HTTPException) as contexto:
                self._actualizar_dispensador(
                    DispenserUpdate(is_active=False, current_food_grams=900.0)
                )

        self.assertEqual(contexto.exception.status_code, 500)
        self.assertEqual(
            self._tips(models.Dispenser, self.dispensador.id, "is_active"),
            True,
            "La modificación se revierte con su registro (RF-2)",
        )
        self.assertEqual(self._logs(), [])

    def test_la_escritura_del_registro_falla_y_el_reset_de_wifi_no_se_aplica(self):
        with patch.object(
            activity_service, "registrar", side_effect=RuntimeError("disco lleno")
        ):
            with self.assertRaises(HTTPException) as contexto:
                self._resetear_wifi()

        self.assertEqual(contexto.exception.status_code, 500)
        self.assertEqual(
            self._tips(models.Dispenser, self.dispensador.id, "pending_wifi_reset"),
            False,
            "La solicitud de reseteo se revierte con su registro (RF-2, RF-10)",
        )
        self.assertEqual(self._logs(), [])

    def test_reset_wifi_escribe_dispenser_wifi_reset_sin_ssid_ni_credenciales(self):
        self._resetear_wifi()

        log = self._logs()[0]
        self.assert_log_base(log, tipo="dispenser_wifi_reset")
        self.assertEqual(log.pet_id, self.mascota.id)
        self.assertEqual(log.dispenser_id, self.dispensador.id)
        self.assertEqual(log.dispenser_mac_masked, MAC_ENMASCARADA)
        self.assertIn(f'"mac": "{MAC_ENMASCARADA}"', log.context)
        for palabra in ("ssid", "wifi", "clave", "contraseña", "password"):
            self.assertNotIn(palabra, log.context.lower())
        self.assert_sin_datos_sensibles()

    def test_un_reset_de_wifi_inexistente_no_registra(self):
        with self.assertRaises(HTTPException) as contexto:
            self._resetear_wifi(models.Dispenser(id=999, pet_id=self.mascota.id))

        self.assertEqual(contexto.exception.status_code, 404)
        self.assertEqual(self._logs(), [])


class TestBorradoDeMascotaPorApi(BaseCrudLogsTests):
    """RF-2, RF-6: el conflicto del borrado llega como 409 y nunca como 500."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        super().setUp()
        app.dependency_overrides.clear()

    def tearDown(self):
        app.dependency_overrides.clear()
        super().tearDown()

    def _autenticar(self):
        from app.api.deps import get_current_user

        usuario = models.User(
            id=self.usuario.id,
            email=self.usuario.email,
            hashed_password=SECRETO,
            is_active=True,
        )
        app.dependency_overrides[get_current_user] = lambda: usuario

    def test_borrar_una_mascota_con_dispensador_responde_conflicto(self):
        self._crear_dispensador()
        self._autenticar()

        respuesta = self.client.delete(f"/pets/{self.mascota.id}")

        self.assertEqual(respuesta.status_code, 409, respuesta.text)
        self.assertEqual(respuesta.json()["detail"]["code"], "pet_has_dispenser")
        self.assertTrue(self._existe(models.Pet, self.mascota.id))
        self.assertEqual(self._logs(), [], "La operación no se confirma ni registra")

    def test_borrar_una_mascota_sin_dispensador_sigue_funcionando(self):
        self._autenticar()

        respuesta = self.client.delete(f"/pets/{self.mascota.id}")

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertFalse(self._existe(models.Pet, self.mascota.id))
        self.assertEqual([log.event_type for log in self._logs()], ["pet_deleted"])
