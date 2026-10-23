import 'package:flutter/material.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_result.dart';

/// Alerta visual cuando el aporte de snacks supera el 10% del MER (RF-3).
///
/// Se muestra únicamente cuando [NutritionResult.exceedsSnackLimit] es
/// verdadero. El significado se transmite con el icono y el título, nunca con
/// el color por sí solo (RNF-5).
class NutritionSnackAlert extends StatelessWidget {
  final NutritionResult result;

  const NutritionSnackAlert({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Snacks por encima del límite',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'El aporte de snacks '
                  '(${result.snacksKcal.toStringAsFixed(1)} kcal) supera el 10% '
                  'del MER (${result.snackLimitKcal.toStringAsFixed(1)} kcal). '
                  'Reduce los snacks para no desequilibrar la dieta.',
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
