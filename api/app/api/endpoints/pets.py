from typing import List
from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.api.deps import CurrentUser
from app.models import models
from app.schemas import schemas
from app.services import pet_service
from app.services.file_storage import FileStorageService

router = APIRouter()
storage_service = FileStorageService()

@router.post("/", response_model=schemas.Pet)
def crear_mascota(
    current_user: CurrentUser,
    name: str = Form(...),
    species: str = Form(...),
    age: int = Form(...),
    weight: float = Form(...),
    file: UploadFile = File(None),
    db: Session = Depends(get_db)
):
    path_url = storage_service.save_pet_image(file=file)
    pet = schemas.PetCreate(
        name=name,
        species=species,
        age=age,
        weight=weight,
        path_url=path_url
    )
    print(f"Pet Creada con exito f{pet}")
    return pet_service.crear_mascota(db=db, pet=pet, user_id=current_user.id)

@router.get("/", response_model=List[schemas.Pet])
def obtener_mascotas(
    current_user: CurrentUser,
    db: Session = Depends(get_db),
   
):
    return pet_service.obtener_mis_mascotas(db=db, user_id=current_user.id)

@router.get("/{pet_id}", response_model=schemas.PetWithSchedules)
def obtener_mascota_detalle(
    current_user: CurrentUser,
    pet_id: int,
    db: Session = Depends(get_db),
):
    return pet_service.obtener_mascota_por_id(db, pet_id=pet_id, user_id=current_user.id)

@router.put("/{pet_id}", response_model=schemas.Pet)
def actualizar_mascota(
    current_user: CurrentUser,
    pet_id: int,
    pet_update: schemas.PetUpdate,
    db: Session = Depends(get_db),
):
    return pet_service.actualizar_mascota(db, pet_id, pet_update, current_user.id)

@router.delete("/{pet_id}")
def eliminar_mascota(
    current_user: CurrentUser,
    pet_id: int,
    db: Session = Depends(get_db),
):
    return pet_service.eliminar_mascota(db, pet_id, current_user.id)