import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';

class GeneratedSchedulesListWidget extends StatelessWidget {
  final List<Schedule> schedules;
  final double waterMin;
  final double waterMax;

  const GeneratedSchedulesListWidget({
    super.key,
    required this.schedules,
    required this.waterMin,
    required this.waterMax,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: AppSpacing.fieldGap),
        Text(
          "Horarios Programados:",
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.md),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: schedules.length,
          itemBuilder: (context, index) {
            final s = schedules[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: ListTile(
                leading: Icon(Icons.access_time, color: esquema.tertiary),
                title: Text(
                  s.time,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: Text(
                  "${s.amount} g",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: esquema.tertiary,
                    fontSize: 15,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: esquema.tertiaryContainer,
            borderRadius: AppRadii.cardRadius,
          ),
          child: Row(
            children: [
              Icon(
                Icons.water_drop,
                color: esquema.onTertiaryContainer,
                size: 28,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  "Agua recomendada: ${waterMin.toStringAsFixed(0)} - ${waterMax.toStringAsFixed(0)} ml/día.",
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: esquema.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
