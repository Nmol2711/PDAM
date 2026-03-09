from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional

from app.db.database import get_db
from app.api.deps import get_current_user
from app.models import models
from app.schemas import schemas
from app.services import schedule_service # <--- Importamos tu archivo único

router = APIRouter()

@router.post("/", response_model=schemas.Schedule)
def crear_horario(
    schedule: schemas.ScheduleCreate, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    return schedule_service.crear_horario(db=db, schedule=schedule, user_id=current_user.id)


@router.get("/", response_model=List[schemas.Schedule])
def obtener_mis_horarios(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    # Esto filtrará para que yo solo vea MIS horarios
    return schedule_service.obtener_mis_horarios(db=db, user_id=current_user.id)


@router.put("/{schedule_id}", response_model=schemas.Schedule)
def editar_horario(     
    schedule_id: int,
    time: Optional[str] = None,
    amount: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    return schedule_service.editar_horario(db=db, schedule_id=schedule_id, time=time, amount=amount, user_id=current_user.id)