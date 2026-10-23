import 'package:dartz/dartz.dart';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_params.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_result.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_validators.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/wsava_engine.dart';

/// Caso de uso de cálculo nutricional WSAVA (RF-3, RF-4).
///
/// Replica el flujo completo del backend: normaliza y valida los parámetros de
/// entrada (RF-1/RF-2, como `NutritionCalculationRequest`) y delega el cálculo
/// en el motor puro (`wsava_engine.dart`). Ante entradas inválidas devuelve
/// `Left(NutritionValidationFailures)` con un mensaje descriptivo en español;
/// ante entradas válidas devuelve `Right(NutritionResult)`.
class CalculateNutritionUsecase {
  const CalculateNutritionUsecase();

  Either<Failures, NutritionResult> call(NutritionParams params) {
    try {
      final species = normalizeSpecies(params.species);
      final mcs = normalizeMcs(params.mcs);
      final activityLevel = normalizeActivityLevel(params.activityLevel);
      final reproductiveStatus =
          normalizeReproductiveStatus(params.reproductiveStatus);
      final lifeStage = normalizeLifeStage(params.lifeStage);

      if (!validateBodyWeight(params.bodyWeight)) {
        throw const NutritionValidationException(
          'El peso corporal (BW) debe ser un número mayor a 0 (kg).',
        );
      }
      if (!validateCaloricDensity(params.caloricDensityKcalPerKg)) {
        throw const NutritionValidationException(
          'La densidad calórica debe ser un número mayor a 0 (kcal/kg).',
        );
      }
      if (!validateBcs(params.bcs)) {
        throw const NutritionValidationException(
          'El BCS debe estar entre 1 y 9.',
        );
      }
      if (!validateMealsPerDay(params.mealsPerDay)) {
        throw const NutritionValidationException(
          'Las comidas diarias deben estar entre 1 y 6.',
        );
      }
      if (!validateSnacksKcal(params.snacksKcal)) {
        throw const NutritionValidationException(
          'Las calorías de snacks no pueden ser negativas.',
        );
      }

      final result = calculateNutrition(
        species: species,
        bodyWeight: params.bodyWeight,
        caloricDensityKcalPerKg: params.caloricDensityKcalPerKg,
        bcs: params.bcs,
        mcs: mcs,
        activityLevel: activityLevel,
        reproductiveStatus: reproductiveStatus,
        lifeStage: lifeStage,
        mealsPerDay: params.mealsPerDay,
        snacksKcal: params.snacksKcal,
      );

      return Right(result);
    } on NutritionValidationException catch (e) {
      return Left(NutritionValidationFailures(e.message));
    }
  }
}
