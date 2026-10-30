import os
import sys
import unittest
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
from app.main import app
from app.models import models


class BaseApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def assert_route_requires_auth(self, method, path, expected_status=401, **kwargs):
        response = getattr(self.client, method)(path, **kwargs)
        self.assertNotEqual(response.status_code, 404, f"La ruta no está registrada: {path}")
        self.assertEqual(
            response.status_code,
            expected_status,
            f"Se esperaba {expected_status} en {method.upper()} {path}, pero se recibió {response.status_code}. Detalle: {response.text}",
        )
        self.assertIn("detail", response.json())


class TestHealthAndAuthEndpoints(BaseApiTests):
    def test_health_endpoint_returns_expected_payload(self):
        response = self.client.get("/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {"status": "Servidor funcionando", "proyecto": "Dispensador IoT"},
        )

    def test_login_returns_token_for_valid_credentials(self):
        fake_hash = "$2b$12$abcdefghijklmnopqrstuv"
        usuario = SimpleNamespace(hashed_password=fake_hash, public_id="public-1")

        with patch("app.api.endpoints.auth.user_service.obtener_usuario_por_correo_normalizado", return_value=usuario), \
             patch("app.api.endpoints.auth.security.verify_password", return_value=True), \
             patch("app.api.endpoints.auth.security.crear_token_acceso", return_value="token-falso"):
            response = self.client.post(
                "/auth/login",
                data={"username": "usuario@test.com", "password": "123456"},
            )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["access_token"], "token-falso")
        self.assertEqual(payload["token_type"], "bearer")
        self.assertEqual(set(payload.keys()), {"access_token", "token_type"})

    def test_login_returns_error_for_invalid_credentials(self):
        with patch("app.api.endpoints.auth.user_service.obtener_usuario_por_correo_normalizado", return_value=None):
            response = self.client.post(
                "/auth/login",
                data={"username": "usuario@test.com", "password": "123456"},
            )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(
            response.json()["detail"],
            {"code": "invalid_credentials", "message": "Correo o contraseña incorrectos"},
        )


class TestLoginConCuentaInactiva(unittest.TestCase):
    """RF-06: el estado de la cuenta no altera el inicio de sesión.

    El login no consulta `is_active`: una cuenta desactivada entra igual y su
    token sirve en las rutas autenticadas. La prueba usa la base de pruebas real
    y limpia las tablas antes y después, como el resto de suites de integración.
    """

    PASSWORD = "claveInactiva123"

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()

    def tearDown(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()

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

    def _crear_usuario(self, email, activo):
        sesion = SessionLocal()
        try:
            usuario = models.User(
                email=email,
                hashed_password=security.get_password_hash(self.PASSWORD),
                is_active=activo,
            )
            sesion.add(usuario)
            sesion.commit()
            sesion.refresh(usuario)
            return usuario
        finally:
            sesion.close()

    def _login(self, email):
        return self.client.post(
            "/auth/login",
            data={"username": email, "password": self.PASSWORD},
        )

    def test_una_cuenta_inactiva_inicia_sesion_y_usa_el_token(self):
        self._crear_usuario("inactiva@test.com", activo=False)

        respuesta = self._login("inactiva@test.com")

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(set(respuesta.json().keys()), {"access_token", "token_type"})

        perfil = self.client.get(
            "/users/me",
            headers={"Authorization": f"Bearer {respuesta.json()['access_token']}"},
        )
        self.assertEqual(perfil.status_code, 200, perfil.text)
        self.assertFalse(perfil.json()["is_active"])
        self.assertEqual(perfil.json()["email"], "inactiva@test.com")

    def test_desactivar_la_cuenta_no_bloquea_el_login(self):
        usuario = self._crear_usuario("activa@test.com", activo=True)
        self.assertEqual(self._login("activa@test.com").status_code, 200)

        sesion = SessionLocal()
        try:
            cuenta = sesion.query(models.User).filter_by(id=usuario.id).one()
            cuenta.is_active = False
            sesion.commit()
        finally:
            sesion.close()

        respuesta = self._login("activa@test.com")

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertIn("access_token", respuesta.json())
