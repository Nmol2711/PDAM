from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app.models import models

from app.schemas import schemas
from app.services.mac_service import (
    CODE_MAC_ALREADY_REGISTERED,
    CODE_MAC_IN_USE,
    CODE_PET_ALREADY_HAS_DISPENSER,
    MENSAJE_MAC_ALREADY_REGISTERED,
    MENSAJE_MAC_IN_USE,
    MENSAJE_PET_ALREADY_HAS_DISPENSER,
    normalize_mac,
    validate_mac_or_raise,
)


def _detalle(codigo: str, mensaje: str) -> dict:
    """Contrato de error de DO-5 y AC-4: `detail` es un objeto clasificable.

    El cliente decide por `code`; el `message` es la copia en español y es genérico,
    sin datos de la mascota, del usuario ni del dispensador en conflicto (RF-16).
    """
    return {"code": codigo, "message": mensaje}


def create_new_dispenser(
        db: Session, 
        new_dispenser: schemas.DispenserCreate
) -> schemas.Dispenser:

    # 1. Validar el formato antes de tocar la base de datos. La comparación posterior
    # se hace siempre con la forma canónica devuelta (RF-02, RF-06).
    mac_normalizada = validate_mac_or_raise(new_dispenser.mac_address)

    # 2. Validar si el hardware ya existe por su forma normalizada, de modo que
    # cualquier formato equivalente cuenta como la misma MAC (RF-03).
    if exist_dispensar(db=db, mac_normalizada=mac_normalizada):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=_detalle(CODE_MAC_ALREADY_REGISTERED, MENSAJE_MAC_ALREADY_REGISTERED)
        )

    # 3. Validar la relación 1-a-1 (regla existente, solo cambia su código de error)
    if has_pet_dispenser(db=db, pet_id=new_dispenser.pet_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_detalle(CODE_PET_ALREADY_HAS_DISPENSER, MENSAJE_PET_ALREADY_HAS_DISPENSER)
        )

    # 4. Creación del registro si todo está OK. `mac_address` conserva el texto tal
    # como lo introdujo el usuario y `mac_normalized` la forma comparable (DO-2).
    dispenser_db = models.Dispenser(
        mac_address=new_dispenser.mac_address,
        mac_normalized=mac_normalizada,
        pet_id=new_dispenser.pet_id,
        is_active=True
    )

    try:
        db.add(dispenser_db)
        db.commit()
        db.refresh(dispenser_db)
        return schemas.Dispenser.model_validate(dispenser_db)
    except IntegrityError:
        # RF-07: la comprobación previa no cubre la carrera entre dos altas simultáneas.
        # El índice único de `mac_normalized` es la garantía real de unicidad.
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=_detalle(CODE_MAC_ALREADY_REGISTERED, MENSAJE_MAC_ALREADY_REGISTERED)
        )
    except Exception as e:
        db.rollback()
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

def exist_dispensar(db: Session, mac_normalizada: str, excluir_id: int | None = None) -> bool:
    """Indica si la forma canónica ya está registrada.

    Solo compara `mac_normalized`, nunca el texto: así todos los formatos
    equivalentes de una misma dirección se consideran el mismo hardware (RF-02).
    `excluir_id` permite ignorar el propio dispensador en una modificación (RF-05).
    """
    try:
        consulta = db.query(models.Dispenser).filter(models.Dispenser.mac_normalized == mac_normalizada)
        if excluir_id is not None:
            consulta = consulta.filter(models.Dispenser.id != excluir_id)
        return consulta.first() is not None

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

    # 2. Si se intenta actualizar la dirección MAC, se compara por forma normalizada:
    # cambiar mayúsculas, guiones o espacios no es cambiar de dirección (CL-4, RF-05).
    if dispenser_update.mac_address is not None:
        mac_normalizada = validate_mac_or_raise(dispenser_update.mac_address)
        # Las filas anteriores a `mac_normalized` pueden tenerlo vacío: se normaliza su
        # texto para no confundir un formato distinto con una dirección nueva.
        actual_normalizada = dispenser_db.mac_normalized or normalize_mac(dispenser_db.mac_address)

        if mac_normalizada != actual_normalizada:
            if exist_dispensar(db=db, mac_normalizada=mac_normalizada, excluir_id=dispenser_db.id):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=_detalle(CODE_MAC_IN_USE, MENSAJE_MAC_IN_USE)
                )

            dispenser_db.mac_normalized = mac_normalizada
            dispenser_db.mac_address = dispenser_update.mac_address

    # 3. Si se intenta cambiar o asignar una mascota, validar las reglas relacionales
    if dispenser_update.pet_id is not None and dispenser_update.pet_id != dispenser_db.pet_id:

        # Validar la relación 1-a-1 (Que la nueva mascota no tenga ya otro equipo asignado)
        if has_pet_dispenser(db=db, pet_id=dispenser_update.pet_id):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=_detalle(CODE_PET_ALREADY_HAS_DISPENSER, MENSAJE_PET_ALREADY_HAS_DISPENSER)
            )

    # 4. Aplicar los cambios dinámicamente desglosando el esquema de Pydantic
    # .model_dump(exclude_unset=True) procesa únicamente los campos que la App envió en el JSON

    if dispenser_update.is_active is not None:
        dispenser_db.is_active = dispenser_update.is_active
    if dispenser_update.pending_dispensing is not None:
        dispenser_db.pending_dispensing = dispenser_update.pending_dispensing

    try:
        db.commit()
        db.refresh(dispenser_db)
        return schemas.Dispenser.model_validate(dispenser_db)
        
    except IntegrityError:
        # RF-07: si otra fila toma la forma normalizada entre la comprobación y el
        # commit, manda el índice único y el cambio se rechaza como conflicto.
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=_detalle(CODE_MAC_IN_USE, MENSAJE_MAC_IN_USE)
        )
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error interno del servidor al actualizar: {str(e)}"
        )
    
def check_pending_task(db: Session, mac_address: str, test:bool = False) -> dict:
    # 1. Buscar el dispensador por la forma normalizada de la MAC que envía el ESP32,
    # con el mismo criterio que el alta y la modificación: el hardware puede usar
    # guiones, espacios, puntos o minúsculas y sigue siendo el mismo equipo (RF-08).
    mac_normalizada = normalize_mac(mac_address)
    dispenser_db = db.query(models.Dispenser).filter(models.Dispenser.mac_normalized == mac_normalizada).first()
    
    if not dispenser_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Dispositivo hardware no registrado."
        )
    
    if not dispenser_db.is_active:
        return {"serve": False, "amount": 0}

    # 2. Si la app o el cron activaron la bandera pendiente...
    if dispenser_db.pending_dispensing:
        
        # Buscamos el horario planeado para esta mascota.
        # Quitamos el filtro estricto de hora aquí, ya que el segundo plano ya lo validó.
        schedule = db.query(models.Schedule).filter(
            models.Schedule.pet_id == dispenser_db.pet_id
        ).first()
        
        # Si por alguna razón extraña no hay horario, salimos SIN apagar la bandera
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
