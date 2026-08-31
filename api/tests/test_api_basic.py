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
    """Base para las pruebas de la API."""

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
    """Pruebas para el estado del servicio y el flujo de autenticación."""

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


class TestUserRegistrationEndpoints(BaseApiTests):
    """Pruebas para el registro de usuarios."""

    def test_user_registration_is_public_and_returns_user_data(self):
        with patch(
            "app.api.endpoints.users.user_service.crear_usuario",
            return_value={"email": "usuario@test.com", "id": 1, "is_active": True},
        ):
            response = self.client.post(
                "/users/",
                json={"email": "usuario@test.com", "password": "123456"},
            )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["email"], "usuario@test.com")
        self.assertEqual(payload["id"], 1)
        self.assertTrue(payload["is_active"])


class TestProtectedEndpoints(BaseApiTests):
    """Pruebas de seguridad para los endpoints protegidos."""

    def test_get_routes_require_authentication(self):
        routes = [
            "/users/me",
            "/pets",
            "/pets/1",
            "/dispensers/1",
            "/logs/",
            "/schedules/",
            "/schedules/1?pet_id=1",
            "/schedules/pet/1",
            "/schedules/check-feeding/1",
        ]

        for route in routes:
            with self.subTest(route=route):
                self.assert_route_requires_auth("get", route)

    def test_post_routes_require_authentication(self):
        routes = [
            ("/pets/", {"name": "Milo", "species": "perro", "age": 3, "weight": 5.2}),
            ("/dispensers/", {"pet_id": 1, "mac_address": "AA:BB:CC:DD:EE:FF", "secret_key_qr": "abc123"}),
            ("/logs/", {"description": "prueba", "type": "info"}),
            ("/schedules/", {"time": "08:00", "amount": 50}),
        ]

        for route, payload in routes:
            with self.subTest(route=route):
                self.assert_route_requires_auth("post", route, json=payload)

    def test_put_routes_require_authentication(self):
        routes = [
            ("/pets/1", {"name": "Milo"}),
            ("/dispensers/1", {"mac_address": "11:22:33:44:55:66"}),
            ("/schedules/1", {"time": "09:00", "amount": 60}),
        ]

        for route, payload in routes:
            with self.subTest(route=route):
                self.assert_route_requires_auth("put", route, json=payload, params={"pet_id": 1})

    def test_delete_routes_require_authentication(self):
        routes = ["/pets/1", "/dispensers/1", "/schedules/1"]

        for route in routes:
            with self.subTest(route=route):
                self.assert_route_requires_auth("delete", route)


if __name__ == "__main__":
    unittest.main()
