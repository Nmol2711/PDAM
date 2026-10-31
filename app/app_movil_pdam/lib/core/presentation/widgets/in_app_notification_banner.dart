import 'package:flutter/material.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';

enum InAppNotificationType { info, warning, success }

class InAppNotificationBanner extends StatelessWidget {
  final String title;
  final String message;
  final InAppNotificationType type;
  final VoidCallback? onClose;
  final VoidCallback? onAction;
  final String? actionLabel;

  const InAppNotificationBanner({
    super.key,
    required this.title,
    required this.message,
    this.type = InAppNotificationType.info,
    this.onClose,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final semantica = AppSemanticColors.of(context);

    // El relleno de cada tipo lleva su color de contenido: éxito y alerta
    // nunca se usan como texto en claro (RF-04).
    final Color backgroundColor;
    final Color borderColor;
    final Color contentColor;
    final IconData iconData;

    switch (type) {
      case InAppNotificationType.success:
        backgroundColor = semantica.success;
        borderColor = semantica.success;
        contentColor = semantica.onSuccess;
        iconData = Icons.check_circle_rounded;
        break;
      case InAppNotificationType.warning:
        backgroundColor = semantica.alert;
        borderColor = semantica.alert;
        contentColor = semantica.onAlert;
        iconData = Icons.warning_rounded;
        break;
      case InAppNotificationType.info:
        backgroundColor = esquema.tertiaryContainer;
        borderColor = esquema.tertiary;
        contentColor = esquema.onTertiaryContainer;
        iconData = Icons.info_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.banner),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, color: contentColor, size: 24),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: contentColor,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: TextStyle(fontSize: 13, color: contentColor),
                ),
                if (onAction != null && actionLabel != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: contentColor,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: contentColor,
              onPressed: onClose,
              tooltip: 'Cerrar',
            ),
        ],
      ),
    );
  }
}
