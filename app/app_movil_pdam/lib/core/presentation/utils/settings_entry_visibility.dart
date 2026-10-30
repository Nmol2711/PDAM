/// Regla pura de visibilidad de la entrada al menú de configuración (RF-01).
///
/// Es la única fuente de verdad: la misma función decide la cabecera de la
/// pantalla y la barra del contenedor, de modo que nunca se dibujan las dos a
/// la vez. No depende de Flutter ni del estado de la aplicación.
library;

/// Punto del árbol donde puede dibujarse la entrada al menú.
enum UbicacionEntrada {
  /// Cabecera propia de una pantalla principal (menos de 600 puntos).
  cabeceraPantalla,

  /// Barra superior del contenedor de navegación (600 puntos o más).
  barraContenedor,
}

/// Ancho a partir del cual la entrada vive en la barra del contenedor.
const double anchoBarraContenedor = 600;

/// Indica si la entrada debe dibujarse en [ubicacion] para [ancho].
///
/// Por debajo de 600 puntos solo se dibuja en la cabecera de la pantalla; desde
/// 600 puntos solo en la barra del contenedor. La comparación es excluyente,
/// por lo que una misma pantalla nunca muestra dos entradas (RF-01).
bool debeMostrarEntrada(double ancho, UbicacionEntrada ubicacion) {
  final esAnchoAmplio = ancho >= anchoBarraContenedor;
  return switch (ubicacion) {
    UbicacionEntrada.cabeceraPantalla => !esAnchoAmplio,
    UbicacionEntrada.barraContenedor => esAnchoAmplio,
  };
}
