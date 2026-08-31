from typing import List
from fastapi import APIRouter, Depends, File, Form, HTTPException, status
from sqlalchemy.orm import Session
from app.core.security import verify_secret_key_qr
from app.db.database import get_db
from app.api.deps import CurrentUser

from app.schemas.schemas import DispenserCreate, User, Dispenser, DispenserUpdate, DispenserAssociation

from app.services import pet_service, dispenser_service

router = APIRouter()

@router.post("/",response_model=Dispenser)
def create_dispenser(
    current_user: CurrentUser,
    dispenser: DispenserAssociation,
    db:Session = Depends(get_db),
): 
    pet_service.obtener_mascota_por_id(
        db=db, 
        pet_id=dispenser.pet_id, 
        user_id=current_user.id
    )

    print(f"mac_address: {dispenser.mac_address} and secret_key: {dispenser.secret_key_qr}")
    if not verify_secret_key_qr(dispenser.secret_key_qr):
        raise HTTPException(
            status_code=403, 
            detail="La llave de autenticación del hardware es inválida o fue falsificada."
        )

    return dispenser_service.create_new_dispenser(
        db=db, 
        new_dispenser=DispenserCreate.model_validate(dispenser.model_dump())
    )

@router.get("/{pet_id}", response_model=Dispenser)
def get_dispenser_by_pet(
    pet_id: int,
    current_user: CurrentUser,
    db:Session = Depends(get_db)
):
    pet_service.obtener_mascota_por_id(db=db, pet_id=pet_id, user_id=current_user.id)
    result = dispenser_service.has_pet_dispenser(db=db, pet_id=pet_id)
    if result is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún dispensador con para esta mascota."
        ) 
    return result

@router.put("/{dispenser_id}",response_model=Dispenser)
def update_dispenser(
    current_user: CurrentUser,
    dispenser_id: int,
    dispenser_to_update: DispenserUpdate,
    db: Session = Depends(get_db),
   
):
    pet_service.obtener_mascota_por_id(
        db=db, 
        pet_id=dispenser_to_update.pet_id, 
        user_id=current_user.id
    )

    return dispenser_service.update_dispenser(
        db=db,
        dispenser_id=dispenser_id,
        dispenser_update=dispenser_to_update
    )

@router.get("check-taks/{address_mac}", response_model=dict)
def check_dispenser_taks(
    address_mac: str,
    db: Session = Depends(get_db)
):
    #return dispenser_service.check_pending_task(db=db, mac_address=address_mac)
    return {
            "serve": True,
            "amount": 50
        }


@router.get("check-taks-test/{address_mac}", response_model=dict)
def check_dispenser_taks_test(
    address_mac: str,
    db: Session = Depends(get_db)
):
    return dispenser_service.check_pending_task(db=db, mac_address=address_mac, test=True)


@router.delete("/{pet_id}")
def delete_dispenser_by_pet(
    current_user: CurrentUser,
    pet_id:int,
    db: Session = Depends(get_db)
) -> bool:
    
    pet_service.obtener_mascota_por_id(
        db=db, 
        pet_id=pet_id, 
        user_id=current_user.id
    )

    return dispenser_service.delete_dispenser(db=db, pet_id=pet_id)