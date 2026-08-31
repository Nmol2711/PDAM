from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app.models import models
from app.schemas import schemas

def crear_mascota(db: Session, pet: schemas.PetCreate, user_id: int):
    nueva_mascota = models.Pet(
        name=pet.name,
        species=pet.species,
        age=pet.age,
        weight=pet.weight,
        path_url=pet.path_url,
        user_id=user_id
    )
    db.add(nueva_mascota)
    try:
        db.commit()
        db.refresh(nueva_mascota)
        return nueva_mascota
    except Exception as e:
        db.rollback()
        raise e

def obtener_mis_mascotas(db: Session, user_id: int):
    return db.query(models.Pet).filter(models.Pet.user_id == user_id).all()

def obtener_mascota_por_id(db: Session, pet_id: int, user_id: int): 
    mascota = db.query(models.Pet).filter(models.Pet.id == pet_id, models.Pet.user_id == user_id).first()
    if not mascota:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mascota no encontrada")
    return mascota

def actualizar_mascota(db: Session, pet_id: int, pet_data: schemas.PetUpdate, user_id: int):
    mascota = obtener_mascota_por_id(db, pet_id, user_id)
     
    if pet_data.name is not None:
        mascota.name = pet_data.name
    if pet_data.species is not None:
        mascota.species = pet_data.species
        
    db.commit()
    db.refresh(mascota)
    return mascota

def eliminar_mascota(db: Session, pet_id: int, user_id: int):
    mascota = obtener_mascota_por_id(db, pet_id, user_id)
    # Al eliminar la mascota, SQLAlchemy se encargará de los horarios 
    # si configuraste el cascade, o puedes borrarlos manualmente aquí.
    db.delete(mascota)
    db.commit()
    return {"message": "Mascota eliminada correctamente"}