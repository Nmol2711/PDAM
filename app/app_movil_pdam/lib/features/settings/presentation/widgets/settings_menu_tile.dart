import 'package:flutter/material.dart';

/// Fila del menú de configuración (RF-02, RF-03).
///
/// Solo recibe datos y emite su pulsación: no conoce destinos ni estado. El
/// título puede ocupar varias líneas para que el escalado de texto no recorte
/// nada (RNF-02).
class SettingsMenuTile extends StatelessWidget {
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: textTheme.titleMedium),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
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
            const SizedBox(width: 8),
            Icon(trailingIcon, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
