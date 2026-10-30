from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.domain.cuenta import ERRORES_CUENTA, normalizar_correo
from app.domain.token import nuevo_jti
from app.services import user_service
from app.core import security
from app.core.confg import settings

router = APIRouter()

@router.post("/login")
def login(
    db: Session = Depends(get_db), 
    form_data: OAuth2PasswordRequestForm = Depends()
):
    # 1. Buscar la cuenta comparando el correo en forma normalizada (RF-19).
    correo = normalizar_correo(form_data.username)
    usuario = user_service.obtener_usuario_por_correo_normalizado(db, correo)

    # 2. Verificar si la cuenta existe y la contraseña es correcta. El rechazo
    #    es el mismo para ambos casos y usa el código del catálogo.
    if usuario is None or not security.verify_password(
        form_data.password, usuario.hashed_password
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "code": "invalid_credentials",
                "message": ERRORES_CUENTA["invalid_credentials"],
            },
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 3. Generar el token con la identidad estable y un `jti` irrepetible.
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = security.crear_token_acceso(
        usuario.public_id,
        nuevo_jti(),
        expires_delta=access_token_expires,
    )

    # 4. Devolver el token al cliente
    return {"access_token": access_token, "token_type": "bearer"}
