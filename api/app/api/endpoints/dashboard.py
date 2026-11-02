"""Endpoint del resumen del panel (spec 022, T2).

Solo compone la respuesta: lee el instante actual del servidor, pide el resumen
al servicio y lo traduce al contrato. No hay constantes, multiplicadores ni
series simuladas; las cifras salen de la actividad registrada del usuario
(RF-1 a RF-7). La lógica vive en `services/dashboard_service.py` y el cálculo en
`domain/panel.py`.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser
from app.db.database import get_db
from app.domain import tiempo
from app.schemas import schemas
from app.services import dashboard_service

router = APIRouter()


@router.get("/summary", response_model=schemas.DashboardSummary)
def get_dashboard_summary(
    current_user: CurrentUser,
    db: Session = Depends(get_db),
):
    """Resumen del panel del usuario autenticado con datos reales."""
    calculado, instante = dashboard_service.resumen(
        db,
        user_id=current_user.id,
        ahora=tiempo.ahora_utc(),
    )

    return schemas.DashboardSummary(
        total_pets=calculado.total_mascotas,
        sterilized_pets=calculado.mascotas_castradas,
        food_dispensed_today=calculado.gramos_hoy,
        food_target_today=calculado.programado_hoy,
        pending_feedings=calculado.pendientes,
        completed_feedings=calculado.completadas,
        # La serie del dominio es una tupla inmutable; el contrato usa lista.
        weekly_dispensed=list(calculado.serie_semanal),
        today_index=calculado.indice_hoy,
        calculated_at=tiempo.a_texto_utc(instante),
    )
