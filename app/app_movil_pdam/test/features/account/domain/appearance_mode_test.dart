import 'package:app_movil_pdam/features/account/domain/entity/appearance_mode.dart';
import 'package:app_movil_pdam/features/account/presentation/utils/appearance_mode_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Catálogo de modos de apariencia (RF-22, RF-23, RF-24).
///
/// El código es el que se persiste en `user_theme_mode` y la etiqueta es la que
/// ve el usuario en la cuarta fila del menú y en el diálogo.
void main() {
  group('Catálogo de modos', () {
    test('cada modo tiene su código y su etiqueta exacta', () {
      expect(AppearanceMode.claro.codigo, 'light');
      expect(AppearanceMode.oscuro.codigo, 'dark');
      expect(AppearanceMode.automatico.codigo, 'system');

      expect(AppearanceMode.claro.etiqueta, 'Claro');
      expect(AppearanceMode.oscuro.etiqueta, 'Oscuro');
      expect(AppearanceMode.automatico.etiqueta, 'Automático');
    });

    test('hay exactamente tres modos', () {
      expect(AppearanceMode.values, hasLength(3));
    });
  });

  group('desdeCodigo (RF-23)', () {
    test('lee el código persistido de cada modo', () {
      expect(AppearanceMode.desdeCodigo('light'), AppearanceMode.claro);
      expect(AppearanceMode.desdeCodigo('dark'), AppearanceMode.oscuro);
      expect(AppearanceMode.desdeCodigo('system'), AppearanceMode.automatico);
    });

    test('sin valor o con un valor desconocido cae en automático', () {
      expect(AppearanceMode.desdeCodigo(null), AppearanceMode.automatico);
      expect(AppearanceMode.desdeCodigo(''), AppearanceMode.automatico);
      expect(AppearanceMode.desdeCodigo('sepia'), AppearanceMode.automatico);
    });
  });

  group('aThemeMode y codigoDeModo (RF-22)', () {
    test('cada modo se traduce al ThemeMode de Flutter', () {
      expect(AppearanceMode.claro.aThemeMode(), ThemeMode.light);
      expect(AppearanceMode.oscuro.aThemeMode(), ThemeMode.dark);
      expect(AppearanceMode.automatico.aThemeMode(), ThemeMode.system);
    });

    test('cada ThemeMode se traduce a su código persistido', () {
      expect(codigoDeModo(ThemeMode.light), 'light');
      expect(codigoDeModo(ThemeMode.dark), 'dark');
      expect(codigoDeModo(ThemeMode.system), 'system');
    });

    test('la ida y vuelta conserva el modo', () {
      for (final modo in AppearanceMode.values) {
        expect(codigoDeModo(modo.aThemeMode()), modo.codigo);
      }
    });
  });
}
