from pydantic import BaseModel, EmailStr
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

# --- SCHEMAS DE HORARIOS ---
class ScheduleBase(BaseModel):
    time: str
    amount: int

class ScheduleCreate(ScheduleBase):
    pass

class Schedule(ScheduleBase):
    id: int
    user_id: int

    class Config:
        from_attributes = True

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