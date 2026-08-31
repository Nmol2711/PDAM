import re
from pydantic import BaseModel, EmailStr, field_validator
from typing import List, Optional
from datetime import datetime

# --- SCHEMAS DE USUARIO ---
class UserBase(BaseModel):
    email: EmailStr

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
    age:int
    weight:float

class PetCreate(PetBase):
    path_url: Optional[str] = None

class PetUpdate(BaseModel):
    name: Optional[str] = None
    species: Optional[str] = None
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
class DispenserBase(BaseModel):
    mac_address: str
    pet_id: int

class DispenserAssociation(DispenserBase):
    secret_key_qr: str

    @field_validator('mac_address')
    @classmethod
    def validate_mac(cls, v: str) -> str:
        mac_regex = r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'
        if not re.match(mac_regex, v):
            raise ValueError('Formato de dirección MAC inválido')
        return v.upper()

class DispenserCreate(DispenserBase):
    pass

class DispenserUpdate(BaseModel):
    pet_id: Optional[int] = None
    mac_address: Optional[str] = None
    is_active : Optional[bool] = None
    pending_dispensing : Optional[bool] = None


class Dispenser(DispenserBase):
    id : int
    is_active : bool 
    pending_dispensing : bool

    class Config:
        from_attributes = True

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

# --- SCHEMAS DE LOGS (HISTORIAL) ---
class ActivityLogBase(BaseModel):
    event: str

class ActivityLogCreate(ActivityLogBase):
    pass

class ActivityLog(ActivityLogBase):
    id: int
    timestamp: datetime
    user_id: int

    class Config:
        from_attributes = True