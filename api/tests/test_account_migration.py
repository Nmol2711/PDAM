"""Pruebas de la migración de `users.public_id` y de la tabla `revoked_tokens`.

Cubre RF-10, RF-19 y RNF-08, RNF-09 de la spec 015 sobre bases SQLite aisladas
en un directorio temporal: nunca se toca `test.db` ni la base real. El listener
`connect` de `app.db.database` es global para todos los `Engine`, así que basta
con abrir una conexión para que la migración se ejecute igual que al arrancar la
API.
"""

import os
import shutil
import sqlite3
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

from app.db import database
from app.models import models
from app.models.models import Base

# Nombre del índice único que garantiza la unicidad de `users.public_id`.
INDICE_UNICO_PUBLIC_ID = "ux_users_public_id"

# Columnas de `revoked_tokens` segun el plan §6 (RF-10, RF-19).
COLUMNAS_REVOKED_TOKENS = {
    "id",
    "jti",
    "public_id",
    "expires_at",
    "revoked_at",
}


class BaseMigracionCuentaTests(unittest.TestCase):
    """Utilidades comunes: base temporal por prueba y motores a limpiar."""

    def setUp(self):
        self.directorio = tempfile.mkdtemp(prefix="pdam-cuenta-migracion-")
        self._motores = []

    def tearDown(self):
        for motor in self._motores:
            motor.dispose()
        shutil.rmtree(self.directorio, ignore_errors=True)

    def _ruta(self, nombre="pdam.db"):
        return os.path.join(self.directorio, nombre)

    def _motor(self, ruta):
        motor = create_engine(f"sqlite:///{ruta}")
        self._motores.append(motor)
        return motor

    def _conectar(self, motor):
        """Abre y cierra una conexión: dispara el listener `connect`."""
        with motor.connect() as conexion:
            conexion.execute(text("SELECT 1"))

    def _crear_base_legada(self, ruta, correos, columna_public_id=False, valores=None):
        """Crea a mano una base anterior a la 015 (sin `public_id`).

        `columna_public_id` permite simular una migración a medias (columna
        presente con huecos) y `valores` inyecta valores concretos para probar
        duplicados sin pasar por el código de la migración.
        """
        conexion = sqlite3.connect(ruta)
        try:
            columnas = (
                "id INTEGER NOT NULL PRIMARY KEY, "
                "email VARCHAR NOT NULL, "
                "hashed_password VARCHAR NOT NULL, "
                "is_active BOOLEAN"
            )
            if columna_public_id:
                columnas += ", public_id VARCHAR"
            conexion.execute(f"CREATE TABLE users ({columnas})")
            for indice, correo in enumerate(correos, start=1):
                valor = None if valores is None else valores[indice - 1]
                if columna_public_id:
                    conexion.execute(
                        "INSERT INTO users (id, email, hashed_password, is_active, "
                        "public_id) VALUES (?, ?, ?, ?, ?)",
                        (indice, correo, f"hash-{indice}", 1, valor),
                    )
                else:
                    conexion.execute(
                        "INSERT INTO users (id, email, hashed_password, is_active) "
                        "VALUES (?, ?, ?, ?)",
                        (indice, correo, f"hash-{indice}", 1),
                    )
            conexion.commit()
        finally:
            conexion.close()

    def _tablas(self, ruta):
        conexion = sqlite3.connect(ruta)
        try:
            return {
                fila[0]
                for fila in conexion.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
        finally:
            conexion.close()

    def _columnas(self, ruta, tabla):
        conexion = sqlite3.connect(ruta)
        try:
            return [fila[1] for fila in conexion.execute(f"PRAGMA table_info({tabla})")]
        finally:
            conexion.close()

    def _indices(self, ruta, tabla):
        """Índices de la tabla: nombre y si es único (PRAGMA index_list)."""
        conexion = sqlite3.connect(ruta)
        try:
            return {
                fila[1]: bool(fila[2])
                for fila in conexion.execute(f"PRAGMA index_list({tabla})")
            }
        finally:
            conexion.close()

    def _columnas_indice(self, ruta, indice):
        conexion = sqlite3.connect(ruta)
        try:
            return [fila[2] for fila in conexion.execute(f"PRAGMA index_info({indice})")]
        finally:
            conexion.close()

    def _filas(self, ruta, consulta):
        conexion = sqlite3.connect(ruta)
        try:
            return conexion.execute(consulta).fetchall()
        finally:
            conexion.close()

    def _esquema(self, ruta):
        conexion = sqlite3.connect(ruta)
        try:
            return conexion.execute(
                "SELECT type, name, sql FROM sqlite_master "
                "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
            ).fetchall()
        finally:
            conexion.close()


class MigracionPublicIdTests(BaseMigracionCuentaTests):
    """`users.public_id` en bases legadas (RF-10, RF-19)."""

    def test_base_legada_sin_public_id_se_rellena_con_hexadecimales_unicos(self):
        ruta = self._ruta()
        self._crear_base_legada(
            ruta, ["uno@test.com", "dos@test.com", "tres@test.com"]
        )

        self._conectar(self._motor(ruta))

        columnas = self._columnas(ruta, "users")
        self.assertIn("public_id", columnas)

        filas = self._filas(ruta, "SELECT id, email, hashed_password, public_id FROM users")
        self.assertEqual(len(filas), 3)
        valores = []
        for id_usuario, correo, hash_guardado, public_id in filas:
            self.assertIsNotNone(public_id)
            self.assertEqual(len(public_id), 32)
            # `int(..., 16)` falla si el valor no es hexadecimal.
            self.assertEqual(int(public_id, 16), int(public_id, 16))
            self.assertEqual(public_id, public_id.lower())
            valores.append(public_id)
            # El resto de columnas no se altera.
            self.assertEqual(correo, f"{['uno', 'dos', 'tres'][id_usuario - 1]}@test.com")
            self.assertEqual(hash_guardado, f"hash-{id_usuario}")

        self.assertEqual(len(set(valores)), 3)

    def test_indice_unico_public_id_existe_tras_migrar(self):
        ruta = self._ruta()
        self._crear_base_legada(ruta, ["uno@test.com", "dos@test.com"])

        self._conectar(self._motor(ruta))

        indices = self._indices(ruta, "users")
        self.assertIn(INDICE_UNICO_PUBLIC_ID, indices)
        self.assertTrue(indices[INDICE_UNICO_PUBLIC_ID])
        self.assertEqual(
            self._columnas_indice(ruta, INDICE_UNICO_PUBLIC_ID), ["public_id"]
        )

    def test_segunda_apertura_no_modifica_datos_ni_esquema(self):
        ruta = self._ruta()
        self._crear_base_legada(ruta, ["uno@test.com", "dos@test.com"])

        self._conectar(self._motor(ruta))
        datos_antes = self._filas(
            ruta, "SELECT id, email, hashed_password, public_id FROM users ORDER BY id"
        )
        esquema_antes = self._esquema(ruta)
        indices_antes = self._indices(ruta, "users")

        # Simula un proceso nuevo: la migración vuelve a ejecutarse al abrir.
        database.olvidar_migraciones(ruta)
        self._conectar(self._motor(ruta))

        self.assertEqual(
            self._filas(
                ruta,
                "SELECT id, email, hashed_password, public_id FROM users ORDER BY id",
            ),
            datos_antes,
        )
        self.assertEqual(self._esquema(ruta), esquema_antes)
        self.assertEqual(self._indices(ruta, "users"), indices_antes)

    def test_columna_presente_con_huecos_se_completa_sin_tocar_los_existentes(self):
        ruta = self._ruta()
        existente = "a" * 32
        self._crear_base_legada(
            ruta,
            ["uno@test.com", "dos@test.com"],
            columna_public_id=True,
            valores=[existente, None],
        )

        self._conectar(self._motor(ruta))

        filas = dict(self._filas(ruta, "SELECT id, public_id FROM users"))
        self.assertEqual(filas[1], existente)
        self.assertIsNotNone(filas[2])
        self.assertEqual(len(filas[2]), 32)
        self.assertNotEqual(filas[2], existente)

    def test_duplicado_inyectado_aborta_sin_borrar_filas(self):
        ruta = self._ruta()
        duplicado = "b" * 32
        self._crear_base_legada(
            ruta,
            ["uno@test.com", "dos@test.com", "tres@test.com"],
            columna_public_id=True,
            valores=[duplicado, duplicado, "c" * 32],
        )

        with self.assertRaises(RuntimeError):
            self._conectar(self._motor(ruta))

        filas = self._filas(
            ruta, "SELECT id, email, hashed_password, public_id FROM users ORDER BY id"
        )
        self.assertEqual(len(filas), 3)
        self.assertEqual([fila[0] for fila in filas], [1, 2, 3])
        self.assertEqual([fila[3] for fila in filas], [duplicado, duplicado, "c" * 32])
        self.assertEqual([fila[2] for fila in filas], ["hash-1", "hash-2", "hash-3"])
        # El fallo no deja el archivo marcado como migrado.
        self.assertNotIn(ruta, database.BASES_MIGRADAS)


class TablaTokensRevocadosTests(BaseMigracionCuentaTests):
    """Tabla `revoked_tokens` en bases existentes y nuevas (RF-10, RF-19)."""

    def test_base_legada_gana_la_tabla_con_su_indice_sobre_jti(self):
        ruta = self._ruta()
        self._crear_base_legada(ruta, ["uno@test.com"])

        self._conectar(self._motor(ruta))

        self.assertIn("revoked_tokens", self._tablas(ruta))
        self.assertEqual(
            set(self._columnas(ruta, "revoked_tokens")), COLUMNAS_REVOKED_TOKENS
        )

        indices = self._indices(ruta, "revoked_tokens")
        unicos = [nombre for nombre, unico in indices.items() if unico]
        self.assertEqual(len(unicos), 1)
        self.assertEqual(self._columnas_indice(ruta, unicos[0]), ["jti"])

    def test_base_nueva_crea_la_tabla_desde_el_modelo(self):
        ruta = self._ruta()
        motor = self._motor(ruta)
        Base.metadata.create_all(bind=motor)

        self.assertIn("revoked_tokens", self._tablas(ruta))
        self.assertEqual(
            set(self._columnas(ruta, "revoked_tokens")), COLUMNAS_REVOKED_TOKENS
        )

        # En una base nueva el índice único de `public_id` lo crea SQLAlchemy
        # (`ix_users_public_id`); el nombre `ux_users_public_id` es el de la
        # migración de bases existentes, igual que en `dispensers.mac_normalized`.
        indices = self._indices(ruta, "users")
        unicos_public_id = [
            nombre
            for nombre, unico in indices.items()
            if unico and self._columnas_indice(ruta, nombre) == ["public_id"]
        ]
        self.assertEqual(len(unicos_public_id), 1)

    def test_jti_no_se_puede_repetir(self):
        ruta = self._ruta()
        motor = self._motor(ruta)
        Base.metadata.create_all(bind=motor)
        Sesion = sessionmaker(bind=motor)

        ahora = datetime(2026, 10, 29, 12, 0, 0)
        db = Sesion()
        try:
            usuario = models.User(email="uno@test.com", hashed_password="hash")
            db.add(usuario)
            db.commit()

            db.add(
                models.RevokedToken(
                    jti="jti-repetido",
                    public_id=usuario.public_id,
                    expires_at=ahora + timedelta(minutes=30),
                    revoked_at=ahora,
                )
            )
            db.commit()

            db.add(
                models.RevokedToken(
                    jti="jti-repetido",
                    public_id=usuario.public_id,
                    expires_at=ahora + timedelta(minutes=30),
                    revoked_at=ahora,
                )
            )
            with self.assertRaises(IntegrityError):
                db.commit()
        finally:
            db.rollback()
            db.close()


class ModeloUsuarioTests(BaseMigracionCuentaTests):
    """`models.User(...)` directo sigue funcionando sin pasar `public_id`."""

    def test_public_id_se_genera_al_insertar(self):
        ruta = self._ruta()
        motor = self._motor(ruta)
        Base.metadata.create_all(bind=motor)
        Sesion = sessionmaker(bind=motor)

        db = Sesion()
        try:
            primero = models.User(email="uno@test.com", hashed_password="hash")
            segundo = models.User(email="dos@test.com", hashed_password="hash")
            db.add_all([primero, segundo])
            db.commit()

            for usuario in (primero, segundo):
                self.assertIsNotNone(usuario.public_id)
                self.assertEqual(len(usuario.public_id), 32)
                self.assertEqual(usuario.public_id, usuario.public_id.lower())
            self.assertNotEqual(primero.public_id, segundo.public_id)
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
