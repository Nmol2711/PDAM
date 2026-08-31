from datetime import datetime
from typing import Optional
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app.models import models
from app.schemas import schemas

def obtener_mis_horarios(db: Session, user_id: int):
    # Ahora buscamos los horarios uniendo la tabla de mascotas
    return db.query(models.Schedule).join(models.Pet).filter(models.Pet.user_id == user_id).all()

def obtener_horario_por_time(db: Session, time: str, pet_id: int):
    # Validamos por mascota
    return db.query(models.Schedule).filter(models.Schedule.time == time, models.Schedule.pet_id == pet_id).first()

def obtener_horario_por_id(db: Session, id: int, pet_id:int):
    return db.query(models.Schedule).filter(models.Schedule.id == id, models.Schedule.pet_id == pet_id).first()

def obtener_horarios_por_mascota(db:Session, pet_id:int):
    return db.query(models.Schedule).filter(models.Schedule.pet_id == pet_id).all()

def crear_horario(db: Session, schedule: schemas.ScheduleCreate, pet_id: int, user_id: int):
    # Verificamos que la mascota pertenezca al usuario
    mascota = db.query(models.Pet).filter(models.Pet.id == pet_id, models.Pet.user_id == user_id).first()
    if not mascota:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="La mascota especificada no existe o no te pertenece."
        )

    horario_existente = obtener_horario_por_time(db, schedule.time, pet_id)
    if horario_existente:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El horario ya existe para esta mascota."
        )
    nuevo_horario = models.Schedule(
        time=schedule.time,
        amount=schedule.amount,
        pet_id=pet_id
    )
    db.add(nuevo_horario)
    db.commit()
    db.refresh(nuevo_horario)
    return nuevo_horario

def editar_horario(db: Session, schedule_id: int, time: Optional[str], amount: Optional[float], user_id: int):
    if not time and not amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No se proporcionó ningún campo para actualizar."
        )

    # Verificamos que el horario pertenezca a una mascota del usuario
    horario_existente = db.query(models.Schedule).join(models.Pet).filter(
        models.Schedule.id == schedule_id, 
        models.Pet.user_id == user_id
    ).first()

    if not horario_existente:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Horario no encontrado o no pertenece a tus mascotas."
        )
        
    horario_existente.time = time if time else horario_existente.time
    horario_existente.amount = amount if amount else horario_existente.amount
    db.commit()
    db.refresh(horario_existente)
    return horario_existente

def eliminar_horario(db: Session, schedule_id: int, user_id: int):
    horario = db.query(models.Schedule).join(models.Pet).filter(
        models.Schedule.id == schedule_id,
        models.Pet.user_id == user_id
    ).first()

    if not horario:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Horario no encontrado."
        )
    
    db.delete(horario)
    db.commit()
    return {"message": "Horario eliminado correctamente"}

def verificar_horario_pet(db: Session, pet_id: int, user_id: int):
    # 1. Validar que la mascota existe y pertenece al usuario
    mascota = db.query(models.Pet).filter(models.Pet.id == pet_id, models.Pet.user_id == user_id).first()
    if not mascota:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mascota no encontrada")

    # 2. Obtener hora actual en minutos desde medianoche
    ahora = datetime.now()
    mins_actuales = ahora.hour * 60 + ahora.minute

    # 3. Revisar horarios de la mascota
    horarios = db.query(models.Schedule).filter(models.Schedule.pet_id == pet_id).all()
    
    for h in horarios:
        try:
            h_partes, m_partes = map(int, h.time.split(":"))
            mins_programados = h_partes * 60 + m_partes
            
            # Si la hora actual está entre la programada y 10 minutos después
            if mins_programados <= mins_actuales <= (mins_programados + 10):
                return {"is_feeding_time": True, "amount": h.amount}
        except (ValueError, IndexError):
            continue

    return {"is_feeding_time": False, "amount": 0}


    
