import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: esquema.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: esquema.outline),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: backgroundColor.withValues(alpha: 0.15),
                borderRadius: AppRadii.controlRadius,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: esquema.tertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: esquema.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardMetricsGrid extends StatelessWidget {
  final int totalPets;
  final int sterilizedPets;
  final double foodDispensedToday;
  final double foodTargetToday;

  const DashboardMetricsGrid({
    super.key,
    required this.totalPets,
    required this.sterilizedPets,
    required this.foodDispensedToday,
    required this.foodTargetToday,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final foodPercentage = foodTargetToday > 0
        ? (foodDispensedToday / foodTargetToday).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Resumen del Sistema",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.lg),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.25,
          children: [
            MetricCard(
              label: "Total Mascotas",
              value: totalPets.toString(),
              icon: Icons.pets,
              iconColor: esquema.tertiary,
              backgroundColor: esquema.tertiary,
            ),
            MetricCard(
              label: "Mascotas Castradas",
              value: sterilizedPets.toString(),
              icon: Icons.medical_services_outlined,
              iconColor: esquema.tertiary,
              backgroundColor: esquema.tertiary,
            ),
            MetricCard(
              label: "Alimento Hoy (g)",
              value: foodDispensedToday.toStringAsFixed(0),
              icon: Icons.local_fire_department_outlined,
              iconColor: esquema.tertiary,
              backgroundColor: esquema.tertiary,
            ),
            MetricCard(
              label: "Cumplimiento Meta",
              value: "${(foodPercentage * 100).toInt()}%",
              icon: Icons.analytics_outlined,
              iconColor: esquema.tertiary,
              backgroundColor: esquema.tertiary,
            ),
          ],
        ),
      ],
    );
  }
}
