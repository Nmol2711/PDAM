"""Actualización y baja de la cuenta (spec 015, T3 y T4).

La validación, la normalización y la decisión viven en `app.domain.cuenta`; este
servicio aplica el plan de actualización con una escritura condicional y resuelve
la baja con un borrado ordenado y una sola transacción (RF-10, RF-11, RF-12,
RF-14, RF-17 a RF-21, RNF-09). No contiene textos de error: los toma del catálogo
del dominio.
"""

from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy import or_, select, update
from sqlalchemy.orm import Session

from app.core import security
from app.core.confg import settings
from app.domain.cuenta import normalizar_correo, resolver_actualizacion
from app.domain.tiempo import a_utc_naive
from app.domain.token import nuevo_jti
from app.models import models
from app.services import user_service


def actualizar_cuenta(
    db: Session,
    user: models.User,
    solicitud,
    ahora: datetime,
    *,
    jti: Optional[str] = None,
    expira_en: Optional[datetime] = None,
):
    """Aplica la actualización del perfil y devuelve el contrato de respuesta.

    `solicitud.email` ausente (`None`) significa «sin cambio de correo», no un
    correo inválido; `new_password` ausente o vacío significa «sin cambio de
    contraseña». El correo nuevo se compara normalizado: si solo difiere en
    mayúsculas o espacios exteriores, cuenta como igual y no se toca.

    La escritura es condicional (`WHERE id AND hashed_password AND email`) para
    detectar una actualización simultánea: si no afecta a ninguna fila se
    revierte y se responde `conflict`. Solo cuando el correo cambia se revoca el
    `jti` usado en esa petición y se emite un token nuevo; el resto de sesiones
    de la cuenta conservan el suyo. Todo ocurre en una única transacción.
    """
    correo_solicitado = user.email if solicitud.email is None else solicitud.email
    plan = resolver_actualizacion(
        user.email, correo_solicitado, solicitud.new_password
    )
    if plan.error is not None:
        raise user_service.error_de_cuenta(plan.error)

    if plan.cambia_correo:
        existente = user_service.obtener_usuario_por_correo_normalizado(
            db, plan.correo_nuevo
        )
        if existente is not None and existente.id != user.id:
            raise user_service.error_de_cuenta("email_already_registered")

    if plan.cambia_correo and not jti:
        # Error de programación: el endpoint siempre pasa el token usado.
        raise ValueError(
            "La actualización con cambio de correo exige el jti del token usado."
        )

    correo_previo = user.email
    hash_previo = user.hashed_password
    correo_final = plan.correo_nuevo if plan.cambia_correo else correo_previo
    activo = bool(user.is_active)
    token_nuevo = None

    try:
        hash_final = (
            security.get_password_hash(solicitud.new_password)
            if plan.cambia_password
            else hash_previo
        )
        resultado = db.execute(
            update(models.User)
            .where(
                models.User.id == user.id,
                models.User.hashed_password == hash_previo,
                models.User.email == correo_previo,
            )
            .values(email=correo_final, hashed_password=hash_final)
        )
        if resultado.rowcount == 0:
            db.rollback()
            raise user_service.error_de_cuenta(
                "conflict", status.HTTP_500_INTERNAL_SERVER_ERROR
            )

        if plan.cambia_correo:
            expiracion = expira_en if expira_en is not None else ahora
            # Purga oportunista: un token revocado ya caducado no puede
            # aceptarse (lo rechaza `exp`) y solo haría crecer la tabla. Se
            # ejecuta en la misma transacción que la revocación (RF-10).
            db.query(models.RevokedToken).filter(
                models.RevokedToken.expires_at < a_utc_naive(ahora)
            ).delete(synchronize_session=False)
            db.add(
                models.RevokedToken(
                    jti=jti,
                    public_id=user.public_id,
                    expires_at=a_utc_naive(expiracion),
                    revoked_at=a_utc_naive(ahora),
                )
            )
            token_nuevo = security.crear_token_acceso(
                user.public_id,
                nuevo_jti(),
                expires_delta=timedelta(
                    minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
                ),
            )

        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise user_service.error_de_cuenta(
            "server_error", status.HTTP_500_INTERNAL_SERVER_ERROR
        ) from None

    return {
        "email": normalizar_correo(correo_final),
        "is_active": activo,
        "access_token": token_nuevo,
        "token_type": "bearer" if token_nuevo else None,
    }


def _predicado_cola(pet_ids, dispenser_ids, schedule_ids):
    """Filas de `dispensing_queue` que pertenecen a la cuenta (RNF-09).

    Se comparte entre el borrado y la comprobación de huérfanos para que ambos
    usen exactamente el mismo criterio.
    """
    return or_(
        models.DispensingQueue.pet_id.in_(pet_ids),
        models.DispensingQueue.dispenser_id.in_(dispenser_ids),
        models.DispensingQueue.schedule_id.in_(schedule_ids),
    )


def _predicado_ordenes(user_id: int, pet_ids, dispenser_ids):
    """Órdenes de la cuenta por propietario, mascota o dispensador (RNF-09)."""
    return or_(
        models.DispensingOrder.user_id == user_id,
        models.DispensingOrder.pet_id.in_(pet_ids),
        models.DispensingOrder.dispenser_id.in_(dispenser_ids),
    )


def _predicado_reabastecimientos(user_id: int, dispenser_ids):
    """Reabastecimientos de la cuenta por propietario o dispensador (RNF-09)."""
    return or_(
        models.RefillOperation.user_id == user_id,
        models.RefillOperation.dispenser_id.in_(dispenser_ids),
    )


def _predicado_registros(user_id: int, pet_ids, dispenser_ids):
    """Registros de actividad de la cuenta (RNF-09).

    Cubre las filas migradas sin propietario (`user_id` nulo) que conservan la
    mascota o el dispensador de la cuenta.
    """
    return or_(
        models.ActivityLog.user_id == user_id,
        models.ActivityLog.pet_id.in_(pet_ids),
        models.ActivityLog.dispenser_id.in_(dispenser_ids),
    )


def contar_huerfanos(
    db: Session,
    user_id: int,
    public_id: str,
    *,
    pet_ids=(),
    dispenser_ids=(),
    schedule_ids=(),
) -> int:
    """Cuenta las filas que siguen referenciando a la cuenta (RNF-09).

    Se invoca dentro de la misma transacción del borrado, después de ejecutar
    las sentencias y antes del `commit`. Como las mascotas y los dispensadores ya
    no existen, sus identificadores se reciben como instantánea capturada antes
    de borrarlos; sin ellos la comprobación de `dispensing_queue`, `schedules` y
    `dispensers` no podría detectar una fila superviviente.

    Cubre las tablas con clave foránea, las que guardan el propietario sin clave
    foránea (`dispensing_orders`, `refill_operations`, `logs`) y las columnas de
    instantánea (`pet_id`, `dispenser_id`). Devuelve la suma de todas las filas.
    """
    mascotas = list(pet_ids)
    dispensadores = list(dispenser_ids)
    horarios = list(schedule_ids)

    comprobaciones = (
        (models.Pet, models.Pet.user_id == user_id),
        (models.Dispenser, models.Dispenser.pet_id.in_(mascotas)),
        (models.Schedule, models.Schedule.pet_id.in_(mascotas)),
        (
            models.DispensingQueue,
            _predicado_cola(mascotas, dispensadores, horarios),
        ),
        (
            models.DispensingOrder,
            _predicado_ordenes(user_id, mascotas, dispensadores),
        ),
        (
            models.RefillOperation,
            _predicado_reabastecimientos(user_id, dispensadores),
        ),
        (
            models.ActivityLog,
            _predicado_registros(user_id, mascotas, dispensadores),
        ),
        (models.RevokedToken, models.RevokedToken.public_id == public_id),
    )

    return sum(
        db.query(modelo).filter(condicion).count()
        for modelo, condicion in comprobaciones
    )


def _identificadores(consulta) -> list:
    return [fila[0] for fila in consulta.all()]


def _borrar_datos(db: Session, user_id: int, public_id: str) -> bool:
    """Borra los datos de la cuenta en el orden que respetan las FK (RF-18).

    Devuelve `False` si la fila de `users` ya no existe: otra baja simultánea se
    adelantó y la operación se resuelve por idempotencia. En ese caso el
    llamador revierte y responde éxito.

    La primera sentencia es una escritura (`DELETE` de la cola) para que SQLite
    tome el bloqueo de escritura antes de leer los identificadores; así dos bajas
    simultáneas se serializan con el `busy_timeout` en lugar de competir por el
    paso de lectura a escritura. Todo ocurre en una única transacción.
    """
    ids_usuario = select(models.User.id).where(models.User.public_id == public_id)
    ids_mascotas = select(models.Pet.id).where(models.Pet.user_id.in_(ids_usuario))
    ids_dispensadores = select(models.Dispenser.id).where(
        models.Dispenser.pet_id.in_(ids_mascotas)
    )
    ids_horarios = select(models.Schedule.id).where(
        models.Schedule.pet_id.in_(ids_mascotas)
    )

    db.query(models.DispensingQueue).filter(
        _predicado_cola(ids_mascotas, ids_dispensadores, ids_horarios)
    ).delete(synchronize_session=False)

    # Instantánea de los identificadores para `contar_huerfanos`: al terminar el
    # borrado las subconsultas ya no podrían encontrarlos.
    mascotas = _identificadores(
        db.query(models.Pet.id).filter(models.Pet.user_id.in_(ids_usuario))
    )
    dispensadores = _identificadores(
        db.query(models.Dispenser.id).filter(models.Dispenser.pet_id.in_(mascotas))
    )
    horarios = _identificadores(
        db.query(models.Schedule.id).filter(models.Schedule.pet_id.in_(mascotas))
    )

    db.query(models.DispensingOrder).filter(
        _predicado_ordenes(user_id, mascotas, dispensadores)
    ).delete(synchronize_session=False)
    db.query(models.RefillOperation).filter(
        _predicado_reabastecimientos(user_id, dispensadores)
    ).delete(synchronize_session=False)
    db.query(models.ActivityLog).filter(
        _predicado_registros(user_id, mascotas, dispensadores)
    ).delete(synchronize_session=False)
    db.query(models.Dispenser).filter(
        models.Dispenser.pet_id.in_(mascotas)
    ).delete(synchronize_session=False)
    db.query(models.Schedule).filter(
        models.Schedule.pet_id.in_(mascotas)
    ).delete(synchronize_session=False)
    db.query(models.Pet).filter(
        models.Pet.user_id.in_(ids_usuario)
    ).delete(synchronize_session=False)
    db.query(models.RevokedToken).filter(
        models.RevokedToken.public_id == public_id
    ).delete(synchronize_session=False)

    filas_usuario = db.query(models.User).filter(
        models.User.public_id == public_id
    ).delete(synchronize_session=False)
    if filas_usuario == 0:
        return False

    if (
        contar_huerfanos(
            db,
            user_id,
            public_id,
            pet_ids=mascotas,
            dispenser_ids=dispensadores,
            schedule_ids=horarios,
        )
        > 0
    ):
        db.rollback()
        raise user_service.error_de_cuenta(
            "server_error", status.HTTP_500_INTERNAL_SERVER_ERROR
        )

    return True


def eliminar_cuenta(
    db: Session,
    public_id: str,
    password,
    ahora: datetime,
) -> dict:
    """Baja física, transaccional e idempotente de la cuenta (RF-17 a RF-21).

    Si la cuenta no existe responde éxito sin verificar la contraseña: es la
    idempotencia que tolera una respuesta perdida y dos bajas simultáneas. La
    contraseña se verifica con `security.verify_password` y no se persiste ni se
    registra (RNF-06); ausente, vacía o incorrecta responde `invalid_password`.

    La lectura de la cuenta se cierra antes de verificar y escribir para no
    retener el bloqueo compartido de SQLite durante el hash: el borrado se hace
    en una transacción nueva con un único `commit`. Cualquier fallo revierte el
    borrado completo y responde `server_error`, nunca `conflict` ni
    `pet_has_dispenser` (RNF-09).

    `ahora` se recibe por coherencia con el resto de servicios, aunque la baja no
    escribe marcas de tiempo: la verificación del token ya la hizo la dependencia.
    """
    fila = (
        db.query(models.User.id, models.User.hashed_password)
        .filter(models.User.public_id == public_id)
        .first()
    )
    if fila is None:
        db.rollback()
        return {"deleted": True}

    user_id, hash_actual = fila
    db.rollback()

    if not isinstance(password, str) or not password:
        raise user_service.error_de_cuenta("invalid_password")
    if not security.verify_password(password, hash_actual):
        raise user_service.error_de_cuenta("invalid_password")

    try:
        if not _borrar_datos(db, user_id, public_id):
            db.rollback()
            return {"deleted": True}
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise user_service.error_de_cuenta(
            "server_error", status.HTTP_500_INTERNAL_SERVER_ERROR
        ) from None

    return {"deleted": True}
