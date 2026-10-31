import 'package:flutter/material.dart';

/// Único archivo de tokens de color de la aplicación (spec 017, RF-03).
///
/// Cada valor existe dos veces, con prefijo `light` y `dark`, porque la
/// paleta clara y la oscura tienen HEX distintos. Ningún otro archivo declara
/// colores literales; las variantes de opacidad sobre un token y
/// `Colors.transparent` son las únicas excepciones permitidas.
class AppColors {
  const AppColors._();

  // ==============================
  // MODO CLARO
  // ==============================

  // Principal: barras, encabezados, selección y acciones no comerciales.
  static const Color lightPrimary = Color(0xFF2E7D32);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFFC8E6C9);
  static const Color lightOnPrimaryContainer = Color(0xFF1B5E20);

  // CTA: solo relleno de creación o compra; nunca texto, fondo ni barra.
  static const Color lightCta = Color(0xFFD84315);
  static const Color lightOnCta = Color(0xFF000000);

  // Fondo, superficie y texto.
  static const Color lightBackground = Color(0xFFFAF6F0);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF3E2723);
  static const Color lightOnSurfaceVariant = Color(0xFF6B544C);

  // Acento (azul): enlaces, iconos, insignias y avisos informativos.
  static const Color lightTertiary = Color(0xFF0277BD);
  static const Color lightOnTertiary = Color(0xFFFFFFFF);
  static const Color lightTertiaryContainer = Color(0xFFD9ECF7);
  static const Color lightOnTertiaryContainer = Color(0xFF01466F);

  // Estados de relleno con su contenido.
  static const Color lightSuccess = Color(0xFF66BB6A);
  static const Color lightOnSuccess = Color(0xFF3E2723);
  static const Color lightAlert = Color(0xFFFFA726);
  static const Color lightOnAlert = Color(0xFF3E2723);
  static const Color lightError = Color(0xFFB3261E);
  static const Color lightOnError = Color(0xFFFFFFFF);
  static const Color lightErrorContainer = Color(0xFFFFDAD6);
  static const Color lightOnErrorContainer = Color(0xFF410002);

  // Bordes: texto y estructura al 60 % y al 24 %.
  static const Color lightOutline = Color(0x993E2723);
  static const Color lightOutlineVariant = Color(0x3D3E2723);
  static const Color lightShadow = Color(0xFF000000);
  static const Color lightScrim = Color(0xFF000000);

  // Contenedores de superficie del esquema.
  static const Color lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLow = Color(0xFFFDF9F5);
  static const Color lightSurfaceContainer = Color(0xFFF5EEE6);
  static const Color lightSurfaceContainerHigh = Color(0xFFEFE6DD);
  static const Color lightSurfaceContainerHighest = Color(0xFFE8DED4);

  // Superficies inversas (velos y franjas de instrucciones).
  static const Color lightInverseSurface = Color(0xFF3E2723);
  static const Color lightOnInverseSurface = Color(0xFFFAF6F0);
  static const Color lightInversePrimary = Color(0xFF81C784);

  // ==============================
  // MODO OSCURO
  // ==============================

  static const Color darkPrimary = Color(0xFF81C784);
  static const Color darkOnPrimary = Color(0xFF171310);
  static const Color darkPrimaryContainer = Color(0xFF2E5B31);
  static const Color darkOnPrimaryContainer = Color(0xFFC8E6C9);

  static const Color darkCta = Color(0xFFFF8A65);
  static const Color darkOnCta = Color(0xFF171310);

  static const Color darkBackground = Color(0xFF171310);
  static const Color darkSurface = Color(0xFF221C18);
  static const Color darkOnSurface = Color(0xFFF2E9DF);
  static const Color darkOnSurfaceVariant = Color(0xFFC9BCB0);

  static const Color darkTertiary = Color(0xFF4FC3F7);
  static const Color darkOnTertiary = Color(0xFF171310);
  static const Color darkTertiaryContainer = Color(0xFF0B3A52);
  static const Color darkOnTertiaryContainer = Color(0xFFBCE4F5);

  static const Color darkSuccess = Color(0xFFA5D6A7);
  static const Color darkOnSuccess = Color(0xFF171310);
  static const Color darkAlert = Color(0xFFFFB74D);
  static const Color darkOnAlert = Color(0xFF171310);
  static const Color darkError = Color(0xFFF2B8B5);
  static const Color darkOnError = Color(0xFF601410);
  static const Color darkErrorContainer = Color(0xFF93000A);
  static const Color darkOnErrorContainer = Color(0xFFFFDAD6);

  static const Color darkOutline = Color(0x99F2E9DF);
  static const Color darkOutlineVariant = Color(0x3DF2E9DF);
  static const Color darkShadow = Color(0xFF000000);
  static const Color darkScrim = Color(0xFF000000);

  static const Color darkSurfaceContainerLowest = Color(0xFF100D0B);
  static const Color darkSurfaceContainerLow = Color(0xFF1C1714);
  static const Color darkSurfaceContainer = Color(0xFF221C18);
  static const Color darkSurfaceContainerHigh = Color(0xFF2B2420);
  static const Color darkSurfaceContainerHighest = Color(0xFF352D28);

  static const Color darkInverseSurface = Color(0xFFF2E9DF);
  static const Color darkOnInverseSurface = Color(0xFF3E2723);
  static const Color darkInversePrimary = Color(0xFF2E7D32);
}
