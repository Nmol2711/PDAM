import 'package:app_movil_pdam/features/dashboard/domain/utils/dashboard_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Utilidades puras del panel (RF-10, RNF-2): porcentaje entero acotado y
/// gramos sin decimales, sin depender del reloj ni de la vista.
void main() {
  group('porcentajeCumplimiento', () {
    test('devuelve null cuando lo programado es 0', () {
      expect(porcentajeCumplimiento(0, 0), isNull);
      expect(porcentajeCumplimiento(150, 0), isNull);
    });

    test('devuelve null cuando lo programado es negativo', () {
      expect(porcentajeCumplimiento(100, -10), isNull);
    });

    test('devuelve 0 cuando no se dispensó nada', () {
      expect(porcentajeCumplimiento(0, 200), 0);
    });

    test('devuelve 50 cuando se dispensó la mitad de lo programado', () {
      expect(porcentajeCumplimiento(150, 300), 50);
    });

    test('redondea al entero más cercano', () {
      expect(porcentajeCumplimiento(1, 3), 33);
      expect(porcentajeCumplimiento(2, 3), 67);
      expect(porcentajeCumplimiento(149, 300), 50);
      expect(porcentajeCumplimiento(151, 300), 50);
    });

    test('acota el resultado entre 0 y 100', () {
      expect(porcentajeCumplimiento(600, 300), 100);
      expect(porcentajeCumplimiento(-20, 300), 0);
    });
  });

  group('formatearGramos', () {
    test('no muestra decimales', () {
      expect(formatearGramos(0), '0');
      expect(formatearGramos(150), '150');
      expect(formatearGramos(149.4), '149');
      expect(formatearGramos(149.6), '150');
      expect(formatearGramos(70.5), '71');
    });
  });
}
