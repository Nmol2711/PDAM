import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/nutrition/domain/usecases/calculate_nutrition_usecase.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/bloc/nutrition_cubit.dart';

/// Pruebas unitarias del [NutritionCubit] de la calculadora nutricional (RF-4).
///
/// Verifican que el formulario es la única fuente de verdad, que los campos se
/// actualizan sin perder el resultado previo cuando corresponde, y que el
/// cálculo sincroniza exactamente con el motor WSAVA del dominio (RF-4, RNF-1).
void main() {
  NutritionCubit buildCubit() => NutritionCubit(
        calculateNutritionUsecase: const CalculateNutritionUsecase(),
      );

  group('NutritionCubit - estado inicial', () {
    test('tiene el formulario con valores por defecto y sin resultado', () {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      expect(cubit.state.result, isNull);
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.form.species, 'canino');
      expect(cubit.state.form.bodyWeight, '');
      expect(cubit.state.form.caloricDensity, '');
      expect(cubit.state.form.bcs, 5);
      expect(cubit.state.form.mcs, 'normal');
      expect(cubit.state.form.activityLevel, 'medium');
      expect(cubit.state.form.reproductiveStatus, 'castrado');
      expect(cubit.state.form.lifeStage, 'adulto');
      expect(cubit.state.form.mealsPerDay, 2);
      expect(cubit.state.form.snacksKcal, '');
    });
  });

  group('NutritionCubit - actualización de campos', () {
    test('actualizar un campo invalida el resultado previo', () {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      cubit.updateBodyWeight('12.5');
      cubit.updateCaloricDensity('4000');
      cubit.calculate();
      expect(cubit.state.result, isNotNull);

      cubit.updateSpecies('felino');
      expect(cubit.state.form.species, 'felino');
      expect(cubit.state.result, isNull, reason: 'el resultado queda obsoleto');
      expect(cubit.state.errorMessage, isNull);
    });

    test('cada actualizador modifica su campo correspondiente', () {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      cubit.updateBcs(7);
      cubit.updateMcs('marked');
      cubit.updateActivityLevel('high');
      cubit.updateReproductiveStatus('entero');
      cubit.updateLifeStage('crecimiento');
      cubit.updateMealsPerDay(4);
      cubit.updateSnacksKcal('20');

      expect(cubit.state.form.bcs, 7);
      expect(cubit.state.form.mcs, 'marked');
      expect(cubit.state.form.activityLevel, 'high');
      expect(cubit.state.form.reproductiveStatus, 'entero');
      expect(cubit.state.form.lifeStage, 'crecimiento');
      expect(cubit.state.form.mealsPerDay, 4);
      expect(cubit.state.form.snacksKcal, '20');
    });
  });

  group('NutritionCubit - cálculo válido', () {
    test('calcula la dosificación correctamente para un perro adulto castrado',
        () {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      cubit.updateBodyWeight('12.5');
      cubit.updateCaloricDensity('4000');
      cubit.updateSnacksKcal('50');
      cubit.calculate();

      expect(cubit.state.errorMessage, isNull);
      final result = cubit.state.result;
      expect(result, isNotNull);
      expect(result!.species, 'canino');
      expect(result.rerKcal, closeTo(465.3508909826865, 1e-6));
      expect(result.merKcal, closeTo(744.5614255722985, 1e-6));
      expect(result.exceedsSnackLimit, isFalse);
      expect(result.dailyRationGrams, greaterThan(0));
    });

    test('snacks sobre el 10% del MER disparan la alerta', () {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      cubit.updateBodyWeight('12.5');
      cubit.updateCaloricDensity('4000');
      cubit.updateSnacksKcal('200');
      cubit.calculate();

      final result = cubit.state.result;
      expect(result, isNotNull);
      expect(result!.exceedsSnackLimit, isTrue);
    });

    test('snacks vacíos se interpretan como 0', () {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      cubit.updateBodyWeight('12.5');
      cubit.updateCaloricDensity('4000');
      cubit.calculate();

      final result = cubit.state.result;
      expect(result, isNotNull);
      expect(result!.snacksKcal, 0.0);
      expect(result.exceedsSnackLimit, isFalse);
    });
  });

  group('NutritionCubit - entradas inválidas', () {
    test('peso no numérico emite error descriptivo', () {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      cubit.updateBodyWeight('abc');
      cubit.updateCaloricDensity('4000');
      cubit.calculate();

      expect(cubit.state.result, isNull);
      expect(cubit.state.errorMessage, isNotNull);
      expect(cubit.state.errorMessage!.toLowerCase(), contains('peso corporal'));
    });

    test('peso cero o negativo delega en la validación del caso de uso', () {
      for (final valor in ['0', '-3']) {
        final cubit = buildCubit();
        addTearDown(cubit.close);

        cubit.updateBodyWeight(valor);
        cubit.updateCaloricDensity('4000');
        cubit.calculate();

        expect(cubit.state.result, isNull, reason: 'valor=$valor');
        expect(cubit.state.errorMessage, isNotNull, reason: 'valor=$valor');
      }
    });

    test('densidad calórica no numérica emite error descriptivo', () {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      cubit.updateBodyWeight('12.5');
      cubit.updateCaloricDensity('xyz');
      cubit.calculate();

      expect(cubit.state.result, isNull);
      expect(
        cubit.state.errorMessage!.toLowerCase(),
        contains('densidad calórica'),
      );
    });

    test('snacks no numéricos emiten error descriptivo', () {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      cubit.updateBodyWeight('12.5');
      cubit.updateCaloricDensity('4000');
      cubit.updateSnacksKcal('muchos');
      cubit.calculate();

      expect(cubit.state.result, isNull);
      expect(cubit.state.errorMessage!.toLowerCase(), contains('snacks'));
    });
  });
}
