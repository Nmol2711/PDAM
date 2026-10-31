import 'package:flutter/material.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';

/// Fila del menú de configuración (RF-02, RF-03).
///
/// Solo recibe datos y emite su pulsación: no conoce destinos ni estado. El
/// título puede ocupar varias líneas para que el escalado de texto no recorte
/// nada (RNF-02).
class SettingsMenuTile extends StatelessWidget {
  /// Lado del contenedor del icono y sangría derivada para los divisores.
  static const double iconContainerSize = 40;
  static const double dividerIndent =
      AppSpacing.lg + iconContainerSize + AppSpacing.lg;

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Icono final de la fila. Las filas que navegan usan el chevron; las que
  /// abren un diálogo de valor usan un indicador de ajuste (RF-03).
  final IconData trailingIcon;

  const SettingsMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailingIcon = Icons.chevron_right,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: iconContainerSize,
              height: iconContainerSize,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: AppRadii.controlRadius,
              ),
              child: Icon(icon, size: 22, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: textTheme.titleMedium),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(trailingIcon, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
