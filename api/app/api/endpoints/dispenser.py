from typing import Any, List
from fastapi import APIRouter, Body, Depends, File, Form, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import ValidationError
from app.core.security import verify_secret_key_qr
from app.db.database import get_db
from app.api.deps import CurrentUser

from app.schemas.schemas import (
    DispenserCreate,
    User,
    Dispenser,
    DispenserUpdate,
    DispenserAssociation,
    DispenserWiFiResetResponse,
    DispenserRefillRequest,
)
from app.schemas.reports import DispenserReportRequest, DispenserReportResponse
from app.domain.catalogos import ErrorDominio

from app.services import pet_service, dispenser_service, order_service
from app.models import models

router = APIRouter()


@router.post("/", response_model=Dispenser)
def create_dispenser(
    current_user: CurrentUser,
    dispenser: DispenserAssociation,
    db: Session = Depends(get_db),
):
    pet_service.obtener_mascota_por_id(
        db=db, pet_id=dispenser.pet_id, user_id=current_user.id
    )

    if not verify_secret_key_qr(dispenser.secret_key_qr):
        raise HTTPException(
            status_code=403,
            detail="La llave de autenticación del hardware es inválida o fue falsificada.",
        )

    return dispenser_service.create_new_dispenser(
        db=db,
        new_dispenser=DispenserCreate.model_validate(dispenser.model_dump()),
        user_id=current_user.id,
    )


@router.get("/{pet_id}", response_model=Dispenser)
def get_dispenser_by_pet(
    pet_id: int, current_user: CurrentUser, db: Session = Depends(get_db)
):
    pet_service.obtener_mascota_por_id(db=db, pet_id=pet_id, user_id=current_user.id)
    result = dispenser_service.has_pet_dispenser(db=db, pet_id=pet_id)
    if result is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún dispensador con para esta mascota.",
        )
    return result


@router.put("/{dispenser_id}", response_model=Dispenser)
def update_dispenser(
    current_user: CurrentUser,
    dispenser_id: int,
    dispenser_to_update: DispenserUpdate,
    db: Session = Depends(get_db),
):
    pet_service.obtener_mascota_por_id(
        db=db, pet_id=dispenser_to_update.pet_id, user_id=current_user.id
    )

    return dispenser_service.update_dispenser(
        db=db,
        dispenser_id=dispenser_id,
        dispenser_update=dispenser_to_update,
        user_id=current_user.id,
    )


@router.get("check-taks/{address_mac}", response_model=dict)
def check_dispenser_taks(address_mac: str, db: Session = Depends(get_db)):
    return {"serve":True,"amount":50}
    return dispenser_service.check_pending_task(db=db, mac_address=address_mac)


@router.get("check-taks-test/{address_mac}", response_model=dict)
def check_dispenser_taks_test(address_mac: str, db: Session = Depends(get_db)):
    return dispenser_service.check_pending_task(
        db=db, mac_address=address_mac, test=True
    )


@router.post("/reports", response_model=DispenserReportResponse)
def report_dispensing_result(
    cuerpo: Any = Body(default=None), db: Session = Depends(get_db)
):
    """Cierre de una orden con el reporte de fin de ciclo del dispositivo.

    Sin token: la autenticación es la MAC registrada del dispensador (RF-14,
    RF-21). Los rechazos de negocio son 400 con `detail={code,message}`; un fallo
    de escritura es 5xx para que el firmware reintente (RF-1).

    El cuerpo se recibe como `Any` y se valida aquí: un cuerpo que no sea un
    objeto JSON (lista, cadena o vacío) responde 400 y nunca 422. El catálogo de
    errores no tiene un código para el cuerpo mal formado y no se inventa uno: se
    usa `motivo_invalido`, que es el rechazo del contrato del reporte.
    """
    if not isinstance(cuerpo, dict):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorDominio("motivo_invalido").detail,
        )

    reporte = DispenserReportRequest.model_validate(cuerpo)
    try:
        return order_service.procesar_reporte(db=db, reporte=reporte)
    except ErrorDominio as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=error.detail
        )


@router.delete("/{pet_id}")
def delete_dispenser_by_pet(
    current_user: CurrentUser, pet_id: int, db: Session = Depends(get_db)
) -> bool:

    pet_service.obtener_mascota_por_id(db=db, pet_id=pet_id, user_id=current_user.id)

    return dispenser_service.delete_dispenser(
        db=db, pet_id=pet_id, user_id=current_user.id
    )


@router.post("/{id}/reset-wifi", response_model=DispenserWiFiResetResponse)
def reset_dispenser_wifi(
    current_user: CurrentUser, id: int, db: Session = Depends(get_db)
):
    dispenser = db.query(models.Dispenser).filter(models.Dispenser.id == id).first()
    if not dispenser:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún dispensador con el ID {id}.",
        )
    pet_service.obtener_mascota_por_id(
        db=db, pet_id=dispenser.pet_id, user_id=current_user.id
    )
    return dispenser_service.reset_wifi_credentials(
        db=db, dispenser_id=id, user_id=current_user.id
    )


@router.post("/{dispenser_id}/refill", response_model=Dispenser)
def refill_dispenser_endpoint(
    current_user: CurrentUser,
    dispenser_id: int,
    cuerpo: Any = Body(default=None),
    db: Session = Depends(get_db),
):
    """Reabastece el dispensador (RF-11, RF-12, RF-22, RF-23).

    El cuerpo se recibe como `Any` y se valida aquí: un cuerpo que no sea un
    objeto JSON responde 400 con `cantidad_invalida` y nunca 422. La cantidad y la
    capacidad se validan en el servicio, que responde 400 con el código del
    catálogo, deja el stock intacto y registra el fallo. Un `operation_id`
    repetido no vuelve a sumar ni a registrar.
    """
    dispenser = (
        db.query(models.Dispenser).filter(models.Dispenser.id == dispenser_id).first()
    )
    if not dispenser:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún dispensador con el ID {dispenser_id}.",
        )
    pet_service.obtener_mascota_por_id(
        db=db, pet_id=dispenser.pet_id, user_id=current_user.id
    )

    if not isinstance(cuerpo, dict):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorDominio("cantidad_invalida").detail,
        )

    try:
        refill_request = DispenserRefillRequest.model_validate(cuerpo)
    except ValidationError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorDominio("cantidad_invalida").detail,
        )

    return dispenser_service.refill_dispenser(
        db=db,
        dispenser_id=dispenser_id,
        refill_data=refill_request,
        user_id=current_user.id,
    )

