import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Quita comentarios para no confundir documentación con código.
String _sinComentarios(String codigo) {
  final sinBloques = codigo.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return sinBloques
      .split('\n')
      .map((linea) {
        final indice = linea.indexOf('//');
        return indice >= 0 ? linea.substring(0, indice) : linea;
      })
      .join('\n');
}

/// RF-03 y RF-06: ningún archivo fuera del de tokens declara colores
/// literales ni conserva nombres de la paleta anterior.
void main() {
  test('solo app_colors.dart contiene HEX y no quedan nombres heredados', () {
    final archivos = <File>[
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((archivo) => archivo.path.endsWith('.dart')),
    ];
    expect(archivos, isNotEmpty);

    const heredados = <String>[
      'purple',
      'primarypurple',
      'purplebackgroud',
      'primarygreen',
      'accentturquoise',
      'accentorange',
      'textprimary',
      'textsecondary',
      'textlight',
      'foodcard',
      'watercard',
      'snackcard',
      'lightcard',
      'darkcard',
    ];

    for (final archivo in archivos) {
      final ruta = archivo.path.replaceAll('\\', '/');
      if (ruta == 'lib/core/theme/app_colors.dart') {
        continue;
      }
      final codigo = _sinComentarios(archivo.readAsStringSync());

      expect(
        codigo.toLowerCase().contains('color(0x'),
        isFalse,
        reason: '$ruta declara un color HEX literal (0x/0X)',
      );
      expect(
        RegExp(
          r'Color\.(?:fromARGB|fromRGBO)',
          caseSensitive: false,
        ).hasMatch(codigo),
        isFalse,
        reason: '$ruta declara un color con canales literales',
      );
      expect(
        RegExp(r'(?<![A-Za-z0-9_])Colors\.(?!transparent\b)').hasMatch(codigo),
        isFalse,
        reason: '$ruta usa Colors.* fuera de Colors.transparent',
      );

      final minusculas = codigo.toLowerCase();
      for (final nombre in heredados) {
        expect(
          minusculas.contains(nombre),
          isFalse,
          reason: '$ruta conserva el nombre heredado «$nombre»',
        );
      }
    }
  });
}
