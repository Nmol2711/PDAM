from pydantic import BaseModel
from typing import Optional

class DispenserBase(BaseModel):
    mac_address: str
    pet_id: int

class DispenserAssociation(DispenserBase):
    secret_key_qr: str

    # El formato de `mac_address` no se valida aquí: un validador de esquema responde
    # 422 con un detalle genérico y obliga a un único formato (mayúsculas y dos puntos),
    # lo que contradice RF-02 y oculta la diferencia entre formato inválido (400
    # `mac_invalid_format`) y conflicto (409). El formato se valida en
    # `app/services/mac_service.py`, que acepta todos los formatos equivalentes.

class DispenserCreate(DispenserBase):
    pass

class DispenserUpdate(BaseModel):
    pet_id: Optional[int] = None
    mac_address: Optional[str] = None
    is_active: Optional[bool] = None
    pending_dispensing: Optional[bool] = None

class Dispenser(DispenserBase):
    id: int
    is_active: bool
    pending_dispensing: bool

    class Config:
        from_attributes = True

class DispenserWiFiResetRequest(BaseModel):
    pass

class DispenserWiFiResetResponse(BaseModel):
    success: bool
    message: str
    dispenser_id: int
    mac_address: str

    class Config:
        from_attributes = True
