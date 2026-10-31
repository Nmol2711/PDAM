import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RF-03: la presentación de dispositivos no conserva literales de color ni
/// radios; el resto de valores sale de los tokens del tema.
void main() {
  test(
    'la presentación de dispositivos no usa literales de color ni radios',
    () {
      final archivos = <File>[
        ...Directory('lib/features/dispenser/presentation')
            .listSync(recursive: true)
            .whereType<File>()
            .where((archivo) => archivo.path.endsWith('.dart')),
      ];
      expect(archivos, isNotEmpty);

      for (final archivo in archivos) {
        final codigo = archivo.readAsStringSync();
        expect(
          RegExp(r'\bColors\.(?!transparent)').hasMatch(codigo),
          isFalse,
          reason: '${archivo.path} usa Colors.*',
        );
        expect(
          RegExp(r'Color\(0x').hasMatch(codigo),
          isFalse,
          reason: '${archivo.path} declara un HEX literal',
        );
        expect(
          RegExp(r'BorderRadius\.circular\(\s*\d').hasMatch(codigo),
          isFalse,
          reason: '${archivo.path} declara un radio literal',
        );
        expect(
          RegExp(r'Radius\.circular\(\s*\d').hasMatch(codigo),
          isFalse,
          reason: '${archivo.path} declara un radio literal',
        );
      }
    },
  );
}
