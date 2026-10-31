import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:app_movil_pdam/features/nutrition/domain/entities/nutrition_result.dart';

/// Tarjeta con los resultados de dosificación WSAVA (RF-4).
///
/// Widget de presentación puro: recibe el resultado ya calculado y solo lo
/// muestra, sin lógica de negocio.
class NutritionResultCard extends StatelessWidget {
  final NutritionResult result;

  const NutritionResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resultado de dosificación',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _MetricRow(
              label: 'Energía en reposo (RER)',
              value: '${result.rerKcal.toStringAsFixed(1)} kcal/día',
            ),
            _MetricRow(
              label: 'Energía de mantenimiento (MER)',
              value: '${result.merKcal.toStringAsFixed(1)} kcal/día',
            ),
            _MetricRow(
              label: 'Rango estimado (variabilidad)',
              value:
                  '${result.variabilityMinKcal.toStringAsFixed(1)} – '
                  '${result.variabilityMaxKcal.toStringAsFixed(1)} kcal/día',
            ),
            const Divider(height: AppSpacing.sectionGap),
            _MetricRow(
              label: 'Ración diaria',
              value: '${result.dailyRationGrams.toStringAsFixed(1)} g/día',
            ),
            _MetricRow(
              label: 'Ración por comida (${result.mealsPerDay} comidas)',
              value: '${result.rationPerMealGrams.toStringAsFixed(1)} g',
            ),
            const Divider(height: AppSpacing.sectionGap),
            _MetricRow(
              label: 'Límite de snacks (10% del MER)',
              value: '${result.snackLimitKcal.toStringAsFixed(1)} kcal/día',
            ),
            _MetricRow(
              label: 'Snacks ingresados',
              value: '${result.snacksKcal.toStringAsFixed(1)} kcal/día',
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: esquema.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: esquema.tertiary,
            ),
          ),
        ],
      ),
    );
  }
}
