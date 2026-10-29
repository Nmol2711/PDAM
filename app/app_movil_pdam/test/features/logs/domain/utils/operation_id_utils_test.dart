import 'dart:math';

import 'package:app_movil_pdam/features/logs/domain/utils/operation_id_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del identificador de operación del reabastecimiento (RF-11, RNF-4).
void main() {
  group('generarIdentificadorOperacion', () {
    test('genera 32 caracteres hexadecimales', () {
      final id = generarIdentificadorOperacion();

      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
    });

    test('mil identificadores no se repiten', () {
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        ids.add(generarIdentificadorOperacion());
      }

      expect(ids.length, 1000);
    });

    test('dos identificadores seguidos son distintos', () {
      expect(
        generarIdentificadorOperacion(),
        isNot(generarIdentificadorOperacion()),
      );
    });

    test('acepta un generador inyectado para las pruebas', () {
      final primero = generarIdentificadorOperacion(random: Random(7));
      final segundo = generarIdentificadorOperacion(random: Random(7));

      expect(primero, segundo);
      expect(primero.length, 32);
    });
  });
}
