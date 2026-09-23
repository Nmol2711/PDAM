from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from datetime import date, datetime, timedelta
from app.db.database import get_db
from app.api.deps import CurrentUser
from app.models import models
from app.schemas import schemas

router = APIRouter()

@router.get("/summary", response_model=schemas.DashboardSummary)
def get_dashboard_summary(
    current_user: CurrentUser,
    db: Session = Depends(get_db)
):
    # 1. Mascotas
    pets = db.query(models.Pet).filter(models.Pet.user_id == current_user.id).all()
    total_pets = len(pets)
    sterilized_pets = sum(1 for p in pets if p.reproductive_status)

    # 2. Horarios y porciones
    pet_ids = [p.id for p in pets]
    schedules = []
    if pet_ids:
        schedules = db.query(models.Schedule).filter(models.Schedule.pet_id.in_(pet_ids)).all()
    
    pending_feedings = len(schedules)
    completed_feedings = 0  # Se puede actualizar si hay logs de hoy

    # 3. Alimento
    food_dispensed_today = sum(s.amount for s in schedules)
    food_target_today = total_pets * 300.0 if total_pets > 0 else 300.0

    # 4. Dispensación semanal simulada/calculada (Lun-Dom)
    # Por defecto generamos valores basados en los horarios totales
    base_daily = sum(s.amount for s in schedules) if schedules else 150.0
    weekly_dispensed = [
        float(base_daily * 0.9),
        float(base_daily * 1.0),
        float(base_daily * 1.1),
        float(base_daily * 0.95),
        float(base_daily * 1.05),
        float(base_daily * 1.2),
        float(base_daily * base_daily > 0 and 1.0 or 0.0),
    ]

    return schemas.DashboardSummary(
        total_pets=total_pets,
        sterilized_pets=sterilized_pets,
        food_dispensed_today=float(food_dispensed_today),
        food_target_today=float(food_target_today),
        pending_feedings=pending_feedings,
        completed_feedings=completed_feedings,
        weekly_dispensed=weekly_dispensed
    )
