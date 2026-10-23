import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser_food_status.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';

void main() {
  group('DispenserFoodStatus and Pure Functions Tests (Spec 007)', () {
    test('percentageRemaining calculates correctly', () {
      const status = DispenserFoodStatus(currentFoodGrams: 2500.0, maxCapacityGrams: 5000.0);
      expect(status.percentageRemaining, 50.0);
    });

    test('isCritical returns true when food is below 20% (< 1000g)', () {
      const criticalStatus = DispenserFoodStatus(currentFoodGrams: 800.0);
      expect(criticalStatus.isCritical, isTrue);

      const normalStatus = DispenserFoodStatus(currentFoodGrams: 1500.0);
      expect(normalStatus.isCritical, isFalse);
    });

    test('convertAndValidateRefill converts grams correctly and validates limits (RF-1, RF-2)', () {
      expect(convertAndValidateRefill(500, 'g'), 500.0);
      expect(convertAndValidateRefill(2.5, 'kg'), 2500.0);
      expect(convertAndValidateRefill(5.0, 'kg'), 5000.0);

      expect(() => convertAndValidateRefill(0, 'g'), throwsArgumentError);
      expect(() => convertAndValidateRefill(-100, 'g'), throwsArgumentError);
      expect(() => convertAndValidateRefill(5.1, 'kg'), throwsArgumentError);
      expect(() => convertAndValidateRefill(5001.0, 'g'), throwsArgumentError);
    });

    test('calculateRemainingRations calculates rations based on schedules (RF-7)', () {
      final schedules = [
        const Schedule(id: 1, time: '08:00', amount: 100.0, petId: 1),
        const Schedule(id: 2, time: '18:00', amount: 100.0, petId: 1),
      ];

      // 2500g remaining, 200g daily consumption -> average 100g per portion -> 25 rations
      expect(calculateRemainingRations(2500.0, schedules), 25);
      expect(calculateRemainingRations(0.0, schedules), 0);
      expect(calculateRemainingRations(1000.0, []), 0);
    });

    test('applyDispensationDiscount discounts stock correctly without dropping below 0 (RF-4)', () {
      expect(applyDispensationDiscount(1000.0, 150.0), 850.0);
      expect(applyDispensationDiscount(100.0, 150.0), 0.0);
    });
  });
}
