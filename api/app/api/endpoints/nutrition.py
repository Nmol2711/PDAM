from fastapi import APIRouter

from app.schemas.nutrition_schemas import (
    NutritionCalculationRequest,
    NutritionCalculationResponse,
)
from app.services import nutrition_service

router = APIRouter()


@router.post("/calculate", response_model=NutritionCalculationResponse)
def calculate_nutrition(request: NutritionCalculationRequest):
    """Calcula la dosificación nutricional WSAVA de forma sincronizada (RF-4).

    Recibe los parámetros ya validados por `NutritionCalculationRequest`
    (RF-1 y RF-2) y devuelve el resultado completo generado por el motor de
    cálculo del servicio (RF-3). Al delegar toda la lógica en el servicio, se
    garantiza que la aplicación móvil obtiene exactamente los mismos resultados
    que el servidor (RNF-1: determinismo).
    """
    return nutrition_service.calculate_nutrition(
        species=request.species,
        body_weight=request.body_weight,
        caloric_density_kcal_per_kg=request.caloric_density_kcal_per_kg,
        bcs=request.bcs,
        mcs=request.mcs,
        activity_level=request.activity_level,
        reproductive_status=request.reproductive_status,
        life_stage=request.life_stage,
        meals_per_day=request.meals_per_day,
        snacks_kcal=request.snacks_kcal,
    )
