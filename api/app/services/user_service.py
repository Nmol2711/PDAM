from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from app.core.security import get_password_hash
from app.domain.cuenta import (
    ERRORES_CUENTA,
    es_correo_valido,
    normalizar_correo,
    validar_password_nueva,
)
from app.models import models
from app.schemas import schemas


def error_de_cuenta(codigo: str, estado: int = status.HTTP_400_BAD_REQUEST) -> HTTPException:
    """Rechazo de negocio con el cuerpo `detail={code,message}` del catálogo.

    Ningún rechazo de validación pasa por Pydantic: el código y el mensaje salen
    siempre de `app.domain.cuenta` (RF-11, §5.4).
    """
    return HTTPException(
        status_code=estado,
        detail={"code": codigo, "message": ERRORES_CUENTA[codigo]},
    )


def obtener_usuario_por_public_id(db: Session, public_id: str):
    """Cuenta por su identidad estable; `None` si ya no existe (RF-19)."""
    return (
        db.query(models.User)
        .filter(models.User.public_id == public_id)
        .first()
    )


def obtener_usuario_por_correo_normalizado(db: Session, email: str):
    """Cuenta cuyo correo coincide en forma normalizada (RF-12, RF-19).

    La comparación usa `lower(trim(email))`, así que un correo guardado con
    mayúsculas o espacios exteriores encuentra su cuenta igualmente.
    """
    normalizado = normalizar_correo(email)
    if not normalizado:
        return None
    return (
        db.query(models.User)
        .filter(func.lower(func.trim(models.User.email)) == normalizado)
        .first()
    )


def crear_usuario(db: Session, user: schemas.UserCreate):
    """Alta de cuenta normalizada y validada con el catálogo (RF-11, RF-12).

    El correo se guarda en su forma canónica y el duplicado se traduce a
    `email_already_registered`, tanto en la comprobación previa como si la
    restricción única salta al confirmar. La validación vive aquí y no en el
    esquema, de modo que los rechazos son 400 con código y nunca 422.
    """
    correo = normalizar_correo(user.email)
    if not es_correo_valido(correo):
        raise error_de_cuenta("invalid_email")

    error_password = validar_password_nueva(user.password)
    if error_password is not None:
        raise error_de_cuenta(error_password)

    if obtener_usuario_por_correo_normalizado(db, correo) is not None:
        raise error_de_cuenta("email_already_registered")

    db_user = models.User(
        email=correo,
        hashed_password=get_password_hash(user.password),
    )
    db.add(db_user)
    try:
        db.commit()
    except IntegrityError:
        # Otra petición registró el mismo correo entre la comprobación y el alta.
        db.rollback()
        raise error_de_cuenta("email_already_registered") from None

    db.refresh(db_user)
    return db_user
