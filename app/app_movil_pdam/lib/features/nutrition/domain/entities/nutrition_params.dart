/// Entidad de dominio con los parámetros de entrada del motor nutricional.
///
/// Representa la misma entrada validada por el backend
/// (`NutritionCalculationRequest` en `api/app/schemas/nutrition_schemas.py`).
/// Es un contenedor inmutable de datos; la validación y normalización se aplica
/// en el caso de uso `CalculateNutritionUsecase`.
class NutritionParams {
  final String species;
  final double bodyWeight;
  final double caloricDensityKcalPerKg;
  final int bcs;
  final String mcs;
  final String activityLevel;
  final String reproductiveStatus;
  final String lifeStage;
  final int mealsPerDay;
  final double snacksKcal;

  const NutritionParams({
    required this.species,
    required this.bodyWeight,
    required this.caloricDensityKcalPerKg,
    required this.bcs,
    required this.mcs,
    required this.activityLevel,
    required this.reproductiveStatus,
    required this.lifeStage,
    required this.mealsPerDay,
    this.snacksKcal = 0.0,
  });
}
