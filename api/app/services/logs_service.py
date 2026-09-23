from typing import Optional
from datetime import date
from sqlalchemy.orm import Session
from sqlalchemy import func
from fastapi import HTTPException, status
from app.models import models
from app.schemas import schemas

def obtener_mis_logs(db: Session, user_id: int, pet_id: Optional[int] = None, fecha: Optional[date] = None):
    query = db.query(models.ActivityLog).filter(models.ActivityLog.user_id == user_id)
    if pet_id is not None:
        query = query.filter(models.ActivityLog.pet_id == pet_id)
    if fecha is not None:
        query = query.filter(func.date(models.ActivityLog.timestamp) == fecha)
    return query.order_by(models.ActivityLog.timestamp.desc()).all()

def crear_log(db: Session, log: schemas.ActivityLogCreate, user_id: int):
    nuevo_log = models.ActivityLog(
        event=log.event,
        pet_id=log.pet_id,
        user_id=user_id
    )
    db.add(nuevo_log)
    db.commit()
    db.refresh(nuevo_log)
    return nuevo_log
