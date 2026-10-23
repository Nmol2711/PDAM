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
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: colors.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resultado de dosificación',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
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
            const Divider(height: 24),
            _MetricRow(
              label: 'Ración diaria',
              value: '${result.dailyRationGrams.toStringAsFixed(1)} g/día',
            ),
            _MetricRow(
              label: 'Ración por comida (${result.mealsPerDay} comidas)',
              value: '${result.rationPerMealGrams.toStringAsFixed(1)} g',
            ),
            const Divider(height: 24),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
