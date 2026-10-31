import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Valores exactos de la paleta de la spec 017. Se declaran aquí como HEX
/// literales para que la prueba compruebe el token y no una referencia a sí
/// misma; el único archivo de tokens sigue siendo `app_colors.dart`.
const Map<String, Color> _esquemaClaro = <String, Color>{
  'primary': Color(0xFF2E7D32),
  'onPrimary': Color(0xFFFFFFFF),
  'primaryContainer': Color(0xFFC8E6C9),
  'onPrimaryContainer': Color(0xFF1B5E20),
  'secondary': Color(0xFF2E7D32),
  'onSecondary': Color(0xFFFFFFFF),
  'secondaryContainer': Color(0xFFC8E6C9),
  'onSecondaryContainer': Color(0xFF1B5E20),
  'tertiary': Color(0xFF0277BD),
  'onTertiary': Color(0xFFFFFFFF),
  'tertiaryContainer': Color(0xFFD9ECF7),
  'onTertiaryContainer': Color(0xFF01466F),
  'error': Color(0xFFB3261E),
  'onError': Color(0xFFFFFFFF),
  'errorContainer': Color(0xFFFFDAD6),
  'onErrorContainer': Color(0xFF410002),
  'surface': Color(0xFFFFFFFF),
  'onSurface': Color(0xFF3E2723),
  'onSurfaceVariant': Color(0xFF6B544C),
  'surfaceContainerLowest': Color(0xFFFFFFFF),
  'surfaceContainerLow': Color(0xFFFDF9F5),
  'surfaceContainer': Color(0xFFF5EEE6),
  'surfaceContainerHigh': Color(0xFFEFE6DD),
  'surfaceContainerHighest': Color(0xFFE8DED4),
  'outline': Color(0x993E2723),
  'outlineVariant': Color(0x3D3E2723),
  'inverseSurface': Color(0xFF3E2723),
  'onInverseSurface': Color(0xFFFAF6F0),
  'inversePrimary': Color(0xFF81C784),
  'surfaceTint': Color(0xFF2E7D32),
  'scrim': Color(0xFF000000),
  'shadow': Color(0xFF000000),
};

const Map<String, Color> _esquemaOscuro = <String, Color>{
  'primary': Color(0xFF81C784),
  'onPrimary': Color(0xFF171310),
  'primaryContainer': Color(0xFF2E5B31),
  'onPrimaryContainer': Color(0xFFC8E6C9),
  'secondary': Color(0xFF81C784),
  'onSecondary': Color(0xFF171310),
  'secondaryContainer': Color(0xFF2E5B31),
  'onSecondaryContainer': Color(0xFFC8E6C9),
  'tertiary': Color(0xFF4FC3F7),
  'onTertiary': Color(0xFF171310),
  'tertiaryContainer': Color(0xFF0B3A52),
  'onTertiaryContainer': Color(0xFFBCE4F5),
  'error': Color(0xFFF2B8B5),
  'onError': Color(0xFF601410),
  'errorContainer': Color(0xFF93000A),
  'onErrorContainer': Color(0xFFFFDAD6),
  'surface': Color(0xFF221C18),
  'onSurface': Color(0xFFF2E9DF),
  'onSurfaceVariant': Color(0xFFC9BCB0),
  'surfaceContainerLowest': Color(0xFF100D0B),
  'surfaceContainerLow': Color(0xFF1C1714),
  'surfaceContainer': Color(0xFF221C18),
  'surfaceContainerHigh': Color(0xFF2B2420),
  'surfaceContainerHighest': Color(0xFF352D28),
  'outline': Color(0x99F2E9DF),
  'outlineVariant': Color(0x3DF2E9DF),
  'inverseSurface': Color(0xFFF2E9DF),
  'onInverseSurface': Color(0xFF3E2723),
  'inversePrimary': Color(0xFF2E7D32),
  'surfaceTint': Color(0xFF81C784),
  'scrim': Color(0xFF000000),
  'shadow': Color(0xFF000000),
};

const Color _ctaClaro = Color(0xFFD84315);
const Color _ctaOscuro = Color(0xFFFF8A65);

/// Recorre todas las ranuras del esquema, incluidas las derivadas, para
/// comprobar que ninguna cae en los valores por defecto de Material.
Map<String, Color> _ranuras(ColorScheme esquema) => <String, Color>{
  'primary': esquema.primary,
  'onPrimary': esquema.onPrimary,
  'primaryContainer': esquema.primaryContainer,
  'onPrimaryContainer': esquema.onPrimaryContainer,
  'secondary': esquema.secondary,
  'onSecondary': esquema.onSecondary,
  'secondaryContainer': esquema.secondaryContainer,
  'onSecondaryContainer': esquema.onSecondaryContainer,
  'tertiary': esquema.tertiary,
  'onTertiary': esquema.onTertiary,
  'tertiaryContainer': esquema.tertiaryContainer,
  'onTertiaryContainer': esquema.onTertiaryContainer,
  'error': esquema.error,
  'onError': esquema.onError,
  'errorContainer': esquema.errorContainer,
  'onErrorContainer': esquema.onErrorContainer,
  'surface': esquema.surface,
  'onSurface': esquema.onSurface,
  'onSurfaceVariant': esquema.onSurfaceVariant,
  'surfaceContainerLowest': esquema.surfaceContainerLowest,
  'surfaceContainerLow': esquema.surfaceContainerLow,
  'surfaceContainer': esquema.surfaceContainer,
  'surfaceContainerHigh': esquema.surfaceContainerHigh,
  'surfaceContainerHighest': esquema.surfaceContainerHighest,
  'outline': esquema.outline,
  'outlineVariant': esquema.outlineVariant,
  'inverseSurface': esquema.inverseSurface,
  'onInverseSurface': esquema.onInverseSurface,
  'inversePrimary': esquema.inversePrimary,
  'surfaceTint': esquema.surfaceTint,
  'scrim': esquema.scrim,
  'shadow': esquema.shadow,
};

BorderRadius _radioDe(ShapeBorder? forma, String nombre) {
  expect(forma, isA<RoundedRectangleBorder>(), reason: '$nombre sin forma');
  return (forma! as RoundedRectangleBorder).borderRadius as BorderRadius;
}

BorderRadius _radioDeEstilo(
  WidgetStateProperty<OutlinedBorder?>? propiedad,
  String nombre,
) {
  final forma = propiedad?.resolve(<WidgetState>{});
  return _radioDe(forma, nombre);
}

void main() {
  group('RF-01 y RF-07: tema claro', () {
    final tema = AppTheme.lightTheme;
    final esquema = tema.colorScheme;

    test('expone los tokens exactos de la tabla clara', () {
      expect(esquema.brightness, Brightness.light);
      expect(tema.brightness, Brightness.light);
      expect(_ranuras(esquema), _esquemaClaro);
    });

    test('usa el fondo y la superficie de los tokens', () {
      // Literal independiente de la spec: detecta un token de fondo erróneo.
      expect(tema.scaffoldBackgroundColor, const Color(0xFFFAF6F0));
      expect(tema.scaffoldBackgroundColor, AppColors.lightBackground);
      expect(tema.canvasColor, AppColors.lightSurface);
      expect(tema.colorScheme.surface, AppColors.lightSurface);
    });

    test('repite el verde en secondary y su contenedor', () {
      expect(esquema.secondary, esquema.primary);
      expect(esquema.onSecondary, esquema.onPrimary);
      expect(esquema.secondaryContainer, esquema.primaryContainer);
      expect(esquema.onSecondaryContainer, esquema.onPrimaryContainer);
      expect(esquema.tertiary, AppColors.lightTertiary);
      expect(esquema.surfaceTint, AppColors.lightPrimary);
    });

    test('el borde sale de texto y estructura con su opacidad', () {
      expect(esquema.outline.a, closeTo(0.6, 0.01));
      expect(esquema.outlineVariant.a, closeTo(0.24, 0.01));
      expect(esquema.outline.withValues(alpha: 1), AppColors.lightOnSurface);
      expect(
        esquema.outlineVariant.withValues(alpha: 1),
        AppColors.lightOnSurface,
      );
    });

    test('el CTA no ocupa ninguna ranura del esquema', () {
      for (final entrada in _ranuras(esquema).entries) {
        expect(
          entrada.value,
          isNot(_ctaClaro),
          reason: 'la ranura ${entrada.key} no debe llevar el CTA',
        );
      }
    });

    test('el texto del tema sale de onSurface', () {
      expect(tema.textTheme.bodyMedium?.color, esquema.onSurface);
      expect(tema.textTheme.titleLarge?.color, esquema.onSurface);
    });
  });

  group('RF-02 y RF-07: tema oscuro', () {
    final tema = AppTheme.darkTheme;
    final esquema = tema.colorScheme;

    test('expone los tokens exactos de la tabla oscura', () {
      expect(esquema.brightness, Brightness.dark);
      expect(tema.brightness, Brightness.dark);
      expect(_ranuras(esquema), _esquemaOscuro);
    });

    test('usa el fondo y la superficie de los tokens', () {
      // Literal independiente de la spec: detecta un token de fondo erróneo.
      expect(tema.scaffoldBackgroundColor, const Color(0xFF171310));
      expect(tema.scaffoldBackgroundColor, AppColors.darkBackground);
      expect(tema.canvasColor, AppColors.darkSurface);
      expect(tema.colorScheme.surface, AppColors.darkSurface);
    });

    test('repite el verde en secondary y su contenedor', () {
      expect(esquema.secondary, esquema.primary);
      expect(esquema.onSecondary, esquema.onPrimary);
      expect(esquema.secondaryContainer, esquema.primaryContainer);
      expect(esquema.onSecondaryContainer, esquema.onPrimaryContainer);
      expect(esquema.tertiary, AppColors.darkTertiary);
      expect(esquema.surfaceTint, AppColors.darkPrimary);
    });

    test('el borde sale de texto y estructura con su opacidad', () {
      expect(esquema.outline.a, closeTo(0.6, 0.01));
      expect(esquema.outlineVariant.a, closeTo(0.24, 0.01));
      expect(esquema.outline.withValues(alpha: 1), AppColors.darkOnSurface);
      expect(
        esquema.outlineVariant.withValues(alpha: 1),
        AppColors.darkOnSurface,
      );
    });

    test('el CTA no ocupa ninguna ranura del esquema', () {
      for (final entrada in _ranuras(esquema).entries) {
        expect(
          entrada.value,
          isNot(_ctaOscuro),
          reason: 'la ranura ${entrada.key} no debe llevar el CTA',
        );
      }
    });

    test('el texto del tema sale de onSurface', () {
      expect(tema.textTheme.bodyMedium?.color, esquema.onSurface);
      expect(tema.textTheme.titleLarge?.color, esquema.onSurface);
    });
  });

  group('RF-06: sin los valores del morado por defecto', () {
    const prohibidos = <Color>[
      Color(0xFF6750A4),
      Color(0xFFEADDFF),
      Color(0xFFE8DEF8),
      Color(0xFFFEF7FF),
      Color(0xFF1D1B20),
      Color(0xFF21005D),
    ];

    for (final caso in <String, ThemeData>{
      'claro': AppTheme.lightTheme,
      'oscuro': AppTheme.darkTheme,
    }.entries) {
      test('el esquema ${caso.key} no usa valores por defecto de Material', () {
        for (final entrada in _ranuras(caso.value.colorScheme).entries) {
          expect(
            prohibidos,
            isNot(contains(entrada.value)),
            reason: 'la ranura ${entrada.key} usa un valor heredado',
          );
        }
      });
    }
  });

  group('RF-04: extensión semántica', () {
    test('el CTA, éxito y alerta viven en la extensión con sus contenidos', () {
      final claro = AppTheme.lightTheme.extension<AppSemanticColors>();
      final oscuro = AppTheme.darkTheme.extension<AppSemanticColors>();

      expect(claro, isNotNull);
      expect(oscuro, isNotNull);
      expect(claro!.cta, AppColors.lightCta);
      expect(claro.onCta, AppColors.lightOnCta);
      expect(claro.success, AppColors.lightSuccess);
      expect(claro.onSuccess, AppColors.lightOnSuccess);
      expect(claro.alert, AppColors.lightAlert);
      expect(claro.onAlert, AppColors.lightOnAlert);
      expect(oscuro!.cta, AppColors.darkCta);
      expect(oscuro.onCta, AppColors.darkOnCta);
      expect(oscuro.success, AppColors.darkSuccess);
      expect(oscuro.onSuccess, AppColors.darkOnSuccess);
      expect(oscuro.alert, AppColors.darkAlert);
      expect(oscuro.onAlert, AppColors.darkOnAlert);
    });

    test('copyWith y lerp conservan los seis colores', () {
      final base = AppSemanticColors.light;
      final copia = base.copyWith(cta: const Color(0xFF123456));
      expect(copia.cta, const Color(0xFF123456));
      expect(copia.onCta, base.onCta);

      final mezcla = base.lerp(AppSemanticColors.dark, 0.5);
      expect(mezcla, isA<AppSemanticColors>());
      expect(mezcla.success, isNot(base.success));
    });

    test('expone los HEX de la spec sin depender de los tokens', () {
      // Valores literales de la spec 017: si un token de `app_colors.dart`
      // cambiara por error, esta prueba falla aunque la de arriba siga
      // comparando contra la propia fuente.
      final claro = AppTheme.lightTheme.extension<AppSemanticColors>()!;
      final oscuro = AppTheme.darkTheme.extension<AppSemanticColors>()!;

      expect(claro.cta, const Color(0xFFD84315));
      expect(claro.onCta, const Color(0xFF000000));
      expect(claro.success, const Color(0xFF66BB6A));
      expect(claro.onSuccess, const Color(0xFF3E2723));
      expect(claro.alert, const Color(0xFFFFA726));
      expect(claro.onAlert, const Color(0xFF3E2723));

      expect(oscuro.cta, const Color(0xFFFF8A65));
      expect(oscuro.onCta, const Color(0xFF171310));
      expect(oscuro.success, const Color(0xFFA5D6A7));
      expect(oscuro.onSuccess, const Color(0xFF171310));
      expect(oscuro.alert, const Color(0xFFFFB74D));
      expect(oscuro.onAlert, const Color(0xFF171310));
    });
  });

  group('RF-08: radios de tokens', () {
    test('el radio base es 8 y los derivados son 8 y 12', () {
      expect(AppRadii.base, 8);
      expect(AppRadii.control, 8);
      expect(AppRadii.card, 8);
      expect(AppRadii.chip, 8);
      expect(AppRadii.fab, 8);
      expect(AppRadii.banner, 8);
      expect(AppRadii.dialog, 12);
      expect(AppRadii.sheet, 12);
      expect(AppRadii.menu, 12);
      expect(AppRadii.controlRadius, BorderRadius.circular(8));
      expect(AppRadii.dialogRadius, BorderRadius.circular(12));
    });

    for (final caso in <String, ThemeData>{
      'claro': AppTheme.lightTheme,
      'oscuro': AppTheme.darkTheme,
    }.entries) {
      test('${caso.key}: tarjetas, botones, campos, chip y FAB usan 8', () {
        final tema = caso.value;
        final tarjeta = tema.cardTheme;
        final formaTarjeta = _radioDe(tarjeta.shape, 'tarjeta');
        expect(formaTarjeta, BorderRadius.circular(8));

        expect(
          _radioDeEstilo(tema.filledButtonTheme.style?.shape, 'botón relleno'),
          BorderRadius.circular(8),
        );
        expect(
          _radioDeEstilo(
            tema.outlinedButtonTheme.style?.shape,
            'botón delineado',
          ),
          BorderRadius.circular(8),
        );
        expect(
          _radioDeEstilo(tema.textButtonTheme.style?.shape, 'botón de texto'),
          BorderRadius.circular(8),
        );
        expect(
          _radioDeEstilo(tema.iconButtonTheme.style?.shape, 'botón de icono'),
          BorderRadius.circular(8),
        );

        final campo = tema.inputDecorationTheme.border;
        expect(campo, isA<OutlineInputBorder>());
        expect(
          (campo! as OutlineInputBorder).borderRadius,
          BorderRadius.circular(8),
        );

        final chip = tema.chipTheme.shape;
        expect(_radioDe(chip, 'chip'), BorderRadius.circular(8));
        expect(chip, isNot(isA<StadiumBorder>()));

        final fab = tema.floatingActionButtonTheme;
        expect(_radioDe(fab.shape, 'FAB'), BorderRadius.circular(8));

        expect(
          _radioDe(tema.snackBarTheme.shape, 'aviso'),
          BorderRadius.circular(8),
        );
      });

      test('${caso.key}: diálogos, hojas y menús usan 12', () {
        final tema = caso.value;
        expect(
          _radioDe(tema.dialogTheme.shape, 'diálogo'),
          BorderRadius.circular(12),
        );
        expect(
          _radioDe(tema.bottomSheetTheme.shape, 'hoja'),
          const BorderRadius.vertical(top: Radius.circular(12)),
        );
        expect(
          _radioDe(tema.popupMenuTheme.shape, 'menú'),
          BorderRadius.circular(12),
        );
      });
    }
  });

  group('RF-09: escala de espaciado', () {
    test('declara 4, 8, 12, 16, 20, 24 y 32', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 12);
      expect(AppSpacing.lg, 16);
      expect(AppSpacing.xl, 20);
      expect(AppSpacing.xxl, 24);
      expect(AppSpacing.xxxl, 32);
    });

    test('declara los espaciados semánticos', () {
      expect(AppSpacing.page, 16);
      expect(AppSpacing.pageWide, 24);
      expect(AppSpacing.fieldGap, 16);
      expect(AppSpacing.cardPadding, 16);
      expect(AppSpacing.sectionGap, 24);
    });

    test('el relleno de pantalla pasa a 24 desde 600 puntos', () {
      expect(AppSpacing.pageFor(320), AppSpacing.page);
      expect(AppSpacing.pageFor(599), AppSpacing.page);
      expect(AppSpacing.pageFor(600), AppSpacing.pageWide);
      expect(AppSpacing.pageFor(840), AppSpacing.pageWide);
    });
  });

  group('RF-07 y RF-14: componentes gobernados por el tema', () {
    for (final caso in <String, ThemeData>{
      'claro': AppTheme.lightTheme,
      'oscuro': AppTheme.darkTheme,
    }.entries) {
      final tema = caso.value;
      final esquema = tema.colorScheme;

      test(
        '${caso.key}: tarjetas con superficie, borde outline y elevación 0',
        () {
          final tarjeta = tema.cardTheme;
          expect(tarjeta.color, esquema.surface);
          expect(tarjeta.elevation, 0);
          expect(tarjeta.surfaceTintColor, Colors.transparent);
          final forma = tarjeta.shape as RoundedRectangleBorder;
          final lado = forma.side;
          expect(lado.color, esquema.outline);
          expect(lado.width, 1);
        },
      );

      test('${caso.key}: barras con el principal y su contenido', () {
        expect(tema.appBarTheme.backgroundColor, esquema.primary);
        expect(tema.appBarTheme.foregroundColor, esquema.onPrimary);
        expect(tema.bottomNavigationBarTheme.backgroundColor, esquema.surface);
        expect(
          tema.bottomNavigationBarTheme.selectedItemColor,
          esquema.primary,
        );
        expect(
          tema.bottomNavigationBarTheme.unselectedItemColor,
          esquema.onSurfaceVariant,
        );
      });

      test('${caso.key}: botones con los roles del esquema', () {
        final relleno = tema.filledButtonTheme.style!;
        expect(
          relleno.backgroundColor!.resolve(<WidgetState>{}),
          esquema.primary,
        );
        expect(
          relleno.foregroundColor!.resolve(<WidgetState>{}),
          esquema.onPrimary,
        );

        final delineado = tema.outlinedButtonTheme.style!;
        expect(
          delineado.foregroundColor!.resolve(<WidgetState>{}),
          esquema.primary,
        );
        expect(
          delineado.side!.resolve(<WidgetState>{})!.color,
          esquema.outline,
        );

        final texto = tema.textButtonTheme.style!;
        expect(
          texto.foregroundColor!.resolve(<WidgetState>{}),
          esquema.primary,
        );
      });

      test('${caso.key}: campos con superficie y borde de tokens', () {
        final campo = tema.inputDecorationTheme;
        expect(campo.fillColor, esquema.surface);
        final borde = campo.border! as OutlineInputBorder;
        expect(borde.borderSide.color, esquema.outline);
        expect(borde.borderSide.width, 1);
        expect(campo.focusedBorder!.borderSide.color, esquema.primary);
      });

      test('${caso.key}: diálogos, hojas y menús sobre superficie', () {
        expect(tema.dialogTheme.backgroundColor, esquema.surface);
        expect(tema.dialogTheme.surfaceTintColor, Colors.transparent);
        expect(tema.dialogTheme.elevation, 0);
        expect(tema.bottomSheetTheme.backgroundColor, esquema.surface);
        expect(tema.bottomSheetTheme.surfaceTintColor, Colors.transparent);
        expect(tema.popupMenuTheme.color, esquema.surface);
        expect(tema.popupMenuTheme.surfaceTintColor, Colors.transparent);
      });

      test('${caso.key}: aviso emergente con inversos y contenido', () {
        final aviso = tema.snackBarTheme;
        expect(aviso.backgroundColor, esquema.inverseSurface);
        expect(aviso.contentTextStyle?.color, esquema.onInverseSurface);
      });

      test('${caso.key}: chip, FAB, divisorias, progreso y cursor', () {
        expect(tema.chipTheme.backgroundColor, esquema.surfaceContainerHighest);
        expect(tema.chipTheme.selectedColor, esquema.primaryContainer);
        expect(tema.chipTheme.labelStyle?.color, esquema.onSurface);

        final fab = tema.floatingActionButtonTheme;
        expect(fab.backgroundColor, esquema.primary);
        expect(fab.foregroundColor, esquema.onPrimary);

        expect(tema.dividerTheme.color, esquema.outlineVariant);
        expect(tema.dividerTheme.thickness, 1);

        expect(tema.progressIndicatorTheme.color, esquema.primary);
        expect(
          tema.progressIndicatorTheme.linearTrackColor,
          esquema.surfaceContainerHighest,
        );

        // El cursor se fija en `textSelectionTheme` (ThemeData.cursorColor ya
        // no existe en esta versión de Flutter).
        expect(tema.textSelectionTheme.cursorColor, esquema.primary);
      });

      test('${caso.key}: iconos sobre la superficie', () {
        expect(tema.iconTheme.color, esquema.onSurface);
      });
    }
  });
}
