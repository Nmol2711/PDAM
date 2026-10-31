import 'package:flutter/material.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser_food_status.dart';

class DispenserFoodProgressBar extends StatelessWidget {
  final double currentFoodGrams;
  final double maxCapacityGrams;

  const DispenserFoodProgressBar({
    super.key,
    required this.currentFoodGrams,
    this.maxCapacityGrams = 5000.0,
  });

  @override
  Widget build(BuildContext context) {
    final status = DispenserFoodStatus(
      currentFoodGrams: currentFoodGrams,
      maxCapacityGrams: maxCapacityGrams,
    );
    final percentage = status.percentageRemaining;
    final isCritical = status.isCritical;
    final esquema = Theme.of(context).colorScheme;
    final semantica = AppSemanticColors.of(context);
    // El relleno crítico usa la alerta; el texto no, porque la alerta como
    // texto no alcanza contraste en modo claro (RF-04).
    final progressColor = isCritical ? semantica.alert : esquema.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text(
              'Alimento restante:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: esquema.onSurfaceVariant,
              ),
            ),
            Text(
              formatFoodProgressLabel(currentFoodGrams, maxCapacityGrams),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: esquema.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadii.controlRadius,
            border: Border.all(color: esquema.outline),
          ),
          child: ClipRRect(
            borderRadius: AppRadii.controlRadius,
            child: LinearProgressIndicator(
              value: percentage / 100.0,
              backgroundColor: esquema.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 8,
            ),
          ),
        ),
        if (isCritical) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Atención: Nivel crítico de alimento (< 20%)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: esquema.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}
