import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_result.dart';

/// Alerta visual cuando el aporte de snacks supera el 10% del MER (RF-3).
///
/// Se muestra únicamente cuando [NutritionResult.exceedsSnackLimit] es
/// verdadero. El significado se transmite con el icono y el título, nunca con
/// el color por sí solo (RNF-5). Usa el relleno de alerta con su contenido.
class NutritionSnackAlert extends StatelessWidget {
  final NutritionResult result;

  const NutritionSnackAlert({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final semantica = AppSemanticColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: semantica.alert,
        borderRadius: BorderRadius.circular(AppRadii.banner),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: semantica.onAlert),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Snacks por encima del límite',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: semantica.onAlert,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'El aporte de snacks '
                  '(${result.snacksKcal.toStringAsFixed(1)} kcal) supera el 10% '
                  'del MER (${result.snackLimitKcal.toStringAsFixed(1)} kcal). '
                  'Reduce los snacks para no desequilibrar la dieta.',
                  style: TextStyle(color: semantica.onAlert),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
