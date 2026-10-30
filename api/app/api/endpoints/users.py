from typing import Any

from fastapi import APIRouter, Body, Depends
from sqlalchemy.orm import Session

from app.api.deps import CurrentIdentity, CurrentUser
from app.db.database import get_db
from app.domain.cuenta import normalizar_correo
from app.domain.tiempo import ahora_utc
from app.schemas import account as account_schemas
from app.schemas import schemas
from app.services import account_service, user_service

router = APIRouter()

@router.post("/", response_model=schemas.User)
def registrar_usuario(user: schemas.UserCreate, db: Session = Depends(get_db)):
    return user_service.crear_usuario(db=db, user=user)

@router.get("/me", response_model=account_schemas.AccountProfile)
def leer_mi_perfil(current_user: CurrentUser):
    """Perfil de la cuenta autenticada con el correo normalizado (RF-06)."""
    return {
        "id": current_user.id,
        "email": normalizar_correo(current_user.email),
        "is_active": bool(current_user.is_active),
    }

@router.patch("/me", response_model=account_schemas.AccountUpdateResponse)
def actualizar_mi_perfil(
    solicitud: account_schemas.AccountUpdateRequest,
    current_user: CurrentUser,
    identidad: CurrentIdentity,
    db: Session = Depends(get_db),
):
    """Actualiza correo o contraseña y emite token nuevo si el correo cambia.

    El endpoint solo traduce HTTP ↔ servicio: la validación, la escritura
    condicional y la revocación viven en `account_service` y en el dominio
    (RF-10 a RF-14, RF-21).
    """
    return account_service.actualizar_cuenta(
        db,
        current_user,
        solicitud,
        ahora_utc(),
        jti=identidad.jti,
        expira_en=identidad.expira_en,
    )


@router.delete("/me", response_model=account_schemas.AccountDeleteResponse)
def eliminar_mi_cuenta(
    identidad: CurrentIdentity,
    cuerpo: Any = Body(default=None),
    db: Session = Depends(get_db),
):
    """Baja física de la cuenta autenticada (RF-17 a RF-21).

    Usa `get_current_identity` y no `get_current_user`: la baja debe responder
    éxito aunque el token corresponda a una cuenta ya eliminada, porque es la
    única excepción al 401 de RF-19 y lo que la hace idempotente.

    El cuerpo se recibe como `Any` para que un cuerpo ausente o mal formado
    llegue al servicio como contraseña vacía y responda 400 `invalid_password`,
    nunca 422. El endpoint solo traduce HTTP ↔ servicio.
    """
    datos = cuerpo if isinstance(cuerpo, dict) else {}
    solicitud = account_schemas.AccountDeleteRequest.model_validate(datos)
    return account_service.eliminar_cuenta(
        db, identidad.public_id, solicitud.password, ahora_utc()
    )
