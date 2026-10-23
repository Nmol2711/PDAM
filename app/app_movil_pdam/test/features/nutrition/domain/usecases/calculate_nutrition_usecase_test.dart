import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_params.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_result.dart';
import 'package:app_movil_pdam/features/nutrition/domain/usecases/calculate_nutrition_usecase.dart';

const CalculateNutritionUsecase usecase = CalculateNutritionUsecase();

NutritionParams _validParams() => const NutritionParams(
      species: 'canino',
      bodyWeight: 12.5,
      caloricDensityKcalPerKg: 4000.0,
      bcs: 5,
      mcs: 'normal',
      activityLevel: 'medio',
      reproductiveStatus: 'castrado',
      lifeStage: 'adulto',
      mealsPerDay: 2,
    );

String _leftMessage(Either<Failures, NutritionResult> result) {
  return result.fold((failure) => failure.message, (_) => '');
}

void main() {
  group('CalculateNutritionUsecase - peticiones válidas', () {
    test('devuelve Right con el resultado completo', () {
      final result = usecase(_validParams());

      expect(result.isRight(), isTrue);
      final nutrition = result.fold(
        (failure) => fail('No debería fallar: ${failure.message}'),
        (value) => value,
      );

      expect(nutrition.species, 'canino');
      expect(nutrition.bodyWeight, 12.5);
      expect(nutrition.mealsPerDay, 2);
      expect(nutrition.rerKcal, closeTo(465.3508909826865, 1e-6));
      expect(nutrition.merKcal, closeTo(744.5614255722985, 1e-6));
      expect(nutrition.variabilityMinKcal, closeTo(521.1929979006089, 1e-6));
      expect(nutrition.variabilityMaxKcal, closeTo(967.9298532439881, 1e-6));
      expect(nutrition.snackLimitKcal, closeTo(74.45614255722985, 1e-6));
      expect(nutrition.snacksKcal, 0.0);
      expect(nutrition.exceedsSnackLimit, isFalse);
      expect(nutrition.finalRationKcal, closeTo(744.5614255722985, 1e-6));
      expect(nutrition.dailyRationGrams, closeTo(186.14035639307463, 1e-6));
      expect(nutrition.rationPerMealGrams, closeTo(93.07017819653731, 1e-6));
    });

    test('normaliza sinónimos de especie a la forma canónica', () {
      final params = NutritionParams(
        species: 'perro',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
      );

      final result = usecase(params);
      expect(result.isRight(), isTrue);
      expect(result.fold((_) => null, (value) => value.species), 'canino');
    });

    test('variabilidad de gato es ±50%', () {
      final params = NutritionParams(
        species: 'gato',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'esterilizado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
      );

      final result = usecase(params);
      expect(result.isRight(), isTrue);
      final nutrition = result.fold((_) => null, (value) => value)!;
      expect(nutrition.variabilityMinKcal,
          closeTo(nutrition.merKcal * 0.5, 1e-6));
      expect(nutrition.variabilityMaxKcal,
          closeTo(nutrition.merKcal * 1.5, 1e-6));
    });
  });

  group('CalculateNutritionUsecase - snacks', () {
    test('snacks bajo el límite no exceden', () {
      final params = NutritionParams(
        species: 'canino',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
        snacksKcal: 50.0,
      );

      final result = usecase(params);
      expect(result.isRight(), isTrue);
      final nutrition = result.fold((_) => null, (value) => value)!;
      expect(nutrition.exceedsSnackLimit, isFalse);
      expect(nutrition.finalRationKcal,
          closeTo(nutrition.merKcal - 50.0, 1e-6));
    });

    test('snacks sobre el límite disparan alerta y recálculo', () {
      const mer = 744.5614255722985;
      final params = NutritionParams(
        species: 'canino',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
        snacksKcal: mer * 0.2,
      );

      final result = usecase(params);
      expect(result.isRight(), isTrue);
      final nutrition = result.fold((_) => null, (value) => value)!;
      expect(nutrition.exceedsSnackLimit, isTrue);
      expect(nutrition.finalRationKcal, closeTo(mer - (mer * 0.2), 1e-6));
    });
  });

  group('CalculateNutritionUsecase - entradas inválidas', () {
    test('peso corporal ausente, cero o negativo es rechazado', () {
      final params = NutritionParams(
        species: 'canino',
        bodyWeight: 0.0,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
      );
      final result = usecase(params);
      expect(result.isLeft(), isTrue);
      expect(_leftMessage(result).toLowerCase(), contains('peso corporal'));
    });

    test('densidad calórica cero es rechazada', () {
      final params = NutritionParams(
        species: 'canino',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 0.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
      );
      final result = usecase(params);
      expect(result.isLeft(), isTrue);
      expect(_leftMessage(result).toLowerCase(), contains('densidad calórica'));
    });

    test('comidas diarias fuera de rango son rechazadas', () {
      for (final meals in [0, 7, -1]) {
        final params = NutritionParams(
          species: 'canino',
          bodyWeight: 12.5,
          caloricDensityKcalPerKg: 4000.0,
          bcs: 5,
          mcs: 'normal',
          activityLevel: 'medio',
          reproductiveStatus: 'castrado',
          lifeStage: 'adulto',
          mealsPerDay: meals,
        );
        final result = usecase(params);
        expect(result.isLeft(), isTrue, reason: 'meals=$meals');
        expect(_leftMessage(result).toLowerCase(), contains('comidas diarias'));
      }
    });

    test('BCS fuera de rango es rechazado', () {
      for (final bcs in [0, 10, -1]) {
        final params = NutritionParams(
          species: 'canino',
          bodyWeight: 12.5,
          caloricDensityKcalPerKg: 4000.0,
          bcs: bcs,
          mcs: 'normal',
          activityLevel: 'medio',
          reproductiveStatus: 'castrado',
          lifeStage: 'adulto',
          mealsPerDay: 2,
        );
        final result = usecase(params);
        expect(result.isLeft(), isTrue, reason: 'bcs=$bcs');
        expect(_leftMessage(result).toLowerCase(), contains('bcs'));
      }
    });

    test('especie inválida es rechazada', () {
      final params = NutritionParams(
        species: 'ave',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
      );
      final result = usecase(params);
      expect(result.isLeft(), isTrue);
      expect(_leftMessage(result).toLowerCase(), contains('especie'));
    });

    test('MCS inválido es rechazado', () {
      final params = NutritionParams(
        species: 'canino',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'severo',
        activityLevel: 'medio',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
      );
      final result = usecase(params);
      expect(result.isLeft(), isTrue);
      expect(_leftMessage(result).toLowerCase(), contains('mcs'));
    });

    test('actividad inválida es rechazada', () {
      final params = NutritionParams(
        species: 'canino',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'extremo',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
      );
      final result = usecase(params);
      expect(result.isLeft(), isTrue);
      expect(_leftMessage(result).toLowerCase(), contains('actividad'));
    });

    test('estatus reproductivo inválido es rechazado', () {
      final params = NutritionParams(
        species: 'canino',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'preñada',
        lifeStage: 'adulto',
        mealsPerDay: 2,
      );
      final result = usecase(params);
      expect(result.isLeft(), isTrue);
      expect(_leftMessage(result).toLowerCase(), contains('reproductivo'));
    });

    test('etapa de vida inválida es rechazada', () {
      final params = NutritionParams(
        species: 'canino',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'castrado',
        lifeStage: 'senior',
        mealsPerDay: 2,
      );
      final result = usecase(params);
      expect(result.isLeft(), isTrue);
      expect(_leftMessage(result).toLowerCase(), contains('etapa de vida'));
    });

    test('snacks negativos son rechazados', () {
      final params = NutritionParams(
        species: 'canino',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: 4000.0,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medio',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
        snacksKcal: -1.0,
      );
      final result = usecase(params);
      expect(result.isLeft(), isTrue);
      expect(_leftMessage(result).toLowerCase(), contains('snacks'));
    });
  });
}
