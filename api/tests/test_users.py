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


class TestUserRegistrationEndpoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

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
