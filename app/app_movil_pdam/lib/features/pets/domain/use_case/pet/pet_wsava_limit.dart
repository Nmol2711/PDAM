import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_result.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/wsava_engine.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';

/// Densidad calórica de referencia (kcal/kg) usada por el detalle de mascota
/// cuando no se conoce la del alimento. Es solo un valor por defecto: la
/// fórmula vive en el motor WSAVA, no en la vista.
const double defaultPetFoodKcalPerKg = 3850.0;

/// Convierte la especie de la mascota a la forma canónica del motor WSAVA.
///
/// Devuelve `null` para `TypePest.otros`: el motor y el backend solo admiten
/// canino/felino (RF-2), por lo que no se debe inventar un cálculo como si la
/// mascota fuera un gato.
String? speciesForNutrition(TypePest species) {
  switch (species) {
    case TypePest.canino:
      return 'canino';
    case TypePest.felino:
      return 'felino';
    case TypePest.otros:
      return null;
  }
}

/// Deriva la etapa de vida WSAVA a partir de la fecha de nacimiento.
///
/// Crecimiento si la mascota tiene menos de 12 meses; adulto en caso contrario.
String lifeStageForPet(Pet pet, {DateTime? today}) {
  final reference = today ?? DateTime.now();
  final ageDays = reference.difference(pet.birthDate).inDays;
  final ageMonths = ageDays / 30.44;
  return ageMonths < 12 ? 'crecimiento' : 'adulto';
}

/// Calcula la ración diaria de referencia de una mascota con el motor unificado.
///
/// Sustituye la fórmula que estaba embebida en `pet_detail_view.dart` (T11,
/// RNF-4). Usa el mismo motor y las mismas tablas que la calculadora nutricional
/// y el backend. Cuando no hay datos de condición corporal, actividad o
/// musculatura, aplica valores neutros (BCS 5, MCS normal, actividad media).
///
/// Devuelve `null` cuando la especie no está soportada por el motor (RF-2).
NutritionResult? petNutritionReference(
  Pet pet, {
  double foodKcalPerKg = defaultPetFoodKcalPerKg,
  DateTime? today,
}) {
  final species = speciesForNutrition(pet.species);
  if (species == null) return null;

  return calculateNutrition(
    species: species,
    bodyWeight: pet.weight,
    caloricDensityKcalPerKg: foodKcalPerKg,
    bcs: 5,
    mcs: 'normal',
    activityLevel: 'medium',
    reproductiveStatus: pet.reproductiveStatus ? 'castrado' : 'entero',
    lifeStage: lifeStageForPet(pet, today: today),
    mealsPerDay: 2,
  );
}

/// Ración diaria de referencia en gramos según el motor WSAVA unificado.
///
/// Devuelve `null` si la especie no está soportada (RF-2), de modo que la
/// interfaz no muestre un límite calculado para una especie distinta.
double? petWsavaDailyLimitGrams(
  Pet pet, {
  double foodKcalPerKg = defaultPetFoodKcalPerKg,
  DateTime? today,
}) {
  return petNutritionReference(
    pet,
    foodKcalPerKg: foodKcalPerKg,
    today: today,
  )?.dailyRationGrams;
}
