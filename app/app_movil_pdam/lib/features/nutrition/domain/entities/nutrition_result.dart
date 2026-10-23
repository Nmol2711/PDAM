/// Entidad de dominio con el resultado completo del cálculo nutricional WSAVA.
///
/// Refleja exactamente los campos devueltos por el motor del backend
/// (`NutritionCalculationResponse` en `api/app/schemas/nutrition_schemas.py`)
/// para que la aplicación móvil obtenga los mismos valores que el servidor
/// (RF-4).
class NutritionResult {
  final String species;
  final double bodyWeight;
  final int mealsPerDay;
  final double rerKcal;
  final double merKcal;
  final double variabilityMinKcal;
  final double variabilityMaxKcal;
  final double snackLimitKcal;
  final double snacksKcal;
  final bool exceedsSnackLimit;
  final double finalRationKcal;
  final double dailyRationGrams;
  final double rationPerMealGrams;

  const NutritionResult({
    required this.species,
    required this.bodyWeight,
    required this.mealsPerDay,
    required this.rerKcal,
    required this.merKcal,
    required this.variabilityMinKcal,
    required this.variabilityMaxKcal,
    required this.snackLimitKcal,
    required this.snacksKcal,
    required this.exceedsSnackLimit,
    required this.finalRationKcal,
    required this.dailyRationGrams,
    required this.rationPerMealGrams,
  });
}
