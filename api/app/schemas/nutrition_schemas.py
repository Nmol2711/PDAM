"""Esquemas Pydantic para la validación estricta de entradas del motor nutricional.

Cubre RF-1 y RF-2 de la Spec 011: rechaza parámetros inválidos (peso corporal,
densidad calórica, comidas diarias, BCS, MCS, actividad, estatus reproductivo,
etapa de vida y especie) con mensajes de error descriptivos en español antes de
que la petición alcance la lógica de negocio.

Los valores de texto se normalizan a una forma canónica (minúsculas, sin
espacios) para garantizar el determinismo (RNF-1) entre el backend y el frontend.
Los campos numéricos ausentes, nulos o no numéricos se interceptan antes de la
validación estricta de Pydantic para emitir mensajes en español (RF-1 y
Constitución §6) en lugar de los mensajes nativos en inglés de Pydantic.
"""

from pydantic import BaseModel, field_validator, model_validator
from pydantic_core import PydanticCustomError

# ---------------------------------------------------------------------------
# Whitelists y valores canónicos
# ---------------------------------------------------------------------------

SPECIES_CANONICAL = {
    "canino": "canino",
    "perro": "canino",
    "dog": "canino",
    "felino": "felino",
    "gato": "felino",
    "cat": "felino",
}

MCS_CANONICAL = {
    "normal": "normal",
    "leve": "mild",
    "mild": "mild",
    "moderada": "moderate",
    "moderate": "moderate",
    "marcada": "marked",
    "marked": "marked",
}

ACTIVITY_CANONICAL = {
    "bajo": "low",
    "low": "low",
    "medio": "medium",
    "medium": "medium",
    "alto": "high",
    "high": "high",
}

REPRODUCTIVE_STATUS_VALUES = {"entero", "castrado", "esterilizado"}

LIFE_STAGE_VALUES = {"crecimiento", "adulto"}


# ---------------------------------------------------------------------------
# Funciones puras de validación de límites (Boundary Validation)
# ---------------------------------------------------------------------------


def validate_body_weight(bw: float) -> bool:
    """True si el peso corporal es estrictamente mayor a 0."""
    return bw > 0


def validate_caloric_density(density: float) -> bool:
    """True si la densidad calórica es estrictamente mayor a 0."""
    return density > 0


def validate_meals_per_day(meals: int) -> bool:
    """True si 1 <= meals_per_day <= 6."""
    return 1 <= meals <= 6


def validate_bcs(bcs: int) -> bool:
    """True si 1 <= bcs <= 9."""
    return 1 <= bcs <= 9


def validate_mcs(mcs: str) -> bool:
    """True si el valor (sin distinguir mayúsculas) es un MCS permitido."""
    return isinstance(mcs, str) and mcs.strip().lower() in MCS_CANONICAL


def validate_activity_level(activity: str) -> bool:
    """True si el nivel de actividad es uno de los permitidos."""
    return isinstance(activity, str) and activity.strip().lower() in ACTIVITY_CANONICAL


def canonical_mcs(value) -> str:
    """Devuelve el MCS canónico o lanza ``ValueError`` si no es válido.

    Reutiliza la whitelist de ``MCS_CANONICAL`` para que cualquier endpoint
    (incluida la generación automática de horarios) acepte los mismos
    sinónimos en español que el cálculo nutricional.
    """
    if not validate_mcs(value):
        raise ValueError(
            "MCS inválido. Valores permitidos: normal, leve, moderada, marcada."
        )
    return MCS_CANONICAL[value.strip().lower()]


def canonical_activity_level(value) -> str:
    """Devuelve el nivel de actividad canónico o lanza ``ValueError``."""
    if not validate_activity_level(value):
        raise ValueError(
            "Nivel de actividad inválido. Valores permitidos: bajo, medio, alto."
        )
    return ACTIVITY_CANONICAL[value.strip().lower()]


def validate_reproductive_status(status: str) -> bool:
    """True si el estatus reproductivo es uno de los permitidos."""
    return (
        isinstance(status, str)
        and status.strip().lower() in REPRODUCTIVE_STATUS_VALUES
    )


def validate_life_stage(stage: str) -> bool:
    """True si la etapa de vida es una de las permitidas."""
    return isinstance(stage, str) and stage.strip().lower() in LIFE_STAGE_VALUES


def _normalize_text(value, mapping, error_message: str) -> str:
    """Normaliza un valor de texto a su forma canónica o lanza un error descriptivo."""
    if not isinstance(value, str):
        raise PydanticCustomError("invalid_value", error_message)
    key = value.strip().lower()
    if key not in mapping:
        raise PydanticCustomError("invalid_value", error_message)
    return mapping[key]


# ---------------------------------------------------------------------------
# Coerción de entradas numéricas (mensajes en español)
# ---------------------------------------------------------------------------


def _coerce_float(value, missing_message: str, not_number_message: str) -> float:
    """Convierte el valor a float o lanza un error descriptivo en español."""
    if value is None:
        raise PydanticCustomError("missing_field", missing_message)
    if isinstance(value, bool):
        raise PydanticCustomError("not_a_number", not_number_message)
    try:
        return float(value)
    except (TypeError, ValueError):
        raise PydanticCustomError("not_a_number", not_number_message)


def _coerce_int(value, missing_message: str, not_number_message: str) -> int:
    """Convierte el valor a int o lanza un error descriptivo en español."""
    if value is None:
        raise PydanticCustomError("missing_field", missing_message)
    if isinstance(value, bool):
        raise PydanticCustomError("not_an_integer", not_number_message)
    if isinstance(value, int):
        return value
    try:
        number = float(value)
    except (TypeError, ValueError):
        raise PydanticCustomError("not_an_integer", not_number_message)
    if not number.is_integer():
        raise PydanticCustomError("not_an_integer", not_number_message)
    return int(number)


# ---------------------------------------------------------------------------
# Esquema Pydantic de entrada
# ---------------------------------------------------------------------------


class NutritionCalculationRequest(BaseModel):
    """Parámetros de entrada del motor de dosificación nutricional WSAVA."""

    species: str
    body_weight: float
    caloric_density_kcal_per_kg: float
    bcs: int
    mcs: str
    activity_level: str
    reproductive_status: str
    life_stage: str
    meals_per_day: int
    snacks_kcal: float = 0.0

    @model_validator(mode="before")
    @classmethod
    def _coerce_numeric_inputs(cls, data):
        """Intercepta campos numéricos ausentes, nulos o no numéricos antes de la
        validación estricta de Pydantic, emitiendo mensajes en español."""
        if not isinstance(data, dict):
            return data
        coerced = dict(data)
        coerced["body_weight"] = _coerce_float(
            coerced.get("body_weight"),
            "El peso corporal (BW) es obligatorio.",
            "El peso corporal (BW) debe ser un número.",
        )
        coerced["caloric_density_kcal_per_kg"] = _coerce_float(
            coerced.get("caloric_density_kcal_per_kg"),
            "La densidad calórica es obligatoria.",
            "La densidad calórica debe ser un número.",
        )
        coerced["meals_per_day"] = _coerce_int(
            coerced.get("meals_per_day"),
            "Las comidas diarias son obligatorias.",
            "Las comidas diarias deben ser un número entero.",
        )
        coerced["bcs"] = _coerce_int(
            coerced.get("bcs"),
            "El BCS es obligatorio.",
            "El BCS debe ser un número entero.",
        )
        return coerced

    @field_validator("species", mode="before")
    @classmethod
    def _validate_species(cls, value) -> str:
        return _normalize_text(
            value,
            SPECIES_CANONICAL,
            "Especie inválida. Valores permitidos: canino/perro o felino/gato.",
        )

    @field_validator("body_weight")
    @classmethod
    def _validate_body_weight(cls, value) -> float:
        if not validate_body_weight(value):
            raise PydanticCustomError(
                "out_of_range",
                "El peso corporal (BW) debe ser un número mayor a 0 (kg).",
            )
        return value

    @field_validator("caloric_density_kcal_per_kg")
    @classmethod
    def _validate_caloric_density(cls, value) -> float:
        if not validate_caloric_density(value):
            raise PydanticCustomError(
                "out_of_range",
                "La densidad calórica debe ser un número mayor a 0 (kcal/kg).",
            )
        return value

    @field_validator("bcs")
    @classmethod
    def _validate_bcs(cls, value) -> int:
        if not validate_bcs(value):
            raise PydanticCustomError("out_of_range", "El BCS debe estar entre 1 y 9.")
        return value

    @field_validator("mcs", mode="before")
    @classmethod
    def _validate_mcs(cls, value) -> str:
        try:
            return canonical_mcs(value)
        except ValueError as exc:
            raise PydanticCustomError("invalid_value", str(exc)) from exc

    @field_validator("activity_level", mode="before")
    @classmethod
    def _validate_activity(cls, value) -> str:
        try:
            return canonical_activity_level(value)
        except ValueError as exc:
            raise PydanticCustomError("invalid_value", str(exc)) from exc

    @field_validator("reproductive_status", mode="before")
    @classmethod
    def _validate_reproductive_status(cls, value) -> str:
        if not validate_reproductive_status(value):
            raise PydanticCustomError(
                "invalid_value",
                "Estatus reproductivo inválido. Valores permitidos: entero, "
                "castrado, esterilizado.",
            )
        return value.strip().lower()

    @field_validator("life_stage", mode="before")
    @classmethod
    def _validate_life_stage(cls, value) -> str:
        if not validate_life_stage(value):
            raise PydanticCustomError(
                "invalid_value",
                "Etapa de vida inválida. Valores permitidos: crecimiento, adulto.",
            )
        return value.strip().lower()

    @field_validator("meals_per_day")
    @classmethod
    def _validate_meals_per_day(cls, value) -> int:
        if not validate_meals_per_day(value):
            raise PydanticCustomError(
                "out_of_range", "Las comidas diarias deben estar entre 1 y 6."
            )
        return value

    @field_validator("snacks_kcal")
    @classmethod
    def _validate_snacks(cls, value) -> float:
        if value < 0:
            raise PydanticCustomError(
                "out_of_range", "Las calorías de snacks no pueden ser negativas."
            )
        return value


class NutritionCalculationResponse(BaseModel):
    """Resultado completo del cálculo de dosificación nutricional WSAVA.

    Refleja exactamente los resultados sincronizados devueltos por el motor de
    cálculo (`app/services/nutrition_service.py`) para que la aplicación móvil
    obtenga los mismos valores que el servidor (RF-4).
    """

    species: str
    body_weight: float
    meals_per_day: int
    rer_kcal: float
    mer_kcal: float
    variability_min_kcal: float
    variability_max_kcal: float
    snack_limit_kcal: float
    snacks_kcal: float
    exceeds_snack_limit: bool
    final_ration_kcal: float
    daily_ration_grams: float
    ration_per_meal_grams: float
