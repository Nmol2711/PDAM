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

/// El reabastecimiento no cabe en el depósito: la cantidad es inválida o la
/// suma con el stock actual supera la capacidad (RF-8, RF-13). El mensaje es el
/// único copy que la interfaz muestra para cualquier rechazo de reabastecimiento.
class RefillLimitException implements Exception {
  static const String message = 'El reabastecimiento supera el límite de 5 kg';

  const RefillLimitException();

  @override
  String toString() => message;
}

double convertAndValidateRefill(double amount, String unit) {
  final normalizedUnit = unit.toLowerCase().trim();
  double grams = normalizedUnit == 'kg' ? amount * 1000.0 : amount;
  if (grams <= 0 || grams > 5000.0) {
    throw const RefillLimitException();
  }
  return grams;
}

/// Suma el alimento reabastecido al stock existente sin superar la capacidad
/// del depósito (RF-7). Si la suma excede el máximo, lanza [RefillLimitException]
/// en lugar de recortar la cantidad en silencio (RF-8).
double applyRefill(
  double currentFoodGrams,
  double addedGrams, {
  double maxCapacityGrams = 5000.0,
}) {
  if (addedGrams <= 0) {
    throw const RefillLimitException();
  }
  final total = currentFoodGrams + addedGrams;
  if (total > maxCapacityGrams) {
    throw const RefillLimitException();
  }
  return total;
}

/// Formatea gramos con separador de miles: `1500` -> `1.500 g`.
String formatGrams(double grams) => '${_withThousandsSeparator(grams.round())} g';

/// Formatea kilogramos con coma decimal y sin ceros sobrantes:
/// `1500` -> `1,5 kg`, `5000` -> `5 kg`, `850` -> `0,85 kg`.
String formatKilograms(double grams) {
  final kilograms = grams / 1000.0;
  final decimals = kilograms < 1 ? 2 : 1;
  var text = kilograms.toStringAsFixed(decimals);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return '${text.replaceAll('.', ',')} kg';
}

/// Etiqueta completa de la barra de progreso, con ambas unidades y porcentaje.
String formatFoodProgressLabel(double currentFoodGrams, double maxCapacityGrams) {
  final status = DispenserFoodStatus(
    currentFoodGrams: currentFoodGrams,
    maxCapacityGrams: maxCapacityGrams,
  );
  final percentage = status.percentageRemaining.toStringAsFixed(0);
  return '${formatKilograms(currentFoodGrams)} (${formatGrams(currentFoodGrams)}) '
      'de ${formatKilograms(maxCapacityGrams)} · $percentage%';
}

String _withThousandsSeparator(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(digits[index]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
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
