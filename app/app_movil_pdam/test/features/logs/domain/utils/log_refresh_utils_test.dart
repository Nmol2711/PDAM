import 'package:app_movil_pdam/features/logs/domain/utils/log_refresh_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas de la ventana de refresco y del ajuste de página (RF-3, RF-5).
void main() {
  group('puedeRefrescarAutomatico', () {
    final ahora = DateTime.utc(2026, 10, 31, 12);
    const ventana = Duration(seconds: 4);

    test('sin refresco previo se permite', () {
      expect(puedeRefrescarAutomatico(null, ahora, ventana), isTrue);
    });

    test('justo al cumplir la ventana se permite', () {
      final ultimoFin = ahora.subtract(ventana);

      expect(puedeRefrescarAutomatico(ultimoFin, ahora, ventana), isTrue);
    });

    test('dentro de la ventana se ignora', () {
      final ultimoFin = ahora.subtract(const Duration(milliseconds: 3999));

      expect(puedeRefrescarAutomatico(ultimoFin, ahora, ventana), isFalse);
    });

    test('pasada la ventana se permite', () {
      final ultimoFin = ahora.subtract(const Duration(seconds: 10));

      expect(puedeRefrescarAutomatico(ultimoFin, ahora, ventana), isTrue);
    });

    test('respeta una ventana distinta a la de por defecto', () {
      final ultimoFin = ahora.subtract(const Duration(seconds: 2));

      expect(
        puedeRefrescarAutomatico(ultimoFin, ahora, const Duration(seconds: 1)),
        isTrue,
      );
      expect(
        puedeRefrescarAutomatico(ultimoFin, ahora, const Duration(seconds: 3)),
        isFalse,
      );
    });

    test('un reloj que retrocede no permite el refresco', () {
      final ultimoFin = ahora.add(const Duration(seconds: 1));

      expect(puedeRefrescarAutomatico(ultimoFin, ahora, ventana), isFalse);
    });
  });

  group('ajustarPagina', () {
    test('sin registros la página disponible es la primera', () {
      expect(ajustarPagina(1, 0), 1);
      expect(ajustarPagina(4, 0), 1);
    });

    test('una página existente se conserva', () {
      expect(ajustarPagina(1, 1), 1);
      expect(ajustarPagina(2, 3), 2);
      expect(ajustarPagina(3, 3), 3);
    });

    test('una página mayor que el total cae en la última disponible', () {
      expect(ajustarPagina(5, 2), 2);
      expect(ajustarPagina(2, 1), 1);
    });

    test('una página menor que la primera se corrige', () {
      expect(ajustarPagina(0, 3), 1);
      expect(ajustarPagina(-2, 3), 1);
    });

    test('un total de páginas negativo se trata como sin registros', () {
      expect(ajustarPagina(3, -1), 1);
    });
  });
}
