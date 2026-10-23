"""Motor de cálculo nutricional WSAVA (funciones puras).

Cubre RF-3 de la Spec 011: calcula el RER, el MER aplicando factores
correctores obligatorios (especie, estatus reproductivo, etapa de vida, nivel de
actividad, condición corporal y masa muscular), notifica el rango de
variabilidad fisiológica esperada, evalúa el límite de snacks al 10% del MER con
alerta/bloqueo y recálculo de la ración principal, y determina la ración diaria
ponderal en gramos.

Todas las funciones son puras y deterministas (RNF-1): ante idénticas entradas
producen siempre el mismo resultado y no dependen de estado externo. La
validación estricta de entradas (RF-1 y RF-2) se realiza en
`app/schemas/nutrition_schemas.py`; aquí se asume que los valores de texto llegan
en su forma canónica y se revalidan defensivamente lanzando `ValueError` ante
valores desconocidos.

Fórmulas (WSAVA / documento técnico):

    RER = 70 * BW^0.75
    MER = RER * Factor_Corrector
    Snack_Limit = MER * 0.10
    Final_Ration_Kcal = max(0.0, MER - Snacks_Kcal)
    Racion_Base (g/día) = Final_Ration_Kcal / (Densidad_Calorica (kcal/g))

Factores correctores empleados (tabla de referencia documentada):

  Base (especie x estatus reproductivo x etapa de vida):
    canino  adulto  entero          -> 1.8
    canino  adulto  castrado/estér. -> 1.6
    canino  crecimiento              -> 2.0
    felino  adulto  entero           -> 1.4
    felino  adulto  castrado/estér.  -> 1.2
    felino  crecimiento              -> 2.5

  Ajuste por nivel de actividad: low 0.9 / medium 1.0 / high 1.2
  Ajuste por condición corporal (BCS): <=3 -> 1.2, 4..6 -> 1.0, >=7 -> 0.8
  Ajuste por masa muscular (MCS): normal/mild -> 1.0, moderate -> 0.95,
    marked -> 0.9

Todos los ajustes se aplican de forma multiplicativa sobre la base.
"""

from typing import Any, Dict, Tuple

# ---------------------------------------------------------------------------
# Tablas de factores correctores WSAVA
# ---------------------------------------------------------------------------

# Factor base del MER por (especie, etapa de vida, estatus reproductivo).
_BASE_MER_FACTORS: Dict[str, Dict[str, Dict[str, float]]] = {
    "canino": {
        "adulto": {"entero": 1.8, "castrado": 1.6, "esterilizado": 1.6},
        "crecimiento": {"entero": 2.0, "castrado": 2.0, "esterilizado": 2.0},
    },
    "felino": {
        "adulto": {"entero": 1.4, "castrado": 1.2, "esterilizado": 1.2},
        "crecimiento": {"entero": 2.5, "castrado": 2.5, "esterilizado": 2.5},
    },
}

# Ajuste multiplicativo por nivel de actividad.
_ACTIVITY_FACTORS: Dict[str, float] = {
    "low": 0.9,
    "medium": 1.0,
    "high": 1.2,
}

# Ajuste multiplicativo por masa muscular (MCS).
_MCS_FACTORS: Dict[str, float] = {
    "normal": 1.0,
    "mild": 1.0,
    "moderate": 0.95,
    "marked": 0.9,
}

# Ajuste multiplicativo por condición corporal (BCS).
_BCS_LOW_FACTOR = 1.2   # bcs <= 3 (bajo peso -> mayor requerimiento)
_BCS_HIGH_FACTOR = 0.8  # bcs >= 7 (sobrepeso -> menor requerimiento)

# Límite máximo de snacks como fracción del MER.
_SNACK_LIMIT_FRACTION = 0.10

# Variabilidad fisiológica esperada por especie.
_VARIABILITY = {
    "canino": (0.7, 1.3),  # ±30%
    "felino": (0.5, 1.5),  # ±50%
}


# ---------------------------------------------------------------------------
# Funciones puras del motor WSAVA
# ---------------------------------------------------------------------------


def calculate_rer(body_weight: float) -> float:
    """Calcula el Requerimiento de Energía en Reposo (RER) en kcal/día.

    Fórmula alométrica estándar: ``RER = 70 * BW^0.75``.
    """
    if body_weight <= 0:
        raise ValueError("El peso corporal debe ser mayor a 0 (kg).")
    return 70.0 * (body_weight ** 0.75)


def _bcs_factor(bcs: int) -> float:
    """Factor corrector por condición corporal (BCS, escala 1-9)."""
    if bcs <= 3:
        return _BCS_LOW_FACTOR
    if bcs >= 7:
        return _BCS_HIGH_FACTOR
    return 1.0


def calculate_mer(
    rer: float,
    species: str,
    reproductive_status: str,
    life_stage: str,
    activity_level: str,
    bcs: int,
    mcs: str,
) -> float:
    """Calcula el Requerimiento de Energía de Mantenimiento (MER) en kcal/día.

    Aplica de forma multiplicativa el factor base (especie x estatus reproductivo
    x etapa de vida) y los ajustes por actividad, condición corporal y masa
    muscular. Lanza `ValueError` ante valores fuera de los whitelists.
    """
    species_key = _normalize(species)
    reproductive_key = _normalize(reproductive_status)
    life_stage_key = _normalize(life_stage)
    activity_key = _normalize(activity_level)
    mcs_key = _normalize(mcs)

    try:
        base_factor = _BASE_MER_FACTORS[species_key][life_stage_key][reproductive_key]
    except KeyError as exc:
        raise ValueError(
            "Combinación inválida de especie, estatus reproductivo o etapa de vida."
        ) from exc

    activity_factor = _ACTIVITY_FACTORS.get(activity_key)
    if activity_factor is None:
        raise ValueError("Nivel de actividad inválido.")

    mcs_factor = _MCS_FACTORS.get(mcs_key)
    if mcs_factor is None:
        raise ValueError("MCS inválido.")

    total_factor = base_factor * activity_factor * _bcs_factor(bcs) * mcs_factor
    return rer * total_factor


def get_variability_range(species: str, mer: float) -> Tuple[float, float]:
    """Devuelve el rango de variabilidad fisiológica esperada ``(mín, máx)``.

    Perros: ±30% (``mer * 0.7``, ``mer * 1.3``); gatos: ±50% (``mer * 0.5``,
    ``mer * 1.5``).
    """
    species_key = _normalize(species)
    if species_key not in _VARIABILITY:
        raise ValueError("Especie inválida. Valores permitidos: canino, felino.")
    low_factor, high_factor = _VARIABILITY[species_key]
    return (mer * low_factor, mer * high_factor)


def evaluate_snacks(mer: float, snacks_kcal: float) -> Dict[str, Any]:
    """Evalúa el aporte calórico de snacks frente al límite del 10% del MER.

    Devuelve un diccionario con:
      - ``snack_limit_kcal``: techo máximo permitido (10% del MER).
      - ``snacks_kcal``: aporte calórico ingresado.
      - ``exceeds_limit``: bandera de alerta/bloqueo si se excede el límite.
      - ``final_ration_kcal``: ración principal recalculada
        ``max(0.0, MER - snacks_kcal)``.
    """
    snack_limit = mer * _SNACK_LIMIT_FRACTION
    exceeds_limit = snacks_kcal > snack_limit
    final_ration_kcal = max(0.0, mer - snacks_kcal)
    return {
        "snack_limit_kcal": snack_limit,
        "snacks_kcal": snacks_kcal,
        "exceeds_limit": exceeds_limit,
        "final_ration_kcal": final_ration_kcal,
    }


def calculate_daily_ration_grams(
    final_ration_kcal: float, caloric_density_kcal_per_kg: float
) -> float:
    """Convierte la ración final en kcal a gramos de alimento por día.

    Usa la densidad calórica en kcal/kg y aplica división segura: si la densidad
    es menor o igual a 0, devuelve ``0.0`` para evitar divisiones inválidas.
    """
    if caloric_density_kcal_per_kg <= 0:
        return 0.0
    density_kcal_per_gram = caloric_density_kcal_per_kg / 1000.0
    return final_ration_kcal / density_kcal_per_gram


def _normalize(value: str) -> str:
    """Normaliza un texto a minúsculas sin espacios para comparaciones canónicas."""
    return value.strip().lower() if isinstance(value, str) else ""


def calculate_nutrition(
    *,
    species: str,
    body_weight: float,
    caloric_density_kcal_per_kg: float,
    bcs: int,
    mcs: str,
    activity_level: str,
    reproductive_status: str,
    life_stage: str,
    meals_per_day: int,
    snacks_kcal: float = 0.0,
) -> Dict[str, Any]:
    """Orquesta el flujo completo de dosificación WSAVA (RF-3, RF-4).

    Recibe los parámetros ya validados y normalizados a su forma canónica (ver
    `NutritionCalculationRequest` en `app/schemas/nutrition_schemas.py`) y
    devuelve un diccionario con los resultados sincronizados: RER, MER, rango de
    variabilidad fisiológica, evaluación del límite de snacks (alerta/bloqueo y
    recálculo de la ración principal) y la ración diaria y por comida en gramos.

    La función es pura y determinista (RNF-1): ante idénticas entradas produce
    siempre el mismo resultado. Las funciones subyacentes revalidan
    defensivamente los valores de texto y lanzan `ValueError` ante entradas fuera
    de los whitelists.
    """
    rer = calculate_rer(body_weight)
    mer = calculate_mer(
        rer,
        species,
        reproductive_status,
        life_stage,
        activity_level,
        bcs,
        mcs,
    )
    variability_min, variability_max = get_variability_range(species, mer)
    snacks = evaluate_snacks(mer, snacks_kcal)
    daily_ration_grams = calculate_daily_ration_grams(
        snacks["final_ration_kcal"], caloric_density_kcal_per_kg
    )
    return {
        "species": species,
        "body_weight": body_weight,
        "meals_per_day": meals_per_day,
        "rer_kcal": rer,
        "mer_kcal": mer,
        "variability_min_kcal": variability_min,
        "variability_max_kcal": variability_max,
        "snack_limit_kcal": snacks["snack_limit_kcal"],
        "snacks_kcal": snacks["snacks_kcal"],
        "exceeds_snack_limit": snacks["exceeds_limit"],
        "final_ration_kcal": snacks["final_ration_kcal"],
        "daily_ration_grams": daily_ration_grams,
        "ration_per_meal_grams": daily_ration_grams / meals_per_day,
    }
