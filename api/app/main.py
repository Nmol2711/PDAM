from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.staticfiles import StaticFiles
from apscheduler.schedulers.background import BackgroundScheduler   
from app.api.endpoints import auth, logs, schedules, users, pets, dispenser
from app.db.database import engine, Base, SessionLocal
from app.models import models

from app.services.background_tasks.background_schedules import check_and_activate_scheduled_feedings

# 1. Crear las tablas de la base de datos
# Esta línea le dice a SQLAlchemy: "Mira todos los modelos en models.py 
# y créalos como tablas en el archivo .db si no existen ya".
models.Base.metadata.create_all(bind=engine)

# 2. Ejecutar tareas en segundo plano
scheduler = BackgroundScheduler()

def execute_cron_task():
    db = SessionLocal()
    try:
        check_and_activate_scheduled_feedings(db=db)
    finally:
        db.close()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 🟢 Al arrancar el servidor: Registramos la tarea para que corra cada 1 minuto
    scheduler.add_job(execute_cron_task, 'interval', minutes=1)
    scheduler.start()
    yield
    # 🔴 Al apagar el servidor: Limpiamos los hilos
    scheduler.shutdown()

# 3. Instanciar la aplicación de FastAPI
app = FastAPI(
    title="API Dispensador Automático",
    description="Backend para gestionar horarios de comida y comunicación con hardware",
    version="0.1.0",
    lifespan=lifespan
)

# 4. Ruta de prueba (Root)
@app.get("/")
def read_root():
    return {"status": "Servidor funcionando", "proyecto": "Dispensador IoT"}




app.include_router(users.router, prefix="/users", tags=["Usuarios"])
app.include_router(auth.router, prefix="/auth", tags=["Autenticación"])
app.include_router(pets.router, prefix="/pets", tags=["Mascotas"])
app.include_router(schedules.router, prefix="/schedules", tags=["Horarios"])
app.include_router(logs.router, prefix="/logs", tags=["Logs"])
app.include_router(dispenser.router,prefix="/dispensers", tags=["Dispensador"])

app.mount("/static", StaticFiles(directory="static"), name="static")