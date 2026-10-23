import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_validators.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/wsava_engine.dart';

void main() {
  group('calculateRer', () {
    test('RER = 70 * BW^0.75 (peso conocido)', () {
      expect(calculateRer(10.0), closeTo(393.6389276332444, 1e-6));
    });

    test('RER con peso unitario es 70', () {
      expect(calculateRer(1.0), closeTo(70.0, 1e-9));
    });

    test('RER con peso fraccionario', () {
      expect(calculateRer(12.5), closeTo(465.3508909826865, 1e-6));
    });

    test('lanza excepción con peso cero', () {
      expect(
        () => calculateRer(0.0),
        throwsA(isA<NutritionValidationException>()
            .having((e) => e.message, 'message', contains('peso corporal'))),
      );
    });

    test('lanza excepción con peso negativo', () {
      expect(() => calculateRer(-5.0),
          throwsA(isA<NutritionValidationException>()));
    });
  });

  group('calculateMer - factores base', () {
    // rer=100, activity=medium, bcs=5, mcs=normal => multiplicadores neutros.
    test('canino adulto entero => 1.8', () {
      expect(calculateMer(100.0, 'canino', 'entero', 'adulto', 'medium', 5, 'normal'),
          closeTo(180.0, 1e-9));
    });

    test('canino adulto castrado => 1.6', () {
      expect(
          calculateMer(100.0, 'canino', 'castrado', 'adulto', 'medium', 5, 'normal'),
          closeTo(160.0, 1e-9));
    });

    test('canino adulto esterilizado => 1.6', () {
      expect(
          calculateMer(
              100.0, 'canino', 'esterilizado', 'adulto', 'medium', 5, 'normal'),
          closeTo(160.0, 1e-9));
    });

    test('canino crecimiento => 2.0', () {
      expect(
          calculateMer(
              100.0, 'canino', 'entero', 'crecimiento', 'medium', 5, 'normal'),
          closeTo(200.0, 1e-9));
    });

    test('felino adulto entero => 1.4', () {
      expect(calculateMer(100.0, 'felino', 'entero', 'adulto', 'medium', 5, 'normal'),
          closeTo(140.0, 1e-9));
    });

    test('felino adulto castrado => 1.2', () {
      expect(
          calculateMer(100.0, 'felino', 'castrado', 'adulto', 'medium', 5, 'normal'),
          closeTo(120.0, 1e-9));
    });

    test('felino crecimiento => 2.5', () {
      expect(
          calculateMer(
              100.0, 'felino', 'entero', 'crecimiento', 'medium', 5, 'normal'),
          closeTo(250.0, 1e-9));
    });
  });

  group('calculateMer - factor de actividad', () {
    test('actividad baja reduce el MER', () {
      expect(
          calculateMer(100.0, 'canino', 'castrado', 'adulto', 'low', 5, 'normal'),
          closeTo(144.0, 1e-9));
    });

    test('actividad media es neutra', () {
      expect(
          calculateMer(
              100.0, 'canino', 'castrado', 'adulto', 'medium', 5, 'normal'),
          closeTo(160.0, 1e-9));
    });

    test('actividad alta aumenta el MER', () {
      expect(
          calculateMer(
              100.0, 'canino', 'castrado', 'adulto', 'high', 5, 'normal'),
          closeTo(192.0, 1e-9));
    });
  });

  group('calculateMer - factor de BCS', () {
    test('BCS bajo (1-3) aumenta el MER', () {
      for (final bcs in [1, 2, 3]) {
        expect(
            calculateMer(100.0, 'canino', 'castrado', 'adulto', 'medium', bcs, 'normal'),
            closeTo(192.0, 1e-9),
            reason: 'bcs=$bcs');
      }
    });

    test('BCS ideal (4-6) es neutro', () {
      for (final bcs in [4, 5, 6]) {
        expect(
            calculateMer(100.0, 'canino', 'castrado', 'adulto', 'medium', bcs, 'normal'),
            closeTo(160.0, 1e-9),
            reason: 'bcs=$bcs');
      }
    });

    test('BCS alto (7-9) reduce el MER', () {
      for (final bcs in [7, 8, 9]) {
        expect(
            calculateMer(100.0, 'canino', 'castrado', 'adulto', 'medium', bcs, 'normal'),
            closeTo(128.0, 1e-9),
            reason: 'bcs=$bcs');
      }
    });
  });

  group('calculateMer - factor de MCS', () {
    test('normal/mild neutro', () {
      for (final mcs in ['normal', 'mild']) {
        expect(
            calculateMer(100.0, 'canino', 'castrado', 'adulto', 'medium', 5, mcs),
            closeTo(160.0, 1e-9),
            reason: 'mcs=$mcs');
      }
    });

    test('moderate reduce el MER', () {
      expect(
          calculateMer(
              100.0, 'canino', 'castrado', 'adulto', 'medium', 5, 'moderate'),
          closeTo(152.0, 1e-9));
    });

    test('marked reduce el MER', () {
      expect(
          calculateMer(100.0, 'canino', 'castrado', 'adulto', 'medium', 5, 'marked'),
          closeTo(144.0, 1e-9));
    });
  });

  group('calculateMer - combinaciones', () {
    test('ejemplo realista completo', () {
      final rer = calculateRer(10.0);
      final mer = calculateMer(
          rer, 'canino', 'castrado', 'adulto', 'medium', 5, 'normal');
      expect(mer, closeTo(629.8222842131911, 1e-6));
    });

    test('actividad alta, bajo peso, MCS moderado', () {
      final rer = calculateRer(10.0);
      final mer = calculateMer(
          rer, 'canino', 'castrado', 'adulto', 'high', 3, 'moderate');
      expect(mer, closeTo(861.5968848036454, 1e-6));
    });

    test('felino, actividad baja, sobrepeso, MCS marcado', () {
      final rer = calculateRer(10.0);
      final mer = calculateMer(
          rer, 'felino', 'entero', 'adulto', 'low', 8, 'marked');
      expect(mer, closeTo(357.1092351488793, 1e-6));
    });

    test('determinista: misma entrada, misma salida', () {
      final first = calculateMer(
          250.0, 'felino', 'esterilizado', 'adulto', 'medium', 5, 'normal');
      final second = calculateMer(
          250.0, 'felino', 'esterilizado', 'adulto', 'medium', 5, 'normal');
      expect(first, second);
    });
  });

  group('calculateMer - entradas inválidas', () {
    test('especie inválida lanza excepción', () {
      for (final species in ['ave', 'conejo', '', 'CANINO_FALSO']) {
        expect(
          () => calculateMer(
              100.0, species, 'castrado', 'adulto', 'medium', 5, 'normal'),
          throwsA(isA<NutritionValidationException>()),
          reason: 'species=$species',
        );
      }
    });

    test('estatus reproductivo inválido lanza excepción', () {
      for (final status in ['preñada', 'lactante', '']) {
        expect(
          () => calculateMer(100.0, 'canino', status, 'adulto', 'medium', 5, 'normal'),
          throwsA(isA<NutritionValidationException>()),
          reason: 'status=$status',
        );
      }
    });

    test('etapa de vida inválida lanza excepción', () {
      for (final stage in ['senior', 'juvenil', '']) {
        expect(
          () => calculateMer(
              100.0, 'canino', 'castrado', stage, 'medium', 5, 'normal'),
          throwsA(isA<NutritionValidationException>()),
          reason: 'stage=$stage',
        );
      }
    });

    test('actividad inválida lanza excepción', () {
      for (final activity in ['extremo', 'sedentario', '']) {
        expect(
          () => calculateMer(
              100.0, 'canino', 'castrado', 'adulto', activity, 5, 'normal'),
          throwsA(isA<NutritionValidationException>()),
          reason: 'activity=$activity',
        );
      }
    });

    test('MCS inválido lanza excepción', () {
      for (final mcs in ['severo', 'excelente', '']) {
        expect(
          () => calculateMer(100.0, 'canino', 'castrado', 'adulto', 'medium', 5, mcs),
          throwsA(isA<NutritionValidationException>()),
          reason: 'mcs=$mcs',
        );
      }
    });
  });

  group('getVariabilityRange', () {
    test('canino ±30%', () {
      final range = getVariabilityRange('canino', 100.0);
      expect(range.$1, closeTo(70.0, 1e-9));
      expect(range.$2, closeTo(130.0, 1e-9));
    });

    test('felino ±50%', () {
      final range = getVariabilityRange('felino', 100.0);
      expect(range.$1, closeTo(50.0, 1e-9));
      expect(range.$2, closeTo(150.0, 1e-9));
    });

    test('MER cero devuelve rango cero', () {
      final range = getVariabilityRange('canino', 0.0);
      expect(range.$1, 0.0);
      expect(range.$2, 0.0);
    });

    test('el mínimo es menor que el máximo', () {
      final range = getVariabilityRange('canino', 300.0);
      expect(range.$1, lessThan(range.$2));
    });

    test('especie inválida lanza excepción', () {
      for (final species in ['ave', '', 'felino_falso']) {
        expect(
          () => getVariabilityRange(species, 100.0),
          throwsA(isA<NutritionValidationException>()),
          reason: 'species=$species',
        );
      }
    });
  });

  group('evaluateSnacks', () {
    test('snacks bajo el límite: sin alerta', () {
      final result = evaluateSnacks(1000.0, 50.0);
      expect(result.snackLimitKcal, closeTo(100.0, 1e-9));
      expect(result.exceedsLimit, isFalse);
      expect(result.finalRationKcal, closeTo(950.0, 1e-9));
    });

    test('snacks en el límite exacto: no excede', () {
      final result = evaluateSnacks(1000.0, 100.0);
      expect(result.exceedsLimit, isFalse);
      expect(result.finalRationKcal, closeTo(900.0, 1e-9));
    });

    test('snacks sobre el límite: alerta', () {
      final result = evaluateSnacks(1000.0, 100.1);
      expect(result.exceedsLimit, isTrue);
      expect(result.finalRationKcal, closeTo(899.9, 1e-9));
    });

    test('snacks mayores al MER: ración ajustada a cero', () {
      final result = evaluateSnacks(1000.0, 1500.0);
      expect(result.exceedsLimit, isTrue);
      expect(result.finalRationKcal, 0.0);
    });

    test('sin snacks: ración igual al MER completo', () {
      final result = evaluateSnacks(800.0, 0.0);
      expect(result.exceedsLimit, isFalse);
      expect(result.finalRationKcal, closeTo(800.0, 1e-9));
    });
  });

  group('calculateDailyRationGrams', () {
    test('conversión típica', () {
      expect(calculateDailyRationGrams(600.0, 4000.0), closeTo(150.0, 1e-9));
    });

    test('densidad 1000 kcal/kg equivale a 1 kcal/g', () {
      expect(calculateDailyRationGrams(600.0, 1000.0), closeTo(600.0, 1e-9));
    });

    test('ración cero devuelve cero', () {
      expect(calculateDailyRationGrams(0.0, 4000.0), 0.0);
    });

    test('densidad cero es segura (devuelve 0)', () {
      expect(calculateDailyRationGrams(600.0, 0.0), 0.0);
    });

    test('densidad negativa es segura (devuelve 0)', () {
      expect(calculateDailyRationGrams(600.0, -4000.0), 0.0);
    });
  });
}
