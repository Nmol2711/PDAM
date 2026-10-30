"""Catálogo de errores de la cuenta en la API (spec 015, T3).

Cubre RF-11, RF-12, RF-19 y RF-21 y el catálogo de errores de la spec: todo
rechazo de negocio responde `detail={code,message}` con el mensaje literal y
ningún rechazo de negocio responde 422. Los diez códigos del catálogo aparecen
aquí; `invalid_password` se emite solo en la baja de T4, así que en esta tarea se
comprueba como parte del catálogo cerrado.
"""

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
from app.domain.cuenta import ERRORES_CUENTA
from app.domain.token import nuevo_jti
from app.main import app
from app.models import models

PASSWORD = "claveActual123"
PASSWORD_NUEVA = "claveNueva456"
HASH_ACTUAL = security.get_password_hash(PASSWORD)

# Tabla «Catálogo de errores de la API» de la spec 015: código → (HTTP, mensaje).
CATALOGO_ESPERADO = {
    "invalid_email": (400, "Introduce un correo electrónico válido."),
    "weak_password": (400, "La contraseña debe tener al menos 8 caracteres."),
    "password_too_long": (400, "La contraseña es demasiado larga."),
    "empty_update": (
        400,
        "No has modificado ningún dato. Escribe un correo nuevo o una "
        "contraseña nueva.",
    ),
    "email_already_registered": (400, "El correo electrónico ya está registrado."),
    "invalid_password": (400, "La contraseña no es correcta."),
    "invalid_credentials": (401, "Correo o contraseña incorrectos"),
    "unauthorized": (401, "La sesión no es válida. Vuelve a iniciar sesión."),
    "conflict": (500, "No se pudo completar la operación. Inténtalo de nuevo."),
    "server_error": (500, "No se pudo completar la operación. Inténtalo de nuevo."),
}


class BaseErroresTests(unittest.TestCase):
    """Una cuenta propia, otra ajena y utilidades de petición."""

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

    def _token(self, public_id=None):
        return security.crear_token_acceso(
            public_id or self.usuario.public_id, nuevo_jti()
        )

    def _patch(self, payload, token=None):
        headers = {} if token is None else {"Authorization": f"Bearer {token}"}
        return self.client.patch("/users/me", json=payload, headers=headers)

    def assert_codigo(self, respuesta, estado, codigo):
        self.assertEqual(respuesta.status_code, estado, respuesta.text)
        detalle = respuesta.json()["detail"]
        self.assertEqual(detalle["code"], codigo)
        self.assertEqual(detalle["message"], CATALOGO_ESPERADO[codigo][1])
        return detalle


class TestCatalogoCerrado(BaseErroresTests):
    """RNF-01 y §5.4: los diez códigos y sus mensajes literales."""

    def test_el_catalogo_del_dominio_coincide_con_la_spec(self):
        self.assertEqual(set(ERRORES_CUENTA.keys()), set(CATALOGO_ESPERADO.keys()))
        for codigo, (_, mensaje) in CATALOGO_ESPERADO.items():
            with self.subTest(codigo=codigo):
                self.assertEqual(ERRORES_CUENTA[codigo], mensaje)

    def test_invalid_password_esta_en_el_catalogo(self):
        # Su único emisor es la baja de T4; aquí se fija el código y el mensaje.
        self.assert_codigo_mensaje("invalid_password")

    def assert_codigo_mensaje(self, codigo):
        self.assertEqual(
            ERRORES_CUENTA[codigo], CATALOGO_ESPERADO[codigo][1]
        )


class TestErroresDeActualizacion(BaseErroresTests):
    """RF-11, RF-12 y RF-21 a través de `PATCH /users/me`."""

    def test_invalid_email(self):
        self.assert_codigo(
            self._patch({"email": "sin-arroba"}, self._token()),
            400,
            "invalid_email",
        )

    def test_weak_password(self):
        self.assert_codigo(
            self._patch({"new_password": "1234567"}, self._token()),
            400,
            "weak_password",
        )

    def test_password_too_long(self):
        self.assert_codigo(
            self._patch({"new_password": "a" * 73}, self._token()),
            400,
            "password_too_long",
        )

    def test_empty_update(self):
        self.assert_codigo(self._patch({}, self._token()), 400, "empty_update")

    def test_email_already_registered(self):
        self.assert_codigo(
            self._patch({"email": "AJENO@test.com"}, self._token()),
            400,
            "email_already_registered",
        )

    def test_conflict(self):
        obsoleta = SimpleNamespace(
            id=self.usuario.id,
            public_id=self.usuario.public_id,
            email="User@Test.com",
            hashed_password="hash-que-ya-no-existe",
            is_active=True,
        )
        with patch(
            "app.api.deps.user_service.obtener_usuario_por_public_id",
            return_value=obsoleta,
        ):
            respuesta = self._patch({"email": "nuevo@test.com"}, self._token())

        self.assert_codigo(respuesta, 500, "conflict")

    def test_server_error(self):
        token = self._token()
        with patch(
            "app.services.account_service.security.crear_token_acceso",
            side_effect=RuntimeError("fallo de escritura simulado"),
        ):
            respuesta = self._patch({"email": "nuevo@test.com"}, token)

        self.assert_codigo(respuesta, 500, "server_error")


class TestErroresDeSesionYRegistro(BaseErroresTests):
    """RF-19: credenciales inválidas, sesión inválida y registro."""

    def test_invalid_credentials(self):
        respuesta = self.client.post(
            "/auth/login",
            data={"username": "user@test.com", "password": "otra-clave-larga"},
        )

        self.assert_codigo(respuesta, 401, "invalid_credentials")

    def test_unauthorized_sin_token(self):
        respuesta = self.client.get("/users/me")

        self.assert_codigo(respuesta, 401, "unauthorized")

    def test_registro_con_correo_invalido(self):
        respuesta = self.client.post(
            "/users/", json={"email": "sin-arroba", "password": PASSWORD}
        )

        self.assert_codigo(respuesta, 400, "invalid_email")

    def test_registro_con_password_corta(self):
        respuesta = self.client.post(
            "/users/", json={"email": "nuevo@test.com", "password": "1234567"}
        )

        self.assert_codigo(respuesta, 400, "weak_password")

    def test_registro_con_password_demasiado_larga(self):
        respuesta = self.client.post(
            "/users/", json={"email": "nuevo@test.com", "password": "a" * 73}
        )

        self.assert_codigo(respuesta, 400, "password_too_long")


class TestNingunRechazoResponde422(BaseErroresTests):
    """§5.4: la validación explícita sustituye a la del framework."""

    def test_los_rechazos_de_negocio_no_son_422(self):
        token = self._token()
        peticiones = [
            ("patch", {"email": ""}, token),
            ("patch", {"email": "   "}, token),
            ("patch", {"email": "sin-arroba"}, token),
            ("patch", {"new_password": ""}, token),
            ("patch", {"new_password": "1234567"}, token),
            ("patch", {"new_password": "a" * 73}, token),
            ("patch", {}, token),
            ("patch", {"email": "ajeno@test.com"}, token),
        ]

        for metodo, payload, cabecera in peticiones:
            with self.subTest(payload=payload):
                respuesta = getattr(self.client, metodo)(
                    "/users/me",
                    json=payload,
                    headers={"Authorization": f"Bearer {cabecera}"},
                )
                self.assertNotEqual(respuesta.status_code, 422, respuesta.text)
                self.assertIn("detail", respuesta.json())

        registros = [
            {"email": "sin-arroba", "password": PASSWORD},
            {"email": "", "password": PASSWORD},
            {"email": "nuevo@test.com", "password": "1234567"},
            {"email": "nuevo@test.com", "password": "a" * 73},
        ]
        for payload in registros:
            with self.subTest(registro=payload["email"]):
                respuesta = self.client.post("/users/", json=payload)
                self.assertNotEqual(respuesta.status_code, 422, respuesta.text)

        login = self.client.post(
            "/auth/login", data={"username": "user@test.com", "password": "x"}
        )
        self.assertNotEqual(login.status_code, 422, login.text)

        sin_token = self.client.get("/users/me")
        self.assertNotEqual(sin_token.status_code, 422, sin_token.text)


if __name__ == "__main__":
    unittest.main()
