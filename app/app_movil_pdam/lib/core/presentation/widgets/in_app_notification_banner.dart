import 'package:flutter/material.dart';
import 'package:app_movil_pdam/core/theme/app_colors.dart';

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
    Color backgroundColor;
    Color borderColor;
    Color iconColor;
    IconData iconData;

    switch (type) {
      case InAppNotificationType.success:
        backgroundColor = AppColors.success.withOpacity(0.12);
        borderColor = AppColors.success;
        iconColor = AppColors.success;
        iconData = Icons.check_circle_rounded;
        break;
      case InAppNotificationType.warning:
        backgroundColor = AppColors.warning.withOpacity(0.12);
        borderColor = AppColors.warning;
        iconColor = AppColors.warning;
        iconData = Icons.warning_rounded;
        break;
      case InAppNotificationType.info:
      default:
        backgroundColor = AppColors.info.withOpacity(0.12);
        borderColor = AppColors.info;
        iconColor = AppColors.info;
        iconData = Icons.info_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : AppColors.textPrimary,
                  ),
                ),
                if (onAction != null && actionLabel != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: iconColor,
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
              color: AppColors.textSecondary,
              onPressed: onClose,
              tooltip: 'Cerrar',
            ),
        ],
      ),
    );
  }
}
