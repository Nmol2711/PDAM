"""Actualización del perfil: `PATCH /users/me` (spec 015, T3).

Cubre RF-10 a RF-14 y RF-21: actualización solo de correo, solo de contraseña y
de ambos; token nuevo y revocación del `jti` usado solo cuando el correo cambia;
otros tokens de la misma cuenta siguen válidos; duplicado normalizado sin
cambios; conflicto de escritura condicional y fallo de escritura con el catálogo
de errores. La confirmación de la contraseña no viaja al servidor.
"""

import os
import sys
import unittest
from datetime import datetime
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

PASSWORD_ACTUAL = "claveActual123"
PASSWORD_NUEVA = "claveNueva456"
HASH_ACTUAL = security.get_password_hash(PASSWORD_ACTUAL)


class BaseActualizacionTests(unittest.TestCase):
    """Dos cuentas y utilidades de petición sobre la base de pruebas."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario("User@Test.com")
        self.ajeno = self._crear_usuario("ajeno@test.com")

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

    def _crear_usuario(self, email):
        sesion = SessionLocal()
        try:
            usuario = models.User(
                email=email, hashed_password=HASH_ACTUAL, is_active=True
            )
            sesion.add(usuario)
            sesion.commit()
            sesion.refresh(usuario)
            return usuario
        finally:
            sesion.close()

    def _recargar(self, usuario):
        sesion = SessionLocal()
        try:
            return (
                sesion.query(models.User)
                .filter(models.User.id == usuario.id)
                .one()
            )
        finally:
            sesion.close()

    def _token(self, usuario=None, jti=None, expires_delta=None):
        usuario = usuario or self.usuario
        return security.crear_token_acceso(
            usuario.public_id,
            jti or nuevo_jti(),
            expires_delta=expires_delta,
        )

    def _patch(self, payload, token=None):
        headers = {} if token is None else {"Authorization": f"Bearer {token}"}
        return self.client.patch("/users/me", json=payload, headers=headers)

    def _get(self, token):
        return self.client.get(
            "/users/me", headers={"Authorization": f"Bearer {token}"}
        )

    def _login(self, email, password):
        return self.client.post(
            "/auth/login", data={"username": email, "password": password}
        )

    def assert_codigo(self, respuesta, estado, codigo):
        self.assertEqual(respuesta.status_code, estado, respuesta.text)
        detalle = respuesta.json()["detail"]
        self.assertEqual(detalle["code"], codigo)
        self.assertTrue(detalle["message"].strip())
        return detalle


class TestActualizacionSoloCorreo(BaseActualizacionTests):
    """RF-10: token nuevo, token usado revocado y otros tokens intactos."""

    def test_solo_correo_devuelve_token_nuevo_y_normaliza(self):
        token_usado = self._token()

        respuesta = self._patch({"email": "  Nuevo@Test.com "}, token_usado)

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        cuerpo = respuesta.json()
        self.assertEqual(
            set(cuerpo.keys()), {"email", "is_active", "access_token", "token_type"}
        )
        self.assertEqual(cuerpo["email"], "nuevo@test.com")
        self.assertTrue(cuerpo["is_active"])
        self.assertTrue(cuerpo["access_token"])
        self.assertEqual(cuerpo["token_type"], "bearer")
        self.assertNotEqual(cuerpo["access_token"], token_usado)

        guardado = self._recargar(self.usuario)
        self.assertEqual(guardado.email, "nuevo@test.com")
        self.assertEqual(guardado.hashed_password, HASH_ACTUAL)

    def test_el_token_usado_en_la_peticion_deja_de_valer(self):
        token_usado = self._token()

        respuesta = self._patch({"email": "nuevo@test.com"}, token_usado)

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        rechazo = self._get(token_usado)
        self.assert_codigo(rechazo, 401, "unauthorized")

    def test_el_token_nuevo_es_utilizable(self):
        respuesta = self._patch({"email": "nuevo@test.com"}, self._token())
        self.assertEqual(respuesta.status_code, 200, respuesta.text)

        perfil = self._get(respuesta.json()["access_token"])

        self.assertEqual(perfil.status_code, 200, perfil.text)
        self.assertEqual(perfil.json()["email"], "nuevo@test.com")

    def test_otro_token_de_la_misma_cuenta_sigue_valido(self):
        token_usado = self._token()
        otro_token = self._token()

        respuesta = self._patch({"email": "nuevo@test.com"}, token_usado)

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        perfil = self._get(otro_token)
        self.assertEqual(perfil.status_code, 200, perfil.text)
        self.assertEqual(perfil.json()["email"], "nuevo@test.com")

    def test_el_token_anterior_se_registra_en_revoked_tokens(self):
        token_usado = self._token()
        respuesta = self._patch({"email": "nuevo@test.com"}, token_usado)
        self.assertEqual(respuesta.status_code, 200, respuesta.text)

        sesion = SessionLocal()
        try:
            revocados = sesion.query(models.RevokedToken).all()
            self.assertEqual(len(revocados), 1)
            self.assertEqual(revocados[0].public_id, self.usuario.public_id)
            self.assertIsNotNone(revocados[0].expires_at)
        finally:
            sesion.close()


class TestActualizacionSoloPassword(BaseActualizacionTests):
    """RF-14: la sesión sigue abierta y la contraseña anterior deja de servir."""

    def test_solo_password_no_emite_token_y_conserva_la_sesion(self):
        token = self._token()

        respuesta = self._patch({"new_password": PASSWORD_NUEVA}, token)

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        cuerpo = respuesta.json()
        self.assertEqual(cuerpo["email"], "user@test.com")
        self.assertIsNone(cuerpo["access_token"])
        self.assertIsNone(cuerpo["token_type"])

        self.assertEqual(self._get(token).status_code, 200)

    def test_la_password_anterior_ya_no_inicia_sesion_y_la_nueva_si(self):
        respuesta = self._patch({"new_password": PASSWORD_NUEVA}, self._token())
        self.assertEqual(respuesta.status_code, 200, respuesta.text)

        anterior = self._login("user@test.com", PASSWORD_ACTUAL)
        self.assert_codigo(anterior, 401, "invalid_credentials")

        nueva = self._login("user@test.com", PASSWORD_NUEVA)
        self.assertEqual(nueva.status_code, 200, nueva.text)

    def test_email_ausente_se_trata_como_sin_cambio(self):
        # Decisión del QA de T2: `email` ausente no es `invalid_email`.
        respuesta = self._patch({"new_password": PASSWORD_NUEVA}, self._token())

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(respuesta.json()["email"], "user@test.com")


class TestActualizacionCorreoYPassword(BaseActualizacionTests):
    """RF-10 y RF-14: ambos cambios en la misma operación."""

    def test_correo_y_password_a_la_vez(self):
        token_usado = self._token()

        respuesta = self._patch(
            {"email": "nuevo@test.com", "new_password": PASSWORD_NUEVA}, token_usado
        )

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        cuerpo = respuesta.json()
        self.assertEqual(cuerpo["email"], "nuevo@test.com")
        self.assertTrue(cuerpo["access_token"])

        self.assertEqual(self._get(token_usado).status_code, 401)
        self.assertEqual(self._get(cuerpo["access_token"]).status_code, 200)

        self.assertEqual(
            self._login("nuevo@test.com", PASSWORD_NUEVA).status_code, 200
        )
        self.assert_codigo(
            self._login("nuevo@test.com", PASSWORD_ACTUAL), 401, "invalid_credentials"
        )


class TestRechazosDeActualizacion(BaseActualizacionTests):
    """RF-11, RF-12 y RF-21: catálogo de errores sin 422."""

    def test_correo_duplicado_normalizado_no_aplica_ningun_cambio(self):
        respuesta = self._patch(
            {"email": "  AJENO@Test.com ", "new_password": PASSWORD_NUEVA},
            self._token(),
        )

        self.assert_codigo(respuesta, 400, "email_already_registered")
        guardado = self._recargar(self.usuario)
        self.assertEqual(guardado.email, "User@Test.com")
        self.assertEqual(guardado.hashed_password, HASH_ACTUAL)
        # Ni el correo ni la contraseña se aplicaron.
        self.assertEqual(
            self._login("user@test.com", PASSWORD_ACTUAL).status_code, 200
        )
        self.assert_codigo(
            self._login("user@test.com", PASSWORD_NUEVA), 401, "invalid_credentials"
        )

    def test_correo_igual_sin_password_es_empty_update(self):
        respuesta = self._patch({"email": "  USER@test.com "}, self._token())

        self.assert_codigo(respuesta, 400, "empty_update")

    def test_correo_igual_con_password_cambia_solo_la_password(self):
        respuesta = self._patch(
            {"email": "USER@test.com", "new_password": PASSWORD_NUEVA}, self._token()
        )

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertIsNone(respuesta.json()["access_token"])
        self.assertEqual(respuesta.json()["email"], "user@test.com")
        self.assertEqual(
            self._login("user@test.com", PASSWORD_NUEVA).status_code, 200
        )

    def test_correo_vacio_explicito_es_invalid_email(self):
        respuesta = self._patch({"email": "   "}, self._token())

        self.assert_codigo(respuesta, 400, "invalid_email")

    def test_correo_con_formato_invalido_es_invalid_email(self):
        respuesta = self._patch({"email": "sin-arroba"}, self._token())

        self.assert_codigo(respuesta, 400, "invalid_email")

    def test_password_corta_es_weak_password(self):
        respuesta = self._patch({"new_password": "1234567"}, self._token())

        self.assert_codigo(respuesta, 400, "weak_password")

    def test_password_de_mas_de_72_bytes_es_password_too_long(self):
        respuesta = self._patch({"new_password": "a" * 73}, self._token())

        self.assert_codigo(respuesta, 400, "password_too_long")

    def test_cuerpo_vacio_es_empty_update(self):
        respuesta = self._patch({}, self._token())

        self.assert_codigo(respuesta, 400, "empty_update")

    def test_escritura_condicional_fallida_es_conflict_sin_cambios(self):
        # La cuenta cargada ya no coincide con la fila: la actualización
        # condicional no escribe y responde 500 `conflict` (RF-21).
        obsoleta = SimpleNamespace(
            id=self.usuario.id,
            public_id=self.usuario.public_id,
            email="User@Test.com",
            hashed_password="hash-que-ya-no-existe",
            is_active=True,
        )
        token = self._token()

        with patch(
            "app.api.deps.user_service.obtener_usuario_por_public_id",
            return_value=obsoleta,
        ):
            respuesta = self._patch({"email": "nuevo@test.com"}, token)

        self.assert_codigo(respuesta, 500, "conflict")
        self.assertEqual(self._recargar(self.usuario).email, "User@Test.com")

    def test_fallo_de_escritura_es_server_error_y_revierte(self):
        token = self._token()

        with patch(
            "app.services.account_service.security.crear_token_acceso",
            side_effect=RuntimeError("fallo de escritura simulado"),
        ):
            respuesta = self._patch({"email": "nuevo@test.com"}, token)

        self.assert_codigo(respuesta, 500, "server_error")
        self.assertEqual(self._recargar(self.usuario).email, "User@Test.com")
        # El token usado no quedó revocado: la transacción se revirtió entera.
        self.assertEqual(self._get(token).status_code, 200)


class TestPurgaTokensRevocados(BaseActualizacionTests):
    """RF-10: la revocación purga los tokens que ya caducaron."""

    def test_el_cambio_de_correo_purga_los_tokens_caducados(self):
        caducado = models.RevokedToken(
            jti=nuevo_jti(),
            public_id=self.ajeno.public_id,
            expires_at=datetime(2020, 1, 1),
            revoked_at=datetime(2020, 1, 1),
        )
        vigente = models.RevokedToken(
            jti=nuevo_jti(),
            public_id=self.ajeno.public_id,
            expires_at=datetime(2099, 1, 1),
            revoked_at=datetime(2020, 1, 1),
        )
        sesion = SessionLocal()
        try:
            sesion.add_all([caducado, vigente])
            sesion.commit()
            jti_caducado = caducado.jti
            jti_vigente = vigente.jti
        finally:
            sesion.close()

        respuesta = self._patch({"email": "nuevo@test.com"}, self._token())

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        sesion = SessionLocal()
        try:
            restantes = sesion.query(models.RevokedToken).all()
            jtis = {fila.jti for fila in restantes}
        finally:
            sesion.close()

        self.assertNotIn(jti_caducado, jtis)
        self.assertIn(jti_vigente, jtis)
        self.assertEqual(len(restantes), 2)


class TestContratoSinFiltraciones(BaseActualizacionTests):
    """RNF-06: ninguna respuesta devuelve credenciales."""

    def test_la_respuesta_no_incluye_hash_ni_password(self):
        respuesta = self._patch(
            {"email": "nuevo@test.com", "new_password": PASSWORD_NUEVA},
            self._token(),
        )

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        texto = respuesta.text
        self.assertNotIn("hashed_password", texto)
        self.assertNotIn(PASSWORD_ACTUAL, texto)
        self.assertNotIn(PASSWORD_NUEVA, texto)


if __name__ == "__main__":
    unittest.main()
