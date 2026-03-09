from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app.models import models
from app.schemas import schemas
from app.core.security import get_password_hash

# Función para buscar si un usuario ya existe
def obtener_usuario_por_email(db: Session, email: str):
    return db.query(models.User).filter(models.User.email == email).first()

def crear_usuario(db: Session, user: schemas.UserCreate):
    # 1. Validar si el usuario ya existe
    usuario_existente = obtener_usuario_por_email(db, user.email)
    if usuario_existente:
        # Lanzamos un error de FastAPI que el usuario podrá entender
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El correo electrónico ya está registrado."
        )

    # 2. Encriptar la contraseña
    hashed_pw = get_password_hash(user.password)
    
    # 3. Crear el objeto del Modelo
    db_user = models.User(
        email=user.email,
        hashed_password=hashed_pw
    )
    
    # 4. Guardar en la base de datos
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user