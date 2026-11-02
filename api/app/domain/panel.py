"""Resumen del panel con actividad real (spec 022).

El resumen distingue lo programado de lo dispensado y elimina las cifras de
relleno: los gramos salen de las dispensaciones registradas, el programado de
los horarios dispensables y las ocurrencias completadas de los éxitos del día
local que traen gramos (RF-1 a RF-5).

Módulo puro: no usa base de datos, ni FastAPI, ni lee el reloj. El instante
actual y la zona horaria del servidor llegan como parámetros, de modo que el
día local, la medianoche y el cambio de semana se prueban sin depender del
reloj ni de la zona del equipo (RNF-2, RF-11).
"""

from dataclasses import dataclass
from datetime import datetime, time, timedelta, timezone, tzinfo
from typing import Iterable, Optional

from app.domain import tiempo
from app.domain.catalogos import EXITO

# Posiciones fijas de la serie semanal: 0 lunes y 6 domingo (RF-5).
DIAS_SEMANA = 7


@dataclass(frozen=True)
class RegistroDispensado:
    """Dispensación registrada que aporta al resumen del panel (RF-2).

    `instante` es UTC sin zona, igual que los `created_at` guardados en la
    tabla de registros. `outcome` es el código del catálogo de resultados:
    solo `success` con gramos completa ocurrencias. Los gramos son opcionales
    porque un cierre sin reporte no los trae.
    """

    instante: datetime
    outcome: str
    measured_grams: Optional[float] = None
    discounted_grams: Optional[float] = None


@dataclass(frozen=True)
class ResumenPanel:
    """Cifras del panel calculadas sin valores de relleno (RF-1).

    `serie_semanal` es una tupla de siete gramos, de lunes a domingo; se usa
    tupla para que el resumen sea inmutable como el resto de sus campos.
    """

    total_mascotas: int
    mascotas_castradas: int
    gramos_hoy: float
    programado_hoy: float
    ocurrencias: int
    completadas: int
    pendientes: int
    serie_semanal: tuple[float, ...]
    indice_hoy: int


def gramos_de_registro(
    medidos: Optional[float], descontados: Optional[float]
) -> float:
    """Gramos que aporta un registro: medidos, si no descontados, si no 0.

    Un medido en cero no cae al descuento: solo la ausencia de medido lo hace
    (RF-2, RF-5).
    """
    if medidos is not None:
        return float(medidos)
    if descontados is not None:
        return float(descontados)
    return 0.0


def tiene_gramos(
    medidos: Optional[float], descontados: Optional[float]
) -> bool:
    """Indica si el registro trae algún gramo medido o descontado.

    Un medido o un descuento en 0 cuenta como dato y completa la ocurrencia
    (RF-2, RF-4).
    """
    return medidos is not None or descontados is not None


def _utc_de_local(local: datetime, zona: Optional[tzinfo]) -> datetime:
    """Instante UTC sin zona de una hora local del servidor.

    Cada fecha local se convierte con el desfase vigente en ese instante, no
    con el de `ahora`, para que el horario de verano no desplace los límites
    (RF-11). `zona` es la zona del servidor; sin ella se usa la local del
    equipo, igual que en `tiempo.a_local_naive`.
    """
    if zona is None:
        return local.astimezone(timezone.utc).replace(tzinfo=None)
    return local.replace(tzinfo=zona).astimezone(timezone.utc).replace(tzinfo=None)


def rango_semana_local(
    ahora: datetime, zona: Optional[tzinfo]
) -> tuple[datetime, datetime, datetime, int]:
    """Límites UTC de la semana en curso y del día de hoy, y la posición de hoy.

    Devuelve `(inicio_semana_utc, inicio_dia_utc, fin_dia_utc, indice_hoy)`,
    con los tres instantes en UTC sin zona y el índice de 0 (lunes) a 6
    (domingo) según el día local del servidor. La semana empieza en la
    medianoche local del lunes; `fin_dia_utc` es la medianoche local del día
    siguiente, extremo derecho exclusivo del día de hoy, y puede no estar a 24
    horas del inicio por el horario de verano (RF-5, RF-6, RF-11).

    `zona` es la zona del servidor; el dominio nunca lee el reloj ni decide la
    zona por su cuenta.
    """
    ahora_utc = tiempo.a_utc_naive(ahora)
    hoy_local = tiempo.a_local_naive(ahora_utc, zona).date()
    indice_hoy = hoy_local.weekday()

    inicio_semana_local = datetime.combine(
        hoy_local - timedelta(days=indice_hoy), time.min
    )
    inicio_dia_local = datetime.combine(hoy_local, time.min)
    fin_dia_local = datetime.combine(hoy_local + timedelta(days=1), time.min)

    return (
        _utc_de_local(inicio_semana_local, zona),
        _utc_de_local(inicio_dia_local, zona),
        _utc_de_local(fin_dia_local, zona),
        indice_hoy,
    )


def calcular_resumen(
    total_mascotas: int,
    mascotas_castradas: int,
    gramos_horarios: Iterable[float],
    registros: Iterable[RegistroDispensado],
    ahora: datetime,
    zona: Optional[tzinfo],
) -> ResumenPanel:
    """Calcula las cifras del panel a partir de la actividad registrada.

    - Los gramos de hoy suman los registros con fecha local de hoy, con o sin
      éxito, con el respaldo por descuento y aunque su hora sea posterior a la
      del cálculo (RF-2).
    - El programado es la suma de los horarios dispensables y las ocurrencias
      su número (RF-3, RF-4).
    - Las completadas son los éxitos de hoy que traen gramos, acotados a las
      ocurrencias, y las pendientes nunca bajan de 0 (RF-4).
    - La serie tiene siete posiciones de lunes a domingo; los días sin
      actividad, los posteriores a hoy y los registros de días anteriores a la
      semana en curso no aportan (RF-5).

    Sin datos, todas las cifras son 0 y la serie son siete ceros (RF-1, RF-7).
    """
    horarios = [float(gramos) for gramos in gramos_horarios]
    ahora_utc = tiempo.a_utc_naive(ahora)
    _, _, _, indice_hoy = rango_semana_local(ahora_utc, zona)

    hoy_local = tiempo.a_local_naive(ahora_utc, zona).date()
    inicio_semana_fecha = hoy_local - timedelta(days=indice_hoy)

    gramos_por_dia = [0.0] * DIAS_SEMANA
    gramos_hoy = 0.0
    completadas = 0

    for registro in registros:
        # La fecha local se calcula con el desfase vigente en el registro.
        fecha_local = tiempo.a_local_naive(registro.instante, zona).date()
        if fecha_local > hoy_local or fecha_local < inicio_semana_fecha:
            # Días posteriores a hoy o fuera de la semana en curso (RF-5).
            continue

        gramos = gramos_de_registro(
            registro.measured_grams, registro.discounted_grams
        )
        posicion = fecha_local.weekday()
        gramos_por_dia[posicion] += gramos

        if fecha_local == hoy_local:
            gramos_hoy += gramos
            if registro.outcome == EXITO and tiene_gramos(
                registro.measured_grams, registro.discounted_grams
            ):
                completadas += 1

    ocurrencias = len(horarios)
    completadas = min(completadas, ocurrencias)

    return ResumenPanel(
        total_mascotas=total_mascotas,
        mascotas_castradas=mascotas_castradas,
        gramos_hoy=gramos_hoy,
        programado_hoy=sum(horarios, 0.0),
        ocurrencias=ocurrencias,
        completadas=completadas,
        pendientes=max(0, ocurrencias - completadas),
        serie_semanal=tuple(gramos_por_dia),
        indice_hoy=indice_hoy,
    )
