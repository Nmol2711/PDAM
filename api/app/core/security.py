from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import jwt
from passlib.context import CryptContext

from app.core.confg import settings  # Importamos nuestra configuración
from app.domain.token import construir_claims



pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password: str):
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str):
    return pwd_context.verify(plain_password, hashed_password)

def crear_token_acceso(
    public_id: str,
    jti: str,
    expires_delta: Optional[timedelta] = None,
) -> str:
    """Firma un token de sesión con `sub=public_id` y su `jti` (RF-10, RF-19).

    La identidad estable de la cuenta sustituye al correo, de modo que registrar
    de nuevo un correo no rehabilita tokens anteriores. Los claims se construyen
    en el dominio puro y aquí solo se firma con la configuración de la app.
    """
    ahora = datetime.now(timezone.utc)
    if expires_delta is None:
        expires_delta = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

    minutos = expires_delta.total_seconds() / 60
    claims = construir_claims(public_id, jti, ahora, minutos)
    return jwt.encode(claims, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

def verify_secret_key_qr(secret_key_qr: str) -> bool:
    return settings.MASTER_HARDWARE_KEY == secret_key_qr
