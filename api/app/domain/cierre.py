"""Resolución del cierre de una orden a partir del reporte (spec 014).

Decide, sin tocar la base de datos, con qué resultado y causa se cierra una
orden pendiente: el cierre tardío manda sobre el motivo del reporte y, si no es
tardío, la causa sale del catálogo cerrado con la comparación de los gramos
medidos contra los solicitados **de la orden** (no los del reporte).

Módulo puro: el instante de recepción y el de entrega se reciben como
parámetros (RNF-4, RNF-8).
"""

from datetime import datetime
from typing import Optional

from app.domain.catalogos import FALLO, resultado_para_motivo
from app.domain.tiempo import plazo_vencido

# Causa con la que se cierra un reporte recibido fuera del plazo (RF-20).
CAUSA_CIERRE_TARDIO = "orden_cerrada"


def resolver_cierre_por_reporte(
    motivo: str,
    solicitados_orden: Optional[float],
    medidos: Optional[float],
    ahora: datetime,
    entregada_en: datetime,
) -> tuple[str, str, bool]:
    """Devuelve `(outcome, cause, tardio)` para el reporte recibido.

    `tardio` es `True` cuando el reporte llegó más de 1 segundo después del
    plazo: en ese caso la orden se cierra como fallo con causa `orden_cerrada` y
    sin descuento, con independencia del motivo declarado (RF-20). Dentro del
    plazo, `objetivo_alcanzado` solo es éxito si los medidos alcanzan los
    solicitados de la orden (RF-15, RF-16) y cualquier otro motivo cierra como
    fallo con su causa homónima (RF-17).
    """
    if plazo_vencido(entregada_en, ahora):
        return FALLO, CAUSA_CIERRE_TARDIO, True

    resultado, causa = resultado_para_motivo(motivo, medidos, solicitados_orden)
    return resultado, causa, False
