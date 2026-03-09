from typing import List
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.models import models
from app.schemas import schemas
from app.services import logs_service
from app.db.database import get_db

router = APIRouter()

@router.get("/", response_model=List[schemas.ActivityLog])
def obtener_mis_logs(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    return logs_service.obtener_mis_logs(db=db, user_id=current_user.id)

@router.post("/", response_model=schemas.ActivityLog)   
def crear_log(
    log: schemas.ActivityLogCreate, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    return logs_service.crear_log(db=db, log=log, user_id=current_user.id)