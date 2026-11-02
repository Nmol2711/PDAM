"""Resumen del panel a partir de la actividad registrada (spec 022, T2).

Este módulo solo consulta y delega: las mascotas, los horarios dispensables y
las dispensaciones del usuario se leen aquí, y las cifras se calculan en
`domain/panel.py`, que es puro y recibe el instante y la zona como parámetros
(RNF-2). La respuesta HTTP la compone el endpoint; el servicio no conoce
FastAPI.

Las consultas se limitan al usuario autenticado (RF-1) y a la semana en curso
en UTC, con el extremo derecho del día de hoy exclusivo y el índice
`ix_logs_user_id_created_at`, que sostiene el filtro por usuario y fecha
(RNF-4, RNF-8). Los instantes se comparan en UTC sin zona, igual que se guardan
en la tabla de registros (RNF-8).
"""

from datetime import datetime, tzinfo
from typing import Optional

from sqlalchemy.orm import Session

from app.domain import panel
from app.domain.catalogos import EVENTO_DISPENSADO
from app.models import models


def resumen(
    db: Session,
    *,
    user_id: int,
    ahora: datetime,
    zona: Optional[tzinfo] = None,
) -> tuple[panel.ResumenPanel, datetime]:
    """Calcula el resumen del panel del usuario en el instante `ahora`.

    Devuelve `(resumen, instante_del_calculo)`. El resultado solo usa filas del
    usuario: sus mascotas y castradas (RF-1), los horarios de las mascotas con
    dispensador vinculado y activo como programado y ocurrencias (RF-3, RF-4), y
    los registros de dispensación del catálogo desde el inicio de la semana en
    curso hasta el fin del día local de hoy, sin incluirlo (RF-2, RF-5).

    `zona` es la zona horaria del servidor; sin ella se usa la local del equipo,
    igual que en `domain/tiempo`. Solo se usa para decidir el día y la semana,
    nunca para reconvertir los instantes guardados.
    """
    (
        inicio_semana_utc,
        _inicio_dia_utc,
        fin_dia_utc,
        _indice_hoy,
    ) = panel.rango_semana_local(ahora, zona)

    mascotas = (
        db.query(models.Pet.id, models.Pet.reproductive_status)
        .filter(models.Pet.user_id == user_id)
        .all()
    )

    # Solo los horarios que el servicio de dispensación puede ejecutar hoy:
    # mascota del usuario con dispensador vinculado y activo (RF-3).
    gramos_horarios = [
        fila.amount
        for fila in (
            db.query(models.Schedule.amount)
            .join(models.Pet, models.Schedule.pet_id == models.Pet.id)
            .join(models.Dispenser, models.Dispenser.pet_id == models.Pet.id)
            .filter(
                models.Pet.user_id == user_id,
                models.Dispenser.is_active.is_(True),
            )
            .all()
        )
    ]

    # Ventana de la semana en curso hasta el fin del día local de hoy (RF-5).
    registros = (
        db.query(
            models.ActivityLog.created_at,
            models.ActivityLog.outcome,
            models.ActivityLog.measured_grams,
            models.ActivityLog.discounted_grams,
        )
        .filter(
            models.ActivityLog.user_id == user_id,
            models.ActivityLog.event_type == EVENTO_DISPENSADO,
            models.ActivityLog.created_at >= inicio_semana_utc,
            models.ActivityLog.created_at < fin_dia_utc,
        )
        .all()
    )

    calculado = panel.calcular_resumen(
        total_mascotas=len(mascotas),
        mascotas_castradas=sum(1 for mascota in mascotas if mascota.reproductive_status),
        gramos_horarios=gramos_horarios,
        registros=[
            panel.RegistroDispensado(
                instante=fila.created_at,
                outcome=fila.outcome,
                measured_grams=fila.measured_grams,
                discounted_grams=fila.discounted_grams,
            )
            for fila in registros
        ],
        ahora=ahora,
        zona=zona,
    )

    return calculado, ahora
