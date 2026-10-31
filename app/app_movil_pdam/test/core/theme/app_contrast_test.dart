import 'dart:math' as math;

import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Luminancia relativa WCAG 2.1 sobre los canales sRGB en 0..1.
double _luminancia(Color color) {
  double canal(double valor) => valor <= 0.03928
      ? valor / 12.92
      : math.pow((valor + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * canal(color.r) +
      0.7152 * canal(color.g) +
      0.0722 * canal(color.b);
}

/// Cociente de contraste WCAG entre dos colores opacos.
double _contraste(Color fondo, Color texto) {
  final l1 = _luminancia(fondo);
  final l2 = _luminancia(texto);
  final alto = math.max(l1, l2);
  final bajo = math.min(l1, l2);
  return (alto + 0.05) / (bajo + 0.05);
}

/// Compone un color con opacidad sobre un fondo opaco para medir el contraste
/// real del borde, tal como se percibe en pantalla.
Color _compuesto(Color color, Color fondo) {
  final alfa = color.a;
  int canal(double frente, double atras) =>
      ((frente * alfa + atras * (1 - alfa)) * 255).round().clamp(0, 255);
  return Color.fromARGB(
    255,
    canal(color.r, fondo.r),
    canal(color.g, fondo.g),
    canal(color.b, fondo.b),
  );
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

void _verificar(String modo, List<List<Object>> filas) {
  for (final fila in filas) {
    final etiqueta = fila[0] as String;
    final color = fila[1] as Color;
    final contra = fila[2] as Color;
    final minimo = fila[3] as double;
    final ratio = _contraste(contra, color);
    // Evidencia en la salida de test: valor medido y mínimo exigido.
    // ignore: avoid_print
    print(
      '$modo | $etiqueta | ${_hex(color)} sobre ${_hex(contra)} '
      '= ${ratio.toStringAsFixed(2)}:1 (mínimo ${minimo.toStringAsFixed(1)}:1)',
    );
    expect(
      ratio,
      greaterThanOrEqualTo(minimo),
      reason: '$modo: $etiqueta no alcanza el mínimo de $minimo:1',
    );
  }
}

void main() {
  group('RNF-03: contraste WCAG del modo claro', () {
    test('contenidos sobre rellenos y textos de apoyo', () {
      _verificar('Claro', <List<Object>>[
        <Object>[
          'Sobre principal sobre principal',
          AppColors.lightOnPrimary,
          AppColors.lightPrimary,
          4.5,
        ],
        <Object>[
          'Sobre contenedor principal',
          AppColors.lightOnPrimaryContainer,
          AppColors.lightPrimaryContainer,
          4.5,
        ],
        <Object>[
          'Sobre CTA sobre CTA',
          AppColors.lightOnCta,
          AppColors.lightCta,
          4.5,
        ],
        <Object>[
          'Texto secundario sobre fondo',
          AppColors.lightOnSurfaceVariant,
          AppColors.lightBackground,
          4.5,
        ],
        <Object>[
          'Texto principal sobre fondo',
          AppColors.lightOnSurface,
          AppColors.lightBackground,
          4.5,
        ],
        <Object>[
          'Texto principal sobre superficie',
          AppColors.lightOnSurface,
          AppColors.lightSurface,
          4.5,
        ],
        <Object>[
          'Texto secundario sobre superficie',
          AppColors.lightOnSurfaceVariant,
          AppColors.lightSurface,
          4.5,
        ],
        <Object>[
          'Acento como enlace sobre blanco',
          AppColors.lightTertiary,
          AppColors.lightSurface,
          4.5,
        ],
        <Object>[
          'Sobre acento sobre acento',
          AppColors.lightOnTertiary,
          AppColors.lightTertiary,
          4.5,
        ],
        <Object>[
          'Sobre contenedor de acento',
          AppColors.lightOnTertiaryContainer,
          AppColors.lightTertiaryContainer,
          4.5,
        ],
        <Object>[
          'Sobre éxito sobre éxito',
          AppColors.lightOnSuccess,
          AppColors.lightSuccess,
          4.5,
        ],
        <Object>[
          'Sobre alerta sobre alerta',
          AppColors.lightOnAlert,
          AppColors.lightAlert,
          4.5,
        ],
        <Object>[
          'Sobre error sobre error',
          AppColors.lightOnError,
          AppColors.lightError,
          4.5,
        ],
        <Object>[
          'Sobre contenedor de error',
          AppColors.lightOnErrorContainer,
          AppColors.lightErrorContainer,
          4.5,
        ],
        <Object>[
          'Principal como enlace sobre el fondo',
          AppColors.lightPrimary,
          AppColors.lightBackground,
          4.5,
        ],
      ]);
    });

    test('elementos gráficos y bordes del modo claro', () {
      _verificar('Claro', <List<Object>>[
        <Object>[
          'Acento gráfico sobre fondo',
          AppColors.lightTertiary,
          AppColors.lightBackground,
          3.0,
        ],
        <Object>[
          'Principal gráfico sobre superficie',
          AppColors.lightPrimary,
          AppColors.lightSurface,
          3.0,
        ],
        <Object>[
          'Error gráfico sobre fondo',
          AppColors.lightError,
          AppColors.lightBackground,
          3.0,
        ],
        <Object>[
          'Borde compuesto sobre fondo',
          _compuesto(AppColors.lightOutline, AppColors.lightBackground),
          AppColors.lightBackground,
          3.0,
        ],
        <Object>[
          'Borde compuesto sobre superficie',
          _compuesto(AppColors.lightOutline, AppColors.lightSurface),
          AppColors.lightSurface,
          3.0,
        ],
      ]);
    });

    test('éxito y alerta no alcanzan para texto en modo claro', () {
      // RF-04: en claro son rellenos; el contraste como texto es insuficiente
      // y por eso ninguna pantalla debe usarlos como color de letra.
      expect(
        _contraste(AppColors.lightBackground, AppColors.lightSuccess),
        lessThan(4.5),
      );
      expect(
        _contraste(AppColors.lightBackground, AppColors.lightAlert),
        lessThan(4.5),
      );
    });
  });

  group('RNF-03: contraste WCAG del modo oscuro', () {
    test('contenidos sobre rellenos y textos de apoyo', () {
      _verificar('Oscuro', <List<Object>>[
        <Object>[
          'Sobre principal sobre principal',
          AppColors.darkOnPrimary,
          AppColors.darkPrimary,
          4.5,
        ],
        <Object>[
          'Sobre contenedor principal',
          AppColors.darkOnPrimaryContainer,
          AppColors.darkPrimaryContainer,
          4.5,
        ],
        <Object>[
          'Sobre CTA sobre CTA',
          AppColors.darkOnCta,
          AppColors.darkCta,
          4.5,
        ],
        <Object>[
          'Texto principal sobre superficie',
          AppColors.darkOnSurface,
          AppColors.darkSurface,
          4.5,
        ],
        <Object>[
          'Texto secundario sobre superficie',
          AppColors.darkOnSurfaceVariant,
          AppColors.darkSurface,
          4.5,
        ],
        <Object>[
          'Acento como texto sobre el fondo',
          AppColors.darkTertiary,
          AppColors.darkBackground,
          4.5,
        ],
        <Object>[
          'Sobre acento sobre acento',
          AppColors.darkOnTertiary,
          AppColors.darkTertiary,
          4.5,
        ],
        <Object>[
          'Sobre contenedor de acento',
          AppColors.darkOnTertiaryContainer,
          AppColors.darkTertiaryContainer,
          4.5,
        ],
        <Object>[
          'Sobre éxito sobre éxito',
          AppColors.darkOnSuccess,
          AppColors.darkSuccess,
          4.5,
        ],
        <Object>[
          'Sobre alerta sobre alerta',
          AppColors.darkOnAlert,
          AppColors.darkAlert,
          4.5,
        ],
        <Object>[
          'Sobre error sobre error',
          AppColors.darkOnError,
          AppColors.darkError,
          4.5,
        ],
        <Object>[
          'Sobre contenedor de error',
          AppColors.darkOnErrorContainer,
          AppColors.darkErrorContainer,
          4.5,
        ],
        <Object>[
          'Éxito como texto sobre el fondo',
          AppColors.darkSuccess,
          AppColors.darkBackground,
          4.5,
        ],
        <Object>[
          'Alerta como texto sobre el fondo',
          AppColors.darkAlert,
          AppColors.darkBackground,
          4.5,
        ],
      ]);
    });

    test('elementos gráficos y bordes del modo oscuro', () {
      _verificar('Oscuro', <List<Object>>[
        <Object>[
          'Acento gráfico sobre superficie',
          AppColors.darkTertiary,
          AppColors.darkSurface,
          3.0,
        ],
        <Object>[
          'Principal gráfico sobre fondo',
          AppColors.darkPrimary,
          AppColors.darkBackground,
          3.0,
        ],
        <Object>[
          'Error gráfico sobre fondo',
          AppColors.darkError,
          AppColors.darkBackground,
          3.0,
        ],
        <Object>[
          'Borde compuesto sobre superficie',
          _compuesto(AppColors.darkOutline, AppColors.darkSurface),
          AppColors.darkSurface,
          3.0,
        ],
        <Object>[
          'Borde compuesto sobre fondo',
          _compuesto(AppColors.darkOutline, AppColors.darkBackground),
          AppColors.darkBackground,
          3.0,
        ],
      ]);
    });
  });
}
