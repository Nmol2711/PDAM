from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app.models import models
from app.schemas import schemas

def obtener_mis_horarios(db: Session, user_id: int):
    return db.query(models.Schedule).filter(models.Schedule.user_id == user_id).all()

def obtener_horario_por_time(db: Session, time: str, user_id: int):
    return db.query(models.Schedule).filter(models.Schedule.time == time, models.Schedule.user_id == user_id).first()

def crear_horario(db: Session, schedule: schemas.ScheduleCreate, user_id: int):
    horario_existente = obtener_horario_por_time(db, schedule.time, user_id)
    if horario_existente:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El horario ya existe."
        )
    nuevo_horario = models.Schedule(
        time=schedule.time,
        amount=schedule.amount,
        user_id=user_id
    )
    db.add(nuevo_horario)
    db.commit()
    db.refresh(nuevo_horario)
    return nuevo_horario

def editar_horario(db: Session, schedule_id: int, time: str, amount: int, user_id: int):
    if not time and not amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No se proporcionó ningún campo para actualizar."
        )

    horario_existente = db.query(models.Schedule).filter(models.Schedule.id == schedule_id, models.Schedule.user_id == user_id).first()

    if not horario_existente:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Horario no encontrado"
        )
    horario_existente.time = time if time else horario_existente.time
    horario_existente.amount = amount if amount else horario_existente.amount
    db.commit()
    db.refresh(horario_existente)
    return horario_existente


    
