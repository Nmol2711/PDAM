import 'package:app_movil_pdam/features/dispenser/domain/utils/quick_dispense_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateQuickDispense', () {
    test('acepta un valor dentro del límite y del stock', () {
      final resultado = validateQuickDispense('50', 1200);

      expect(resultado.isValid, true);
      expect(resultado.grams, 50.0);
    });

    test('acepta el límite exacto de 200 g', () {
      final resultado = validateQuickDispense('200', 1200);

      expect(resultado.isValid, true);
      expect(resultado.grams, 200.0);
    });

    test('acepta coma decimal', () {
      final resultado = validateQuickDispense('12,5', 1200);

      expect(resultado.isValid, true);
      expect(resultado.grams, 12.5);
    });

    test('rechaza vacío, texto y valores no finitos', () {
      for (final texto in ['', '   ', 'abc', 'NaN', 'Infinity']) {
        final resultado = validateQuickDispense(texto, 1200);
        expect(resultado.isValid, false, reason: texto);
      }
    });

    test('rechaza cero y negativos', () {
      for (final texto in ['0', '-1', '-0.1']) {
        final resultado = validateQuickDispense(texto, 1200);
        expect(
          resultado.error,
          QuickDispenseValidationError.notPositive,
          reason: texto,
        );
      }
    });

    test('rechaza más de 200 g', () {
      final resultado = validateQuickDispense('200.1', 1200);

      expect(resultado.error, QuickDispenseValidationError.exceedsLimit);
    });

    test('rechaza más que el stock', () {
      final resultado = validateQuickDispense('50', 40);

      expect(resultado.error, QuickDispenseValidationError.exceedsStock);
    });

    test('acepta la cantidad igual al stock', () {
      final resultado = validateQuickDispense('40', 40);

      expect(resultado.isValid, true);
    });

    test('con stock cero rechaza cualquier cantidad', () {
      final resultado = validateQuickDispense('1', 0);

      expect(resultado.error, QuickDispenseValidationError.exceedsStock);
    });
  });
}
