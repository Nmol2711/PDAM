"""Mascotas y sus registros de actividad (spec 014).

Cada alta, modificación y eliminación de una mascota escribe su registro
tipado en la **misma transacción** que el cambio de estado (RF-2, RF-4 a RF-6):
si la escritura del registro falla, no queda ni el cambio ni el registro.

`pet_updated` guarda solo los **nombres** de los campos modificados, nunca los
valores anteriores ni los nuevos (RF-5), y `pet_deleted` conserva el
identificador y el nombre de la mascota en el registro, de modo que sus
históricos siguen siendo consultables aunque la mascota ya no exista (RF-6).

Los textos visibles están en español y no incluyen datos personales del usuario
(RNF-1).
"""

from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.domain import catalogos
from app.models import models
from app.schemas import schemas
from app.services import activity_service

# Campos de la mascota que se pueden modificar, en un orden estable para que el
# contexto del registro sea determinista.
CAMPOS_MODIFICABLES = (
    "name",
    "species",
    "birth_date",
    "weight",
    "reproductive_status",
    "path_url",
)

EVENTO_CREADA = "pet_created"
EVENTO_MODIFICADA = "pet_updated"
EVENTO_ELIMINADA = "pet_deleted"

DESCRIPCION_CREADA = "Mascota creada"
DESCRIPCION_MODIFICADA = "Mascota modificada"
DESCRIPCION_ELIMINADA = "Mascota eliminada"

# Conflicto del borrado: la relación 1-a-1 con el dispensador impide eliminar la
# mascota mientras el equipo siga vinculado. Es un rechazo de negocio (409, el
# mismo estatus que ya usa el proyecto para los conflictos de vínculo) y no un
# 500: el catálogo de errores de la spec 014 no tiene un código para este caso y
# no se inventa un 400 ajeno a él (RNF-7).
CODE_PET_HAS_DISPENSER = "pet_has_dispenser"
MENSAJE_PET_HAS_DISPENSER = (
    "La mascota tiene un dispensador vinculado. Desvincule el dispensador antes "
    "de eliminarla."
)


def crear_mascota(db: Session, pet: schemas.PetCreate, user_id: int):
    """Crea la mascota y su registro `pet_created` en una única transacción."""
    nueva_mascota = models.Pet(
        name=pet.name,
        species=pet.species,
        birth_date=pet.birth_date,
        weight=pet.weight,
        reproductive_status=pet.reproductive_status,
        path_url=pet.path_url,
        user_id=user_id,
    )

    try:
        db.add(nueva_mascota)
        # El identificador se necesita para el registro y para las respuestas.
        db.flush()
        activity_service.registrar(
            db,
            event_type=EVENTO_CREADA,
            outcome=catalogos.EXITO,
            description=f"{DESCRIPCION_CREADA}: {nueva_mascota.name}",
            user_id=user_id,
            pet_id=nueva_mascota.id,
            pet_name=nueva_mascota.name,
            context={
                "mascota_id": nueva_mascota.id,
                "mascota": nueva_mascota.name,
                "especie": nueva_mascota.species,
            },
        )
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


def _campos_modificados(mascota: models.Pet, pet_data: schemas.PetUpdate) -> dict:
    """Campos enviados cuyo valor cambia respecto del guardado.

    Se comparan valores para no declarar como modificado un campo que el cliente
    reenvía igual; el resultado solo se usa para guardar sus **nombres** en el
    contexto del registro (RF-5).
    """
    cambios = {}
    for campo in CAMPOS_MODIFICABLES:
        valor = getattr(pet_data, campo, None)
        if valor is not None and getattr(mascota, campo) != valor:
            cambios[campo] = valor
    return cambios


def actualizar_mascota(db: Session, pet_id: int, pet_data: schemas.PetUpdate, user_id: int):
    """Modifica la mascota y registra `pet_updated` con los nombres de los campos."""
    mascota = obtener_mascota_por_id(db, pet_id, user_id)

    cambios = _campos_modificados(mascota, pet_data)
    for campo, valor in cambios.items():
        setattr(mascota, campo, valor)

    contexto = {
        "mascota_id": mascota.id,
        "campos_modificados": [campo for campo in CAMPOS_MODIFICABLES if campo in cambios],
    }

    try:
        db.flush()
        activity_service.registrar(
            db,
            event_type=EVENTO_MODIFICADA,
            outcome=catalogos.EXITO,
            description=f"{DESCRIPCION_MODIFICADA}: {mascota.name}",
            user_id=user_id,
            pet_id=mascota.id,
            pet_name=mascota.name,
            context=contexto,
        )
        db.commit()
        db.refresh(mascota)
        return mascota
    except Exception:
        db.rollback()
        raise


def eliminar_mascota(db: Session, pet_id: int, user_id: int):
    """Elimina la mascota y conserva su referencia en el registro e históricos.

    El registro `pet_deleted` se escribe en la misma transacción que el borrado y
    guarda `pet_id` y `pet_name`, que son instantáneas sin clave foránea: los
    registros anteriores de la mascota siguen siendo consultables (RF-6, RF-27).
    """
    mascota = obtener_mascota_por_id(db, pet_id, user_id)
    identificador = mascota.id
    nombre = mascota.name

    try:
        activity_service.registrar(
            db,
            event_type=EVENTO_ELIMINADA,
            outcome=catalogos.EXITO,
            description=f"{DESCRIPCION_ELIMINADA}: {nombre}",
            user_id=user_id,
            pet_id=identificador,
            pet_name=nombre,
            context={"mascota_id": identificador, "mascota": nombre},
        )
        db.delete(mascota)
        db.commit()
        return {"message": "Mascota eliminada correctamente"}
    except IntegrityError:
        # La relación 1-a-1 con `dispensers` intenta anular `pet_id`, que es
        # obligatorio: el borrado se rechaza como conflicto y no como 500.
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": CODE_PET_HAS_DISPENSER, "message": MENSAJE_PET_HAS_DISPENSER},
        )
    except Exception:
        db.rollback()
        raise


def nombre_y_propietario(db: Session, pet_id: Optional[int]) -> tuple[Optional[str], Optional[int]]:
    """Devuelve `(nombre, user_id)` de la mascota, o `(None, None)` si no existe.

    Lo usan los servicios de dispensadores para registrar la mascota afectada y
    su propietario sin depender de que el endpoint los pase.
    """
    if pet_id is None:
        return None, None

    mascota = db.query(models.Pet).filter(models.Pet.id == pet_id).first()
    if mascota is None:
        return None, None
    return mascota.name, mascota.user_id
