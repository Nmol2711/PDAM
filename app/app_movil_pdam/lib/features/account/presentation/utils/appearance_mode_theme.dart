import 'package:app_movil_pdam/features/account/domain/entity/appearance_mode.dart';
import 'package:flutter/material.dart';

/// Traducción entre el catálogo de modos del dominio y el `ThemeMode` de
/// Flutter (RF-22, RF-23, RF-24).
///
/// Vive en presentación porque `ThemeMode` es del framework y el dominio debe
/// quedar libre de Flutter (RNF-04).
extension AppearanceModeTheme on AppearanceMode {
  /// Modo de tema que aplica `MaterialApp` para este modo de apariencia.
  ThemeMode aThemeMode() {
    switch (this) {
      case AppearanceMode.claro:
        return ThemeMode.light;
      case AppearanceMode.oscuro:
        return ThemeMode.dark;
      case AppearanceMode.automatico:
        return ThemeMode.system;
    }
  }
}

/// Código persistido de un `ThemeMode`; es el inverso de
/// [AppearanceModeTheme.aThemeMode].
String codigoDeModo(ThemeMode modo) {
  switch (modo) {
    case ThemeMode.light:
      return AppearanceMode.claro.codigo;
    case ThemeMode.dark:
      return AppearanceMode.oscuro.codigo;
    case ThemeMode.system:
      return AppearanceMode.automatico.codigo;
  }
}
