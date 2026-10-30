from uuid import uuid4

from sqlalchemy import (
    Column,
    Float,
    Integer,
    String,
    Boolean,
    ForeignKey,
    DateTime,
    Date,
    Text,
    Index,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
    # Identidad estable de la cuenta para el token (RF-10, RF-19). Es opaca y no
    # se muestra: sustituye al correo en `sub`, de modo que registrar de nuevo un
    # correo no rehabilita los tokens de la cuenta eliminada. El valor por
    # defecto es invocable para que cada alta reciba un identificador distinto.
    public_id = Column(
        String,
        unique=True,
        index=True,
        nullable=False,
        default=lambda: uuid4().hex,
    )

    # Relaciones cruzadas correctamente con sus hijos
    pets = relationship("Pet", back_populates="owner")
    logs = relationship("ActivityLog", back_populates="owner")


class Pet(Base): 
    __tablename__ = "pets"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    species = Column(String, nullable=False)
    birth_date = Column(Date, nullable=False)
    weight = Column(Float, nullable=False)
    reproductive_status = Column(Boolean, nullable=False, default=False)

    path_url = Column(String, nullable=True)
    user_id = Column(Integer, ForeignKey("users.id"))

    # Relación hacia el padre (User) y hacia sus hijos (Schedule)
    owner = relationship("User", back_populates="pets")
    dispenser = relationship("Dispenser", back_populates="pet", uselist=False)
    schedules = relationship("Schedule", back_populates="pet")
    

class Dispenser(Base):
    __tablename__ = "dispensers"

    id = Column(Integer, primary_key=True, index=True)
    # Texto tal como lo introdujo o escaneó el usuario: es lo que se muestra.
    mac_address = Column(String, unique=True, nullable=False)
    # Forma canónica (12 hexadecimales en mayúsculas, sin separadores). Es el
    # único campo con el que se compara y el que garantiza la unicidad real
    # mediante su índice único (RF-01, RF-07). La migración que lo rellena está
    # en el listener `connect` de `app/db/database.py`.
    mac_normalized = Column(String, nullable=True, unique=True, index=True)
    is_active = Column(Boolean, default=True)
    pending_dispensing = Column(Boolean, default=False, nullable=False)
    pending_wifi_reset = Column(Boolean, default=False, nullable=False)
    current_food_grams = Column(Float, default=5000.0, nullable=False)

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
    """Registro de actividad del sistema (RF-1, RF-3, RF-41).

    `pet_id` y `dispenser_id` son instantáneas sin clave foránea: la referencia
    debe sobrevivir al borrado de la mascota o del dispensador (RF-6, RF-27).
    Los registros históricos anteriores a la spec 014 quedan con `event_type`,
    `outcome` y `cause` en `NULL` y se presentan como «Sin clasificar».
    """

    __tablename__ = "logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    pet_id = Column(Integer, nullable=True, index=True)
    pet_name = Column(String, nullable=True)
    dispenser_id = Column(Integer, nullable=True, index=True)
    dispenser_mac_masked = Column(String, nullable=True)
    event_type = Column(String, nullable=True, index=True)
    outcome = Column(String, nullable=True, index=True)
    cause = Column(String, nullable=True)
    description = Column(String, nullable=False)
    context = Column(Text, nullable=True)
    order_id = Column(Integer, nullable=True, index=True)
    requested_grams = Column(Float, nullable=True)
    measured_grams = Column(Float, nullable=True)
    discounted_grams = Column(Float, nullable=True)
    resulting_stock = Column(Float, nullable=True)
    retry_count = Column(Integer, nullable=True)
    # Hora del servidor en UTC y sin zona horaria (RNF-8). El valor por defecto
    # es el de SQLite, que ya es UTC, para no depender del reloj del proceso.
    created_at = Column(DateTime, nullable=False, default=func.now(), index=True)

    __table_args__ = (
        # Sostiene la consulta del historial: usuario, orden por fecha y
        # desempate por identificador (RF-26, RNF-2). También se crea de forma
        # idempotente en la migración de `logs` (T2).
        Index("ix_logs_user_id_created_at", "user_id", "created_at"),
    )

    # Relación hacia el usuario que generó el log
    owner = relationship("User", back_populates="logs")


class DispensingOrder(Base):
    """Orden de dispensación entregada al dispositivo (RF-13, RF-18, RF-19).

    `status` solo admite `pending` o `closed`; las transiciones se hacen con
    `UPDATE ... WHERE status = 'pending'` y `rowcount` (RNF-3). Las referencias a
    mascota y dispensador son instantáneas, igual que en `logs`.
    """

    __tablename__ = "dispensing_orders"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=True)
    pet_id = Column(Integer, nullable=True)
    pet_name = Column(String, nullable=True)
    dispenser_id = Column(Integer, nullable=True)
    dispenser_mac_masked = Column(String, nullable=True)
    requested_grams = Column(Float, nullable=False)
    delivered_at = Column(DateTime, nullable=False)
    status = Column(String, nullable=False, default="pending")
    closed_at = Column(DateTime, nullable=True)
    outcome = Column(String, nullable=True)
    cause = Column(String, nullable=True)
    measured_grams = Column(Float, nullable=True)
    discounted_grams = Column(Float, nullable=True)
    resulting_stock = Column(Float, nullable=True)
    retry_count = Column(Integer, nullable=True)
    log_id = Column(Integer, nullable=True)

    __table_args__ = (
        Index("ix_dispensing_orders_status_delivered_at", "status", "delivered_at"),
        Index("ix_dispensing_orders_dispenser_id_status", "dispenser_id", "status"),
        # Una sola orden pendiente por dispensador (RNF-3). El índice es parcial
        # para que las órdenes cerradas no cuenten; SQLite y PostgreSQL admiten
        # la misma cláusula. En bases existentes lo crea la migración
        # (`database._crear_indice_orden_pendiente`) porque `create_all` no añade
        # índices a tablas ya creadas.
        Index(
            "ux_dispensing_orders_pending_dispenser",
            "dispenser_id",
            unique=True,
            sqlite_where=text("status = 'pending'"),
            postgresql_where=text("status = 'pending'"),
        ),
    )


class DispensingQueue(Base):
    """Comida programada que espera su turno (RF-25).

    La restricción única impide encolar dos veces la misma ocurrencia de un
    horario para un dispensador.
    """

    __tablename__ = "dispensing_queue"

    id = Column(Integer, primary_key=True, index=True)
    dispenser_id = Column(
        Integer, ForeignKey("dispensers.id", ondelete="CASCADE"), nullable=False
    )
    pet_id = Column(Integer, nullable=True)
    schedule_id = Column(
        Integer, ForeignKey("schedules.id", ondelete="CASCADE"), nullable=False
    )
    amount = Column(Float, nullable=False)
    scheduled_for = Column(DateTime, nullable=False)
    consumed_at = Column(DateTime, nullable=True)

    __table_args__ = (
        UniqueConstraint(
            "dispenser_id",
            "schedule_id",
            "scheduled_for",
            name="ux_dispensing_queue_ocurrencia",
        ),
    )


class RefillOperation(Base):
    """Reabastecimiento idempotente por `operation_id` (RF-11).

    Un reintento de la app reenvía el mismo `operation_id` y no debe incrementar
    el stock ni escribir otro registro.
    """

    __tablename__ = "refill_operations"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False)
    operation_id = Column(String, nullable=False)
    dispenser_id = Column(Integer, nullable=False)
    grams = Column(Float, nullable=False)
    applied_at = Column(DateTime, nullable=False)
    log_id = Column(Integer, nullable=True)

    __table_args__ = (
        UniqueConstraint(
            "user_id", "operation_id", name="ux_refill_operations_usuario_operacion"
        ),
    )


class RevokedToken(Base):
    """Token invalidado antes de su caducidad (RF-10, RF-19).

    Se revoca por `jti` y no por cuenta: al cambiar el correo solo deja de valer
    el token usado en esa petición y los demás dispositivos conservan el suyo
    hasta que caduque. `public_id` es una instantánea sin clave foránea para que
    el registro sobreviva a la baja de la cuenta, que lo borra explícitamente
    (RF-18).
    """

    __tablename__ = "revoked_tokens"

    id = Column(Integer, primary_key=True, index=True)
    jti = Column(String, unique=True, index=True, nullable=False)
    public_id = Column(String, index=True, nullable=False)
    expires_at = Column(DateTime, nullable=False)
    revoked_at = Column(DateTime, nullable=False)
