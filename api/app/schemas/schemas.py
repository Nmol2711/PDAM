import re
from pydantic import BaseModel, Field, field_validator
from typing import List, Optional
from datetime import datetime, date

# --- SCHEMAS DE USUARIO ---
# El correo se recibe como texto sin restricciones de Pydantic: el formato, la
# normalización y los límites de la contraseña los valida el servicio con el
# catálogo de la cuenta, para que un rechazo de negocio no responda 422 (spec
# 015, RF-11, §5.4).
class UserBase(BaseModel):
    email: str

class UserCreate(UserBase):
    password: str # Solo se usa al recibir el registro

class User(UserBase):
    id: int
    is_active: bool

    class Config:
        from_attributes = True # Esto permite que Pydantic lea modelos de SQLAlchemy

# --- SCHEMAS DE MASCOTAS ---
class PetBase(BaseModel):
    name: str
    species: str
    birth_date: date
    weight:float
    reproductive_status: bool = False

class PetCreate(PetBase):
    path_url: Optional[str] = None

class PetUpdate(BaseModel):
    name: Optional[str] = None
    species: Optional[str] = None
    birth_date: Optional[date] = None
    weight: Optional[float] = None
    reproductive_status: Optional[bool] = None
    path_url: Optional[str] = None

class Pet(PetBase):
    path_url: Optional[str] = None
    id: int
    user_id: int

    class Config:
        from_attributes = True

class PetWithSchedules(Pet):
    schedules: List["Schedule"] = []

# --- SCHEMA DE DISPENSADORES ---
from app.schemas.dispenser import (
    DispenserBase,
    DispenserAssociation,
    DispenserCreate,
    DispenserUpdate,
    Dispenser,
    DispenserRefillRequest,
    DispenserWiFiResetRequest,
    DispenserWiFiResetResponse,
)

# --- SCHEMAS DE HORARIOS ---
class ScheduleBase(BaseModel):
    time: str
    amount: float

    @field_validator('time')
    @classmethod
    def validate_time(cls, v: str) -> str:
        # Valida formato HH:MM (24h) desde 00:00 hasta 23:59
        if not re.match(r"^([01]\d|2[0-3]):([0-5]\d)$", v):
            raise ValueError('El formato de hora debe ser HH:MM (24h), ejemplo: "14:30"')
        return v

    @field_validator('amount')
    @classmethod
    def validate_amount(cls, v: float) -> float:
        if v <= 0:
            raise ValueError('La cantidad debe ser un número positivo mayor a cero')
        return v

class ScheduleCreate(ScheduleBase):
    pass

class ScheduleUpdate(BaseModel):
    time: Optional[str] = None
    amount: Optional[float] = None

    @field_validator('time')
    @classmethod
    def validate_time(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not re.match(r"^([01]\d|2[0-3]):([0-5]\d)$", v):
            raise ValueError('El formato de hora debe ser HH:MM (24h), ejemplo: "14:30"')
        return v

    @field_validator('amount')
    @classmethod
    def validate_amount(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and v <= 0:
            raise ValueError('La cantidad debe ser un número positivo mayor a cero')
        return v

class Schedule(ScheduleBase):
    id: int
    pet_id: int 

    class Config:
        from_attributes = True

class FeedingStatus(BaseModel):
    is_feeding_time: bool
    amount: float

class AutoScheduleRequest(BaseModel):
    food_kcal_per_kg: float
    bcs: int = 5
    mcs: str = "normal"
    activity_level: str = "medium"
    meals_per_day: int = 2

class AutoScheduleResponse(BaseModel):
    rer: float
    mer: float
    daily_grams: float
    water_min_ml: float
    water_max_ml: float
    warnings: List[str]
    schedules: List[Schedule]

    class Config:
        from_attributes = True

# --- SCHEMAS DE LOGS (HISTORIAL) ---
# La consulta del historial vive en `app/schemas/logs.py` desde la T7 de la spec
# 014: sobre paginado, etiquetas en español y catálogo de filtros. El alta viaja
# solo por `activity_service`, así que no existe un esquema de creación.

# --- SCHEMAS DE DASHBOARD ---
class DashboardSummary(BaseModel):
    """Resumen del panel calculado con datos reales (spec 022, RF-6).

    Conserva los siete campos anteriores y añade `today_index` (posición de hoy
    en la serie, de 0 lunes a 6 domingo) y `calculated_at` (instante del cálculo
    en UTC con sufijo `Z`). La app usa estos dos campos del servidor como fuente
    de verdad, nunca el reloj del dispositivo.
    """

    total_pets: int
    sterilized_pets: int
    food_dispensed_today: float
    food_target_today: float
    pending_feedings: int
    completed_feedings: int
    # Exactamente siete posiciones (lunes a domingo) y una posición de hoy
    # válida: el contrato no admite series incompletas ni índices fuera de rango
    # (RF-5, RF-6).
    weekly_dispensed: List[float] = Field(min_length=7, max_length=7)
    today_index: int = Field(ge=0, le=6)
    calculated_at: str
