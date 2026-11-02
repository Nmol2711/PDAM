"""Barrido periódico del servidor (specs 014 y 021, RF-19, RF-25, RF-3, RNF-3).

Un único ciclo ejecuta primero el cierre de las órdenes vencidas, después el
descarte de las solicitudes rápidas que nunca se entregaron y por último el
encolado de las comidas programadas. Se retiró el job anterior de 60 s que
activaba `dispensers.pending_dispensing`: esa bandera ya no es fuente de verdad,
porque la comida programada vive en `dispensing_queue` y se entrega en la
consulta del dispositivo. El resto de tareas programadas del proyecto no cambia.
"""

from datetime import datetime
from typing import Optional

from sqlalchemy.orm import Session

from app.services import order_service


def ejecutar_barrido(db: Session, ahora: Optional[datetime] = None) -> dict:
    """Cierra los vencimientos, descarta las solicitudes y encola, en ese orden.

    El orden importa: una orden que acaba de vencer libera el bloqueo antes de
    que se encole la comida que coincidía con ella (RF-19, RF-25), y el descarte
    de una solicitud rápida vencida libera su reserva sin tocar la cola ni las
    órdenes (spec 021, RF-3). El instante se inyecta para poder probar las
    fronteras con un reloj falso y se comparte con los tres pasos (RNF-8).
    """
    cerradas = order_service.cerrar_vencidas(db, ahora=ahora)
    descartadas = order_service.descartar_solicitudes_vencidas(db, ahora=ahora)
    encoladas = order_service.encolar_comida(db, ahora=ahora)
    return {
        "cerradas": cerradas,
        "descartadas": descartadas,
        "encoladas": encoladas,
    }
