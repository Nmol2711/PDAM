"""Identidad del token de sesión y login normalizado (spec 015, T3).

Cubre RF-10 y RF-19: el token identifica la cuenta por `public_id` y `jti`, el
login compara el correo en forma normalizada, `get_current_identity` no exige
que la cuenta exista (lo necesita la baja de T4) y `get_current_user` sí, además
de rechazar los `jti` revocados. También cubre el registro normalizado de RF-12.
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

from fastapi import HTTPException
from fastapi.testclient import TestClient
from jose import jwt

from app.api.deps import get_current_identity, get_current_user
from app.core import security
from app.core.confg import settings
from app.db.database import SessionLocal
from app.domain.token import nuevo_jti
from app.main import app
from app.models import models

PASSWORD = "claveActual123"
HASH_ACTUAL = security.get_password_hash(PASSWORD)


class BaseIdentidadTests(unittest.TestCase):
    """Una cuenta con el correo sin normalizar y utilidades de token."""

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

    def _token(self, public_id=None, jti=None):
        return security.crear_token_acceso(
            public_id or self.usuario.public_id, jti or nuevo_jti()
        )

    def _login(self, email, password=PASSWORD):
        return self.client.post(
            "/auth/login", data={"username": email, "password": password}
        )

    def _get(self, token):
        return self.client.get(
            "/users/me", headers={"Authorization": f"Bearer {token}"}
        )


class TestLoginNormalizado(BaseIdentidadTests):
    """RF-19: el correo se compara normalizado y el error es único."""

    def test_login_acepta_el_correo_en_minusculas(self):
        respuesta = self._login("user@test.com")

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(set(respuesta.json().keys()), {"access_token", "token_type"})

    def test_login_recorta_los_espacios_exteriores(self):
        respuesta = self._login("  USER@test.com  ")

        self.assertEqual(respuesta.status_code, 200, respuesta.text)

    def test_login_con_password_incorrecta_es_invalid_credentials(self):
        respuesta = self._login("user@test.com", "otra-clave-larga")

        self.assertEqual(respuesta.status_code, 401, respuesta.text)
        self.assertEqual(
            respuesta.json()["detail"],
            {
                "code": "invalid_credentials",
                "message": "Correo o contraseña incorrectos",
            },
        )

    def test_login_con_correo_inexistente_da_el_mismo_error(self):
        respuesta = self._login("nadie@test.com")

        self.assertEqual(respuesta.status_code, 401, respuesta.text)
        self.assertEqual(respuesta.json()["detail"]["code"], "invalid_credentials")

    def test_el_token_emitido_lleva_public_id_y_jti(self):
        respuesta = self._login("user@test.com")
        self.assertEqual(respuesta.status_code, 200, respuesta.text)

        payload = jwt.decode(
            respuesta.json()["access_token"],
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )

        self.assertEqual(payload["sub"], self.usuario.public_id)
        self.assertNotEqual(payload["sub"], self.usuario.email)
        self.assertTrue(payload["jti"])
        self.assertIn("exp", payload)

    def test_dos_logins_emiten_jti_distintos(self):
        primero = self._login("user@test.com").json()["access_token"]
        segundo = self._login("user@test.com").json()["access_token"]

        claims_primero = jwt.decode(
            primero, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        claims_segundo = jwt.decode(
            segundo, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        self.assertNotEqual(claims_primero["jti"], claims_segundo["jti"])


class TestIdentidadYUsuarioActual(BaseIdentidadTests):
    """RF-05, RF-18, RF-19: identidad sin cuenta y usuario con cuenta."""

    def test_get_current_identity_no_exige_que_la_cuenta_exista(self):
        jti = nuevo_jti()
        token = self._token(public_id="cuenta-eliminada", jti=jti)

        sesion = SessionLocal()
        try:
            identidad = get_current_identity(db=sesion, token=token)
        finally:
            sesion.close()

        self.assertEqual(identidad.public_id, "cuenta-eliminada")
        self.assertEqual(identidad.jti, jti)
        self.assertIsNotNone(identidad.expira_en)

    def test_get_current_user_rechaza_una_cuenta_inexistente(self):
        token = self._token(public_id="cuenta-eliminada")

        sesion = SessionLocal()
        try:
            with self.assertRaises(HTTPException) as capturado:
                get_current_user(db=sesion, identidad=get_current_identity(
                    db=sesion, token=token
                ))
        finally:
            sesion.close()

        self.assertEqual(capturado.exception.status_code, 401)
        self.assertEqual(
            capturado.exception.detail["code"], "unauthorized"
        )

    def test_un_jti_revocado_no_permite_la_peticion(self):
        jti = nuevo_jti()
        token = self._token(jti=jti)
        sesion = SessionLocal()
        try:
            sesion.add(
                models.RevokedToken(
                    jti=jti,
                    public_id=self.usuario.public_id,
                    expires_at=datetime.now(timezone.utc).replace(tzinfo=None)
                    + timedelta(minutes=30),
                    revoked_at=datetime.now(timezone.utc).replace(tzinfo=None),
                )
            )
            sesion.commit()
        finally:
            sesion.close()

        respuesta = self._get(token)

        self.assertEqual(respuesta.status_code, 401, respuesta.text)
        self.assertEqual(respuesta.json()["detail"]["code"], "unauthorized")

    def test_otro_jti_revocado_no_afecta_al_token(self):
        sesion = SessionLocal()
        try:
            sesion.add(
                models.RevokedToken(
                    jti="otro-jti",
                    public_id=self.usuario.public_id,
                    expires_at=datetime.now(timezone.utc).replace(tzinfo=None)
                    + timedelta(minutes=30),
                    revoked_at=datetime.now(timezone.utc).replace(tzinfo=None),
                )
            )
            sesion.commit()
        finally:
            sesion.close()

        self.assertEqual(self._get(self._token()).status_code, 200)


class TestRegistroNormalizado(BaseIdentidadTests):
    """RF-12 y RF-19: alta normalizada y duplicado con código."""

    def test_el_registro_normaliza_el_correo(self):
        respuesta = self.client.post(
            "/users/",
            json={"email": "  Nuevo@Test.com ", "password": PASSWORD},
        )

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        self.assertEqual(respuesta.json()["email"], "nuevo@test.com")

        sesion = SessionLocal()
        try:
            guardado = (
                sesion.query(models.User)
                .filter(models.User.email == "nuevo@test.com")
                .one()
            )
            self.assertEqual(guardado.email, "nuevo@test.com")
        finally:
            sesion.close()

    def test_el_duplicado_normalizado_responde_email_already_registered(self):
        respuesta = self.client.post(
            "/users/",
            json={"email": "USER@test.com", "password": PASSWORD},
        )

        self.assertEqual(respuesta.status_code, 400, respuesta.text)
        self.assertEqual(
            respuesta.json()["detail"],
            {
                "code": "email_already_registered",
                "message": "El correo electrónico ya está registrado.",
            },
        )

    def test_el_registro_nuevo_puede_iniciar_sesion_con_cualquier_caja(self):
        self.client.post(
            "/users/",
            json={"email": "Nuevo@Test.com", "password": PASSWORD},
        )

        respuesta = self._login("nuevo@test.com")

        self.assertEqual(respuesta.status_code, 200, respuesta.text)


if __name__ == "__main__":
    unittest.main()
