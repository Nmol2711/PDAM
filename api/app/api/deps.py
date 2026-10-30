"""Dependencias de autenticación de la API (spec 015, T3).

El token identifica la cuenta por su identidad estable (`sub=public_id`) y por
`jti`. `get_current_identity` valida el token y su revocación sin exigir que la
cuenta exista, porque la baja de RF-18 necesita responder éxito cuando la cuenta
ya no está; `get_current_user` añade la consulta de la cuenta y es la dependencia
del resto de rutas protegidas. Todo rechazo responde 401 `unauthorized` con el
cuerpo del catálogo (RF-05, RF-19).
"""

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Annotated, Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.core.confg import settings
from app.db.database import get_db
from app.domain.cuenta import ERRORES_CUENTA
from app.domain.tiempo import a_utc_naive, ahora_utc
from app.domain.token import claims_utilizables
from app.models import models
from app.services import user_service

# `auto_error=False` para responder siempre con el cuerpo del catálogo y no con
# el 401 de texto plano que emite el esquema cuando falta el token.
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login", auto_error=False)


@dataclass(frozen=True)
class Identidad:
    """Identidad del token ya validado, sin exigir que la cuenta exista.

    `expira_en` es el `exp` del token en UTC sin zona, necesario para registrar
    la revocación del `jti` con su caducidad real (RF-10).
    """

    public_id: str
    jti: str
    expira_en: Optional[datetime] = None


def error_autorizacion() -> HTTPException:
    """401 `unauthorized` del catálogo para cualquier token no utilizable."""
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={
            "code": "unauthorized",
            "message": ERRORES_CUENTA["unauthorized"],
        },
        headers={"WWW-Authenticate": "Bearer"},
    )


def _esta_revocado(db: Session, jti: str) -> bool:
    return (
        db.query(models.RevokedToken.id)
        .filter(models.RevokedToken.jti == jti)
        .first()
        is not None
    )


def _expira_en(payload: dict) -> Optional[datetime]:
    exp = payload.get("exp")
    if isinstance(exp, bool) or not isinstance(exp, (int, float)):
        return None
    return a_utc_naive(datetime.fromtimestamp(float(exp), tz=timezone.utc))


def get_current_identity(
    db: Session = Depends(get_db),
    token: Optional[str] = Depends(oauth2_scheme),
) -> Identidad:
    """Identidad del token sin consultar la cuenta (RF-10, RF-18, RF-19)."""
    if not token:
        raise error_autorizacion()

    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
    except JWTError:
        raise error_autorizacion() from None

    jti = payload.get("jti")
    revocados = {jti} if isinstance(jti, str) and _esta_revocado(db, jti) else set()
    if not claims_utilizables(payload, ahora_utc(), revocados):
        raise error_autorizacion()

    return Identidad(
        public_id=payload["sub"],
        jti=payload["jti"],
        expira_en=_expira_en(payload),
    )


def get_current_user(
    db: Session = Depends(get_db),
    identidad: Identidad = Depends(get_current_identity),
):
    """Cuenta autenticada por `public_id`; 401 si ya no existe (RF-19)."""
    user = user_service.obtener_usuario_por_public_id(db, identidad.public_id)
    if user is None:
        raise error_autorizacion()
    return user


CurrentUser = Annotated[models.User, Depends(get_current_user)]
CurrentIdentity = Annotated[Identidad, Depends(get_current_identity)]
