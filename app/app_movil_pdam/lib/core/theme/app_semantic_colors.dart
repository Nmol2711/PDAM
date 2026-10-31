import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Colores semánticos que no ocupan ranura del `ColorScheme` (spec 017).
///
/// El CTA vive aquí porque solo debe pintar la acción de creación o compra:
/// si ocupara `secondary` se propagaría al botón flotante, los chips y la
/// navegación. El éxito y la alerta se usan como relleno con su contenido.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.cta,
    required this.onCta,
    required this.success,
    required this.onSuccess,
    required this.alert,
    required this.onAlert,
  });

  final Color cta;
  final Color onCta;
  final Color success;
  final Color onSuccess;
  final Color alert;
  final Color onAlert;

  static const AppSemanticColors light = AppSemanticColors(
    cta: AppColors.lightCta,
    onCta: AppColors.lightOnCta,
    success: AppColors.lightSuccess,
    onSuccess: AppColors.lightOnSuccess,
    alert: AppColors.lightAlert,
    onAlert: AppColors.lightOnAlert,
  );

  static const AppSemanticColors dark = AppSemanticColors(
    cta: AppColors.darkCta,
    onCta: AppColors.darkOnCta,
    success: AppColors.darkSuccess,
    onSuccess: AppColors.darkOnSuccess,
    alert: AppColors.darkAlert,
    onAlert: AppColors.darkOnAlert,
  );

  /// Extensión del tema activo; si falta, usa los valores claros para no
  /// romper pruebas aisladas de widgets.
  static AppSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<AppSemanticColors>() ?? light;

  @override
  AppSemanticColors copyWith({
    Color? cta,
    Color? onCta,
    Color? success,
    Color? onSuccess,
    Color? alert,
    Color? onAlert,
  }) {
    return AppSemanticColors(
      cta: cta ?? this.cta,
      onCta: onCta ?? this.onCta,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      alert: alert ?? this.alert,
      onAlert: onAlert ?? this.onAlert,
    );
  }

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) {
      return this;
    }
    return AppSemanticColors(
      cta: Color.lerp(cta, other.cta, t)!,
      onCta: Color.lerp(onCta, other.onCta, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      onAlert: Color.lerp(onAlert, other.onAlert, t)!,
    );
  }
}
