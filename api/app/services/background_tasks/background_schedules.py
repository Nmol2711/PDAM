from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from app.models.models import Dispenser, Schedule

def check_and_activate_scheduled_feedings(db: Session):
    # Obtener la hora actual del servidor (solo hora y minutos)
    hour = datetime.now()
    current_time = hour.time()
    
    # Definir el margen de tiempo 
    marge_minutes = (hour - timedelta(minutes=10)).time()
    print("Ejecucion en segundo plano")

    try:
        # Buscar todos los horarios que correspondan al rango actual
        # Dependiendo de si guardas 'time' como String o Time en SQL, adaptamos el filtro.
        # Aquí asumimos que está en un formato comparable dentro del rango de 10 min.
        active_schedules = db.query(Schedule).filter(
            Schedule.time <= current_time,
            Schedule.time >= marge_minutes  
        ).all()

        for schedule in active_schedules:
            # 3. Buscar el dispensador asociado a la mascota de ese horario
            dispenser = db.query(Dispenser).filter(
                Dispenser.pet_id == schedule.pet_id,
                Dispenser.is_active == True,
                Dispenser.pending_dispensing == False 
            ).first()

            # 4. Si el dispensador existe y está libre, activar la comida
            if dispenser:
                dispenser.pending_dispensing = True
                # Nota: Si necesitas pasar la cantidad (amount), podrías guardarla en una columna
                # temporal o usarla para calcular los segundos de giro dinámicamente aquí.
                print(f"⏰ Horario cumplido para mascota {schedule.pet_id}. Dispensador activado.")
        
        db.commit()

    except Exception as e:
        db.rollback()
        print(f"Error en el planificador de comidas: {str(e)}")