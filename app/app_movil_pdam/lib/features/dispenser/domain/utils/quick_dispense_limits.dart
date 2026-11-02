/// Límite y validación local de la dispensación rápida (spec 020).
///
/// El servidor sigue siendo la autoridad: esta validación solo da respuesta
/// inmediata en la hoja y evita enviar cantidades evidentemente inválidas.
library;

const double maxQuickDispenseGrams = 200.0;

enum QuickDispenseValidationError {
  empty,
  notNumeric,
  notPositive,
  exceedsLimit,
  exceedsStock,
}

class QuickDispenseValidation {
  final double? grams;
  final QuickDispenseValidationError? error;

  const QuickDispenseValidation._({this.grams, this.error});

  const QuickDispenseValidation.valid(double grams)
    : this._(grams: grams);

  const QuickDispenseValidation.invalid(QuickDispenseValidationError error)
    : this._(error: error);

  bool get isValid => error == null;
}

/// Valida el texto de la hoja contra el límite de 200 g y el stock disponible.
QuickDispenseValidation validateQuickDispense(String raw, double stock) {
  final texto = raw.trim().replaceAll(',', '.');
  if (texto.isEmpty) {
    return const QuickDispenseValidation.invalid(
      QuickDispenseValidationError.empty,
    );
  }

  final gramos = double.tryParse(texto);
  if (gramos == null || !gramos.isFinite) {
    return const QuickDispenseValidation.invalid(
      QuickDispenseValidationError.notNumeric,
    );
  }

  if (gramos <= 0) {
    return const QuickDispenseValidation.invalid(
      QuickDispenseValidationError.notPositive,
    );
  }

  if (gramos > maxQuickDispenseGrams) {
    return const QuickDispenseValidation.invalid(
      QuickDispenseValidationError.exceedsLimit,
    );
  }

  if (gramos > stock) {
    return const QuickDispenseValidation.invalid(
      QuickDispenseValidationError.exceedsStock,
    );
  }

  return QuickDispenseValidation.valid(gramos);
}
