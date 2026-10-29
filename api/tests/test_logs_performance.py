"""Rendimiento de la consulta del historial (T7).

RNF-2: con 10 000 registros del usuario y los cuatro filtros aplicados, el 95 %
de las consultas se resuelve en menos de 1 segundo, medido sobre 100 consultas
consecutivas en el entorno de pruebas. La prueba mide `GET /logs/` completo
(validación, `count`, página y serialización) con `time.perf_counter`, descarta
las llamadas de calentamiento y publica el p50 y el p95 al ejecutarse con `-s`
para poder documentarlos.

También comprueba que existe el índice compuesto `(user_id, created_at)` que
sostiene la consulta por usuario y orden, tanto en el modelo como en la base
migrada.
"""

import os
import statistics
import sys
import time
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from sqlalchemy import text
from fastapi.testclient import TestClient

from app.api.deps import get_current_user
from app.db.database import SessionLocal
from app.main import app
from app.models import models

EMAIL = "dueno@rendimiento.test"
EMAIL_AJENO = "ajeno@rendimiento.test"
SECRETO = "clave-de-prueba-que-no-debe-registrarse"

# 10 000 registros repartidos en 20 días.
TOTAL_REGISTROS = 10_000
DIAS = 20
BASE = datetime(2026, 9, 1, 0, 0, 0)

# RNF-2: percentil 95 por debajo de 1 segundo.
LIMITE_P95_SEGUNDOS = 1.0
CONSULTAS = 100
CALENTAMIENTO = 3

# Consulta con los cuatro filtros aplicados.
FILTROS = {
    "event_type": "feeding_dispensed",
    "outcome": "success",
    "from": "2026-09-01T00:00:00Z",
    "to": "2026-09-21T00:00:00Z",
}


class TestRendimientoDeLaConsulta(unittest.TestCase):
    """RNF-2: p95 inferior a 1 s con 10 000 registros y cuatro filtros."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)
        cls._limpiar_base_de_datos()
        cls.usuario = cls._crear_usuario(EMAIL)
        cls.ajeno = cls._crear_usuario(EMAIL_AJENO)
        cls.milo = cls._crear_mascota(cls.usuario, "Milo")
        cls.nina = cls._crear_mascota(cls.usuario, "Nina")
        cls.mascota_ajena = cls._crear_mascota(cls.ajeno, "Pelota")
        cls.total_sembrado = cls._sembrar_historial()

    @classmethod
    def tearDownClass(cls):
        app.dependency_overrides.clear()
        cls._limpiar_base_de_datos()

    # --- Escenario ----------------------------------------------------------

    @classmethod
    def _guardar(cls, entidad):
        sesion = SessionLocal()
        try:
            sesion.add(entidad)
            sesion.commit()
            sesion.refresh(entidad)
            return entidad
        finally:
            sesion.close()

    @classmethod
    def _limpiar_base_de_datos(cls):
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
                models.User,
            ):
                sesion.query(modelo).delete()
            sesion.commit()
        finally:
            sesion.close()

    @classmethod
    def _crear_usuario(cls, email):
        return cls._guardar(
            models.User(email=email, hashed_password=SECRETO, is_active=True)
        )

    @classmethod
    def _crear_mascota(cls, usuario, nombre):
        return cls._guardar(
            models.Pet(
                name=nombre,
                species="perro",
                birth_date=date(2023, 1, 1),
                weight=5.5,
                reproductive_status=False,
                user_id=usuario.id,
            )
        )

    @classmethod
    def _sembrar_historial(cls):
        """Inserta `TOTAL_REGISTROS` filas del usuario en una sola operación."""
        tipos = ("feeding_dispensed", "dispenser_refilled", "pet_updated")
        mascotas = (cls.milo, cls.nina)

        filas = []
        for indice in range(TOTAL_REGISTROS):
            mascota = mascotas[indice % 2]
            tipo = tipos[indice % 3]
            exito = indice % 2 == 0
            filas.append(
                {
                    "user_id": cls.usuario.id,
                    "pet_id": mascota.id,
                    "pet_name": mascota.name,
                    "dispenser_mac_masked": "**:AB:1F",
                    "event_type": tipo,
                    "outcome": "success" if exito else "failure",
                    "cause": None if exito else "sin_reporte",
                    "description": "Registro de rendimiento",
                    "created_at": BASE + timedelta(seconds=indice * 173),
                }
            )

        sesion = SessionLocal()
        try:
            sesion.bulk_insert_mappings(models.ActivityLog, filas)
            sesion.commit()
            cls.total_filtrado = (
                sesion.query(models.ActivityLog)
                .filter(
                    models.ActivityLog.user_id == cls.usuario.id,
                    models.ActivityLog.pet_id == cls.milo.id,
                    models.ActivityLog.event_type == FILTROS["event_type"],
                    models.ActivityLog.outcome == FILTROS["outcome"],
                    models.ActivityLog.created_at
                    >= datetime(2026, 9, 1, 0, 0, 0),
                    models.ActivityLog.created_at
                    <= datetime(2026, 9, 21, 0, 0, 0),
                )
                .count()
            )
            return sesion.query(models.ActivityLog).filter(
                models.ActivityLog.user_id == cls.usuario.id
            ).count()
        finally:
            sesion.close()

    # --- Peticiones ---------------------------------------------------------

    def _get(self, **params):
        app.dependency_overrides[get_current_user] = lambda: self.usuario
        return self.client.get("/logs/", params=params)

    def test_la_consulta_con_cuatro_filtros_cumple_el_p95(self):
        params = dict(FILTROS, pet_id=str(self.milo.id))

        # Calentamiento: el primer acceso abre conexión y compila la consulta.
        for _ in range(CALENTAMIENTO):
            self.assertEqual(self._get(**params).status_code, 200)

        tiempos = []
        for _ in range(CONSULTAS):
            inicio = time.perf_counter()
            respuesta = self._get(**params)
            tiempos.append(time.perf_counter() - inicio)
            self.assertEqual(respuesta.status_code, 200, respuesta.text)

        cuerpo = respuesta.json()
        self.assertEqual(cuerpo["total"], self.total_filtrado)
        self.assertGreater(cuerpo["total"], 0, "La consulta no puede ser vacía")
        self.assertEqual(len(cuerpo["items"]), 50)

        tiempos.sort()
        p50 = statistics.median(tiempos)
        # Percentil 95 por interpolación lineal sobre 100 muestras.
        posicion = (len(tiempos) - 1) * 0.95
        inferior = int(posicion)
        superior = min(inferior + 1, len(tiempos) - 1)
        p95 = tiempos[inferior] + (posicion - inferior) * (
            tiempos[superior] - tiempos[inferior]
        )

        print(
            f"\nRNF-2 con {self.total_sembrado} registros y 4 filtros: "
            f"p50={p50 * 1000:.1f} ms, p95={p95 * 1000:.1f} ms, "
            f"máximo={tiempos[-1] * 1000:.1f} ms en {CONSULTAS} consultas"
        )

        self.assertLess(
            p95,
            LIMITE_P95_SEGUNDOS,
            f"El p95 fue {p95:.3f} s y RNF-2 exige menos de 1 s",
        )

    def test_la_primera_pagina_sin_filtros_tambien_cumple_el_p95(self):
        for _ in range(CALENTAMIENTO):
            self._get()

        tiempos = []
        for _ in range(CONSULTAS):
            inicio = time.perf_counter()
            respuesta = self._get()
            tiempos.append(time.perf_counter() - inicio)
            self.assertEqual(respuesta.status_code, 200, respuesta.text)

        self.assertEqual(respuesta.json()["total"], self.total_sembrado)

        tiempos.sort()
        p95 = tiempos[min(len(tiempos) - 1, int(len(tiempos) * 0.95))]
        print(
            f"Sin filtros con {self.total_sembrado} registros: "
            f"p50={statistics.median(tiempos) * 1000:.1f} ms, "
            f"p95={p95 * 1000:.1f} ms"
        )
        self.assertLess(p95, LIMITE_P95_SEGUNDOS)

    def test_existe_el_indice_compuesto_de_usuario_y_fecha(self):
        # RNF-2 depende de que la consulta por usuario y orden tenga su índice
        # también en una base ya migrada (migración idempotente de T2).
        columnas = [
            fila[2] for fila in _columnas_del_indice("ix_logs_user_id_created_at")
        ]

        self.assertEqual(
            columnas,
            ["user_id", "created_at"],
            "Falta el índice compuesto (user_id, created_at) que sostiene la "
            "consulta por usuario y orden (RNF-2)",
        )


def _columnas_del_indice(nombre):
    """Columnas de un índice de `logs`, para comprobar su composición."""
    sesion = SessionLocal()
    try:
        return sesion.execute(text(f"PRAGMA index_info('{nombre}')")).fetchall()
    finally:
        sesion.close()


if __name__ == "__main__":
    unittest.main()
