"""Barrido periódico del servidor (spec 014, RF-19, RF-25, RNF-3).

Un único ciclo ejecuta primero el cierre de las órdenes vencidas y después el
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
    """Cierra los vencimientos y encola las ocurrencias, en ese orden.

    El orden importa: una orden que acaba de vencer libera el bloqueo antes de
    que se encole la comida que coincidía con ella (RF-19, RF-25). El instante
    se inyecta para poder probar las fronteras con un reloj falso.
    """
    cerradas = order_service.cerrar_vencidas(db, ahora=ahora)
    encoladas = order_service.encolar_comida(db, ahora=ahora)
    return {"cerradas": cerradas, "encoladas": encoladas}
