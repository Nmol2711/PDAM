/// Prueba de contrato compartida backend<->frontend del motor nutricional WSAVA.
///
/// Cubre RF-4 de la Spec 011: el backend y la aplicacion movil deben aplicar
/// exactamente las mismas formulas y tablas. Esta suite y
/// `api/tests/test_nutrition_contract.py` consumen el MISMO fixture
/// `specs/011-refactorizacion-modular-nutricion-y-specs/fixtures/nutrition_contract_cases.json`;
/// si una formula o tabla se altera en un solo lado, al menos una de las dos
/// suites falla.
///
/// El fixture no se copia dentro del paquete: se localiza subiendo desde el
/// directorio de trabajo del proceso de test (la raiz del paquete o la raiz del
/// repositorio) hasta encontrar la carpeta `specs/`. La tolerancia decimal se
/// lee del propio fixture para que ambas suites usen exactamente la misma.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_movil_pdam/features/nutrition/domain/entities/wsava_engine.dart';

const String _fixtureRelativePath =
    'specs/011-refactorizacion-modular-nutricion-y-specs/fixtures/'
    'nutrition_contract_cases.json';

/// Localiza el fixture compartido desde la raiz del repositorio.
///
/// Parte del directorio de trabajo (`app/app_movil_pdam` al ejecutar
/// `flutter test`) y sube por los directorios padre hasta encontrar el archivo.
/// Asi no depende de una profundidad fija ni de un `cwd` concreto.
File _resolveFixture() {
  Directory directory = Directory.current;
  while (true) {
    final candidate = File('${directory.path}/$_fixtureRelativePath');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      fail(
        'No se encontro el fixture compartido "$_fixtureRelativePath" subiendo '
        'desde ${Directory.current.path}.',
      );
    }
    directory = parent;
  }
}

Map<String, dynamic> _loadFixture() {
  final file = _resolveFixture();
  final decoded = jsonDecode(file.readAsStringSync());
  return decoded as Map<String, dynamic>;
}

void main() {
  final fixture = _loadFixture();
  final double tolerance = (fixture['tolerance'] as num).toDouble();
  final List<dynamic> cases = fixture['cases'] as List<dynamic>;

  group('contrato nutricional compartido (RF-4)', () {
    test('el fixture cubre los escenarios requeridos', () {
      bool any(bool Function(Map<String, dynamic> input) predicate) =>
          cases.any((dynamic raw) {
            final input = (raw as Map<String, dynamic>)['input']
                as Map<String, dynamic>;
            return predicate(input);
          });

      bool anyExpected(bool Function(Map<String, dynamic> expected) predicate) =>
          cases.any((dynamic raw) {
            final expected = (raw as Map<String, dynamic>)['expected']
                as Map<String, dynamic>;
            return predicate(expected);
          });

      expect(cases.length, greaterThanOrEqualTo(6));
      expect(any((input) => input['species'] == 'canino'), isTrue);
      expect(any((input) => input['species'] == 'felino'), isTrue);
      expect(any((input) => input['life_stage'] == 'crecimiento'), isTrue);
      expect(any((input) => (input['bcs'] as num) <= 3), isTrue);
      expect(any((input) => (input['bcs'] as num) >= 7), isTrue);
      expect(any((input) => input['mcs'] == 'moderate'), isTrue);
      expect(any((input) => input['mcs'] == 'marked'), isTrue);
      expect(
        anyExpected((expected) => expected['exceeds_snack_limit'] == true),
        isTrue,
      );
      expect(
        anyExpected((expected) => expected['exceeds_snack_limit'] == false),
        isTrue,
      );
      expect(
        cases.any((dynamic raw) =>
            (raw as Map<String, dynamic>)['id'] ==
            'canino_adulto_snacks_en_el_limite'),
        isTrue,
      );
    });

    for (final dynamic raw in cases) {
      final contractCase = raw as Map<String, dynamic>;
      final String caseId = contractCase['id'] as String;
      final input = contractCase['input'] as Map<String, dynamic>;
      final expected = contractCase['expected'] as Map<String, dynamic>;

      test(caseId, () {
        final result = calculateNutrition(
          species: input['species'] as String,
          bodyWeight: (input['body_weight'] as num).toDouble(),
          caloricDensityKcalPerKg:
              (input['caloric_density_kcal_per_kg'] as num).toDouble(),
          bcs: (input['bcs'] as num).toInt(),
          mcs: input['mcs'] as String,
          activityLevel: input['activity_level'] as String,
          reproductiveStatus: input['reproductive_status'] as String,
          lifeStage: input['life_stage'] as String,
          mealsPerDay: (input['meals_per_day'] as num).toInt(),
          snacksKcal: (input['snacks_kcal'] as num).toDouble(),
        );

        expect(result.species, input['species']);
        expect(result.bodyWeight, (input['body_weight'] as num).toDouble());
        expect(result.mealsPerDay, (input['meals_per_day'] as num).toInt());

        expect(result.rerKcal, closeTo(expected['rer_kcal'] as num, tolerance));
        expect(result.merKcal, closeTo(expected['mer_kcal'] as num, tolerance));
        expect(
          result.variabilityMinKcal,
          closeTo(expected['variability_min_kcal'] as num, tolerance),
        );
        expect(
          result.variabilityMaxKcal,
          closeTo(expected['variability_max_kcal'] as num, tolerance),
        );
        expect(
          result.snackLimitKcal,
          closeTo(expected['snack_limit_kcal'] as num, tolerance),
        );
        expect(
          result.exceedsSnackLimit,
          expected['exceeds_snack_limit'] as bool,
        );
        expect(
          result.finalRationKcal,
          closeTo(expected['final_ration_kcal'] as num, tolerance),
        );
        expect(
          result.dailyRationGrams,
          closeTo(expected['daily_ration_grams'] as num, tolerance),
        );
        expect(
          result.rationPerMealGrams,
          closeTo(expected['ration_per_meal_grams'] as num, tolerance),
        );
      });
    }
  });
}
