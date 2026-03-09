from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

from app.core.confg import settings

# El archivo se creará en la raíz del proyecto
# Se usar SQLite para el desarrollo al momento de subir a 
# produccion si es necesario cambiar de gestor sera muy facil
SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

# Dependencia para obtener la DB en las rutas
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()