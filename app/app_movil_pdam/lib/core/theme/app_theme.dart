import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Temas claro y oscuro de la aplicación (spec 017).
///
/// Todas las ranuras del `ColorScheme` se fijan con los tokens de
/// `AppColors`; no se usa `ColorScheme.fromSeed` para que ningún valor por
/// defecto de Material llegue a botones, navegación, cursores ni avisos.
class AppTheme {
  const AppTheme._();

  static ThemeData get lightTheme =>
      _construir(_esquemaClaro, AppSemanticColors.light);

  static ThemeData get darkTheme =>
      _construir(_esquemaOscuro, AppSemanticColors.dark);

  static const ColorScheme _esquemaClaro = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.lightPrimary,
    onPrimary: AppColors.lightOnPrimary,
    primaryContainer: AppColors.lightPrimaryContainer,
    onPrimaryContainer: AppColors.lightOnPrimaryContainer,
    secondary: AppColors.lightPrimary,
    onSecondary: AppColors.lightOnPrimary,
    secondaryContainer: AppColors.lightPrimaryContainer,
    onSecondaryContainer: AppColors.lightOnPrimaryContainer,
    tertiary: AppColors.lightTertiary,
    onTertiary: AppColors.lightOnTertiary,
    tertiaryContainer: AppColors.lightTertiaryContainer,
    onTertiaryContainer: AppColors.lightOnTertiaryContainer,
    error: AppColors.lightError,
    onError: AppColors.lightOnError,
    errorContainer: AppColors.lightErrorContainer,
    onErrorContainer: AppColors.lightOnErrorContainer,
    surface: AppColors.lightSurface,
    onSurface: AppColors.lightOnSurface,
    onSurfaceVariant: AppColors.lightOnSurfaceVariant,
    surfaceContainerLowest: AppColors.lightSurfaceContainerLowest,
    surfaceContainerLow: AppColors.lightSurfaceContainerLow,
    surfaceContainer: AppColors.lightSurfaceContainer,
    surfaceContainerHigh: AppColors.lightSurfaceContainerHigh,
    surfaceContainerHighest: AppColors.lightSurfaceContainerHighest,
    outline: AppColors.lightOutline,
    outlineVariant: AppColors.lightOutlineVariant,
    inverseSurface: AppColors.lightInverseSurface,
    onInverseSurface: AppColors.lightOnInverseSurface,
    inversePrimary: AppColors.lightInversePrimary,
    surfaceTint: AppColors.lightPrimary,
    scrim: AppColors.lightScrim,
    shadow: AppColors.lightShadow,
  );

  static const ColorScheme _esquemaOscuro = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.darkOnPrimary,
    primaryContainer: AppColors.darkPrimaryContainer,
    onPrimaryContainer: AppColors.darkOnPrimaryContainer,
    secondary: AppColors.darkPrimary,
    onSecondary: AppColors.darkOnPrimary,
    secondaryContainer: AppColors.darkPrimaryContainer,
    onSecondaryContainer: AppColors.darkOnPrimaryContainer,
    tertiary: AppColors.darkTertiary,
    onTertiary: AppColors.darkOnTertiary,
    tertiaryContainer: AppColors.darkTertiaryContainer,
    onTertiaryContainer: AppColors.darkOnTertiaryContainer,
    error: AppColors.darkError,
    onError: AppColors.darkOnError,
    errorContainer: AppColors.darkErrorContainer,
    onErrorContainer: AppColors.darkOnErrorContainer,
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkOnSurface,
    onSurfaceVariant: AppColors.darkOnSurfaceVariant,
    surfaceContainerLowest: AppColors.darkSurfaceContainerLowest,
    surfaceContainerLow: AppColors.darkSurfaceContainerLow,
    surfaceContainer: AppColors.darkSurfaceContainer,
    surfaceContainerHigh: AppColors.darkSurfaceContainerHigh,
    surfaceContainerHighest: AppColors.darkSurfaceContainerHighest,
    outline: AppColors.darkOutline,
    outlineVariant: AppColors.darkOutlineVariant,
    inverseSurface: AppColors.darkInverseSurface,
    onInverseSurface: AppColors.darkOnInverseSurface,
    inversePrimary: AppColors.darkInversePrimary,
    surfaceTint: AppColors.darkPrimary,
    scrim: AppColors.darkScrim,
    shadow: AppColors.darkShadow,
  );

  static ThemeData _construir(
    ColorScheme esquema,
    AppSemanticColors semantica,
  ) {
    final esClaro = esquema.brightness == Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      brightness: esquema.brightness,
      colorScheme: esquema,
      extensions: <ThemeExtension<dynamic>>[semantica],
    );
    final textos = base.textTheme.apply(
      bodyColor: esquema.onSurface,
      displayColor: esquema.onSurface,
    );
    final fondo = esClaro
        ? AppColors.lightBackground
        : AppColors.darkBackground;

    final bordeCampo = OutlineInputBorder(
      borderRadius: AppRadii.controlRadius,
      borderSide: BorderSide(color: esquema.outline),
    );

    return base.copyWith(
      textTheme: textos,
      scaffoldBackgroundColor: fondo,
      canvasColor: esquema.surface,
      cardTheme: CardThemeData(
        color: esquema.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardRadius,
          side: BorderSide(color: esquema.outline),
        ),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: esquema.primary,
        foregroundColor: esquema.onPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: esClaro ? Brightness.light : Brightness.dark,
          statusBarBrightness: esClaro ? Brightness.dark : Brightness.light,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: esquema.surface,
        selectedItemColor: esquema.primary,
        unselectedItemColor: esquema.onSurfaceVariant,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: esquema.surface,
        indicatorColor: esquema.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: esquema.primary,
          foregroundColor: esquema.onPrimary,
          disabledBackgroundColor: esquema.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: esquema.onSurface.withValues(alpha: 0.38),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.controlRadius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: esquema.primary,
          side: BorderSide(color: esquema.outline),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.controlRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadii.controlRadius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: esquema.primary,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.controlRadius),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadii.controlRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: esquema.surface,
        border: bordeCampo,
        enabledBorder: bordeCampo,
        focusedBorder: bordeCampo.copyWith(
          borderSide: BorderSide(color: esquema.primary),
        ),
        errorBorder: bordeCampo.copyWith(
          borderSide: BorderSide(color: esquema.error),
        ),
        focusedErrorBorder: bordeCampo.copyWith(
          borderSide: BorderSide(color: esquema.error),
        ),
        disabledBorder: bordeCampo.copyWith(
          borderSide: BorderSide(color: esquema.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: esquema.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: esquema.scrim.withValues(alpha: 0.54),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: esquema.outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: esquema.surface,
        modalBackgroundColor: esquema.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: esquema.scrim.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetRadius),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: esquema.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.menuRadius,
          side: BorderSide(color: esquema.outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: esquema.inverseSurface,
        contentTextStyle: textos.bodyMedium?.copyWith(
          color: esquema.onInverseSurface,
        ),
        actionTextColor: esquema.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.banner),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: esquema.surfaceContainerHighest,
        selectedColor: esquema.primaryContainer,
        secondarySelectedColor: esquema.secondaryContainer,
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: esquema.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        labelStyle: textos.labelLarge?.copyWith(color: esquema.onSurface),
        secondaryLabelStyle: textos.labelLarge?.copyWith(
          color: esquema.onPrimaryContainer,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: esquema.primary,
        foregroundColor: esquema.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.fab),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: esquema.outlineVariant,
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: esquema.primary,
        linearTrackColor: esquema.surfaceContainerHighest,
        circularTrackColor: esquema.surfaceContainerHighest,
      ),
      iconTheme: IconThemeData(color: esquema.onSurface),
      // En esta versión de Flutter el cursor vive solo en `textSelectionTheme`.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: esquema.primary,
        selectionColor: esquema.primary.withValues(alpha: 0.24),
        selectionHandleColor: esquema.primary,
      ),
    );
  }
}
