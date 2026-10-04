import 'package:flutter/material.dart';

// Componente de aviso reutilizable (RF-09 · RNF-01 a RNF-07 · CL-13).
//
// Vive en `core` y solo recibe parámetros primitivos: tono, icono, título,
// descripción y etiqueta de la acción. No importa nada de ningún `features/`,
// de modo que cualquier funcionalidad puede mostrarlo (RNF-02).
//
// Estilo Material 3: la jerarquía visual la marca el icono y el título, el
// ancho del contenido está acotado y el cuerpo se desplaza en lugar de
// desbordarse cuando la fuente está ampliada. Los colores salen del tema, así
// que el mismo aviso se ve bien en modo claro y oscuro (RNF-04).

/// Carácter del aviso: informativo o de advertencia (RF-09).
enum AppNoticeTone { info, warning }

/// Parámetros con los que se muestra un aviso reutilizable.
///
/// Permite transportar el aviso completo como un solo valor (por ejemplo, el
/// resultado de un mapper de copy) sin que el diálogo conozca el dominio.
class AppNoticeParams {
  final AppNoticeTone tone;
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;

  const AppNoticeParams({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
  });
}

/// Ventana emergente de aviso con estilo Material 3.
///
/// Se muestra con [AppNoticeDialog.show] y se cierra con su acción principal
/// (RNF-03). El significado lo transmiten el icono y el título, nunca el color
/// por sí solo (RNF-05).
class AppNoticeDialog extends StatelessWidget {
  /// Ancho máximo del contenido: evita que el texto se estire en pantallas
  /// grandes (RNF-06).
  static const double anchoMaximoContenido = 420;

  /// Margen horizontal del contenido del diálogo, declarado aquí para poder
  /// acotar también el ancho del diálogo completo.
  static const double margenContenido = 24;

  /// Ancho máximo del diálogo completo: el contenido acotado más sus márgenes.
  static const double anchoMaximoDialogo =
      anchoMaximoContenido + 2 * margenContenido;

  /// Ancho mínimo del diálogo: el mínimo de Material 3, para que no se estreche
  /// de más en pantallas pequeñas.
  static const double anchoMinimoDialogo = 280;

  /// Margen respecto a los bordes de la pantalla. Menor que el de Material por
  /// defecto para aprovechar el ancho en pantallas estrechas; en las anchas manda
  /// [anchoMaximoDialogo] (CL-13, RNF-06).
  static const EdgeInsets margenPantalla = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 24,
  );

  /// Altura mínima de la acción principal: objetivo táctil de 48 dp (RNF-07).
  static const Size tamanoMinimoAccion = Size(64, 48);

  final AppNoticeTone tone;
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;

  const AppNoticeDialog({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
  });

  /// Muestra el aviso y espera a que el usuario lo cierre con su acción.
  static Future<void> show(
    BuildContext context, {
    required AppNoticeTone tone,
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AppNoticeDialog(
        tone: tone,
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool esAdvertencia = tone == AppNoticeTone.warning;

    // El ancho se acota con `constraints` del propio `AlertDialog` y no con un
    // `ConstrainedBox` alrededor: la ruta del diálogo entrega restricciones
    // *estrechas* al contenido de la ventana y `ConstrainedBox` solo puede
    // agrandarlas, nunca reducirlas. El diálogo queda, por tanto, con un ancho
    // útil de [anchoMaximoContenido] en pantallas grandes (RNF-06).
    return AlertDialog(
      constraints: const BoxConstraints(
        minWidth: anchoMinimoDialogo,
        maxWidth: anchoMaximoDialogo,
      ),
      insetPadding: margenPantalla,
      // Con la fuente ampliada en una pantalla estrecha el aviso se desplaza en
      // lugar de desbordarse ni recortar texto, y su acción sigue visible
      // porque las acciones quedan fuera de la zona desplazable (RNF-06, CL-13).
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(
        margenContenido,
        16,
        margenContenido,
        24,
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        margenContenido,
        24,
        margenContenido,
        8,
      ),
      icon: Semantics(
        container: true,
        label: esAdvertencia ? 'Advertencia' : 'Información',
        child: CircleAvatar(
          radius: 24,
          backgroundColor: esAdvertencia
              ? colors.errorContainer
              : colors.primaryContainer,
          child: Icon(
            icon,
            size: 32,
            color: esAdvertencia
                ? colors.onErrorContainer
                : colors.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      // Con `scrollable: true` el `AlertDialog` ya envuelve icono, título y
      // descripción en un `Column(mainAxisSize: min)` dentro de un `Flexible` +
      // `SingleChildScrollView`. Añadir aquí otro `Flexible` fallaría, porque su
      // altura llegaría sin cota superior.
      content: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      // El botón ya expone su texto como nombre accesible y como botón, así que
      // no se envuelve en otro `Semantics`: solo duplicaría el anuncio (RNF-07).
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(minimumSize: tamanoMinimoAccion),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}
