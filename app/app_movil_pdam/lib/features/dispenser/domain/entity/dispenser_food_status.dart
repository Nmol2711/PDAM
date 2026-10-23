import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';

class DispenserFoodStatus {
  final double currentFoodGrams;
  final double maxCapacityGrams;

  const DispenserFoodStatus({
    required this.currentFoodGrams,
    this.maxCapacityGrams = 5000.0,
  });

  double get percentageRemaining {
    if (maxCapacityGrams <= 0) return 0.0;
    final pct = (currentFoodGrams / maxCapacityGrams) * 100.0;
    if (pct < 0) return 0.0;
    if (pct > 100) return 100.0;
    return pct;
  }

  bool get isCritical => currentFoodGrams < (maxCapacityGrams * 0.20);

  DispenserFoodStatus copyWith({
    double? currentFoodGrams,
    double? maxCapacityGrams,
  }) {
    return DispenserFoodStatus(
      currentFoodGrams: currentFoodGrams ?? this.currentFoodGrams,
      maxCapacityGrams: maxCapacityGrams ?? this.maxCapacityGrams,
    );
  }
}

double convertAndValidateRefill(double amount, String unit) {
  final normalizedUnit = unit.toLowerCase().trim();
  double grams = normalizedUnit == 'kg' ? amount * 1000.0 : amount;
  if (grams <= 0) {
    throw ArgumentError('El reabastecimiento debe ser mayor a cero.');
  }
  if (grams > 5000.0) {
    throw ArgumentError('La capacidad máxima es de 5 kg (5000 g).');
  }
  return grams;
}

int calculateRemainingRations(double currentFoodGrams, List<Schedule> schedules) {
  if (currentFoodGrams <= 0 || schedules.isEmpty) return 0;
  double dailyConsumption = schedules.fold(0.0, (sum, schedule) => sum + schedule.amount);
  if (dailyConsumption <= 0) return 0;
  double averagePortion = dailyConsumption / schedules.length;
  if (averagePortion <= 0) return 0;
  return (currentFoodGrams / averagePortion).floor();
}

double applyDispensationDiscount(double currentStockGrams, double dispensedGrams) {
  double newStock = currentStockGrams - dispensedGrams;
  return newStock < 0 ? 0.0 : newStock;
}
