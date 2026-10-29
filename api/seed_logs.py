"""Siembra registros de actividad de ejemplo en la base de desarrollo.

Usa el esquema de la spec 014. Las filas se siembran sin tipo de evento,
resultado ni causa para ejercitar la presentación «Sin clasificar» (RF-41);
las columnas de métricas quedan en NULL. No se ejecuta en pruebas.
"""

from datetime import datetime, timedelta, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.models.models import ActivityLog, Pet, User

DATABASE_URL = "sqlite:///./app/db/pdam.db"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)
db = SessionLocal()

user = db.query(User).first()
pet = db.query(Pet).first()

if user:
    user_id = user.id
    pet_id = pet.id if pet else None
    pet_name = pet.name if pet else None
    # UTC sin zona horaria, igual que el resto de fechas del servidor (RNF-8).
    ahora = datetime.now(timezone.utc).replace(tzinfo=None)

    sample_events = [
        ("Dispensador activado correctamente (Porción automática)", ahora - timedelta(hours=2)),
        ("Alimentación servida con éxito", ahora - timedelta(hours=8)),
        ("Horarios de alimentación sincronizados con el hardware", ahora - timedelta(days=1)),
        ("Dispensador activado manualmente desde la app", ahora - timedelta(days=2)),
    ]

    for description, created_at in sample_events:
        log = ActivityLog(
            description=description,
            user_id=user_id,
            pet_id=pet_id,
            pet_name=pet_name,
            created_at=created_at,
        )
        db.add(log)

    db.commit()
    print("¡Registros de prueba insertados exitosamente!")
else:
    print("No se encontró ningún usuario en la base de datos para asociar los logs.")

db.close()
