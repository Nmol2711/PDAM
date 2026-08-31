import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi.testclient import TestClient

from app.main import app


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

        with patch("app.api.endpoints.auth.user_service.obtener_password_por_email", return_value=fake_hash), \
             patch("app.api.endpoints.auth.security.verify_password", return_value=True), \
             patch("app.api.endpoints.auth.security.create_access_token", return_value="token-falso"):
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
        with patch("app.api.endpoints.auth.user_service.obtener_password_por_email", return_value=None):
            response = self.client.post(
                "/auth/login",
                data={"username": "usuario@test.com", "password": "123456"},
            )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"], "Correo o contraseña incorrectos")
