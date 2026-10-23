import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_validators.dart';

void main() {
  group('Validación de límites (Boundary Validation)', () {
    group('validateBodyWeight', () {
      test('acepta pesos estrictamente mayores a 0', () {
        expect(validateBodyWeight(12.5), isTrue);
        expect(validateBodyWeight(0.01), isTrue);
      });

      test('rechaza cero y negativos', () {
        expect(validateBodyWeight(0.0), isFalse);
        expect(validateBodyWeight(-5.0), isFalse);
      });
    });

    group('validateCaloricDensity', () {
      test('acepta densidades mayores a 0', () {
        expect(validateCaloricDensity(4000.0), isTrue);
      });

      test('rechaza cero y negativos', () {
        expect(validateCaloricDensity(0.0), isFalse);
        expect(validateCaloricDensity(-4000.0), isFalse);
      });
    });

    group('validateMealsPerDay', () {
      test('acepta comidas entre 1 y 6', () {
        for (final meals in [1, 2, 3, 4, 5, 6]) {
          expect(validateMealsPerDay(meals), isTrue, reason: 'meals=$meals');
        }
      });

      test('rechaza 0, negativos y mayores a 6', () {
        for (final meals in [0, -1, 7, 10]) {
          expect(validateMealsPerDay(meals), isFalse, reason: 'meals=$meals');
        }
      });
    });

    group('validateBcs', () {
      test('acepta BCS entre 1 y 9', () {
        for (final bcs in [1, 5, 9]) {
          expect(validateBcs(bcs), isTrue, reason: 'bcs=$bcs');
        }
      });

      test('rechaza 0, negativos y mayores a 9', () {
        for (final bcs in [0, -1, 10, 99]) {
          expect(validateBcs(bcs), isFalse, reason: 'bcs=$bcs');
        }
      });
    });

    group('validateMcs', () {
      test('acepta valores permitidos y sus sinónimos', () {
        for (final mcs in [
          'normal',
          'leve',
          'mild',
          'moderada',
          'moderate',
          'marcada',
          'marked',
        ]) {
          expect(validateMcs(mcs), isTrue, reason: 'mcs=$mcs');
        }
      });

      test('rechaza valores inválidos', () {
        for (final mcs in ['', 'severo', 'excelente', 'none']) {
          expect(validateMcs(mcs), isFalse, reason: 'mcs=$mcs');
        }
      });
    });

    group('validateActivityLevel', () {
      test('acepta valores permitidos y sus sinónimos', () {
        for (final activity in ['bajo', 'low', 'medio', 'medium', 'alto', 'high']) {
          expect(validateActivityLevel(activity), isTrue,
              reason: 'activity=$activity');
        }
      });

      test('rechaza valores inválidos', () {
        for (final activity in ['', 'extremo', 'sedentario', 'none']) {
          expect(validateActivityLevel(activity), isFalse,
              reason: 'activity=$activity');
        }
      });
    });

    group('validateReproductiveStatus', () {
      test('acepta los valores permitidos', () {
        for (final status in ['entero', 'castrado', 'esterilizado']) {
          expect(validateReproductiveStatus(status), isTrue,
              reason: 'status=$status');
        }
      });

      test('rechaza valores inválidos', () {
        for (final status in ['', 'preñada', 'lactante', 'none']) {
          expect(validateReproductiveStatus(status), isFalse,
              reason: 'status=$status');
        }
      });
    });

    group('validateLifeStage', () {
      test('acepta los valores permitidos', () {
        expect(validateLifeStage('crecimiento'), isTrue);
        expect(validateLifeStage('adulto'), isTrue);
      });

      test('rechaza valores inválidos', () {
        for (final stage in ['', 'senior', 'juvenil', 'none']) {
          expect(validateLifeStage(stage), isFalse, reason: 'stage=$stage');
        }
      });
    });

    group('validateSnacksKcal', () {
      test('acepta cero y positivos', () {
        expect(validateSnacksKcal(0.0), isTrue);
        expect(validateSnacksKcal(45.5), isTrue);
      });

      test('rechaza negativos', () {
        expect(validateSnacksKcal(-1.0), isFalse);
        expect(validateSnacksKcal(-0.5), isFalse);
      });
    });
  });

  group('Normalización a forma canónica', () {
    group('normalizeSpecies', () {
      test('mapea sinónimos a la forma canónica', () {
        const cases = <String, String>{
          'canino': 'canino',
          'perro': 'canino',
          'dog': 'canino',
          'felino': 'felino',
          'gato': 'felino',
          'cat': 'felino',
        };
        cases.forEach((raw, expected) {
          expect(normalizeSpecies(raw), expected, reason: 'species=$raw');
        });
      });

      test('normaliza mayúsculas y espacios', () {
        expect(normalizeSpecies('CANINO'), 'canino');
        expect(normalizeSpecies(' Perro '), 'canino');
      });

      test('rechaza especies inválidas con mensaje descriptivo', () {
        for (final species in ['', 'ave', 'conejo', 'none']) {
          expect(
            () => normalizeSpecies(species),
            throwsA(isA<NutritionValidationException>()
                .having((e) => e.message, 'message', contains('Especie inválida'))),
            reason: 'species=$species',
          );
        }
      });
    });

    group('normalizeMcs', () {
      test('mapea sinónimos a la forma canónica', () {
        const cases = <String, String>{
          'normal': 'normal',
          'leve': 'mild',
          'mild': 'mild',
          'moderada': 'moderate',
          'moderate': 'moderate',
          'marcada': 'marked',
          'marked': 'marked',
        };
        cases.forEach((raw, expected) {
          expect(normalizeMcs(raw), expected, reason: 'mcs=$raw');
        });
      });

      test('rechaza MCS inválidos con mensaje descriptivo', () {
        expect(
          () => normalizeMcs('severo'),
          throwsA(isA<NutritionValidationException>()
              .having((e) => e.message, 'message', contains('MCS inválido'))),
        );
      });
    });

    group('normalizeActivityLevel', () {
      test('mapea sinónimos a la forma canónica', () {
        const cases = <String, String>{
          'bajo': 'low',
          'low': 'low',
          'medio': 'medium',
          'medium': 'medium',
          'alto': 'high',
          'high': 'high',
        };
        cases.forEach((raw, expected) {
          expect(normalizeActivityLevel(raw), expected, reason: 'activity=$raw');
        });
      });

      test('rechaza actividad inválida con mensaje descriptivo', () {
        expect(
          () => normalizeActivityLevel('extremo'),
          throwsA(isA<NutritionValidationException>().having(
              (e) => e.message, 'message', contains('actividad inválido'))),
        );
      });
    });

    group('normalizeReproductiveStatus', () {
      test('normaliza a minúsculas sin modificar el valor canónico', () {
        expect(normalizeReproductiveStatus('Castrado'), 'castrado');
        expect(normalizeReproductiveStatus(' ENTERO '), 'entero');
      });

      test('rechaza valores inválidos', () {
        expect(
          () => normalizeReproductiveStatus('preñada'),
          throwsA(isA<NutritionValidationException>().having(
              (e) => e.message, 'message', contains('reproductivo inválido'))),
        );
      });
    });

    group('normalizeLifeStage', () {
      test('normaliza a minúsculas sin modificar el valor canónico', () {
        expect(normalizeLifeStage('Adulto'), 'adulto');
        expect(normalizeLifeStage(' Crecimiento '), 'crecimiento');
      });

      test('rechaza valores inválidos', () {
        expect(
          () => normalizeLifeStage('senior'),
          throwsA(isA<NutritionValidationException>().having(
              (e) => e.message, 'message', contains('Etapa de vida inválida'))),
        );
      });
    });
  });
}
