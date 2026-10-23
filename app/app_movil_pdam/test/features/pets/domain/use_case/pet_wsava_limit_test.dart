import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/wsava_engine.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/pet/pet_wsava_limit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fecha de referencia fija para que las etapas de vida sean deterministas.
final DateTime _hoy = DateTime(2026, 10, 22);

Pet _pet({
  required TypePest species,
  required DateTime birthDate,
  required double weight,
  bool reproductiveStatus = false,
}) {
  return Pet(
    id: 1,
    name: 'Mascota de prueba',
    species: species,
    birthDate: birthDate,
    weight: weight,
    reproductiveStatus: reproductiveStatus,
  );
}

void main() {
  group('petWsavaDailyLimitGrams - regresión T11 (motor unificado)', () {
    test('canino adulto castrado fija los valores del motor WSAVA', () {
      final pet = _pet(
        species: TypePest.canino,
        birthDate: DateTime(2018, 1, 1),
        weight: 12.5,
        reproductiveStatus: true,
      );

      final grams = petWsavaDailyLimitGrams(pet, today: _hoy)!;

      // RER = 70*12.5^0.75 = 465.35089; MER = RER*1.6; densidad 3850 kcal/kg.
      expect(grams, closeTo(193.39257807072687, 1e-6));
    });

    test('felino adulto entero fija los valores del motor WSAVA', () {
      final pet = _pet(
        species: TypePest.felino,
        birthDate: DateTime(2019, 5, 1),
        weight: 4.0,
      );

      final grams = petWsavaDailyLimitGrams(pet, today: _hoy)!;

      // RER = 197.98990; MER = RER*1.4; densidad 3850 kcal/kg.
      expect(grams, closeTo(71.99632681172119, 1e-6));
    });

    test('cachorro canino usa la etapa de crecimiento del motor', () {
      final pet = _pet(
        species: TypePest.canino,
        birthDate: DateTime(2026, 3, 1),
        weight: 8.0,
      );

      final grams = petWsavaDailyLimitGrams(pet, today: _hoy)!;

      // RER = 332.97799; MER = RER*2.0; densidad 3850 kcal/kg.
      expect(grams, closeTo(172.97558036403214, 1e-6));
    });

    test('coincide exactamente con calculateNutrition del motor unificado', () {
      final pet = _pet(
        species: TypePest.canino,
        birthDate: DateTime(2018, 1, 1),
        weight: 12.5,
        reproductiveStatus: true,
      );

      final reference = petNutritionReference(pet, today: _hoy)!;
      final motor = calculateNutrition(
        species: 'canino',
        bodyWeight: 12.5,
        caloricDensityKcalPerKg: defaultPetFoodKcalPerKg,
        bcs: 5,
        mcs: 'normal',
        activityLevel: 'medium',
        reproductiveStatus: 'castrado',
        lifeStage: 'adulto',
        mealsPerDay: 2,
      );

      expect(reference.dailyRationGrams, motor.dailyRationGrams);
      expect(reference.merKcal, motor.merKcal);
      expect(reference.rerKcal, motor.rerKcal);
    });
  });

  group('mapeo mascota -> motor', () {
    test('solo canino y felino tienen forma canónica para el motor', () {
      expect(speciesForNutrition(TypePest.canino), 'canino');
      expect(speciesForNutrition(TypePest.felino), 'felino');
      expect(speciesForNutrition(TypePest.otros), isNull);
    });

    test('especie otros no produce límite WSAVA (RF-2)', () {
      final pet = _pet(
        species: TypePest.otros,
        birthDate: DateTime(2019, 5, 1),
        weight: 4.0,
      );

      expect(petNutritionReference(pet, today: _hoy), isNull);
      expect(petWsavaDailyLimitGrams(pet, today: _hoy), isNull);
    });

    test('etapa de vida cambia al cumplir 12 meses', () {
      final menor = _pet(
        species: TypePest.canino,
        birthDate: DateTime(2026, 3, 1),
        weight: 8.0,
      );
      final adulto = _pet(
        species: TypePest.canino,
        birthDate: DateTime(2025, 10, 1),
        weight: 8.0,
      );

      expect(lifeStageForPet(menor, today: _hoy), 'crecimiento');
      expect(lifeStageForPet(adulto, today: _hoy), 'adulto');
    });

    test('estatus reproductivo booleano se traduce a castrado/entero', () {
      final castrado = _pet(
        species: TypePest.canino,
        birthDate: DateTime(2018, 1, 1),
        weight: 10.0,
        reproductiveStatus: true,
      );
      final entero = _pet(
        species: TypePest.canino,
        birthDate: DateTime(2018, 1, 1),
        weight: 10.0,
        reproductiveStatus: false,
      );

      // Mismo peso y etapa: castrado (1.6) produce menos gramos que entero (1.8).
      expect(
        petWsavaDailyLimitGrams(castrado, today: _hoy)!,
        lessThan(petWsavaDailyLimitGrams(entero, today: _hoy)!),
      );
    });
  });
}
