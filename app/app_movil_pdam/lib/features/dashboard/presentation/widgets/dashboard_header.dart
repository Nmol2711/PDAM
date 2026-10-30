import 'package:app_movil_pdam/core/presentation/utils/settings_entry_visibility.dart';
import 'package:app_movil_pdam/core/presentation/widgets/settings_entry_button.dart';
import 'package:flutter/material.dart';

/// Cabecera del panel principal (RF-04).
///
/// Conserva el saludo y el cierre de sesión, pierde el control de tema y gana
/// la entrada al menú de configuración cuando el ancho es menor que 600. En
/// pantallas anchas la entrada vive únicamente en la barra del contenedor.
class DashboardHeader extends StatelessWidget {
  final String userName;
  final VoidCallback onLogout;

  const DashboardHeader({
    super.key,
    required this.userName,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                userName,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Panel de Control Nutricional',
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SettingsEntryButton(
          ubicacion: UbicacionEntrada.cabeceraPantalla,
        ),
        const SizedBox(width: 4),
        CircleAvatar(
          radius: 20,
          backgroundColor: colors.primaryContainer,
          child: IconButton(
            icon: const Icon(Icons.logout, size: 18),
            tooltip: 'Cerrar sesión',
            onPressed: onLogout,
          ),
        ),
      ],
    );
  }
}
