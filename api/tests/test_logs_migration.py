"""Pruebas de la migración de `logs` y de las tablas nuevas (spec 014, T2).

Cubre RF-3, RF-6, RF-41 y RNF-8 sobre bases SQLite aisladas en un directorio
temporal: nunca se toca `test.db` ni la base real. El listener `connect` de
`app.db.database` es global para todos los `Engine`, así que basta con abrir una
conexión para que la migración se ejecute igual que al arrancar la API.
"""

import os
import shutil
import sqlite3
import sys
import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path
from unittest.mock import patch

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

# Esquema final de `logs` según el plan §6.1. La igualdad es estricta: no debe
# quedar ninguna columna de la implementación legada ni de la descartada.
COLUMNAS_FINALES_LOGS = {
    "id",
    "user_id",
    "pet_id",
    "pet_name",
    "dispenser_id",
    "dispenser_mac_masked",
    "event_type",
    "outcome",
    "cause",
    "description",
    "context",
    "order_id",
    "requested_grams",
    "measured_grams",
    "discounted_grams",
    "resulting_stock",
    "retry_count",
    "created_at",
}

COLUMNAS_FINALES_ORDERS = {
    "id",
    "user_id",
    "pet_id",
    "pet_name",
    "dispenser_id",
    "dispenser_mac_masked",
    "requested_grams",
    "delivered_at",
    "status",
    "closed_at",
    "outcome",
    "cause",
    "measured_grams",
    "discounted_grams",
    "resulting_stock",
    "retry_count",
    "log_id",
}

COLUMNAS_FINALES_QUEUE = {
    "id",
    "dispenser_id",
    "pet_id",
    "schedule_id",
    "amount",
    "scheduled_for",
    "consumed_at",
}

COLUMNAS_FINALES_REFILL = {
    "id",
    "user_id",
    "operation_id",
    "dispenser_id",
    "grams",
    "applied_at",
    "log_id",
}

# Columnas de la implementación parcial descartada que nunca deben sobrevivir.
COLUMNAS_PARCIALES_DESCARTADAS = {
    "resultado",
    "stock_solicitado",
    "stock_medido",
    "stock_resultante",
    "descripcion_contexto",
    "dispensador_mac_parcial",
    "reintentos",
}

# Índices del esquema final de `logs`. El compuesto de usuario y fecha lo añade
# la consulta del historial (T7, RNF-2) y también debe existir en una base
# migrada, no solo en una creada desde cero.
INDICES_LOGS = {
    "ix_logs_id",
    "ix_logs_pet_id",
    "ix_logs_dispenser_id",
    "ix_logs_event_type",
    "ix_logs_outcome",
    "ix_logs_order_id",
    "ix_logs_created_at",
    "ix_logs_user_id_created_at",
}


class BaseMigracionTests(unittest.TestCase):
    """Utilidades comunes: base temporal por prueba y motores a limpiar."""

    def setUp(self):
        self.directorio = tempfile.mkdtemp(prefix="pdam-migracion-")
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

    def _ejecutar_migracion(self, motor):
        """Invoca `_migrar_logs` directamente sobre una conexión cruda."""
        conexion = motor.raw_connection()
        cursor = conexion.cursor()
        try:
            return database._migrar_logs(conexion, cursor)
        finally:
            cursor.close()
            conexion.close()

    def _migrar_en_crudo(self, ruta):
        """Ejecuta `_migrar_logs` con `sqlite3` puro, sin disparar el listener.

        Así se observa el valor devuelto por la propia migración (`True` cuando
        reconstruyó), cosa que no ocurre si la conexión ya migró al abrirse.
        """
        conexion = sqlite3.connect(ruta)
        try:
            cursor = conexion.cursor()
            try:
                return database._migrar_logs(conexion, cursor)
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

    def _claves_foraneas(self, ruta, tabla):
        """Claves foráneas de una tabla: (tabla_destino, origen, on_delete, ...)."""
        conexion = sqlite3.connect(ruta)
        try:
            return list(conexion.execute(f"PRAGMA foreign_key_list({tabla})"))
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

    # --- Constructores de bases de datos ---

    def _crear_base_legada(self, ruta, filas):
        """Esquema anterior a la 014: `logs(id, event, timestamp, user_id, pet_id)`.

        Replica la FK `ON DELETE SET NULL` de `pet_id`, que es exactamente lo que
        la reconstrucción debe eliminar (RF-6, RF-27).
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
                CREATE TABLE logs (
                    id INTEGER NOT NULL PRIMARY KEY,
                    event VARCHAR NOT NULL,
                    timestamp DATETIME,
                    user_id INTEGER,
                    pet_id INTEGER,
                    FOREIGN KEY(user_id) REFERENCES users (id),
                    FOREIGN KEY(pet_id) REFERENCES pets (id) ON DELETE SET NULL
                );
                CREATE INDEX ix_logs_id ON logs (id);
                INSERT INTO users (id, email) VALUES (7, 'dueno@test.com');
                INSERT INTO pets (id, name) VALUES (3, 'Milo');
                """
            )
            conexion.executemany(
                "INSERT INTO logs (id, event, timestamp, user_id, pet_id) "
                "VALUES (?, ?, ?, ?, ?)",
                filas,
            )
            conexion.commit()
        finally:
            conexion.close()

    def _crear_base_parcial(self, ruta, filas):
        """Esquema con las columnas de la implementación parcial descartada."""
        conexion = sqlite3.connect(ruta)
        try:
            conexion.executescript(
                """
                CREATE TABLE users (
                    id INTEGER NOT NULL PRIMARY KEY,
                    email VARCHAR NOT NULL
                );
                CREATE TABLE pets (
                    id INTEGER NOT NULL PRIMARY KEY,
                    name VARCHAR NOT NULL
                );
                CREATE TABLE logs (
                    id INTEGER NOT NULL PRIMARY KEY,
                    description VARCHAR NOT NULL,
                    resultado VARCHAR,
                    stock_solicitado FLOAT,
                    stock_medido FLOAT,
                    stock_resultante FLOAT,
                    descripcion_contexto TEXT,
                    dispensador_mac_parcial VARCHAR,
                    reintentos INTEGER,
                    user_id INTEGER,
                    pet_id INTEGER,
                    created_at DATETIME
                );
                INSERT INTO users (id, email) VALUES (7, 'dueno@test.com');
                INSERT INTO pets (id, name) VALUES (3, 'Milo');
                """
            )
            conexion.executemany(
                "INSERT INTO logs (id, description, resultado, stock_solicitado, "
                "stock_medido, stock_resultante, descripcion_contexto, "
                "dispensador_mac_parcial, reintentos, user_id, pet_id, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                filas,
            )
            conexion.commit()
        finally:
            conexion.close()


class TestBaseNueva(BaseMigracionTests):
    def test_crea_el_esquema_final_y_la_migracion_no_actua(self):
        ruta = self._ruta()
        motor = self._motor(ruta)

        Base.metadata.create_all(motor)

        self.assertEqual(set(self._columnas(ruta, "logs")), COLUMNAS_FINALES_LOGS)
        self.assertEqual(set(self._columnas(ruta, "dispensing_orders")), COLUMNAS_FINALES_ORDERS)
        self.assertEqual(set(self._columnas(ruta, "dispensing_queue")), COLUMNAS_FINALES_QUEUE)
        self.assertEqual(set(self._columnas(ruta, "refill_operations")), COLUMNAS_FINALES_REFILL)

        # La base nueva no necesita reconstrucción.
        self.assertFalse(self._ejecutar_migracion(motor))
        self.assertEqual(set(self._columnas(ruta, "logs")), COLUMNAS_FINALES_LOGS)

    def test_completa_el_indice_compuesto_que_falta_sin_reconstruir(self):
        # T7: una base que ya tiene el esquema final pero le falta el índice de
        # la consulta recibe el índice al abrirse, sin perder filas (RNF-2).
        ruta = self._ruta()
        motor = self._motor(ruta)
        Base.metadata.create_all(motor)
        # Se libera la conexión para que la siguiente apertura dispare de nuevo
        # el listener `connect`.
        motor.dispose()
        conexion = sqlite3.connect(ruta)
        try:
            conexion.execute("DROP INDEX ix_logs_user_id_created_at")
            conexion.commit()
        finally:
            conexion.close()
        self.assertNotIn("ix_logs_user_id_created_at", self._indices(ruta, "logs"))

        # El índice se borró por fuera de SQLAlchemy; se olvida la marca de este
        # proceso para simular el arranque de uno nuevo que debe repararlo.
        database.olvidar_migraciones(ruta)
        self._conectar(self._motor(ruta))

        self.assertIn("ix_logs_user_id_created_at", self._indices(ruta, "logs"))
        self.assertEqual(set(self._columnas(ruta, "logs")), COLUMNAS_FINALES_LOGS)

    def test_crea_los_indices_de_consulta_y_de_las_tablas_nuevas(self):
        ruta = self._ruta()
        motor = self._motor(ruta)
        Base.metadata.create_all(motor)

        self.assertEqual(self._indices(ruta, "logs"), INDICES_LOGS)
        indices_orders = self._indices(ruta, "dispensing_orders")
        self.assertIn("ix_dispensing_orders_status_delivered_at", indices_orders)
        self.assertIn("ix_dispensing_orders_dispenser_id_status", indices_orders)
        self.assertIn(
            database.INDICE_UNICO_ORDEN_PENDIENTE,
            indices_orders,
            "El índice único parcial debe crearse también en una base nueva",
        )

    def test_completa_el_indice_parcial_de_orden_pendiente_que_falta(self):
        # Una base ya creada no recibe índices nuevos de `create_all`; la
        # migración debe añadir el índice parcial sin reconstruir la tabla.
        ruta = self._ruta()
        motor = self._motor(ruta)
        Base.metadata.create_all(motor)
        motor.dispose()

        conexion = sqlite3.connect(ruta)
        try:
            conexion.execute(
                f"DROP INDEX {database.INDICE_UNICO_ORDEN_PENDIENTE}"
            )
            conexion.commit()
        finally:
            conexion.close()
        self.assertNotIn(
            database.INDICE_UNICO_ORDEN_PENDIENTE,
            self._indices(ruta, "dispensing_orders"),
        )

        database.olvidar_migraciones(ruta)
        self._conectar(self._motor(ruta))

        self.assertIn(
            database.INDICE_UNICO_ORDEN_PENDIENTE,
            self._indices(ruta, "dispensing_orders"),
        )
        self.assertEqual(set(self._columnas(ruta, "dispensing_orders")), COLUMNAS_FINALES_ORDERS)

    def test_no_repite_la_migracion_en_otra_conexion_del_mismo_proceso(self):
        # La bandera por archivo y proceso evita repetir el DDL en cada conexión
        # del pool (punto 4 de la revisión de la spec 014).
        ruta = self._ruta()
        self._crear_base_legada(
            ruta,
            [
                (1, "Comida dispensada", "2026-01-02 03:04:05", 7, 3),
            ],
        )
        database.olvidar_migraciones(ruta)
        self._conectar(self._motor(ruta))

        with patch.object(
            database, "_migrar_logs", wraps=database._migrar_logs
        ) as espia:
            self._conectar(self._motor(ruta))
            espia.assert_not_called()


class TestBaseLegada(BaseMigracionTests):
    FILAS = [
        (1, "Comida dispensada", "2026-01-02 03:04:05", 7, 3),
        (2, "Mascota creada", "2026-01-03 03:04:05", 7, None),
    ]

    def test_reconstruye_y_conserva_las_filas_como_sin_clasificar(self):
        ruta = self._ruta()
        self._crear_base_legada(ruta, self.FILAS)

        self._conectar(self._motor(ruta))

        columnas = set(self._columnas(ruta, "logs"))
        self.assertEqual(columnas, COLUMNAS_FINALES_LOGS)
        self.assertNotIn("event", columnas)
        self.assertNotIn("timestamp", columnas)

        filas = self._filas(
            ruta,
            "SELECT id, user_id, pet_id, pet_name, description, created_at, "
            "event_type, outcome, cause, context, order_id, requested_grams, "
            "measured_grams, discounted_grams, resulting_stock, retry_count, "
            "dispenser_id, dispenser_mac_masked FROM logs ORDER BY id",
        )
        self.assertEqual(len(filas), len(self.FILAS))

        primera = filas[0]
        self.assertEqual(primera[0], 1)                      # id
        self.assertEqual(primera[1], 7)                      # user_id
        self.assertEqual(primera[2], 3)                      # pet_id
        self.assertEqual(primera[3], "Milo")                 # pet_name desde pets
        self.assertEqual(primera[4], "Comida dispensada")    # description = event
        self.assertEqual(primera[5], "2026-01-02 03:04:05")  # created_at = timestamp
        # Campos tipados y métricas en NULL: «Sin clasificar» (RF-41).
        for valor in primera[6:]:
            self.assertIsNone(valor, f"Se esperaba NULL y llegó {valor!r}")

        segunda = filas[1]
        self.assertIsNone(segunda[2])                        # mascota ya eliminada
        self.assertIsNone(segunda[3])                        # sin nombre que copiar

    def test_crea_las_tablas_nuevas_en_una_base_existente(self):
        ruta = self._ruta()
        self._crear_base_legada(ruta, self.FILAS)
        motor = self._motor(ruta)
        self._conectar(motor)

        Base.metadata.create_all(motor)

        tablas = self._tablas(ruta)
        for tabla in ("dispensing_orders", "dispensing_queue", "refill_operations"):
            self.assertIn(tabla, tablas)
        # `create_all` no altera `logs`, que ya quedó reconstruida.
        self.assertEqual(set(self._columnas(ruta, "logs")), COLUMNAS_FINALES_LOGS)

    def test_crea_los_indices_de_logs_tras_reconstruir(self):
        ruta = self._ruta()
        self._crear_base_legada(ruta, self.FILAS)

        self._conectar(self._motor(ruta))

        self.assertEqual(self._indices(ruta, "logs"), INDICES_LOGS)

    def test_borrar_la_mascota_no_anula_pet_id_ni_dispenser_id(self):
        ruta = self._ruta()
        self._crear_base_legada(ruta, self.FILAS)
        motor = self._motor(ruta)
        self._conectar(motor)

        # El esquema reconstruido no debe conservar la FK `ON DELETE SET NULL`.
        conexion = sqlite3.connect(ruta)
        try:
            conexion.execute("PRAGMA foreign_keys = ON")
            conexion.execute("DELETE FROM pets WHERE id = 3")
            conexion.commit()
        finally:
            conexion.close()

        filas = self._filas(ruta, "SELECT id, pet_id, pet_name FROM logs ORDER BY id")
        self.assertEqual(filas[0][1], 3, "logs.pet_id debe sobrevivir al borrado (RF-6)")
        self.assertEqual(filas[0][2], "Milo", "pet_name es una instantánea")

    def test_borrar_el_dispensador_no_anula_dispenser_id(self):
        """Comprueba `dispenser_id` con una fila que sí lo informa."""
        ruta = self._ruta()
        motor = self._motor(ruta)
        Base.metadata.create_all(motor)

        Sesion = sessionmaker(bind=motor)
        sesion = Sesion()
        try:
            usuario = models.User(email="dueno@test.com", hashed_password="hash")
            sesion.add(usuario)
            sesion.commit()
            mascota = models.Pet(
                name="Milo",
                species="perro",
                birth_date=date(2023, 1, 1),
                weight=5.5,
                reproductive_status=False,
                user_id=usuario.id,
            )
            sesion.add(mascota)
            sesion.commit()
            dispensador = models.Dispenser(
                mac_address="AA:BB:CC:DD:AB:1F",
                mac_normalized="AABBCCDDAB1F",
                pet_id=mascota.id,
            )
            sesion.add(dispensador)
            sesion.commit()
            log = models.ActivityLog(
                user_id=usuario.id,
                pet_id=mascota.id,
                pet_name="Milo",
                dispenser_id=dispensador.id,
                dispenser_mac_masked="**:AB:1F",
                description="Comida dispensada",
                created_at=datetime(2026, 1, 2, 3, 4, 5),
            )
            sesion.add(log)
            sesion.commit()
            id_mascota = mascota.id
            id_dispensador = dispensador.id
            id_log = log.id
        finally:
            sesion.close()

        conexion = sqlite3.connect(ruta)
        try:
            conexion.execute("PRAGMA foreign_keys = ON")
            conexion.execute("DELETE FROM pets WHERE id = ?", (id_mascota,))
            conexion.commit()
        finally:
            conexion.close()

        filas = self._filas(
            ruta,
            f"SELECT pet_id, pet_name, dispenser_id FROM logs WHERE id = {id_log}",
        )
        self.assertEqual(filas[0][0], id_mascota)
        self.assertEqual(filas[0][1], "Milo")
        self.assertEqual(filas[0][2], id_dispensador)


class TestColumnasParciales(BaseMigracionTests):
    FILAS = [
        (
            5,
            "Comida dispensada",
            "exito",
            50.0,
            48.0,
            500.0,
            '{"faltante": 0}',
            "**:AB:1F",
            2,
            7,
            3,
            "2026-02-03 04:05:06",
        )
    ]

    def test_reconstruye_sin_dejar_columnas_viejas(self):
        ruta = self._ruta()
        self._crear_base_parcial(ruta, self.FILAS)

        self._conectar(self._motor(ruta))

        columnas = set(self._columnas(ruta, "logs"))
        self.assertEqual(columnas, COLUMNAS_FINALES_LOGS)
        self.assertEqual(columnas & COLUMNAS_PARCIALES_DESCARTADAS, set())

        filas = self._filas(
            ruta,
            "SELECT id, user_id, pet_id, pet_name, description, created_at, "
            "event_type, outcome, cause, context, order_id, requested_grams, "
            "measured_grams, discounted_grams, resulting_stock, retry_count, "
            "dispenser_id, dispenser_mac_masked FROM logs",
        )
        self.assertEqual(len(filas), len(self.FILAS))
        fila = filas[0]
        self.assertEqual(fila[0], 5)
        self.assertEqual(fila[1], 7)
        self.assertEqual(fila[2], 3)
        self.assertEqual(fila[3], "Milo")
        self.assertEqual(fila[4], "Comida dispensada")
        self.assertEqual(fila[5], "2026-02-03 04:05:06")
        for valor in fila[6:]:
            self.assertIsNone(valor, f"Se esperaba NULL y llegó {valor!r}")


class TestDisparadorDeReconstruccion(BaseMigracionTests):
    """El disparador mira el esquema final completo, no solo tres columnas.

    Una base puede tener ya `event_type`, `description` y `created_at`, y aun así
    estar incompleta (le faltan `pet_name`, `order_id` o `dispenser_id`) o
    conservar la FK `ON DELETE SET NULL` de `pet_id`, que anula la referencia al
    borrar la mascota (RF-6). SQLite expone la acción de borrado en la columna
    `on_delete` de `PRAGMA foreign_key_list`, así que ese caso sí es detectable.
    """

    # Tipos del esquema final (plan §6.1), solo para construir las bases de prueba.
    TIPOS = {
        "id": "INTEGER NOT NULL PRIMARY KEY",
        "user_id": "INTEGER",
        "pet_id": "INTEGER",
        "pet_name": "VARCHAR",
        "dispenser_id": "INTEGER",
        "dispenser_mac_masked": "VARCHAR",
        "event_type": "VARCHAR",
        "outcome": "VARCHAR",
        "cause": "VARCHAR",
        "description": "VARCHAR NOT NULL",
        "context": "TEXT",
        "order_id": "INTEGER",
        "requested_grams": "FLOAT",
        "measured_grams": "FLOAT",
        "discounted_grams": "FLOAT",
        "resulting_stock": "FLOAT",
        "retry_count": "INTEGER",
        "created_at": "DATETIME NOT NULL",
    }

    FILAS = [
        (1, 7, 3, "Comida dispensada", "2026-01-02 03:04:05"),
        (2, 7, None, "Mascota creada", "2026-01-03 03:04:05"),
    ]

    def _crear_base_con_columnas(self, ruta, omitidas=(), fk_pet_anulable=False):
        """Crea `logs` con las columnas finales menos `omitidas`.

        Opcionalmente añade la FK `pet_id -> pets ON DELETE SET NULL` del esquema
        legado, que la reconstrucción debe eliminar.
        """
        definiciones = [
            f"{nombre} {self.TIPOS[nombre]}"
            for nombre in sorted(COLUMNAS_FINALES_LOGS)
            if nombre not in omitidas
        ]
        if fk_pet_anulable:
            definiciones.append(
                "FOREIGN KEY(pet_id) REFERENCES pets (id) ON DELETE SET NULL"
            )

        conexion = sqlite3.connect(ruta)
        try:
            conexion.executescript(
                f"""
                PRAGMA foreign_keys = ON;
                CREATE TABLE users (
                    id INTEGER NOT NULL PRIMARY KEY,
                    email VARCHAR NOT NULL
                );
                CREATE TABLE pets (
                    id INTEGER NOT NULL PRIMARY KEY,
                    name VARCHAR NOT NULL
                );
                CREATE TABLE logs (
                    {", ".join(definiciones)}
                );
                INSERT INTO users (id, email) VALUES (7, 'dueno@test.com');
                INSERT INTO pets (id, name) VALUES (3, 'Milo');
                """
            )
            conexion.executemany(
                "INSERT INTO logs (id, user_id, pet_id, description, created_at) "
                "VALUES (?, ?, ?, ?, ?)",
                self.FILAS,
            )
            conexion.commit()
        finally:
            conexion.close()

    def test_la_lista_de_columnas_finales_coincide_con_el_plan(self):
        self.assertEqual(set(database.COLUMNAS_LOGS), COLUMNAS_FINALES_LOGS)
        self.assertEqual(
            len(database.COLUMNAS_LOGS),
            len(set(database.COLUMNAS_LOGS)),
            "La lista de columnas finales no debe repetir nombres",
        )

    def test_reconstruye_si_falta_pet_name_order_id_o_dispenser_id(self):
        ruta = self._ruta()
        omitidas = {"pet_name", "order_id", "dispenser_id"}
        self._crear_base_con_columnas(ruta, omitidas=omitidas)
        self.assertEqual(
            set(self._columnas(ruta, "logs")),
            COLUMNAS_FINALES_LOGS - omitidas,
        )

        self.assertTrue(self._migrar_en_crudo(ruta))

        self.assertEqual(set(self._columnas(ruta, "logs")), COLUMNAS_FINALES_LOGS)
        self.assertEqual(self._indices(ruta, "logs"), INDICES_LOGS)

        filas = self._filas(
            ruta,
            "SELECT id, pet_name, order_id, dispenser_id, description, created_at "
            "FROM logs ORDER BY id",
        )
        self.assertEqual(len(filas), len(self.FILAS))
        self.assertEqual(filas[0][0], 1)
        self.assertEqual(filas[0][1], "Milo", "pet_name se rellena desde pets")
        self.assertIsNone(filas[0][2])
        self.assertIsNone(filas[0][3])
        self.assertEqual(filas[0][4], "Comida dispensada")
        self.assertEqual(filas[0][5], "2026-01-02 03:04:05")

    def test_reconstruye_si_pet_id_conserva_la_fk_on_delete_set_null(self):
        ruta = self._ruta()
        self._crear_base_con_columnas(ruta, fk_pet_anulable=True)
        self.assertEqual(set(self._columnas(ruta, "logs")), COLUMNAS_FINALES_LOGS)

        def anulables(tabla):
            return [
                fila
                for fila in self._claves_foraneas(ruta, tabla)
                if fila[2] == "pets"
                and fila[3] == "pet_id"
                and (fila[6] or "").upper() == "SET NULL"
            ]

        # SQLite informa de la acción de borrado: el caso es detectable aunque
        # todas las columnas finales estén presentes.
        self.assertEqual(len(anulables("logs")), 1)

        self.assertTrue(self._migrar_en_crudo(ruta))

        self.assertEqual(anulables("logs"), [])
        self.assertEqual(set(self._columnas(ruta, "logs")), COLUMNAS_FINALES_LOGS)

        # La referencia sobrevive al borrado de la mascota (RF-6).
        conexion = sqlite3.connect(ruta)
        try:
            conexion.execute("PRAGMA foreign_keys = ON")
            conexion.execute("DELETE FROM pets WHERE id = 3")
            conexion.commit()
        finally:
            conexion.close()

        filas = self._filas(ruta, "SELECT pet_id, pet_name FROM logs ORDER BY id")
        self.assertEqual(filas[0][0], 3)
        self.assertEqual(filas[0][1], "Milo")


class TestMigracionSegura(BaseMigracionTests):
    def test_si_la_copia_no_coincide_no_borra_la_tabla_original(self):
        ruta = self._ruta()
        self._crear_base_legada(
            ruta,
            [
                (1, "Comida dispensada", "2026-01-02 03:04:05", 7, 3),
                (2, "Mascota creada", "2026-01-02 03:04:05", 7, 3),
            ],
        )

        motor = self._motor(ruta)
        with patch("app.db.database._copiar_filas_logs", return_value=1):
            with self.assertRaises(RuntimeError):
                motor.connect().close()
        motor.dispose()

        columnas = set(self._columnas(ruta, "logs"))
        self.assertIn("event", columnas)
        self.assertNotIn("event_type", columnas)
        self.assertEqual(len(self._filas(ruta, "SELECT id FROM logs")), 2)
        self.assertNotIn("logs_nueva", self._tablas(ruta))

    def test_la_segunda_apertura_no_cambia_nada(self):
        ruta = self._ruta()
        self._crear_base_legada(
            ruta,
            [
                (1, "Comida dispensada", "2026-01-02 03:04:05", 7, 3),
                (2, "Mascota creada", "2026-01-03 03:04:05", 7, None),
            ],
        )

        primer_motor = self._motor(ruta)
        self._conectar(primer_motor)
        esquema_inicial = self._esquema(ruta)
        filas_iniciales = self._filas(ruta, "SELECT * FROM logs ORDER BY id")
        primer_motor.dispose()

        segundo_motor = self._motor(ruta)
        self._conectar(segundo_motor)

        self.assertEqual(self._esquema(ruta), esquema_inicial)
        self.assertEqual(
            self._filas(ruta, "SELECT * FROM logs ORDER BY id"), filas_iniciales
        )
        self.assertFalse(self._ejecutar_migracion(segundo_motor))


class TestRestriccionesTablasNuevas(BaseMigracionTests):
    def setUp(self):
        super().setUp()
        self.ruta = self._ruta()
        self.motor = self._motor(self.ruta)
        Base.metadata.create_all(self.motor)
        self.sesion = sessionmaker(bind=self.motor)()
        self.usuario = models.User(email="dueno@test.com", hashed_password="hash")
        self.sesion.add(self.usuario)
        self.sesion.commit()
        self.mascota = models.Pet(
            name="Milo",
            species="perro",
            birth_date=date(2023, 1, 1),
            weight=5.5,
            reproductive_status=False,
            user_id=self.usuario.id,
        )
        self.sesion.add(self.mascota)
        self.sesion.commit()
        self.dispensador = models.Dispenser(
            mac_address="AA:BB:CC:DD:AB:1F",
            mac_normalized="AABBCCDDAB1F",
            pet_id=self.mascota.id,
        )
        self.horario = models.Schedule(time="08:00", amount=50, pet_id=self.mascota.id)
        self.sesion.add_all([self.dispensador, self.horario])
        self.sesion.commit()

    def tearDown(self):
        self.sesion.close()
        super().tearDown()

    def test_refill_operations_no_duplica_operation_id_por_usuario(self):
        def crear():
            return models.RefillOperation(
                user_id=self.usuario.id,
                operation_id="op-1",
                dispenser_id=self.dispensador.id,
                grams=100.0,
                applied_at=datetime(2026, 3, 1, 10, 0, 0),
            )

        self.sesion.add(crear())
        self.sesion.commit()
        self.sesion.add(crear())
        with self.assertRaises(IntegrityError):
            self.sesion.commit()
        self.sesion.rollback()

    def test_dispensing_queue_no_duplica_la_misma_ocurrencia(self):
        ocurrencia = datetime(2026, 3, 1, 8, 0, 0)

        def crear():
            return models.DispensingQueue(
                dispenser_id=self.dispensador.id,
                pet_id=self.mascota.id,
                schedule_id=self.horario.id,
                amount=50.0,
                scheduled_for=ocurrencia,
            )

        self.sesion.add(crear())
        self.sesion.commit()
        self.sesion.add(crear())
        with self.assertRaises(IntegrityError):
            self.sesion.commit()
        self.sesion.rollback()


if __name__ == "__main__":
    unittest.main()
