"""Baja de cuenta transaccional e idempotente (spec 015, T4).

Cubre RF-17 a RF-21 y RNF-05, RNF-08 y RNF-09 sobre la aplicación completa:

- la baja con la contraseña correcta borra físicamente la cuenta y sus datos en
  las siete tablas afectadas, incluidas las que guardan el propietario sin clave
  foránea (`dispensing_orders`, `refill_operations`, `logs`);
- la contraseña incorrecta, ausente o vacía responde 400 `invalid_password` sin
  tocar nada;
- la cuenta ya inexistente responde 200 sin verificar la contraseña, incluso con
  el token de la cuenta eliminada y en dos bajas simultáneas;
- un fallo inyectado dentro de la transacción revierte el borrado completo;
- el correo queda libre, la MAC deja de estar registrada y el token anterior no
  sirve en ninguna otra ruta.
"""

import os
import sys
import threading
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi.testclient import TestClient

from app.core import security
from app.db.database import SessionLocal
from app.domain.token import nuevo_jti
from app.main import app
from app.models import models
from app.services import account_service
from app.services.mac_service import normalize_mac

PASSWORD = "claveActual123"
PASSWORD_NUEVA = "claveNueva456"
HASH_ACTUAL = security.get_password_hash(PASSWORD)
MAC = "AA:BB:CC:DD:AB:1F"
MAC_AJENA = "AA:BB:CC:DD:AB:2F"
AHORA_NAIVE = datetime(2026, 10, 1, 12, 0, 0)

CODIGO_SERVER_ERROR = {
    "code": "server_error",
    "message": "No se pudo completar la operación. Inténtalo de nuevo.",
}


class BaseBajaTests(unittest.TestCase):
    """Dos cuentas completas: la que se da de baja y una ajena que debe sobrevivir."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario("User@Test.com")
        self.ajeno = self._crear_usuario("ajeno@test.com")
        self.datos = self._crear_datos(self.usuario, MAC, "propia")
        self.datos_ajenos = self._crear_datos(self.ajeno, MAC_AJENA, "ajena")

    def tearDown(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()

    # --- Escenario ----------------------------------------------------------

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
                models.RevokedToken,
                models.User,
            ):
                sesion.query(modelo).delete()
            sesion.commit()
        finally:
            sesion.close()

    def _guardar(self, entidad):
        sesion = SessionLocal()
        try:
            sesion.add(entidad)
            sesion.commit()
            sesion.refresh(entidad)
            return entidad
        finally:
            sesion.close()

    def _crear_usuario(self, email):
        return self._guardar(
            models.User(email=email, hashed_password=HASH_ACTUAL, is_active=True)
        )

    def _crear_datos(self, usuario, mac, sufijo):
        """Mascota, dispensador, horario, cola, orden, reabastecimiento y registro."""
        mascota = self._guardar(
            models.Pet(
                name=f"Milo {sufijo}",
                species="perro",
                birth_date=date(2023, 1, 1),
                weight=5.5,
                reproductive_status=False,
                user_id=usuario.id,
            )
        )
        dispensador = self._guardar(
            models.Dispenser(
                mac_address=mac,
                mac_normalized=normalize_mac(mac),
                pet_id=mascota.id,
                is_active=True,
                pending_dispensing=False,
                pending_wifi_reset=False,
                current_food_grams=1000.0,
            )
        )
        horario = self._guardar(
            models.Schedule(time="08:00", amount=50.0, pet_id=mascota.id)
        )
        cola = self._guardar(
            models.DispensingQueue(
                dispenser_id=dispensador.id,
                pet_id=mascota.id,
                schedule_id=horario.id,
                amount=50.0,
                scheduled_for=AHORA_NAIVE,
            )
        )
        orden = self._guardar(
            models.DispensingOrder(
                user_id=usuario.id,
                pet_id=mascota.id,
                pet_name=mascota.name,
                dispenser_id=dispensador.id,
                dispenser_mac_masked="**:AB:1F",
                requested_grams=50.0,
                delivered_at=AHORA_NAIVE,
                status="pending",
            )
        )
        reabastecimiento = self._guardar(
            models.RefillOperation(
                user_id=usuario.id,
                operation_id=f"op-{sufijo}",
                dispenser_id=dispensador.id,
                grams=100.0,
                applied_at=AHORA_NAIVE,
            )
        )
        registro = self._guardar(
            models.ActivityLog(
                user_id=usuario.id,
                pet_id=mascota.id,
                pet_name=mascota.name,
                dispenser_id=dispensador.id,
                description=f"Registro {sufijo}",
            )
        )
        revocado = self._guardar(
            models.RevokedToken(
                jti=nuevo_jti(),
                public_id=usuario.public_id,
                expires_at=AHORA_NAIVE + timedelta(minutes=30),
                revoked_at=AHORA_NAIVE,
            )
        )
        return SimpleNamespace(
            mascota=mascota,
            dispensador=dispensador,
            horario=horario,
            cola=cola,
            orden=orden,
            reabastecimiento=reabastecimiento,
            registro=registro,
            revocado=revocado,
        )

    # --- Utilidades de la prueba -------------------------------------------

    def _token(self, usuario=None, expires_delta=None):
        usuario = usuario or self.usuario
        return security.crear_token_acceso(
            usuario.public_id, nuevo_jti(), expires_delta=expires_delta
        )

    def _baja(self, token=None, payload=None, cliente=None):
        cliente = cliente or self.client
        headers = {} if token is None else {"Authorization": f"Bearer {token}"}
        if payload is None:
            payload = {"password": PASSWORD}
        kwargs = {} if payload is _SIN_CUERPO else {"json": payload}
        # `TestClient.delete` de httpx no admite cuerpo; `request` sí.
        return cliente.request("DELETE", "/users/me", headers=headers, **kwargs)

    def _contar(self, modelo, *condiciones):
        sesion = SessionLocal()
        try:
            consulta = sesion.query(modelo)
            for condicion in condiciones:
                consulta = consulta.filter(condicion)
            return consulta.count()
        finally:
            sesion.close()

    def _filas_del_usuario(self, usuario, datos):
        """Recuento por tabla de los datos asociados a una cuenta."""
        return {
            "pets": self._contar(models.Pet, models.Pet.user_id == usuario.id),
            "dispensers": self._contar(
                models.Dispenser, models.Dispenser.pet_id == datos.mascota.id
            ),
            "schedules": self._contar(
                models.Schedule, models.Schedule.pet_id == datos.mascota.id
            ),
            "dispensing_queue": self._contar(
                models.DispensingQueue,
                models.DispensingQueue.dispenser_id == datos.dispensador.id,
            ),
            "dispensing_orders": self._contar(
                models.DispensingOrder,
                models.DispensingOrder.user_id == usuario.id,
            ),
            "refill_operations": self._contar(
                models.RefillOperation,
                models.RefillOperation.user_id == usuario.id,
            ),
            "logs": self._contar(
                models.ActivityLog, models.ActivityLog.user_id == usuario.id
            ),
            "revoked_tokens": self._contar(
                models.RevokedToken,
                models.RevokedToken.public_id == usuario.public_id,
            ),
            "users": self._contar(models.User, models.User.id == usuario.id),
        }

    def _assert_codigo(self, respuesta, estado, codigo, mensaje):
        self.assertEqual(respuesta.status_code, estado, respuesta.text)
        detalle = respuesta.json()["detail"]
        self.assertEqual(detalle, {"code": codigo, "message": mensaje})


# `_SIN_CUERPO` distingue «no enviar cuerpo» de enviar `null` en `_baja`.
_SIN_CUERPO = object()


class TestBajaCorrecta(BaseBajaTests):
    """RF-18, RF-19 y RNF-09: borrado físico total en una transacción."""

    def test_borra_la_cuenta_y_las_siete_tablas_afectadas(self):
        respuesta = self._baja(self._token())

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(respuesta.json(), {"deleted": True})

        filas = self._filas_del_usuario(self.usuario, self.datos)
        for tabla, cantidad in filas.items():
            with self.subTest(tabla=tabla):
                self.assertEqual(cantidad, 0, f"Quedaron filas en {tabla}")

    def test_no_toca_los_datos_de_otra_cuenta(self):
        self._baja(self._token())

        filas = self._filas_del_usuario(self.ajeno, self.datos_ajenos)
        for tabla, cantidad in filas.items():
            with self.subTest(tabla=tabla):
                self.assertEqual(cantidad, 1, f"Se borraron filas ajenas en {tabla}")

    def test_la_mac_borrada_ya_no_esta_registrada(self):
        self._baja(self._token())

        reporte = self.client.post(
            "/dispensers/reports",
            json={
                "mac": MAC,
                "order_id": None,
                "motivo": "objetivo_alcanzado",
                "gramos_solicitados": 50.0,
                "gramos_medidos": 50.0,
                "reintentos": 0,
            },
        )

        self._assert_codigo(
            reporte, 400, "mac_no_registrada", "El dispensador no está registrado."
        )

    def test_el_correo_queda_libre_y_el_registro_nuevo_nace_vacio(self):
        token_anterior = self._token()
        self._baja(token_anterior)

        alta = self.client.post(
            "/users/", json={"email": "User@Test.com", "password": PASSWORD_NUEVA}
        )
        self.assertEqual(alta.status_code, 200, alta.text)

        sesion = SessionLocal()
        try:
            nueva = (
                sesion.query(models.User)
                .filter(models.User.email == "user@test.com")
                .one()
            )
            nuevo_id = nueva.id
            nuevo_public_id = nueva.public_id
        finally:
            sesion.close()

        self.assertNotEqual(nuevo_id, self.usuario.id)
        self.assertNotEqual(nuevo_public_id, self.usuario.public_id)
        self.assertEqual(
            self._contar(models.Pet, models.Pet.user_id == nuevo_id), 0
        )
        self.assertEqual(
            self._contar(models.Dispenser), 1, "Solo queda el dispensador ajeno"
        )
        self.assertEqual(self._contar(models.Schedule), 1, "Solo queda el horario ajeno")
        self.assertEqual(
            self._contar(models.DispensingQueue), 1, "Solo queda la cola ajena"
        )
        self.assertEqual(
            self._contar(models.DispensingOrder), 1, "Solo queda la orden ajena"
        )
        self.assertEqual(
            self._contar(models.RefillOperation), 1, "Solo queda el reabastecimiento ajeno"
        )
        self.assertEqual(
            self._contar(models.ActivityLog), 1, "Solo queda el registro ajeno"
        )
        self.assertEqual(
            self._contar(
                models.RevokedToken, models.RevokedToken.public_id == nuevo_public_id
            ),
            0,
            "La cuenta nueva no hereda sesiones revocadas",
        )

        # La cuenta nueva inicia sesión con la contraseña nueva y no con la anterior.
        self.assertEqual(
            self.client.post(
                "/auth/login",
                data={"username": "user@test.com", "password": PASSWORD_NUEVA},
            ).status_code,
            200,
        )
        anterior = self.client.post(
            "/auth/login",
            data={"username": "user@test.com", "password": PASSWORD},
        )
        self._assert_codigo(
            anterior, 401, "invalid_credentials", "Correo o contraseña incorrectos"
        )

        # El token de la cuenta eliminada no se rehabilita con el correo nuevo.
        perfil = self.client.get(
            "/users/me", headers={"Authorization": f"Bearer {token_anterior}"}
        )
        self._assert_codigo(
            perfil,
            401,
            "unauthorized",
            "La sesión no es válida. Vuelve a iniciar sesión.",
        )

    def test_la_respuesta_no_expone_la_contrasena(self):
        respuesta = self._baja(self._token())

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertNotIn(PASSWORD, respuesta.text)
        self.assertEqual(set(respuesta.json().keys()), {"deleted"})


class TestBajaConBaseMigrada(BaseBajaTests):
    """RF-18 y RNF-09: las filas migradas sin propietario no bloquean la baja.

    `_migrar_logs` deja `user_id` nulo en los registros de una base legada que
    no tenía esa columna. Si el borrado mirara solo `user_id`, la fila
    sobreviviría, el recuento de huérfanos daría más de cero y la baja
    respondería 500 para siempre, sin que el reintento de RF-21 lo resolviera.
    """

    def _huerfanos(self):
        sesion = SessionLocal()
        try:
            return account_service.contar_huerfanos(
                sesion,
                self.usuario.id,
                self.usuario.public_id,
                pet_ids=[self.datos.mascota.id],
                dispenser_ids=[self.datos.dispensador.id],
                schedule_ids=[self.datos.horario.id],
            )
        finally:
            sesion.close()

    def test_una_fila_de_logs_sin_user_id_no_bloquea_la_baja(self):
        self._guardar(
            models.ActivityLog(
                user_id=None,
                pet_id=self.datos.mascota.id,
                description="Registro migrado sin propietario",
            )
        )

        respuesta = self._baja(self._token())

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(respuesta.json(), {"deleted": True})
        self.assertEqual(
            self._contar(
                models.ActivityLog,
                models.ActivityLog.pet_id == self.datos.mascota.id,
            ),
            0,
            "La fila migrada sobrevivió a la baja",
        )
        self.assertEqual(self._huerfanos(), 0)

    def test_una_orden_sin_user_id_de_la_mascota_tampoco_bloquea(self):
        self._guardar(
            models.DispensingOrder(
                user_id=None,
                pet_id=self.datos.mascota.id,
                pet_name=self.datos.mascota.name,
                requested_grams=50.0,
                delivered_at=AHORA_NAIVE,
                status="closed",
            )
        )

        respuesta = self._baja(self._token())

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(
            self._contar(
                models.DispensingOrder,
                models.DispensingOrder.pet_id == self.datos.mascota.id,
            ),
            0,
            "La orden migrada sobrevivió a la baja",
        )
        self.assertEqual(self._huerfanos(), 0)


class TestBajaRechazos(BaseBajaTests):
    """RF-17 y RNF-06: la contraseña incorrecta o ausente no borra nada."""

    def _assert_nada_borrado(self):
        filas = self._filas_del_usuario(self.usuario, self.datos)
        for tabla, cantidad in filas.items():
            with self.subTest(tabla=tabla):
                self.assertEqual(cantidad, 1, f"Se borraron filas en {tabla}")

    def test_contrasena_incorrecta_no_borra_nada_y_conserva_la_sesion(self):
        token = self._token()

        respuesta = self._baja(token, {"password": "contrasenaIncorrecta"})

        self._assert_codigo(
            respuesta, 400, "invalid_password", "La contraseña no es correcta."
        )
        self._assert_nada_borrado()
        perfil = self.client.get(
            "/users/me", headers={"Authorization": f"Bearer {token}"}
        )
        self.assertEqual(perfil.status_code, 200, perfil.text)

    def test_sin_cuerpo_responde_invalid_password_sin_verificar(self):
        respuesta = self._baja(self._token(), payload=_SIN_CUERPO)

        self._assert_codigo(
            respuesta, 400, "invalid_password", "La contraseña no es correcta."
        )
        self._assert_nada_borrado()

    def test_password_ausente_vacia_o_nula_responde_invalid_password(self):
        for payload in ({}, {"password": ""}, {"password": None}, {"otra": "x"}):
            with self.subTest(payload=payload):
                respuesta = self._baja(self._token(), payload)
                self._assert_codigo(
                    respuesta,
                    400,
                    "invalid_password",
                    "La contraseña no es correcta.",
                )
        self._assert_nada_borrado()

    def test_sin_token_responde_unauthorized(self):
        respuesta = self._baja(payload={"password": PASSWORD})

        self._assert_codigo(
            respuesta,
            401,
            "unauthorized",
            "La sesión no es válida. Vuelve a iniciar sesión.",
        )
        self._assert_nada_borrado()

    def test_token_invalido_o_caducado_responde_unauthorized(self):
        caducado = self._token(expires_delta=timedelta(minutes=-1))

        for token in ("token-invalido", caducado):
            with self.subTest(token=token):
                respuesta = self._baja(token, {"password": PASSWORD})
                self._assert_codigo(
                    respuesta,
                    401,
                    "unauthorized",
                    "La sesión no es válida. Vuelve a iniciar sesión.",
                )
        self._assert_nada_borrado()


class TestBajaIdempotente(BaseBajaTests):
    """RF-18 y RF-21: repetir la baja de una cuenta inexistente responde éxito."""

    def test_cuenta_inexistente_responde_200_sin_verificar_contrasena(self):
        token = self._token()
        self.assertEqual(self._baja(token).status_code, 200)

        segunda = self._baja(token, {"password": "otraCualquiera"})

        self.assertEqual(segunda.status_code, 200, segunda.text)
        self.assertEqual(segunda.json(), {"deleted": True})

    def test_el_token_de_la_cuenta_eliminada_solo_sirve_para_la_baja(self):
        token = self._token()
        self.assertEqual(self._baja(token).status_code, 200)

        perfil = self.client.get(
            "/users/me", headers={"Authorization": f"Bearer {token}"}
        )
        self._assert_codigo(
            perfil,
            401,
            "unauthorized",
            "La sesión no es válida. Vuelve a iniciar sesión.",
        )

        repetida = self._baja(token)
        self.assertEqual(repetida.status_code, 200, repetida.text)

    def test_dos_bajas_simultaneas_responden_ambas_200(self):
        token = self._token()
        barrera = threading.Barrier(2)
        resultados = []
        errores = []

        def dar_de_baja():
            cliente = TestClient(app)
            try:
                barrera.wait(timeout=10)
                respuesta = self._baja(token, {"password": PASSWORD}, cliente=cliente)
                resultados.append((respuesta.status_code, respuesta.json()))
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                cliente.close()

        hilos = [threading.Thread(target=dar_de_baja) for _ in range(2)]
        for hilo in hilos:
            hilo.start()
        for hilo in hilos:
            hilo.join(timeout=30)

        self.assertEqual(errores, [], f"Las bajas simultáneas no deben fallar: {errores}")
        self.assertEqual(len(resultados), 2)
        for estado, cuerpo in resultados:
            self.assertEqual(estado, 200)
            self.assertEqual(cuerpo, {"deleted": True})

        filas = self._filas_del_usuario(self.usuario, self.datos)
        for tabla, cantidad in filas.items():
            with self.subTest(tabla=tabla):
                self.assertEqual(cantidad, 0, f"Quedaron filas en {tabla}")


class TestBajaAtomica(BaseBajaTests):
    """RNF-09: un fallo dentro de la transacción revierte el borrado completo."""

    def test_fallo_inyectado_revierte_toda_la_transaccion(self):
        token = self._token()

        with patch.object(
            account_service,
            "contar_huerfanos",
            side_effect=RuntimeError("fallo inyectado"),
        ):
            respuesta = self._baja(token, {"password": PASSWORD})

        self.assertEqual(respuesta.status_code, 500, respuesta.text)
        self.assertEqual(respuesta.json()["detail"], CODIGO_SERVER_ERROR)

        filas = self._filas_del_usuario(self.usuario, self.datos)
        for tabla, cantidad in filas.items():
            with self.subTest(tabla=tabla):
                self.assertEqual(cantidad, 1, f"El rollback no restauró {tabla}")

        perfil = self.client.get(
            "/users/me", headers={"Authorization": f"Bearer {token}"}
        )
        self.assertEqual(perfil.status_code, 200, perfil.text)
        self.assertEqual(perfil.json()["email"], "user@test.com")


class TestContarHuerfanos(BaseBajaTests):
    """RNF-09: la comprobación cubre las tablas sin FK y las instantáneas."""

    def _contar_con_instantaneas(self):
        sesion = SessionLocal()
        try:
            return account_service.contar_huerfanos(
                sesion,
                self.usuario.id,
                self.usuario.public_id,
                pet_ids=[self.datos.mascota.id],
                dispenser_ids=[self.datos.dispensador.id],
                schedule_ids=[self.datos.horario.id],
            )
        finally:
            sesion.close()

    def test_cuenta_todos_los_huerfanos_antes_de_la_baja(self):
        # Una fila por cada tabla afectada más el token revocado de la cuenta.
        self.assertEqual(self._contar_con_instantaneas(), 8)

    def test_devuelve_cero_tras_la_baja(self):
        self._baja(self._token())

        self.assertEqual(self._contar_con_instantaneas(), 0)

    def test_no_cuenta_las_filas_de_otra_cuenta(self):
        sesion = SessionLocal()
        try:
            huerfanos = account_service.contar_huerfanos(
                sesion,
                self.ajeno.id,
                self.ajeno.public_id,
                pet_ids=[self.datos_ajenos.mascota.id],
                dispenser_ids=[self.datos_ajenos.dispensador.id],
                schedule_ids=[self.datos_ajenos.horario.id],
            )
        finally:
            sesion.close()

        self.assertEqual(huerfanos, 8)


if __name__ == "__main__":
    unittest.main()
