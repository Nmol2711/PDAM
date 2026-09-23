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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: backgroundColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
    final foodPercentage = foodTargetToday > 0
        ? (foodDispensedToday / foodTargetToday).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Resumen del Sistema",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.25,
          children: [
            MetricCard(
              label: "Total Mascotas",
              value: totalPets.toString(),
              icon: Icons.pets,
              iconColor: const Color(0xFF00C853),
              backgroundColor: const Color(0xFF00C853),
            ),
            MetricCard(
              label: "Mascotas Castradas",
              value: sterilizedPets.toString(),
              icon: Icons.medical_services_outlined,
              iconColor: const Color(0xFF6C63FF),
              backgroundColor: const Color(0xFF6C63FF),
            ),
            MetricCard(
              label: "Alimento Hoy (g)",
              value: foodDispensedToday.toStringAsFixed(0),
              icon: Icons.local_fire_department_outlined,
              iconColor: const Color(0xFFFFB300),
              backgroundColor: const Color(0xFFFFB300),
            ),
            MetricCard(
              label: "Cumplimiento Meta",
              value: "${(foodPercentage * 100).toInt()}%",
              icon: Icons.analytics_outlined,
              iconColor: const Color(0xFF00B8D4),
              backgroundColor: const Color(0xFF00B8D4),
            ),
          ],
        ),
      ],
    );
  }
}