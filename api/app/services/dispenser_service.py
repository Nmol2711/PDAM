from datetime import datetime, timedelta

from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app.models import models

from app.schemas import schemas


def create_new_dispenser(
        db: Session, 
        new_dispenser: schemas.DispenserCreate
) -> schemas.Dispenser:
    
    # 1. Validar si el hardware ya existe
    if exist_dispensar(db=db, mac_address=new_dispenser.mac_address):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Esta dirección MAC ya está registrada."
        )
    
    
    # 2. Validar la relación 1-a-1
    if has_pet_dispenser(db=db, pet_id=new_dispenser.pet_id):
        # 🔴 CORRECCIÓN: Se agregó el 'raise' que faltaba aquí
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Esta mascota ya posee un dispensador registrado."
        )

    # 3. Creación del registro si todo está OK
    dispenser_db = models.Dispenser(
        mac_address=new_dispenser.mac_address,
        pet_id=new_dispenser.pet_id,
        is_active=True
    )

    try:
        db.add(dispenser_db)
        db.commit()
        db.refresh(dispenser_db)
        return schemas.Dispenser.model_validate(dispenser_db)
    except Exception as e:
        db.rollback()
        if "UNIQUE constraint failed" in str(e) or "duplicate key" in str(e):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Este dispensador (dirección MAC) ya está registrado con otra mascota."
            )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error interno del servidor: {str(e)}"
        )

def has_pet_dispenser(db: Session, pet_id: int) -> schemas.Dispenser | None:
    try:
        result = db.query(models.Dispenser).filter(models.Dispenser.pet_id == pet_id).first()
        if result:
            return schemas.Dispenser.model_validate(result)
        else: 
            return None 

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error interno del servidor en la validación: {str(e)}"
        )

def exist_dispensar(db: Session, mac_address: str) -> bool:
    try:
        result = db.query(models.Dispenser).filter(models.Dispenser.mac_address == mac_address).first()
        return result is not None 

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error interno del servidor en la validación: {str(e)}"
        )

def update_dispenser(
    db: Session, 
    dispenser_id: int, 
    dispenser_update: schemas.DispenserUpdate
) -> schemas.Dispenser:
    
    # 1. Verificar si el dispensador que se quiere actualizar realmente existe
    dispenser_db = db.query(models.Dispenser).filter(models.Dispenser.id == dispenser_id).first()
    if not dispenser_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún dispensador con el ID {dispenser_id}."
        )

    # 2. Si se intenta actualizar la dirección MAC, validar que no esté duplicada
    if dispenser_update.mac_address is not None and dispenser_update.mac_address != dispenser_db.mac_address:
        if exist_dispensar(db=db, mac_address=dispenser_update.mac_address):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La nueva dirección MAC ya se encuentra registrada en otro dispositivo."
            )

    # 3. Si se intenta cambiar o asignar una mascota, validar las reglas relacionales
    if dispenser_update.pet_id is not None and dispenser_update.pet_id != dispenser_db.pet_id:

        # Validar la relación 1-a-1 (Que la nueva mascota no tenga ya otro equipo asignado)
        if has_pet_dispenser(db=db, pet_id=dispenser_update.pet_id):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La mascota especificada ya posee un dispensador registrado."
            )

    # 4. Aplicar los cambios dinámicamente desglosando el esquema de Pydantic
    # .model_dump(exclude_unset=True) procesa únicamente los campos que la App envió en el JSON

    print("antes actualizados: ", dispenser_db)
   
    if dispenser_update.mac_address is not None:
        dispenser_db.mac_address = dispenser_update.mac_address
    if dispenser_update.is_active is not None:
        dispenser_db.is_active = dispenser_update.is_active
    if dispenser_update.pending_dispensing is not None:
        dispenser_db.pending_dispensing = dispenser_update.pending_dispensing

    
    print("Datos actualizados: ", dispenser_db)

    try:
        db.commit()
        db.refresh(dispenser_db)
        return schemas.Dispenser.model_validate(dispenser_db)
        
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error interno del servidor al actualizar: {str(e)}"
        )
    
def check_pending_task(db: Session, mac_address: str, test:bool = False) -> dict:
    # 1. Buscar el dispensador por la MAC que envía el ESP32
    dispenser_db = db.query(models.Dispenser).filter(models.Dispenser.mac_address == mac_address).first()
    
    if not dispenser_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Dispositivo hardware no registrado."
        )
    
    if not dispenser_db.is_active:
        return {"serve": False, "amount": 0}

    # 2. Si la app o el cron activaron la bandera pendiente...
    if dispenser_db.pending_dispensing:
        
        # 🔍 Buscamos el horario planeado para esta mascota.
        # Quitamos el filtro estricto de hora aquí, ya que el segundo plano ya lo validó.
        schedule = db.query(models.Schedule).filter(
            models.Schedule.pet_id == dispenser_db.pet_id
        ).first()
        
        # 🚨 Si por alguna razón extraña no hay horario, salimos SIN apagar la bandera
        if schedule is None:
            return {"serve": False, "amount": 0}
            
        if not test:
            # 3. Si todo está correcto, bajamos la bandera y confirmamos la orden
            dispenser_db.pending_dispensing = False
            db.commit()
        
        return {
            "serve": True,
            "amount": schedule.amount 
        }

    return {"serve": False, "amount": 0}

def delete_dispenser(db:Session, pet_id:int) -> bool:

    try:
        dispenser = db.query(models.Dispenser).filter(models.Dispenser.pet_id == pet_id).first()

        if dispenser is None:
            raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="La mascota no tiene ningun dispensador asignado."
        )

        db.delete(dispenser)
        db.commit()
        return True
    except Exception as e:
        db.rollback()
        print("Error fue: ",str(e))
        return False