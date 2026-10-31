import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:flutter/material.dart';

/// Botón de la acción principal de creación o compra (spec 017, RF-05).
///
/// Lee el CTA de [AppSemanticColors] para que no se propague a otros botones:
/// el resto de acciones principales heredan el principal del tema. No contiene
/// lógica de negocio; solo compone el botón y reenvía [onPressed].
class AppCtaButton extends StatelessWidget {
  const AppCtaButton({
    super.key,
    required this.child,
    this.onPressed,
    this.icon,
    this.autofocus = false,
  });

  /// Etiqueta del botón.
  final Widget child;

  /// Acción a ejecutar; `null` deshabilita el botón.
  final VoidCallback? onPressed;

  /// Icono opcional que acompaña a la etiqueta.
  final IconData? icon;

  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final semantica = AppSemanticColors.of(context);
    final esquema = Theme.of(context).colorScheme;
    final estilo = FilledButton.styleFrom(
      backgroundColor: semantica.cta,
      foregroundColor: semantica.onCta,
      // Deshabilitado legible: contraste suficiente sobre el contenedor.
      disabledBackgroundColor: esquema.surfaceContainerHighest,
      disabledForegroundColor: esquema.onSurfaceVariant,
    );

    final icono = icon;
    if (icono == null) {
      return FilledButton(
        onPressed: onPressed,
        autofocus: autofocus,
        style: estilo,
        child: child,
      );
    }

    return FilledButton.icon(
      onPressed: onPressed,
      autofocus: autofocus,
      style: estilo,
      icon: Icon(icono),
      label: child,
    );
  }
}
