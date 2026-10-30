import 'package:app_movil_pdam/core/presentation/utils/settings_entry_visibility.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Etiqueta accesible y descripción emergente fija de la entrada (RF-01).
const String etiquetaAbrirConfiguracion = 'Abrir configuración';

/// Entrada única al menú de configuración (RF-01).
///
/// Se dibuja solo cuando [debeMostrarEntrada] lo indica para su [ubicacion] y
/// el ancho actual: en la cabecera de la pantalla por debajo de 600 puntos y
/// en la barra del contenedor desde 600. El icono y la etiqueta son siempre los
/// mismos, con independencia del factor de forma.
class SettingsEntryButton extends StatelessWidget {
  /// Lugar del árbol donde se coloca el botón.
  final UbicacionEntrada ubicacion;

  /// Acción al pulsar. Por defecto abre `/settings` con el enrutador.
  final VoidCallback? onPressed;

  const SettingsEntryButton({
    super.key,
    required this.ubicacion,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    if (!debeMostrarEntrada(ancho, ubicacion)) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: etiquetaAbrirConfiguracion,
      onPressed: onPressed ?? () => context.push('/settings'),
    );
  }
}
