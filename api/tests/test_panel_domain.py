"""Pruebas del dominio puro del resumen del panel (spec 022, T1).

Cubren el día local y la semana en curso (RF-11), los gramos dispensados por
registro (RF-2), el programado a partir de los horarios (RF-3), las ocurrencias
completadas con gramos (RF-4), la serie de siete posiciones (RF-5) y el resumen
sin datos (RF-1, RF-7). No tocan base de datos, FastAPI ni SQLAlchemy: el
instante y la zona llegan como parámetros, así que la suite no depende del
reloj ni de la zona del equipo que la ejecuta.

Zona fija de las pruebas: UTC-05, la del servidor de referencia. El horario de
verano se prueba aparte con `ZoneInfo` de la biblioteca estándar.
"""

import sys
import unittest
from dataclasses import FrozenInstanceError
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.domain.panel import (
    RegistroDispensado,
    ResumenPanel,
    calcular_resumen,
    gramos_de_registro,
    rango_semana_local,
    tiene_gramos,
)

# Zona fija del servidor en las pruebas: nunca la del equipo.
ZONA = timezone(timedelta(hours=-5))

# Semana de referencia: lunes 26 de octubre al domingo 1 de noviembre de 2026.
LUNES_INICIO_UTC = datetime(2026, 10, 26, 5, 0)


def instante_local(texto: str) -> datetime:
    """Instante UTC naive de una hora local del servidor.

    `texto` se interpreta en la zona fija `ZONA` y se devuelve como UTC sin
    zona, igual que se guardan los `created_at` de los registros.
    """
    local = datetime.fromisoformat(texto).replace(tzinfo=ZONA)
    return local.astimezone(timezone.utc).replace(tzinfo=None)


def registro(
    texto_local: str,
    outcome: str = "success",
    medidos: float | None = None,
    descontados: float | None = None,
) -> RegistroDispensado:
    """Registro dispensado ubicado en una hora local del servidor."""
    return RegistroDispensado(
        instante=instante_local(texto_local),
        outcome=outcome,
        measured_grams=medidos,
        discounted_grams=descontados,
    )


class TestGramosDeRegistro(unittest.TestCase):
    """RF-2: medidos, si no descontados, si no 0."""

    def test_los_gramos_medidos_prevalecen_sobre_los_descontados(self):
        self.assertEqual(gramos_de_registro(50.0, 45.0), 50.0)

    def test_sin_medidos_se_usa_el_descuento(self):
        self.assertEqual(gramos_de_registro(None, 45.0), 45.0)

    def test_sin_medidos_ni_descontados_no_aporta_gramos(self):
        self.assertEqual(gramos_de_registro(None, None), 0.0)

    def test_un_medido_en_cero_no_cae_al_descuento(self):
        # 0 no es nulo: el registro aporta 0 g y no el descuento.
        self.assertEqual(gramos_de_registro(0.0, 45.0), 0.0)

    def test_devuelve_siempre_un_float(self):
        self.assertIsInstance(gramos_de_registro(12, None), float)
        self.assertIsInstance(gramos_de_registro(None, None), float)


class TestTieneGramos(unittest.TestCase):
    """RF-2, RF-4: un 0 es un dato y completa la ocurrencia."""

    def test_sin_medidos_ni_descontados_no_tiene_gramos(self):
        self.assertFalse(tiene_gramos(None, None))

    def test_un_medido_en_cero_cuenta_como_dato(self):
        self.assertTrue(tiene_gramos(0.0, None))

    def test_un_descuento_en_cero_cuenta_como_dato(self):
        self.assertTrue(tiene_gramos(None, 0.0))

    def test_cualquier_valor_no_nulo_tiene_gramos(self):
        for medidos, descontados in ((50.0, None), (None, 45.0), (50.0, 45.0)):
            with self.subTest(medidos=medidos, descontados=descontados):
                self.assertTrue(tiene_gramos(medidos, descontados))


class TestRangoSemanaLocal(unittest.TestCase):
    """RF-5, RF-6, RF-11: límites UTC de la semana y del día local de hoy."""

    def test_lunes_devuelve_la_primera_posicion_y_el_inicio_de_semana(self):
        inicio_semana, inicio_dia, fin_dia, indice = rango_semana_local(
            instante_local("2026-10-26 12:00"), ZONA
        )
        self.assertEqual(inicio_semana, LUNES_INICIO_UTC)
        self.assertEqual(inicio_dia, LUNES_INICIO_UTC)
        self.assertEqual(fin_dia, instante_local("2026-10-27 00:00"))
        self.assertEqual(indice, 0)

    def test_domingo_devuelve_la_ultima_posicion_y_conserva_el_lunes(self):
        inicio_semana, inicio_dia, fin_dia, indice = rango_semana_local(
            instante_local("2026-11-01 23:59"), ZONA
        )
        self.assertEqual(inicio_semana, LUNES_INICIO_UTC)
        self.assertEqual(inicio_dia, instante_local("2026-11-01 00:00"))
        self.assertEqual(fin_dia, instante_local("2026-11-02 00:00"))
        self.assertEqual(indice, 6)

    def test_los_limites_son_utc_sin_zona(self):
        limites = rango_semana_local(instante_local("2026-10-28 10:00"), ZONA)[:3]
        for limite in limites:
            with self.subTest(limite=limite):
                self.assertIsNone(limite.tzinfo)

    def test_el_dia_de_hoy_va_de_medianoche_a_medianoche_local(self):
        _, inicio_dia, fin_dia, _ = rango_semana_local(
            instante_local("2026-10-28 10:00"), ZONA
        )
        self.assertEqual(inicio_dia, instante_local("2026-10-28 00:00"))
        self.assertEqual(fin_dia, instante_local("2026-10-29 00:00"))

    def test_todos_los_dias_de_la_semana_comparten_el_mismo_inicio(self):
        # De lunes 26 de octubre al domingo 1 de noviembre, siete posiciones.
        dias = [f"2026-10-{dia:02d}" for dia in range(26, 32)] + ["2026-11-01"]
        for indice_esperado, fecha in enumerate(dias):
            with self.subTest(fecha=fecha):
                inicio_semana, _, _, indice = rango_semana_local(
                    instante_local(f"{fecha} 08:00"), ZONA
                )
                self.assertEqual(inicio_semana, LUNES_INICIO_UTC)
                self.assertEqual(indice, indice_esperado)


class TestHorarioDeVerano(unittest.TestCase):
    """RF-11: cada límite usa el desfase vigente en ese instante."""

    def setUp(self):
        self.nueva_york = ZoneInfo("America/New_York")

    def _utc(self, anio: int, mes: int, dia: int, hora: int) -> datetime:
        """Instante UTC naive de una hora local de Nueva York."""
        local = datetime(anio, mes, dia, hora, tzinfo=self.nueva_york)
        return local.astimezone(timezone.utc).replace(tzinfo=None)

    def test_al_terminar_el_horario_de_verano_cada_limite_usa_su_desfase(self):
        # Domingo 1 de noviembre de 2026: a las 02:00 EDT el reloj vuelve a la
        # 01:00 EST, así que el domingo local dura 25 horas.
        inicio_semana, inicio_dia, fin_dia, indice = rango_semana_local(
            self._utc(2026, 11, 1, 12), self.nueva_york
        )
        self.assertEqual(indice, 6)
        # Lunes 26 y domingo 1 a medianoche todavía en EDT (UTC-4).
        self.assertEqual(inicio_semana, datetime(2026, 10, 26, 4, 0))
        self.assertEqual(inicio_dia, datetime(2026, 11, 1, 4, 0))
        # Lunes 2 a medianoche ya en EST (UTC-5).
        self.assertEqual(fin_dia, datetime(2026, 11, 2, 5, 0))

    def test_al_empezar_el_horario_de_verano_el_dia_dura_veintitres_horas(self):
        # Domingo 8 de marzo de 2026: a las 02:00 EST el reloj pasa a las
        # 03:00 EDT, así que el domingo local dura 23 horas.
        inicio_semana, inicio_dia, fin_dia, _ = rango_semana_local(
            self._utc(2026, 3, 8, 12), self.nueva_york
        )
        self.assertEqual(inicio_semana, datetime(2026, 3, 2, 5, 0))
        self.assertEqual(inicio_dia, datetime(2026, 3, 8, 5, 0))
        self.assertEqual(fin_dia, datetime(2026, 3, 9, 4, 0))


class TestDiaLocalYSemana(unittest.TestCase):
    """RF-2, RF-5, RF-11: límites del día local y de la semana en curso."""

    def test_la_medianoche_local_pertenece_al_dia_que_empieza(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[50.0],
            registros=[registro("2026-10-26 00:00", medidos=50.0)],
            ahora=instante_local("2026-10-26 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.indice_hoy, 0)
        self.assertEqual(resumen.gramos_hoy, 50.0)
        self.assertEqual(resumen.serie_semanal[0], 50.0)
        self.assertEqual(resumen.completadas, 1)

    def test_domingo_a_las_2359_va_a_la_ultima_posicion(self):
        domingo_noche = instante_local("2026-11-01 23:59")
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[40.0],
            registros=[registro("2026-11-01 23:59", medidos=40.0)],
            ahora=domingo_noche,
            zona=ZONA,
        )
        self.assertEqual(resumen.indice_hoy, 6)
        self.assertEqual(resumen.gramos_hoy, 40.0)
        self.assertEqual(resumen.serie_semanal[6], 40.0)

    def test_lunes_a_las_0000_abre_la_semana_nueva(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[30.0],
            registros=[
                registro("2026-11-01 23:59", medidos=40.0),
                registro("2026-11-02 00:00", medidos=30.0),
            ],
            ahora=instante_local("2026-11-02 00:30"),
            zona=ZONA,
        )
        # El domingo anterior ya no pertenece a la semana en curso.
        self.assertEqual(resumen.indice_hoy, 0)
        self.assertEqual(
            resumen.serie_semanal, (30.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        )
        self.assertEqual(resumen.gramos_hoy, 30.0)
        self.assertEqual(resumen.completadas, 1)

    def test_un_registro_de_hoy_con_hora_posterior_a_ahora_suma_y_completa(self):
        # Un reloj adelantado no excluye el registro si su fecha local es hoy.
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[50.0],
            registros=[registro("2026-10-28 18:00", medidos=60.0)],
            ahora=instante_local("2026-10-28 10:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.gramos_hoy, 60.0)
        self.assertEqual(resumen.serie_semanal[2], 60.0)
        self.assertEqual(resumen.completadas, 1)
        self.assertEqual(resumen.pendientes, 0)

    def test_un_registro_de_un_dia_posterior_no_se_incluye(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[50.0],
            registros=[
                registro("2026-10-28 09:00", medidos=20.0),
                registro("2026-10-29 09:00", medidos=70.0),
                registro("2026-11-01 09:00", medidos=80.0),
            ],
            ahora=instante_local("2026-10-28 10:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.gramos_hoy, 20.0)
        self.assertEqual(
            resumen.serie_semanal, (0.0, 0.0, 20.0, 0.0, 0.0, 0.0, 0.0)
        )
        self.assertEqual(resumen.completadas, 1)

    def test_la_zona_decide_el_dia_y_la_posicion_de_hoy(self):
        # 2026-11-02T02:00Z es domingo 21:00 en UTC-05 y lunes 04:00 en UTC+02.
        ahora = datetime(2026, 11, 2, 2, 0)
        resumen_oeste = calcular_resumen(
            total_mascotas=0,
            mascotas_castradas=0,
            gramos_horarios=[],
            registros=[RegistroDispensado(instante=ahora, outcome="success")],
            ahora=ahora,
            zona=ZONA,
        )
        resumen_este = calcular_resumen(
            total_mascotas=0,
            mascotas_castradas=0,
            gramos_horarios=[],
            registros=[RegistroDispensado(instante=ahora, outcome="success")],
            ahora=ahora,
            zona=timezone(timedelta(hours=2)),
        )
        self.assertEqual(resumen_oeste.indice_hoy, 6)
        self.assertEqual(resumen_este.indice_hoy, 0)


class TestGramosYCompletadas(unittest.TestCase):
    """RF-2, RF-3, RF-4: sumas de hoy, programado y ocurrencias."""

    def test_un_fallo_con_gramos_medidos_suma_y_no_completa(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[50.0],
            registros=[registro("2026-10-28 09:00", "failure", medidos=25.0)],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.gramos_hoy, 25.0)
        self.assertEqual(resumen.serie_semanal[2], 25.0)
        self.assertEqual(resumen.completadas, 0)
        self.assertEqual(resumen.pendientes, 1)

    def test_un_exito_sin_medidos_usa_los_descontados(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[50.0],
            registros=[
                registro("2026-10-28 09:00", medidos=None, descontados=45.0)
            ],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.gramos_hoy, 45.0)
        self.assertEqual(resumen.completadas, 1)
        self.assertEqual(resumen.pendientes, 0)

    def test_un_exito_sin_gramos_no_completa_la_ocurrencia(self):
        # Definición de ocurrencia completada: éxito con medido o descuento.
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[50.0],
            registros=[
                registro(
                    "2026-10-28 09:00", "success", medidos=None, descontados=None
                )
            ],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.gramos_hoy, 0.0)
        self.assertEqual(resumen.serie_semanal, (0.0,) * 7)
        self.assertEqual(resumen.completadas, 0)
        self.assertEqual(resumen.pendientes, 1)

    def test_un_exito_con_medido_en_cero_completa_sin_sumar_gramos(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[50.0],
            registros=[registro("2026-10-28 09:00", medidos=0.0)],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.gramos_hoy, 0.0)
        self.assertEqual(resumen.completadas, 1)
        self.assertEqual(resumen.pendientes, 0)

    def test_mas_exitos_que_horarios_no_superan_las_ocurrencias(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[50.0, 40.0],
            registros=[
                registro("2026-10-28 08:00", medidos=20.0),
                registro("2026-10-28 09:00", medidos=20.0),
                registro("2026-10-28 10:00", medidos=20.0),
            ],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.ocurrencias, 2)
        self.assertEqual(resumen.completadas, 2)
        self.assertEqual(resumen.pendientes, 0)
        self.assertEqual(resumen.programado_hoy, 90.0)
        self.assertEqual(resumen.gramos_hoy, 60.0)

    def test_sin_horarios_no_hay_ocurrencias_ni_pendientes(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=1,
            gramos_horarios=[],
            registros=[registro("2026-10-28 09:00", medidos=30.0)],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.ocurrencias, 0)
        self.assertEqual(resumen.programado_hoy, 0.0)
        self.assertEqual(resumen.completadas, 0)
        self.assertEqual(resumen.pendientes, 0)
        # Una dispensación manual suma gramos aunque no haya ocurrencias.
        self.assertEqual(resumen.gramos_hoy, 30.0)

    def test_el_programado_es_la_suma_de_los_horarios(self):
        resumen = calcular_resumen(
            total_mascotas=2,
            mascotas_castradas=1,
            gramos_horarios=[12.5, 30.0, 7.5],
            registros=[],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.programado_hoy, 50.0)
        self.assertEqual(resumen.ocurrencias, 3)
        self.assertEqual(resumen.pendientes, 3)

    def test_las_mascotas_se_copian_sin_calcular(self):
        resumen = calcular_resumen(
            total_mascotas=3,
            mascotas_castradas=2,
            gramos_horarios=[],
            registros=[],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.total_mascotas, 3)
        self.assertEqual(resumen.mascotas_castradas, 2)


class TestSerieSemanal(unittest.TestCase):
    """RF-5: siete posiciones Lun-Dom, sin actividad y futuros en 0."""

    def test_la_semana_vacia_devuelve_siete_ceros(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[50.0],
            registros=[],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.serie_semanal, (0.0,) * 7)
        self.assertEqual(len(resumen.serie_semanal), 7)
        self.assertEqual(resumen.gramos_hoy, 0.0)
        self.assertEqual(resumen.indice_hoy, 2)

    def test_suma_cada_dia_y_deja_en_cero_los_dias_sin_actividad(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[5.0],
            registros=[
                registro("2026-10-26 08:00", medidos=10.0),
                registro("2026-10-26 20:00", medidos=5.0),
                registro("2026-10-28 09:00", medidos=20.0),
                registro("2026-10-30 09:00", medidos=5.0),
            ],
            ahora=instante_local("2026-10-30 12:00"),
            zona=ZONA,
        )
        self.assertEqual(
            resumen.serie_semanal, (15.0, 0.0, 20.0, 0.0, 5.0, 0.0, 0.0)
        )
        self.assertEqual(resumen.gramos_hoy, 5.0)
        self.assertEqual(resumen.indice_hoy, 4)

    def test_los_dias_posteriores_a_hoy_quedan_en_cero(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[],
            registros=[registro("2026-10-27 09:00", medidos=35.0)],
            ahora=instante_local("2026-10-27 12:00"),
            zona=ZONA,
        )
        self.assertEqual(
            resumen.serie_semanal, (0.0, 35.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        )
        self.assertEqual(resumen.indice_hoy, 1)

    def test_los_registros_de_la_semana_anterior_no_entran_en_la_serie(self):
        resumen = calcular_resumen(
            total_mascotas=1,
            mascotas_castradas=0,
            gramos_horarios=[],
            registros=[registro("2026-10-25 23:00", medidos=99.0)],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(resumen.serie_semanal, (0.0,) * 7)
        self.assertEqual(resumen.gramos_hoy, 0.0)

    def test_se_devuelven_exactamente_siete_posiciones_numericas(self):
        resumen = calcular_resumen(
            total_mascotas=0,
            mascotas_castradas=0,
            gramos_horarios=[],
            registros=[],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        self.assertEqual(len(resumen.serie_semanal), 7)
        for posicion in resumen.serie_semanal:
            with self.subTest(posicion=posicion):
                self.assertIsInstance(posicion, float)


class TestRegistrosInmutables(unittest.TestCase):
    """RNF-2: el dominio no modifica sus entradas ni su resultado."""

    def test_un_registro_dispensado_es_inmutable(self):
        creado = registro("2026-10-28 09:00", medidos=20.0)
        with self.assertRaises(FrozenInstanceError):
            creado.outcome = "failure"

    def test_el_resumen_es_inmutable(self):
        resumen = calcular_resumen(
            total_mascotas=0,
            mascotas_castradas=0,
            gramos_horarios=[],
            registros=[],
            ahora=instante_local("2026-10-28 12:00"),
            zona=ZONA,
        )
        with self.assertRaises(FrozenInstanceError):
            resumen.gramos_hoy = 1.0
        self.assertIsInstance(resumen, ResumenPanel)
