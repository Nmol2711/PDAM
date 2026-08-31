import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    PROJECT_NAME: str = "Dispensador API"
    # Si no encuentra la variable en el .env, usa el valor por defecto
    SECRET_KEY: str = os.getenv("SECRET_KEY")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 30 # Unos 30 dia aviles Zzz
    DATABASE_URL: str = os.getenv("DATABASE_URL")
    MASTER_HARDWARE_KEY = "PDAM_SECURE_KEY_2026"

settings = Settings()

# Validaciones de seguridad: Evitar que la app arranque sin configuración crítica
if not settings.SECRET_KEY:
    raise ValueError("FATAL: No se ha configurado la variable de entorno SECRET_KEY. Revisa tu archivo .env.")

if not settings.DATABASE_URL:
    raise ValueError("FATAL: No se ha configurado la variable de entorno DATABASE_URL. Revisa tu archivo .env.")