from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from datetime import timedelta

from app.db.database import get_db
from app.services import user_service
from app.core import security
from app.core.confg import settings

router = APIRouter()

@router.post("/login")
def login(
    db: Session = Depends(get_db), 
    form_data: OAuth2PasswordRequestForm = Depends()
):
    # 1. Buscar al usuario por email (OAuth2 llama al campo 'username')
    user = user_service.obtener_usuario_por_email(db, email=form_data.username)
    
    # 2. Verificar si el usuario existe y la contraseña es correcta
    if not user or not security.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Correo o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 3. Generar el Token JWT
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = security.create_access_token(
        data={"sub": user.email}, expires_delta=access_token_expires
    )
    
    # 4. Devolver el token al cliente
    return {"access_token": access_token, "token_type": "bearer"}