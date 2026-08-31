import os
import sys
import unittest
from pathlib import Path

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


class TestProtectedEndpoints(BaseApiTests):
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
