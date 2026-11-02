"""Resumen del panel con datos reales (spec 022, T2).

Cubre el contrato completo de `GET /dashboard/summary`: las cifras salen solo de
las mascotas, los horarios dispensables y las dispensaciones registradas del
usuario (RF-1 a RF-5), con `weekly_dispensed` de siete posiciones, `today_index`
y `calculated_at` en UTC (RF-6), y sin valores de relleno cuando no hay datos
(RF-7). También comprueba el aislamiento por usuario (RF-1) y que días futuros,
fallos con gramos y éxitos sin gramos se tratan según la spec.

El reloj del endpoint se fija con `unittest.mock`: el instante de referencia es
un miércoles en UTC y los límites del día y de la semana se derivan con
`panel.rango_semana_local`, así que la suite no depende del reloj ni de la zona
del equipo que la ejecuta. Las filas se siembran directamente en las tablas para
controlar `created_at` sin depender de otros servicios.
"""

import os
import sys
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi.testclient import TestClient

from app.api.deps import get_current_user
from app.db.database import SessionLocal
from app.domain import panel, tiempo
from app.main import app
from app.models import models

EMAIL = "dueno@panel.test"
EMAIL_AJENO = "ajeno@panel.test"
SECRETO = "clave-de-prueba-que-no-debe-registrarse"

# Miércoles 28 de octubre de 2026 a las 12:00 UTC. La posición y los límites
# locales se derivan con la zona del servidor, nunca con una fija en la prueba.
AHORA = datetime(2026, 10, 28, 12, 0, 0, tzinfo=timezone.utc)

CAMPOS_ESPERADOS = {
    "total_pets",
    "sterilized_pets",
    "food_dispensed_today",
    "food_target_today",
    "pending_feedings",
    "completed_feedings",
    "weekly_dispensed",
    "today_index",
    "calculated_at",
}


class BaseDashboardTests(unittest.TestCase):
    """Un usuario con sus mascotas y otro usuario ajeno para el aislamiento."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario(EMAIL)
        self.ajeno = self._crear_usuario(EMAIL_AJENO)

        # Límites del día local del servidor para ubicar las filas sembradas.
        (
            self.inicio_semana_utc,
            self.inicio_dia_utc,
            self.fin_dia_utc,
            self.indice_hoy,
        ) = panel.rango_semana_local(AHORA, None)

        # El día anterior se deriva de su propio instante, no restando uno al
        # índice de hoy: así el índice sembrado es válido aunque la zona del
        # equipo desplace la fecha.
        (
            _,
            self.inicio_dia_ayer_utc,
            _,
            self.indice_ayer,
        ) = panel.rango_semana_local(AHORA - timedelta(days=1), None)

        self.ayer_utc = self.inicio_dia_ayer_utc + timedelta(hours=1)
        self.manana_utc = self.fin_dia_utc + timedelta(hours=1)

    def tearDown(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()

    # --- Escenario ----------------------------------------------------------

    def _guardar(self, entidad):
        sesion = SessionLocal()
        try:
            sesion.add(entidad)
            sesion.commit()
            sesion.refresh(entidad)
            return entidad
        finally:
            sesion.close()

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
                models.User,
            ):
                sesion.query(modelo).delete()
            sesion.commit()
        finally:
            sesion.close()

    def _crear_usuario(self, email):
        return self._guardar(
            models.User(email=email, hashed_password=SECRETO, is_active=True)
        )

    def _crear_mascota(self, nombre, *, castrada=False, usuario=None):
        usuario = usuario or self.usuario
        return self._guardar(
            models.Pet(
                name=nombre,
                species="perro",
                birth_date=date(2023, 1, 1),
                weight=5.5,
                reproductive_status=castrada,
                user_id=usuario.id,
            )
        )

    def _crear_dispensador(self, mascota, *, mac, activo=True):
        return self._guardar(
            models.Dispenser(
                mac_address=mac,
                mac_normalized=mac.replace(":", "").upper(),
                is_active=activo,
                pet_id=mascota.id,
            )
        )

    def _crear_horario(self, mascota, *, hora, gramos):
        return self._guardar(
            models.Schedule(time=hora, amount=gramos, pet_id=mascota.id)
        )

    def _anular_estado_del_dispensador(self, dispensador):
        """Deja `is_active` en NULL, como una fila legada.

        El valor por defecto de la columna se aplica al insertar, así que la
        fila se crea activa y se anula después para probar el estado nulo.
        """
        sesion = SessionLocal()
        try:
            sesion.query(models.Dispenser).filter(
                models.Dispenser.id == dispensador.id
            ).update({models.Dispenser.is_active: None})
            sesion.commit()
        finally:
            sesion.close()

    def _crear_log(
        self,
        *,
        usuario=None,
        creado,
        tipo="feeding_dispensed",
        resultado="success",
        medidos=None,
        descontados=None,
    ):
        usuario = usuario or self.usuario
        return self._guardar(
            models.ActivityLog(
                user_id=usuario.id,
                event_type=tipo,
                outcome=resultado,
                cause="objetivo_alcanzado" if resultado == "success" else "sin_reporte",
                description="Comida dispensada",
                measured_grams=medidos,
                discounted_grams=descontados,
                created_at=creado,
            )
        )

    # --- Petición -----------------------------------------------------------

    def _resumen(self, usuario=None):
        """Llama al endpoint con el reloj fijo en `AHORA` y exige 200."""
        app.dependency_overrides[get_current_user] = lambda: usuario or self.usuario
        with patch("app.domain.tiempo.ahora_utc", return_value=AHORA):
            respuesta = self.client.get("/dashboard/summary")
        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        return respuesta.json()


class TestResumenConDatos(BaseDashboardTests):
    """RF-1 a RF-6: hoy y semana reales, contrato completo."""

    def test_devuelve_gramos_y_ocurrencias_reales_de_hoy_y_de_la_semana(self):
        milo = self._crear_mascota("Milo", castrada=True)
        self._crear_dispensador(milo, mac="AA:BB:CC:DD:EE:01")
        self._crear_horario(milo, hora="08:00", gramos=50.0)
        self._crear_horario(milo, hora="20:00", gramos=60.0)

        self._crear_log(creado=self.inicio_dia_utc + timedelta(hours=1), medidos=50.0)
        self._crear_log(creado=self.ayer_utc, medidos=60.0)
        # Registros de otros tipos con gramos y resultado exitoso: si el filtro
        # por `event_type` desapareciera, sumarían gramos y completarían
        # ocurrencias, así que la prueba falla sin él (RF-2).
        self._crear_log(
            creado=self.inicio_dia_utc + timedelta(hours=2),
            tipo="dispenser_refilled",
            medidos=999.0,
        )
        self._crear_log(
            creado=self.inicio_dia_utc + timedelta(hours=3),
            tipo="dispenser_linked",
            medidos=500.0,
        )

        cuerpo = self._resumen()

        self.assertEqual(set(cuerpo.keys()), CAMPOS_ESPERADOS)
        self.assertEqual(cuerpo["total_pets"], 1)
        self.assertEqual(cuerpo["sterilized_pets"], 1)
        self.assertEqual(cuerpo["food_dispensed_today"], 50.0)
        self.assertEqual(cuerpo["food_target_today"], 110.0)
        self.assertEqual(cuerpo["pending_feedings"], 1)
        self.assertEqual(cuerpo["completed_feedings"], 1)
        esperado = [0.0] * panel.DIAS_SEMANA
        esperado[self.indice_hoy] = 50.0
        esperado[self.indice_ayer] = 60.0
        self.assertEqual(cuerpo["weekly_dispensed"], esperado)
        self.assertNotIn(999.0, cuerpo["weekly_dispensed"])
        self.assertEqual(sum(cuerpo["weekly_dispensed"]), 110.0)
        self.assertEqual(cuerpo["today_index"], self.indice_hoy)

    def test_un_registro_de_hoy_con_hora_posterior_al_calculo_si_cuenta(self):
        milo = self._crear_mascota("Milo")
        self._crear_dispensador(milo, mac="AA:BB:CC:DD:EE:02")
        self._crear_horario(milo, hora="22:00", gramos=80.0)
        # El fin del día local es posterior a `AHORA`: el registro entra igual.
        self._crear_log(
            creado=self.fin_dia_utc - timedelta(hours=1), medidos=80.0
        )

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["food_dispensed_today"], 80.0)
        self.assertEqual(cuerpo["completed_feedings"], 1)
        self.assertEqual(cuerpo["weekly_dispensed"][self.indice_hoy], 80.0)

    def test_el_fallo_con_gramos_medidos_suma_gramos_y_no_completa(self):
        milo = self._crear_mascota("Milo")
        self._crear_dispensador(milo, mac="AA:BB:CC:DD:EE:03")
        self._crear_horario(milo, hora="08:00", gramos=50.0)
        self._crear_log(
            creado=self.inicio_dia_utc + timedelta(hours=1),
            resultado="failure",
            medidos=30.0,
        )

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["food_dispensed_today"], 30.0)
        self.assertEqual(cuerpo["completed_feedings"], 0)
        self.assertEqual(cuerpo["pending_feedings"], 1)
        self.assertEqual(cuerpo["weekly_dispensed"][self.indice_hoy], 30.0)

    def test_un_exito_sin_gramos_no_aporta_ni_completa(self):
        milo = self._crear_mascota("Milo")
        self._crear_dispensador(milo, mac="AA:BB:CC:DD:EE:04")
        self._crear_horario(milo, hora="08:00", gramos=50.0)
        self._crear_log(creado=self.inicio_dia_utc + timedelta(hours=1))

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["food_dispensed_today"], 0.0)
        self.assertEqual(cuerpo["completed_feedings"], 0)
        self.assertEqual(cuerpo["pending_feedings"], 1)
        self.assertEqual(cuerpo["weekly_dispensed"], [0.0] * panel.DIAS_SEMANA)

    def test_mas_exitos_que_horarios_no_supera_las_ocurrencias(self):
        milo = self._crear_mascota("Milo")
        self._crear_dispensador(milo, mac="AA:BB:CC:DD:EE:05")
        self._crear_horario(milo, hora="08:00", gramos=15.0)
        for hora in (1, 2, 3):
            self._crear_log(
                creado=self.inicio_dia_utc + timedelta(hours=hora), medidos=10.0
            )

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["food_dispensed_today"], 30.0)
        self.assertEqual(cuerpo["completed_feedings"], 1)
        self.assertEqual(cuerpo["pending_feedings"], 0)

    def test_un_registro_con_fecha_futura_no_entra_en_la_serie(self):
        milo = self._crear_mascota("Milo")
        self._crear_dispensador(milo, mac="AA:BB:CC:DD:EE:06")
        self._crear_horario(milo, hora="08:00", gramos=50.0)
        self._crear_log(creado=self.inicio_dia_utc + timedelta(hours=1), medidos=10.0)
        self._crear_log(creado=self.manana_utc, medidos=99.0)

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["food_dispensed_today"], 10.0)
        self.assertEqual(sum(cuerpo["weekly_dispensed"]), 10.0)
        self.assertEqual(cuerpo["weekly_dispensed"][self.indice_hoy], 10.0)


class TestProgramadoSoloDispensable(BaseDashboardTests):
    """RF-3: solo los horarios de mascotas con dispensador vinculado y activo."""

    def test_dispensador_inactivo_o_ausente_no_cuenta_como_programado(self):
        inactiva = self._crear_mascota("Nina")
        self._crear_dispensador(inactiva, mac="AA:BB:CC:DD:EE:07", activo=False)
        self._crear_horario(inactiva, hora="08:00", gramos=80.0)

        sin_dispensador = self._crear_mascota("Toby")
        self._crear_horario(sin_dispensador, hora="12:00", gramos=40.0)

        activa = self._crear_mascota("Milo")
        self._crear_dispensador(activa, mac="AA:BB:CC:DD:EE:08", activo=True)
        self._crear_horario(activa, hora="18:00", gramos=30.0)

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["total_pets"], 3)
        self.assertEqual(cuerpo["food_target_today"], 30.0)
        self.assertEqual(cuerpo["pending_feedings"], 1)
        self.assertEqual(cuerpo["completed_feedings"], 0)

    def test_las_dispensaciones_de_una_mascota_no_dispensable_si_suman(self):
        inactiva = self._crear_mascota("Nina")
        self._crear_dispensador(inactiva, mac="AA:BB:CC:DD:EE:09", activo=False)
        self._crear_log(creado=self.inicio_dia_utc + timedelta(hours=1), medidos=25.0)

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["food_dispensed_today"], 25.0)
        self.assertEqual(cuerpo["food_target_today"], 0.0)
        # Sin ocurrencias dispensables no hay nada que completar.
        self.assertEqual(cuerpo["completed_feedings"], 0)
        self.assertEqual(cuerpo["pending_feedings"], 0)

    def test_un_dispensador_con_estado_nulo_no_cuenta_como_programado(self):
        # Solo un `is_active` verdadero es dispensable: un estado nulo no se
        # interpreta como activo.
        milo = self._crear_mascota("Milo", castrada=True)
        dispensador = self._crear_dispensador(milo, mac="AA:BB:CC:DD:EE:0C")
        self._anular_estado_del_dispensador(dispensador)
        self._crear_horario(milo, hora="08:00", gramos=70.0)
        self._crear_log(creado=self.inicio_dia_utc + timedelta(hours=1), medidos=20.0)

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["food_target_today"], 0.0)
        self.assertEqual(cuerpo["pending_feedings"], 0)
        self.assertEqual(cuerpo["completed_feedings"], 0)
        self.assertEqual(cuerpo["food_dispensed_today"], 20.0)


class TestResumenSinDatos(BaseDashboardTests):
    """RF-1, RF-7 y RF-6: ceros reales, nunca valores de relleno."""

    def test_sin_actividad_devuelve_ceros_y_el_programado(self):
        milo = self._crear_mascota("Milo")
        self._crear_dispensador(milo, mac="AA:BB:CC:DD:EE:0A")
        self._crear_horario(milo, hora="08:00", gramos=40.0)

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["food_dispensed_today"], 0.0)
        self.assertEqual(cuerpo["food_target_today"], 40.0)
        self.assertEqual(cuerpo["pending_feedings"], 1)
        self.assertEqual(cuerpo["completed_feedings"], 0)
        self.assertEqual(cuerpo["weekly_dispensed"], [0.0] * panel.DIAS_SEMANA)

    def test_sin_mascotas_todo_es_cero_sin_la_meta_de_trescientos(self):
        cuerpo = self._resumen()

        self.assertEqual(cuerpo["total_pets"], 0)
        self.assertEqual(cuerpo["sterilized_pets"], 0)
        self.assertEqual(cuerpo["food_dispensed_today"], 0.0)
        self.assertEqual(cuerpo["food_target_today"], 0.0)
        self.assertEqual(cuerpo["pending_feedings"], 0)
        self.assertEqual(cuerpo["completed_feedings"], 0)
        self.assertEqual(cuerpo["weekly_dispensed"], [0.0] * panel.DIAS_SEMANA)

    def test_un_usuario_ajeno_no_ve_las_filas_del_otro(self):
        ajena = self._crear_mascota("Pelota", usuario=self.ajeno)
        self._crear_dispensador(ajena, mac="AA:BB:CC:DD:EE:0B")
        self._crear_horario(ajena, hora="08:00", gramos=100.0)
        # La actividad del usuario ajeno tampoco entra en el resumen propio.
        self._crear_log(
            usuario=self.ajeno,
            creado=self.inicio_dia_utc + timedelta(hours=1),
            medidos=80.0,
        )

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["total_pets"], 0)
        self.assertEqual(cuerpo["food_target_today"], 0.0)
        self.assertEqual(cuerpo["food_dispensed_today"], 0.0)
        self.assertEqual(cuerpo["weekly_dispensed"], [0.0] * panel.DIAS_SEMANA)


class TestContratoTemporal(BaseDashboardTests):
    """RF-6, RF-11: posición de hoy y marca del cálculo en UTC."""

    def test_today_index_corresponde_al_dia_local_del_servidor(self):
        esperado = tiempo.a_local_naive(AHORA, None).weekday()

        cuerpo = self._resumen()

        self.assertEqual(cuerpo["today_index"], esperado)
        self.assertGreaterEqual(cuerpo["today_index"], 0)
        self.assertLessEqual(cuerpo["today_index"], 6)

    def test_calculated_at_es_el_instante_del_calculo_en_utc_con_z(self):
        cuerpo = self._resumen()

        self.assertTrue(cuerpo["calculated_at"].endswith("Z"))
        instante = datetime.fromisoformat(
            cuerpo["calculated_at"].replace("Z", "+00:00")
        )
        self.assertEqual(instante.utcoffset(), timedelta(0))
        self.assertEqual(instante, AHORA)


if __name__ == "__main__":
    unittest.main()
