"""Contrato del reporte de fin de ciclo del dispositivo (spec 014, §5.2).

Los campos se declaran permisivos (`Any`) a propósito: el reporte lo envía el
firmware y cualquier rechazo debe ser un 400 del catálogo de errores con el
código de negocio, nunca un 422 de validación de esquema (RF-14, RF-21). La
normalización de la MAC, el catálogo de motivos y la existencia de la orden se
comprueban en `order_service`.
"""

from typing import Any, Optional

from pydantic import BaseModel, ConfigDict


class DispenserReportRequest(BaseModel):
    """Cuerpo del reporte: MAC, orden, motivo, gramos y reintentos."""

    # `extra="ignore"`: los campos no definidos no se guardan ni son fuente de
    # verdad; el stock nunca se acepta del dispositivo (RF-14, RF-23).
    model_config = ConfigDict(extra="ignore")

    mac: Any = None
    order_id: Any = None
    motivo: Any = None
    gramos_solicitados: Any = None
    gramos_medidos: Any = None
    reintentos: Any = None


class DispenserReportResponse(BaseModel):
    """Respuesta del cierre: resultado guardado, gramos y stock resultante."""

    order_id: Optional[int] = None
    outcome: str
    cause: str
    requested_grams: float
    measured_grams: Optional[float] = None
    discounted_grams: float = 0.0
    resulting_stock: float = 0.0
    ya_cerrada: bool = False
