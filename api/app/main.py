from fastapi import FastAPI
from app.api.endpoints import auth, logs, schedules, users
from app.db.database import engine, Base
from app.models import models

# 1. Crear las tablas de la base de datos
# Esta línea le dice a SQLAlchemy: "Mira todos los modelos en models.py 
# y créalos como tablas en el archivo .db si no existen ya".
models.Base.metadata.create_all(bind=engine)

# 2. Instanciar la aplicación de FastAPI
app = FastAPI(
    title="API Dispensador Automático",
    description="Backend para gestionar horarios de comida y comunicación con hardware",
    version="0.1.0"
)

# 3. Ruta de prueba (Root)
@app.get("/")
def read_root():
    return {"status": "Servidor funcionando", "proyecto": "Dispensador IoT"}

app.include_router(users.router, prefix="/users", tags=["Usuarios"])
app.include_router(auth.router, prefix="/auth", tags=["Autenticación"])
app.include_router(schedules.router, prefix="/schedules", tags=["Horarios"])
app.include_router(logs.router, prefix="/logs", tags=["Logs"])