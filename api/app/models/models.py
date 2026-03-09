from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)

    # Relaciones: "back_populates" sirve para que si tengo el usuario, 
    # pueda acceder a sus horarios con user.schedules fácilmente.
    schedules = relationship("Schedule", back_populates="owner")
    logs = relationship("ActivityLog", back_populates="owner")

class Schedule(Base):
    __tablename__ = "schedules"

    id = Column(Integer, primary_key=True, index=True)
    time = Column(String, nullable=False) # Guardaremos formato "HH:MM"
    amount = Column(Integer, nullable=False) # Cantidad de comida en gramos
    user_id = Column(Integer, ForeignKey("users.id"))

    owner = relationship("User", back_populates="schedules")

class ActivityLog(Base):
    __tablename__ = "logs"

    id = Column(Integer, primary_key=True, index=True)
    event = Column(String, nullable=False) # Ej: "Dispensador activado"
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    user_id = Column(Integer, ForeignKey("users.id"))

    owner = relationship("User", back_populates="logs")