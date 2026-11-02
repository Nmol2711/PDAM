"""Rendimiento del resumen del panel (spec 022, T8).

RNF-4: con 10 000 registros del usuario, de los cuales 6 000 caen en la semana
en curso y 4 000 en días anteriores, el 95 % de las consultas del resumen se
resuelve en menos de 500 ms. Se miden 100 consultas consecutivas de
`dashboard_service.resumen` con el instante y la zona fijos, tras tres llamadas
de calentamiento, y se publica el p50 y el p95 al ejecutar la suite con `-s`.

La medición corresponde al entorno de pruebas (SQLite local, proceso único, sin
red): sirve para detectar regresiones de la consulta y del cálculo, no como
cifra de producción.

La prueba es autocontenida: abre un motor y un archivo SQLite propios dentro de
un directorio temporal creado en `setUpClass`, crea allí el esquema con
`Base.metadata.create_all` y lo borra al terminar. No usa `SessionLocal`, ni
`get_db`, ni variables de entorno, así que la base compartida `api/test.db` no
se lee, no se modifica y ningún archivo queda en el repositorio.

Los días anteriores a la semana se siembran con gramos distintos a los de la
semana: si el filtro de fechas desapareciera, la suma de la serie cambiaría y
la prueba fallaría además de medir.
"""

import statistics
import sys
import tempfile
import time
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db.database import Base
from app.domain import panel
from app.models import models
from app.services import dashboard_service

NOMBRE_BASE = "rendimiento_panel.db"

# Miércoles 28 de octubre de 2026 a las 12:00 UTC, con la zona del servidor
# fija en UTC-5: ni la fecha ni el día de la semana dependen del equipo.
AHORA = datetime(2026, 10, 28, 12, 0, 0, tzinfo=timezone.utc)
ZONA = timezone(timedelta(hours=-5))

TOTAL_REGISTROS = 10_000
EN_SEMANA = 6_000
ANTERIORES = TOTAL_REGISTROS - EN_SEMANA
GRAMOS_EN_SEMANA = 10.0
GRAMOS_ANTERIORES = 99.0

# RNF-4: percentil 95 por debajo de 500 ms.
LIMITE_P95_SEGUNDOS = 0.5
CONSULTAS = 100
CALENTAMIENTO = 3


class TestRendimientoDelResumen(unittest.TestCase):
    """RNF-4: p95 inferior a 500 ms con 10 000 registros del usuario."""

    @classmethod
    def setUpClass(cls):
        # Base y sesión propias: el archivo vive en un directorio temporal y se
        # elimina en `tearDownClass`, así que la suite no comparte ni toca
        # `api/test.db`.
        cls.directorio = tempfile.TemporaryDirectory(prefix="pdam-panel-")
        cls.ruta_base = Path(cls.directorio.name) / NOMBRE_BASE
        cls.engine = create_engine(
            f"sqlite:///{cls.ruta_base}",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=cls.engine)
        cls.fabrica_sesiones = sessionmaker(
            autocommit=False, autoflush=False, bind=cls.engine
        )

        cls._sembrar_escenario()

        # Ventana que consulta el servicio: de la medianoche local del lunes al
        # fin del día local de hoy, ambos en UTC sin zona.
        (
            cls.inicio_semana_utc,
            _,
            cls.fin_dia_utc,
            cls.indice_hoy,
        ) = panel.rango_semana_local(AHORA, ZONA)

        cls.total_sembrado = cls._sembrar_registros()

    @classmethod
    def tearDownClass(cls):
        cls.engine.dispose()
        cls.directorio.cleanup()
        # La prueba no debe dejar archivos: se comprueba con datos, no con fe.
        assert not cls.ruta_base.exists(), (
            f"Quedó el archivo temporal {cls.ruta_base} tras la prueba"
        )

    # --- Escenario ----------------------------------------------------------

    @classmethod
    def _guardar(cls, entidad):
        sesion = cls.fabrica_sesiones()
        try:
            sesion.add(entidad)
            sesion.commit()
            sesion.refresh(entidad)
            return entidad
        finally:
            sesion.close()

    @classmethod
    def _sembrar_escenario(cls):
        """Usuario, dos mascotas dispensables y sus horarios (90 g al día)."""
        cls.usuario = cls._guardar(
            models.User(
                email="dueno@panel-rendimiento.test",
                hashed_password="clave-de-prueba-no-real",
                is_active=True,
            )
        )
        cls.mascotas = (
            cls._crear_mascota("Milo"),
            cls._crear_mascota("Nina"),
        )
        cls._crear_dispensador(cls.mascotas[0], "AA:BB:CC:DD:FF:01")
        cls._crear_dispensador(cls.mascotas[1], "AA:BB:CC:DD:FF:02")
        cls._crear_horario(cls.mascotas[0], "08:00", 50.0)
        cls._crear_horario(cls.mascotas[1], "20:00", 40.0)

    @classmethod
    def _crear_mascota(cls, nombre):
        return cls._guardar(
            models.Pet(
                name=nombre,
                species="perro",
                birth_date=date(2023, 1, 1),
                weight=5.5,
                reproductive_status=False,
                user_id=cls.usuario.id,
            )
        )

    @classmethod
    def _crear_dispensador(cls, mascota, mac):
        return cls._guardar(
            models.Dispenser(
                mac_address=mac,
                mac_normalized=mac.replace(":", "").upper(),
                is_active=True,
                pet_id=mascota.id,
            )
        )

    @classmethod
    def _crear_horario(cls, mascota, hora, gramos):
        return cls._guardar(
            models.Schedule(time=hora, amount=gramos, pet_id=mascota.id)
        )

    @classmethod
    def _fila(cls, indice, creado, gramos):
        mascota = cls.mascotas[indice % len(cls.mascotas)]
        return {
            "user_id": cls.usuario.id,
            "pet_id": mascota.id,
            "pet_name": mascota.name,
            "dispenser_mac_masked": "**:FF:0" + str(indice % 2 + 1),
            "event_type": "feeding_dispensed",
            "outcome": "success",
            "cause": "objetivo_alcanzado",
            "description": "Registro de rendimiento",
            "measured_grams": gramos,
            "created_at": creado,
        }

    @classmethod
    def _sembrar_registros(cls):
        """Inserta 10 000 registros en una sola operación.

        `EN_SEMANA` caen dentro de la ventana del resumen y `ANTERIORES` en los
        30 días previos al inicio de la semana, con gramos distintos para que
        una fuga del filtro de fechas sea visible en la serie.
        """
        filas = []

        # Semana en curso: reparto uniforme de la medianoche del lunes al fin
        # del día local de hoy.
        ventana = (cls.fin_dia_utc - cls.inicio_semana_utc).total_seconds()
        paso = ventana / EN_SEMANA
        for indice in range(EN_SEMANA):
            filas.append(
                cls._fila(
                    indice,
                    cls.inicio_semana_utc + timedelta(seconds=indice * paso),
                    GRAMOS_EN_SEMANA,
                )
            )

        # Días anteriores: 30 días antes del inicio de la semana.
        inicio_anteriores = cls.inicio_semana_utc - timedelta(days=30)
        paso_anterior = (
            (cls.inicio_semana_utc - inicio_anteriores).total_seconds()
            / ANTERIORES
        )
        for indice in range(ANTERIORES):
            filas.append(
                cls._fila(
                    indice,
                    inicio_anteriores + timedelta(seconds=indice * paso_anterior),
                    GRAMOS_ANTERIORES,
                )
            )

        sesion = cls.fabrica_sesiones()
        try:
            sesion.bulk_insert_mappings(models.ActivityLog, filas)
            sesion.commit()
            return sesion.query(models.ActivityLog).filter(
                models.ActivityLog.user_id == cls.usuario.id
            ).count()
        finally:
            sesion.close()

    # --- Consultas ----------------------------------------------------------

    @classmethod
    def _resumen_una_vez(cls):
        """Ejecuta el servicio con el instante y la zona fijos y cierra sesión."""
        sesion = cls.fabrica_sesiones()
        try:
            resumen, calculado = dashboard_service.resumen(
                sesion,
                user_id=cls.usuario.id,
                ahora=AHORA,
                zona=ZONA,
            )
            return resumen, calculado
        finally:
            sesion.close()

    def test_cien_consultas_del_resumen_cumplen_el_p95(self):
        esperado_semana = EN_SEMANA * GRAMOS_EN_SEMANA

        resumen, calculado = self._resumen_una_vez()
        self.assertEqual(calculado, AHORA)
        self.assertEqual(resumen.total_mascotas, len(self.mascotas))
        self.assertEqual(resumen.indice_hoy, self.indice_hoy)
        self.assertEqual(resumen.programado_hoy, 90.0)
        # Solo los registros de la semana aportan a la serie (RF-5).
        self.assertAlmostEqual(sum(resumen.serie_semanal), esperado_semana)

        # Calentamiento: la primera consulta abre conexión y compila la query.
        for _ in range(CALENTAMIENTO):
            self._resumen_una_vez()

        tiempos = []
        for _ in range(CONSULTAS):
            inicio = time.perf_counter()
            resumen, _ = self._resumen_una_vez()
            tiempos.append(time.perf_counter() - inicio)
            self.assertAlmostEqual(
                sum(resumen.serie_semanal),
                esperado_semana,
                msg="La ventana de la semana dejó de filtrar los días anteriores",
            )

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
            f"\nRNF-4 con {self.total_sembrado} registros "
            f"({EN_SEMANA} en la semana, {ANTERIORES} anteriores): "
            f"p50={p50 * 1000:.1f} ms, p95={p95 * 1000:.1f} ms, "
            f"máximo={tiempos[-1] * 1000:.1f} ms en {CONSULTAS} consultas"
        )

        self.assertLess(
            p95,
            LIMITE_P95_SEGUNDOS,
            f"El p95 fue {p95:.3f} s y RNF-4 exige menos de "
            f"{LIMITE_P95_SEGUNDOS * 1000:.0f} ms",
        )

    def test_los_registros_anteriores_a_la_semana_no_entran_en_el_resumen(self):
        resumen, _ = self._resumen_una_vez()

        self.assertGreater(self.total_sembrado, ANTERIORES)
        self.assertAlmostEqual(
            sum(resumen.serie_semanal), EN_SEMANA * GRAMOS_EN_SEMANA
        )
        self.assertNotIn(
            GRAMOS_ANTERIORES,
            resumen.serie_semanal,
            "Un registro anterior a la semana en curso entró en la serie",
        )


if __name__ == "__main__":
    unittest.main()
