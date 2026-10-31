import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pruebas estáticas de RF-03 y RF-06: los tokens de color solo se consumen
/// desde el tema y no queda ningún nombre de la paleta anterior.
void main() {
  final archivosLib = <File>[
    ...Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((archivo) => archivo.path.endsWith('.dart')),
  ];

  test('RF-03: AppColors solo se usa dentro de lib/core/theme', () {
    expect(archivosLib, isNotEmpty, reason: 'no se encontró lib/');
    for (final archivo in archivosLib) {
      final ruta = archivo.path.replaceAll('\\', '/');
      if (ruta.startsWith('lib/core/theme/')) {
        continue;
      }
      final codigo = archivo.readAsStringSync();
      expect(
        codigo.contains('AppColors'),
        isFalse,
        reason:
            '$ruta usa AppColors; debe leer Theme.of(context).colorScheme '
            'o AppSemanticColors.of(context)',
      );
    }
  });

  test('RF-06: no quedan nombres heredados de la paleta anterior', () {
    const heredados = <String>[
      'primaryGreen',
      'accentTurquoise',
      'accentOrange',
      'darkCard',
      'lightCard',
      'purpleBackgroud',
      'primaryPurple',
      'textPrimary',
      'textSecondary',
      'textLight',
      'foodCard',
      'waterCard',
      'snackCard',
    ];

    for (final archivo in archivosLib) {
      final codigo = archivo.readAsStringSync();
      final ruta = archivo.path.replaceAll('\\', '/');
      for (final nombre in heredados) {
        expect(
          RegExp('\\b$nombre\\b').hasMatch(codigo),
          isFalse,
          reason: '$ruta conserva el nombre heredado «$nombre»',
        );
      }
      expect(
        RegExp('purple', caseSensitive: false).hasMatch(codigo),
        isFalse,
        reason: '$ruta menciona la paleta morada anterior',
      );
    }
  });

  test('RF-03: app_colors solo declara tokens light* y dark*', () {
    final tokens = File('lib/core/theme/app_colors.dart').readAsStringSync();
    final declaraciones = RegExp(
      r'static\s+const\s+Color\s+(\w+)',
    ).allMatches(tokens).map((coincidencia) => coincidencia.group(1)!);

    expect(declaraciones, isNotEmpty);
    for (final nombre in declaraciones) {
      expect(
        nombre.startsWith('light') || nombre.startsWith('dark'),
        isTrue,
        reason: 'el nombre «$nombre» no es un token por modo',
      );
    }
  });

  test('RF-05: el CTA solo se pinta desde AppCtaButton', () {
    final patron = RegExp(r'\.(cta|onCta)\b');
    for (final archivo in archivosLib) {
      final ruta = archivo.path.replaceAll('\\', '/');
      if (ruta.startsWith('lib/core/theme/') ||
          ruta.endsWith('core/presentation/widgets/app_cta_button.dart')) {
        continue;
      }
      expect(
        patron.hasMatch(archivo.readAsStringSync()),
        isFalse,
        reason:
            '$ruta pinta el CTA fuera de AppCtaButton; el resto de acciones '
            'usa el principal del tema',
      );
    }
  });
}
