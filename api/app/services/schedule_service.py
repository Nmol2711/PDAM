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

def auto_generar_horarios_wsava(db: Session, pet_id: int, user_id: int, req: schemas.AutoScheduleRequest):
    mascota = db.query(models.Pet).filter(models.Pet.id == pet_id, models.Pet.user_id == user_id).first()
    if not mascota:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mascota no encontrada")
    
    hoy = datetime.now().date()
    edad_dias = (hoy - mascota.birth_date).days
    edad_meses = edad_dias / 30.44

    weight = mascota.weight
    rer = 70 * (weight ** 0.75)

    species = mascota.species.lower()
    is_neutered = mascota.reproductive_status
    is_growth = edad_meses < 12

    factor_mer = 1.6
    if "canino" in species or "dog" in species:
        if is_growth:
            factor_mer = 3.0 if edad_meses < 4 else 2.0
        else:
            if is_neutered:
                factor_mer = 1.4 if req.activity_level == "low" else 1.6
            else:
                factor_mer = 1.8
    elif "felino" in species or "cat" in species:
        if is_growth:
            factor_mer = 2.5
        else:
            if is_neutered:
                factor_mer = 1.0 if req.activity_level == "low" else 1.2
            else:
                factor_mer = 1.4

    if req.bcs >= 7:
        factor_mer *= 0.85
    elif req.bcs <= 3:
        factor_mer *= 1.15

    # Ajuste adicional por MCS (Masa muscular)
    if req.mcs == "moderate":
        factor_mer *= 1.05
    elif req.mcs == "marked":
        factor_mer *= 1.10

    mer = rer * factor_mer
    daily_kcal = mer
    daily_grams = (daily_kcal / req.food_kcal_per_kg) * 1000

    # Requerimiento de agua (ml/día) según WSAVA (44 - 66 ml/kg)
    water_min_ml = weight * 44
    water_max_ml = weight * 66

    warnings = []
    if req.mcs != "normal":
        warnings.append("Riesgo de Desequilibrio Metabólico detectado (MCS anormal). Se sugiere evaluación veterinaria.")
    if req.bcs >= 7 or req.bcs <= 3:
        warnings.append(f"Condición Corporal (BCS {req.bcs}/9) fuera del rango ideal (4-5). Se ajustó el requerimiento energético.")
    if "canino" in species or "dog" in species:
        warnings.append("Nota: El MER en perros puede variar ±30% según metabolismo individual.")
    else:
        warnings.append("Nota: El MER en gatos puede variar ±50% según metabolismo individual.")

    db.query(models.Schedule).filter(models.Schedule.pet_id == pet_id).delete()

    meals = req.meals_per_day
    grams_per_meal = round(daily_grams / meals, 2)

    horas_sugeridas = []
    if meals == 1:
        horas_sugeridas = ["08:00"]
    elif meals == 2:
        horas_sugeridas = ["08:00", "20:00"]
    elif meals == 3:
        horas_sugeridas = ["08:00", "14:00", "20:00"]
    elif meals == 4:
        horas_sugeridas = ["07:00", "12:00", "17:00", "21:00"]
    elif meals == 5:
        horas_sugeridas = ["07:00", "11:00", "15:00", "19:00", "22:00"]
    else:
        horas_sugeridas = ["06:00", "09:30", "13:00", "16:30", "20:00", "23:00"]

    nuevos_horarios = []
    for hora in horas_sugeridas[:meals]:
        horario = models.Schedule(
            time=hora,
            amount=grams_per_meal,
            pet_id=pet_id
        )
        db.add(horario)
        nuevos_horarios.append(horario)

    db.commit()
    for h in nuevos_horarios:
        db.refresh(h)

    return {
        "rer": round(rer, 2),
        "mer": round(mer, 2),
        "daily_grams": round(daily_grams, 2),
        "water_min_ml": round(water_min_ml, 1),
        "water_max_ml": round(water_max_ml, 1),
        "warnings": warnings,
        "schedules": nuevos_horarios
    }


    
