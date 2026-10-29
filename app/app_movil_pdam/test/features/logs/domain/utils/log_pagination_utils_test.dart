import 'package:app_movil_pdam/features/logs/domain/utils/log_pagination_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del cálculo de páginas (RF-32, RF-33).
void main() {
  group('calcularTotalPaginas', () {
    test('sin registros hay una página', () {
      expect(calcularTotalPaginas(0, 50), 1);
    });

    test('un total menor que el tamaño cabe en una página', () {
      expect(calcularTotalPaginas(1, 50), 1);
      expect(calcularTotalPaginas(50, 50), 1);
    });

    test('redondea hacia arriba las páginas incompletas', () {
      expect(calcularTotalPaginas(51, 50), 2);
      expect(calcularTotalPaginas(100, 50), 2);
      expect(calcularTotalPaginas(101, 50), 3);
    });

    test('rechaza un tamaño de página no positivo', () {
      expect(() => calcularTotalPaginas(10, 0), throwsArgumentError);
      expect(() => calcularTotalPaginas(10, -1), throwsArgumentError);
    });

    test('trata un total negativo como vacío', () {
      expect(calcularTotalPaginas(-5, 50), 1);
    });
  });
}
