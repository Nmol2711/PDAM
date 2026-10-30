/// Modos de apariencia del dispositivo (RF-22, RF-23, RF-24).
///
/// Es una preferencia del dispositivo y no de la cuenta: se conserva al cerrar
/// sesión y al eliminar la cuenta. El código es el que se persiste en
/// `user_theme_mode` y la etiqueta es la que se muestra en el diálogo y en la
/// cuarta fila del menú.
///
/// Módulo puro: la traducción al `ThemeMode` de Flutter vive en la capa de
/// presentación (`appearance_mode_theme.dart`), para no arrastrar el framework
/// al dominio (RNF-04).
enum AppearanceMode {
  claro(codigo: 'light', etiqueta: 'Claro'),
  oscuro(codigo: 'dark', etiqueta: 'Oscuro'),
  automatico(codigo: 'system', etiqueta: 'Automático');

  const AppearanceMode({required this.codigo, required this.etiqueta});

  final String codigo;
  final String etiqueta;

  /// Modo correspondiente al código persistido; `system` es el valor por
  /// defecto de un dispositivo que nunca ha elegido (RF-23).
  static AppearanceMode desdeCodigo(String? codigo) {
    for (final modo in AppearanceMode.values) {
      if (modo.codigo == codigo) return modo;
    }
    return AppearanceMode.automatico;
  }
}
