from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app.models import models
from app.schemas import schemas

def obtener_mis_logs(db: Session, user_id: int):
    return db.query(models.ActivityLog).filter(models.ActivityLog.user_id == user_id).all()

def crear_log(db: Session, log: schemas.ActivityLogCreate, user_id: int):
    nuevo_log = models.ActivityLog(
        event=log.event,
        user_id=user_id
       
    )
    db.add(nuevo_log)
    db.commit()
    db.refresh(nuevo_log)
    return nuevo_log    