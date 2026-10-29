from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.staticfiles import StaticFiles
from apscheduler.schedulers.background import BackgroundScheduler   
from app.api.endpoints import auth, logs, schedules, users, pets, dispenser, dashboard, sync, nutrition
from app.db.database import engine, Base, SessionLocal
from app.domain.tiempo import INTERVALO_BARRIDO
from app.models import models

from app.services.background_tasks.background_schedules import ejecutar_barrido

# 1. Crear las tablas de la base de datos
# Esta línea le dice a SQLAlchemy: "Mira todos los modelos en models.py 
# y créalos como tablas en el archivo .db si no existen ya".
models.Base.metadata.create_all(bind=engine)

# 2. Ejecutar tareas en segundo plano
scheduler = BackgroundScheduler()

# Identificador estable del job: volver a arrancar la aplicación reemplaza el
# mismo trabajo en lugar de acumular duplicados.
ID_JOB_BARRIDO = "barrido_ordenes"

def execute_cron_task():
    db = SessionLocal()
    try:
        # Un único ciclo: primero se cierran los vencimientos y después se
        # encolan las comidas programadas (RF-19, RF-25, RNF-3).
        ejecutar_barrido(db=db)
    finally:
        db.close()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Un único job cada 30 s, sin ejecuciones simultáneas ni acumulación de
    # ciclos atrasados (`max_instances=1`, `coalesce=True`). Sustituye al job
    # anterior de 60 s que activaba `pending_dispensing`; esa bandera ya no es
    # fuente de verdad.
    scheduler.add_job(
        execute_cron_task,
        'interval',
        seconds=int(INTERVALO_BARRIDO.total_seconds()),
        id=ID_JOB_BARRIDO,
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
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
app.include_router(dashboard.router, prefix="/dashboard", tags=["Dashboard"])
app.include_router(sync.router, prefix="/sync", tags=["Sincronización"])
app.include_router(nutrition.router, prefix="/nutrition", tags=["Nutrición"])

app.mount("/static", StaticFiles(directory="static"), name="static")