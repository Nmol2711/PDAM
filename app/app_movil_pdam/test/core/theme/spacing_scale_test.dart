import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Escala de espaciado de la spec 017: 4, 8, 12, 16, 20, 24 y 32.
final Set<double> _escala = <double>{
  0.0,
  4.0,
  8.0,
  12.0,
  16.0,
  20.0,
  24.0,
  32.0,
};

/// Excepciones de la spec que sí son detectables: mínimo táctil de 48 y trazo
/// de 1 punto.
final Set<double> _accesibilidad = <double>{1.0, 48.0};

/// Dimensiones fijas realmente usadas como contenedores con `child` (nunca
/// como huecos). Cualquier otro valor fuera de la escala falla.
final Map<double, String> _dimensionesFijas = <double, String>{
  18.0: 'spinner compacto de las acciones de diálogo',
  180.0: 'alto de la gráfica semanal',
  220.0: 'alto de la foto del detalle de mascota',
};

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

double? _numero(String texto) {
  final valor = double.tryParse(texto);
  return valor;
}

Iterable<RegExpMatch> _coincidencias(String codigo, String patron) =>
    RegExp(patron, dotAll: true).allMatches(codigo);

/// Comprueba los números de un bloque de `EdgeInsets`.
void _validarEdgeInsets(
  String ruta,
  String codigo,
  String fragmento,
  String tipo,
) {
  for (final coincidencia in RegExp(
    r'\b(?:horizontal|vertical|left|right|top|bottom):\s*([0-9]+(?:\.[0-9]+)?)',
  ).allMatches(fragmento)) {
    final valor = _numero(coincidencia.group(1)!)!;
    expect(
      _escala.contains(valor) || _accesibilidad.contains(valor),
      isTrue,
      reason:
          '$ruta: EdgeInsets.$tipo usa $valor fuera de la escala y de las excepciones',
    );
  }
}

void main() {
  test('EdgeInsets, SizedBox y spacing usan la escala de tokens', () {
    final archivos = <File>[
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((archivo) => archivo.path.endsWith('.dart')),
    ];
    expect(archivos, isNotEmpty);

    for (final archivo in archivos) {
      final ruta = archivo.path.replaceAll('\\', '/');
      if (ruta == 'lib/core/theme/app_colors.dart') {
        continue;
      }
      final codigo = _sinComentarios(archivo.readAsStringSync());

      for (final coincidencia in _coincidencias(
        codigo,
        r'EdgeInsets\.all\(\s*([0-9]+(?:\.[0-9]+)?)',
      )) {
        final valor = _numero(coincidencia.group(1)!)!;
        expect(
          _escala.contains(valor) || _accesibilidad.contains(valor),
          isTrue,
          reason: '$ruta: EdgeInsets.all($valor) fuera de la escala',
        );
      }

      for (final tipo in <String>['symmetric', 'only']) {
        for (final coincidencia in _coincidencias(
          codigo,
          'EdgeInsets\\.$tipo\\(([^)]*)\\)',
        )) {
          _validarEdgeInsets(ruta, codigo, coincidencia.group(1)!, tipo);
        }
      }

      for (final coincidencia in _coincidencias(
        codigo,
        r'EdgeInsets\.fromLTRB\(([^)]*)\)',
      )) {
        for (final numero in RegExp(
          r'\b[0-9]+(?:\.[0-9]+)?',
        ).allMatches(coincidencia.group(1)!)) {
          final valor = _numero(numero.group(0)!)!;
          expect(
            _escala.contains(valor) || _accesibilidad.contains(valor),
            isTrue,
            reason: '$ruta: EdgeInsets.fromLTRB usa $valor fuera de la escala',
          );
        }
      }

      for (final coincidencia in _coincidencias(
        codigo,
        r'SizedBox\(([^)]*)\)',
      )) {
        final bloque = coincidencia.group(1)!;
        final tieneChild = RegExp(r'\bchild:').hasMatch(bloque);
        for (final medida in RegExp(
          r'(?:width|height):\s*([0-9]+(?:\.[0-9]+)?)',
        ).allMatches(bloque)) {
          final valor = _numero(medida.group(1)!)!;
          final esDimensionFija =
              tieneChild && _dimensionesFijas.containsKey(valor);
          expect(
            _escala.contains(valor) || esDimensionFija,
            isTrue,
            reason:
                '$ruta: SizedBox con $valor fuera de la escala. Solo se admite '
                'como dimensión fija con child: y una justificación documentada',
          );
        }
      }

      for (final coincidencia in _coincidencias(
        codigo,
        r'\b(?:spacing|runSpacing):\s*([0-9]+(?:\.[0-9]+)?)',
      )) {
        final valor = _numero(coincidencia.group(1)!)!;
        expect(
          _escala.contains(valor),
          isTrue,
          reason: '$ruta: spacing/runSpacing $valor fuera de la escala',
        );
      }
    }
  });
}
