"""Consulta del perfil de la cuenta: `GET /users/me` (spec 015, T3).

Cubre RF-06, RF-07 y RF-19: el perfil devuelve el correo normalizado y el estado
informativo de la cuenta con un token vigente, y responde 401 `unauthorized` sin
token, con token inválido, caducado, sin `jti` o emitido para una cuenta que ya
no existe. Se usa la base de pruebas compartida y se limpia antes y después de
cada caso, como el resto de suites de integración.
"""

import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi.testclient import TestClient
from jose import jwt

from app.core import security
from app.core.confg import settings
from app.db.database import SessionLocal
from app.domain.token import nuevo_jti
from app.main import app
from app.models import models

PASSWORD = "claveActual123"
HASH_ACTUAL = security.get_password_hash(PASSWORD)


class BasePerfilTests(unittest.TestCase):
    """Usuario con correo sin normalizar y utilidades de petición."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario("User@Test.com")

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

    def _crear_usuario(self, email, activo=True):
        sesion = SessionLocal()
        try:
            usuario = models.User(
                email=email, hashed_password=HASH_ACTUAL, is_active=activo
            )
            sesion.add(usuario)
            sesion.commit()
            sesion.refresh(usuario)
            return usuario
        finally:
            sesion.close()

    def _token(self, public_id=None, jti=None, expires_delta=None):
        return security.crear_token_acceso(
            public_id or self.usuario.public_id,
            jti or nuevo_jti(),
            expires_delta=expires_delta,
        )

    def _get(self, token=None):
        headers = {} if token is None else {"Authorization": f"Bearer {token}"}
        return self.client.get("/users/me", headers=headers)

    def assert_unauthorized(self, respuesta):
        self.assertEqual(respuesta.status_code, 401, respuesta.text)
        detalle = respuesta.json()["detail"]
        self.assertEqual(detalle["code"], "unauthorized")
        self.assertEqual(
            detalle["message"], "La sesión no es válida. Vuelve a iniciar sesión."
        )
        self.assertEqual(respuesta.headers.get("WWW-Authenticate"), "Bearer")


class TestPerfilConToken(BasePerfilTests):
    """RF-06: datos reales de la cuenta, sin credenciales."""

    def test_token_vigente_devuelve_el_perfil_con_el_correo_normalizado(self):
        respuesta = self._get(self._token())

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        perfil = respuesta.json()
        self.assertEqual(set(perfil.keys()), {"id", "email", "is_active"})
        self.assertEqual(perfil["id"], self.usuario.id)
        self.assertEqual(perfil["email"], "user@test.com")
        self.assertTrue(perfil["is_active"])
        self.assertNotIn("hashed_password", perfil)
        self.assertNotIn("password", perfil)
        self.assertNotIn("public_id", perfil)

    def test_una_cuenta_inactiva_se_informa_sin_bloquear_la_consulta(self):
        inactivo = self._crear_usuario("inactivo@test.com", activo=False)

        respuesta = self._get(self._token(public_id=inactivo.public_id))

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertFalse(respuesta.json()["is_active"])


class TestPerfilRechazado(BasePerfilTests):
    """RF-05, RF-19: todo token no utilizable responde 401 `unauthorized`."""

    def test_sin_token_responde_401_unauthorized(self):
        self.assert_unauthorized(self._get())

    def test_token_invalido_responde_401_unauthorized(self):
        self.assert_unauthorized(self._get("esto-no-es-un-jwt"))

    def test_token_caducado_responde_401_unauthorized(self):
        caducado = self._token(expires_delta=timedelta(seconds=-5))

        self.assert_unauthorized(self._get(caducado))

    def test_token_de_una_cuenta_inexistente_responde_401_unauthorized(self):
        # La identidad es válida, pero la cuenta ya no existe (RF-19).
        huerfano = self._token(public_id="cuenta-que-ya-no-existe")

        self.assert_unauthorized(self._get(huerfano))

    def test_token_sin_jti_responde_401_unauthorized(self):
        # Token firmado a mano sin `jti`: no es revocable y no se acepta.
        exp = int(
            (datetime.now(timezone.utc) + timedelta(minutes=5)).timestamp()
        )
        sin_jti = jwt.encode(
            {"sub": self.usuario.public_id, "exp": exp},
            settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
        )

        self.assert_unauthorized(self._get(sin_jti))

    def test_token_antiguo_con_sub_de_correo_responde_401_unauthorized(self):
        # El cambio de identidad es intencionado: `sub=email` ya no vale.
        exp = int(
            (datetime.now(timezone.utc) + timedelta(minutes=5)).timestamp()
        )
        antiguo = jwt.encode(
            {"sub": "user@test.com", "jti": nuevo_jti(), "exp": exp},
            settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
        )

        self.assert_unauthorized(self._get(antiguo))


if __name__ == "__main__":
    unittest.main()
