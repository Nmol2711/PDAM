from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional

from app.db.database import get_db
from app.api.deps import CurrentUser
from app.models import models
from app.schemas import schemas
from app.services import schedule_service, pet_service # <--- Importamos tu archivo único

router = APIRouter()

@router.post("/", response_model=schemas.Schedule)
def crear_horario(
    current_user: CurrentUser,
    schedule: schemas.ScheduleCreate,
    pet_id: int,
    db: Session = Depends(get_db),
):
    return schedule_service.crear_horario(db=db, schedule=schedule, pet_id=pet_id, user_id=current_user.id)


@router.get("/", response_model=List[schemas.Schedule])
def obtener_mis_horarios(
    current_user: CurrentUser,
    db: Session = Depends(get_db),
):
    # Esto filtrará para que yo solo vea MIS horarios
    return schedule_service.obtener_mis_horarios(db=db, user_id=current_user.id)


@router.put("/{schedule_id}", response_model=schemas.Schedule)
def editar_horario(     
    current_user: CurrentUser,
    schedule_id: int,
    schedule_update: schemas.ScheduleUpdate,
    db: Session = Depends(get_db),
):
    return schedule_service.editar_horario(db=db, schedule_id=schedule_id, time=schedule_update.time, amount=schedule_update.amount, user_id=current_user.id)

@router.delete("/{schedule_id}")
def eliminar_horario(
    current_user: CurrentUser,
    schedule_id: int,
    db: Session = Depends(get_db),
):
    return schedule_service.eliminar_horario(db=db, schedule_id=schedule_id, user_id=current_user.id)

@router.get("/check-feeding/{pet_id}", response_model=schemas.FeedingStatus)
def consultar_estado_alimentacion(
    current_user: CurrentUser,
    pet_id: int,
    db: Session = Depends(get_db),
):
    """Endpoint para que el hardware verifique si debe dispensar comida."""
    return schedule_service.verificar_horario_pet(db=db, pet_id=pet_id, user_id=current_user.id)

@router.get("/{schedule_id}", response_model=schemas.Schedule)
def obtener_horario_por_id(
    current_user: CurrentUser,
    schedule_id:int,
    pet_id:int,
    db: Session = Depends(get_db),
    ):
    pet = pet_service.obtener_mascota_por_id(db=db, pet_id=pet_id, user_id=current_user.id)
    return schedule_service.obtener_horario_por_id(db=db, id=schedule_id, pet_id=pet.id)

@router.get("/pet/{pet_id}", response_model=List[schemas.Schedule])
def obtener_horario_por_mascota(
    current_user: CurrentUser,
    pet_id:int,
    db: Session = Depends(get_db),
    ):
    pet = pet_service.obtener_mascota_por_id(db=db, pet_id=pet_id, user_id=current_user.id)

    return schedule_service.obtener_horarios_por_mascota(db=db, pet_id=pet.id)