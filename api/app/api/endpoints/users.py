from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api.deps import CurrentUser
from app.models import models
from app.schemas import schemas
from app.services import user_service
from app.db.database import get_db

router = APIRouter()

@router.post("/", response_model=schemas.User)
def registrar_usuario(user: schemas.UserCreate, db: Session = Depends(get_db)):
    return user_service.crear_usuario(db=db, user=user)

@router.get("/me", response_model=schemas.User)

def leer_mi_perfil(current_user: CurrentUser):
    return current_user