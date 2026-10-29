from pydantic import BaseModel
from typing import Any, Optional

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
    # Se sigue aceptando por compatibilidad, pero se ignora sin error: el stock
    # solo lo calcula el servidor y la respuesta devuelve su valor (RF-23).
    current_food_grams: Optional[float] = None

    # `pending_dispensing` ya no forma parte del contrato de actualización
    # (spec 014, T5): la comida programada vive en la cola del servidor. Pydantic
    # ignora el campo extra, así que un cliente antiguo que lo envíe no recibe un
    # 422 pero tampoco cambia la bandera. Solo se consume si ya estaba puesta en
    # la base, como compatibilidad con datos anteriores.

class Dispenser(DispenserBase):
    id: int
    is_active: bool
    pending_dispensing: bool
    current_food_grams: float = 5000.0

    class Config:
        from_attributes = True

class DispenserRefillRequest(BaseModel):
    """Solicitud de reabastecimiento (RFC-12 de la spec 012 y RF-11 de la 014).

    La cantidad y la unidad se declaran como `Any` a propósito: la validación vive
    en el servicio para que un valor cero, negativo o no numérico responda 400 del
    catálogo y nunca un 422 del esquema. `operation_id` hace idempotente la
    sincronización sin conexión y `origen` marca el camino por el que llegó el
    reabastecimiento (`servidor` o `sincronizacion_sin_conexion`).
    """

    amount: Any = None
    unit: Any = "g"
    operation_id: Any = None
    origen: Any = None

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
