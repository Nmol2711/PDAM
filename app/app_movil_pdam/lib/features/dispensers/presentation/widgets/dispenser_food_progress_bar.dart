import 'package:flutter/material.dart';
import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_food_status.dart';

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
    final progressColor = isCritical ? AppColors.warning : AppColors.primaryGreen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Alimento restante:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              currentFoodGrams >= 1000
                  ? '${(currentFoodGrams / 1000).toStringAsFixed(1)} kg / ${(maxCapacityGrams / 1000).toStringAsFixed(0)} kg (${percentage.toStringAsFixed(0)}%)'
                  : '${currentFoodGrams.toStringAsFixed(0)} g / ${maxCapacityGrams.toStringAsFixed(0)} g (${percentage.toStringAsFixed(0)}%)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isCritical ? AppColors.warning : AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percentage / 100.0,
            backgroundColor: AppColors.textSecondary.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            minHeight: 8,
          ),
        ),
        if (isCritical) ...[
          const SizedBox(height: 4),
          const Text(
            'Atención: Nivel crítico de alimento (< 20%)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.warning,
            ),
          ),
        ],
      ],
    );
  }
}
