/// Escala de espaciado de la aplicación (spec 017, RF-09).
///
/// Solo existen 4, 8, 12, 16, 20, 24 y 32, más los valores semánticos que
/// usan las pantallas. Quedan fuera las dimensiones fijas, el mínimo de
/// accesibilidad de 48 y los trazos de 1 punto.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Relleno horizontal de pantalla: 16 y 24 desde 600 puntos.
  static const double page = lg;
  static const double pageWide = xxl;

  /// Separación entre campos de un formulario.
  static const double fieldGap = lg;

  /// Relleno interior de una tarjeta.
  static const double cardPadding = lg;

  /// Separación entre secciones de una pantalla.
  static const double sectionGap = xxl;

  /// Relleno de pantalla según el ancho disponible (RF-09).
  static double pageFor(double ancho) => ancho >= 600 ? pageWide : page;
}
