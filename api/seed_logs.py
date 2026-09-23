from datetime import datetime, timedelta
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.models.models import ActivityLog, User, Pet

DATABASE_URL = "sqlite:///./app/db/pdam.db"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)
db = SessionLocal()

user = db.query(User).first()
pet = db.query(Pet).first()

if user:
    user_id = user.id
    pet_id = pet.id if pet else None

    sample_events = [
        ("Dispensador activado correctamente (Porción automática)", pet_id, datetime.now() - timedelta(hours=2)),
        ("Alimentación servida con éxito", pet_id, datetime.now() - timedelta(hours=8)),
        ("Horarios de alimentación sincronizados con el hardware", pet_id, datetime.now() - timedelta(days=1)),
        ("Dispensador activado manualmente desde la app", pet_id, datetime.now() - timedelta(days=2)),
    ]

    for event_text, p_id, ts in sample_events:
        log = ActivityLog(event=event_text, user_id=user_id, pet_id=p_id, timestamp=ts)
        db.add(log)
    
    db.commit()
    print("¡Registros de prueba insertados exitosamente!")
else:
    print("No se encontró ningún usuario en la base de datos para asociar los logs.")

db.close()
