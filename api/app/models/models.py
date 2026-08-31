from sqlalchemy import Column, Float, Integer, String, Boolean, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)

    # Relaciones cruzadas correctamente con sus hijos
    pets = relationship("Pet", back_populates="owner")
    logs = relationship("ActivityLog", back_populates="owner")


class Pet(Base): 
    __tablename__ = "pets"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    species = Column(String, nullable=False)
    age = Column(Integer, nullable=False)
    weight = Column(Float, nullable=False)

    path_url = Column(String, nullable=True)
    user_id = Column(Integer, ForeignKey("users.id"))

    # Relación hacia el padre (User) y hacia sus hijos (Schedule)
    owner = relationship("User", back_populates="pets")
    dispenser = relationship("Dispenser", back_populates="pet", uselist=False)
    schedules = relationship("Schedule", back_populates="pet")
    

class Dispenser(Base):
    __tablename__ = "dispensers"

    id = Column(Integer, primary_key=True, index=True)
    mac_address = Column(String, unique=True, nullable=False)
    is_active = Column(Boolean, default=True)
    pending_dispensing = Column(Boolean, default=False, nullable=False)

    pet_id = Column(
        Integer,
        ForeignKey("pets.id",ondelete="CASCADE"),
        nullable=False,
        unique=True
    )

    pet = relationship("Pet", back_populates="dispenser", uselist=False)

class Schedule(Base):
    __tablename__ = "schedules"

    id = Column(Integer, primary_key=True, index=True)
    time = Column(String, nullable=False)    # Formato "HH:MM"
    amount = Column(Float, nullable=False) # Cantidad en gramos
    pet_id = Column(Integer, ForeignKey("pets.id"))

    # Relación correcta: un horario le pertenece a una mascota (Pet), no a un User directamente
    pet = relationship("Pet", back_populates="schedules")


class ActivityLog(Base):
    __tablename__ = "logs"

    id = Column(Integer, primary_key=True, index=True)
    event = Column(String, nullable=False)   # Ej: "Dispensador activado"
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    user_id = Column(Integer, ForeignKey("users.id"))

    # Relación hacia el usuario que generó el log
    owner = relationship("User", back_populates="logs")