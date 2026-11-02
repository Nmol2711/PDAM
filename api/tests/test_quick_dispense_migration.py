"""Pruebas de la migración de `manual_dispensing_requests` (spec 020, T1).

Cubre RF-14 sobre bases SQLite aisladas en un directorio temporal: nunca se toca
`test.db` ni la base real. Una base anterior a la spec 020 no tiene
`operation_id`; al abrirla, el listener `connect` de `app.db.database` añade la
columna, rellena las filas existentes con `legado:<id>` y crea el índice único
`(dispenser_id, operation_id)` sin borrar datos. Una base nueva recibe la
columna y el índice de `Base.metadata.create_all`.

El listener `connect` es global para todos los `Engine`, así que basta con abrir
una conexión para que la migración se ejecute igual que al arrancar la API.
"""

import os
import shutil
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError

from app.db import database
from app.models.models import Base

# Esquema final de la tabla (plan 020): `operation_id` se añadió en T1.
COLUMNAS_FINALES_SOLICITUDES = {
    "id",
    "dispenser_id",
    "pet_id",
    "amount",
    "operation_id",
    "requested_at",
    "consumed_at",
}

# Filas de la base anterior a la 020: (id, dispenser_id, pet_id, amount,
# requested_at, consumed_at).
FILAS_ANTIGUAS = [
    (1, 4, 3, 50.0, "2026-10-01 08:00:00", None),
    (2, 4, 3, 30.5, "2026-10-01 09:30:00", "2026-10-01 09:35:00"),
]


class BaseMigracionSolicitudesTests(unittest.TestCase):
    """Utilidades comunes: base temporal por prueba y motores a limpiar."""

    def setUp(self):
        self.directorio = tempfile.mkdtemp(prefix="pdam-migracion-rapida-")
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

    def _migrar_en_crudo(self, ruta):
        """Ejecuta la migración con `sqlite3` puro, sin disparar el listener."""
        conexion = sqlite3.connect(ruta)
        try:
            cursor = conexion.cursor()
            try:
                database._migrar_solicitudes_rapidas(conexion, cursor)
            finally:
                cursor.close()
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
        conexion = sqlite3.connect(ruta)
        try:
            return {
                fila[0]
                for fila in conexion.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ?",
                    (tabla,),
                )
            }
        finally:
            conexion.close()

    def _filas(self, ruta, consulta):
        conexion = sqlite3.connect(ruta)
        try:
            return conexion.execute(consulta).fetchall()
        finally:
            conexion.close()

    def _esquema(self, ruta, tabla):
        conexion = sqlite3.connect(ruta)
        try:
            return conexion.execute(
                "SELECT type, name, sql FROM sqlite_master "
                "WHERE tbl_name = ? OR name = ? ORDER BY type, name",
                (tabla, tabla),
            ).fetchall()
        finally:
            conexion.close()

    # --- Constructores de bases de datos ---

    def _crear_base_antigua(self, ruta, filas=FILAS_ANTIGUAS):
        """Esquema anterior a la 020: sin `operation_id` ni índice único.

        Replica la FK `ON DELETE CASCADE` del dispensador para comprobar que la
        migración no reconstruye la tabla ni pierde la cascada (RF-16).
        """
        conexion = sqlite3.connect(ruta)
        try:
            conexion.executescript(
                """
                PRAGMA foreign_keys = ON;
                CREATE TABLE users (
                    id INTEGER NOT NULL PRIMARY KEY,
                    email VARCHAR NOT NULL
                );
                CREATE TABLE pets (
                    id INTEGER NOT NULL PRIMARY KEY,
                    name VARCHAR NOT NULL
                );
                CREATE TABLE dispensers (
                    id INTEGER NOT NULL PRIMARY KEY,
                    mac_address VARCHAR NOT NULL,
                    pet_id INTEGER NOT NULL,
                    FOREIGN KEY(pet_id) REFERENCES pets (id) ON DELETE CASCADE
                );
                CREATE TABLE manual_dispensing_requests (
                    id INTEGER NOT NULL PRIMARY KEY,
                    dispenser_id INTEGER NOT NULL,
                    pet_id INTEGER,
                    amount FLOAT NOT NULL,
                    requested_at DATETIME NOT NULL,
                    consumed_at DATETIME,
                    FOREIGN KEY(dispenser_id) REFERENCES dispensers (id)
                        ON DELETE CASCADE
                );
                CREATE INDEX ix_manual_dispensing_pending
                    ON manual_dispensing_requests (
                        dispenser_id, consumed_at, requested_at
                    );
                INSERT INTO users (id, email) VALUES (7, 'dueno@test.com');
                INSERT INTO pets (id, name) VALUES (3, 'Milo');
                INSERT INTO dispensers (id, mac_address, pet_id)
                    VALUES (4, 'AA:BB:CC:DD:AB:1F', 3);
                INSERT INTO dispensers (id, mac_address, pet_id)
                    VALUES (5, 'AA:BB:CC:DD:AB:20', 3);
                """
            )
            conexion.executemany(
                "INSERT INTO manual_dispensing_requests "
                "(id, dispenser_id, pet_id, amount, requested_at, consumed_at) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                filas,
            )
            conexion.commit()
        finally:
            conexion.close()

    def _insertar_solicitud(self, ruta, id_solicitud, dispenser_id, operation_id):
        conexion = sqlite3.connect(ruta)
        try:
            conexion.execute(
                "INSERT INTO manual_dispensing_requests "
                "(id, dispenser_id, pet_id, amount, operation_id, requested_at) "
                "VALUES (?, ?, 3, 10.0, ?, '2026-10-02 10:00:00')",
                (id_solicitud, dispenser_id, operation_id),
            )
            conexion.commit()
        finally:
            conexion.close()


class TestBaseNueva(BaseMigracionSolicitudesTests):
    def test_crea_la_columna_y_el_indice_unico_sin_migrar(self):
        ruta = self._ruta()
        motor = self._motor(ruta)

        Base.metadata.create_all(motor)

        self.assertEqual(
            set(self._columnas(ruta, "manual_dispensing_requests")),
            COLUMNAS_FINALES_SOLICITUDES,
        )
        indices = self._indices(ruta, "manual_dispensing_requests")
        self.assertIn(database.INDICE_UNICO_SOLICITUD_RAPIDA, indices)
        self.assertIn("ix_manual_dispensing_pending", indices)

    def test_la_migracion_no_actua_si_la_tabla_no_existe(self):
        ruta = self._ruta()
        conexion = sqlite3.connect(ruta)
        try:
            conexion.execute(
                "CREATE TABLE users (id INTEGER NOT NULL PRIMARY KEY, email VARCHAR)"
            )
            conexion.commit()
        finally:
            conexion.close()

        self._migrar_en_crudo(ruta)

        self.assertNotIn("manual_dispensing_requests", self._tablas(ruta))


class TestBaseAntigua(BaseMigracionSolicitudesTests):
    def test_la_apertura_anade_la_columna_y_rellena_las_filas(self):
        ruta = self._ruta()
        self._crear_base_antigua(ruta)
        self.assertNotIn(
            "operation_id", self._columnas(ruta, "manual_dispensing_requests")
        )

        self._conectar(self._motor(ruta))

        self.assertEqual(
            set(self._columnas(ruta, "manual_dispensing_requests")),
            COLUMNAS_FINALES_SOLICITUDES,
        )

        filas = self._filas(
            ruta,
            "SELECT id, dispenser_id, pet_id, amount, requested_at, consumed_at, "
            "operation_id FROM manual_dispensing_requests ORDER BY id",
        )
        self.assertEqual(len(filas), len(FILAS_ANTIGUAS))
        for fila, esperada in zip(filas, FILAS_ANTIGUAS):
            self.assertEqual(fila[:6], esperada, "La migración no altera los datos")
            self.assertEqual(
                fila[6],
                f"legado:{fila[0]}",
                "Las filas legadas quedan identificadas por su id",
            )

    def test_la_apertura_crea_el_indice_unico_si_falta(self):
        ruta = self._ruta()
        self._crear_base_antigua(ruta)
        self.assertNotIn(
            database.INDICE_UNICO_SOLICITUD_RAPIDA,
            self._indices(ruta, "manual_dispensing_requests"),
        )

        self._conectar(self._motor(ruta))

        self.assertIn(
            database.INDICE_UNICO_SOLICITUD_RAPIDA,
            self._indices(ruta, "manual_dispensing_requests"),
        )

    def test_el_indice_unico_impide_repetir_la_operacion_por_dispensador(self):
        ruta = self._ruta()
        self._crear_base_antigua(ruta)
        self._conectar(self._motor(ruta))

        # Misma operación en el mismo dispensador: la base la rechaza (RF-14).
        with self.assertRaises(sqlite3.IntegrityError):
            self._insertar_solicitud(ruta, 10, 4, "legado:1")

        # El alcance es el dispensador: otra unidad puede usar el mismo valor.
        self._insertar_solicitud(ruta, 11, 5, "legado:1")
        filas = self._filas(
            ruta,
            "SELECT id, operation_id FROM manual_dispensing_requests "
            "WHERE id = 11",
        )
        self.assertEqual(filas, [(11, "legado:1")])

    def test_un_insert_duplicado_desde_sqlalchemy_tambien_se_rechaza(self):
        ruta = self._ruta()
        self._crear_base_antigua(ruta)
        motor = self._motor(ruta)
        self._conectar(motor)

        with self.assertRaises(IntegrityError):
            with motor.begin() as conexion:
                conexion.execute(
                    text(
                        "INSERT INTO manual_dispensing_requests "
                        "(id, dispenser_id, pet_id, amount, operation_id, "
                        "requested_at) VALUES (12, 4, 3, 10.0, 'legado:2', "
                        "'2026-10-02 10:00:00')"
                    )
                )

    def test_la_segunda_apertura_no_cambia_nada(self):
        ruta = self._ruta()
        self._crear_base_antigua(ruta)

        primer_motor = self._motor(ruta)
        self._conectar(primer_motor)
        esquema_inicial = self._esquema(ruta, "manual_dispensing_requests")
        filas_iniciales = self._filas(
            ruta, "SELECT * FROM manual_dispensing_requests ORDER BY id"
        )
        primer_motor.dispose()

        # Se simula el arranque de un proceso nuevo que vuelve a comprobarlo.
        database.olvidar_migraciones(ruta)
        self._conectar(self._motor(ruta))

        self.assertEqual(
            self._esquema(ruta, "manual_dispensing_requests"), esquema_inicial
        )
        self.assertEqual(
            self._filas(ruta, "SELECT * FROM manual_dispensing_requests ORDER BY id"),
            filas_iniciales,
        )

    def test_la_migracion_directa_es_idempotente(self):
        ruta = self._ruta()
        self._crear_base_antigua(ruta)
        self._conectar(self._motor(ruta))
        esquema = self._esquema(ruta, "manual_dispensing_requests")
        filas = self._filas(
            ruta, "SELECT * FROM manual_dispensing_requests ORDER BY id"
        )

        self._migrar_en_crudo(ruta)

        self.assertEqual(self._esquema(ruta, "manual_dispensing_requests"), esquema)
        self.assertEqual(
            self._filas(ruta, "SELECT * FROM manual_dispensing_requests ORDER BY id"),
            filas,
        )


if __name__ == "__main__":
    unittest.main()
