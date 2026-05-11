from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.core.confg import settings
from app.services import user_service
from app.models import models
from typing import Annotated

# Esto le dice a FastAPI que busque el token en el header "Authorization"
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")

def get_current_user(db: Session = Depends(get_db), token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudo validar el token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        # 1. Decodificar el token
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    
    # 2. Buscar al usuario en la DB
    user = user_service.obtener_usuario_por_email(db, email=email)
    if user is None:
        raise credentials_exception
    return user

CurrentUser = Annotated[models.User, Depends(get_current_user)]