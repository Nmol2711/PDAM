import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class DashboardHeroCard extends StatelessWidget {
  final int totalFeedings;
  final int completedFeedings;
  final int pendingFeedings;
  final VoidCallback onLogsPressed;

  const DashboardHeroCard({
    super.key,
    required this.totalFeedings,
    required this.completedFeedings,
    required this.pendingFeedings,
    required this.onLogsPressed,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: esquema.primary,
        borderRadius: AppRadii.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Alimentaciones para hoy",
            style: TextStyle(
              color: esquema.onPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "$pendingFeedings",
                style: TextStyle(
                  color: esquema.onPrimary,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "$completedFeedings realizadas de $totalFeedings",
                        style: TextStyle(
                          color: esquema.onPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.end,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        "porciones pendientes",
                        style: TextStyle(
                          color: esquema.onPrimary,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _estadoYAccion(esquema),
        ],
      ),
    );
  }

  Widget _estadoYAccion(ColorScheme esquema) {
    final estado = Row(
      children: [
        Icon(Icons.access_time_filled, color: esquema.onPrimary, size: 16),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            "Dispensador activo y sincronizado",
            style: TextStyle(color: esquema.onPrimary, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final boton = TextButton(
      onPressed: onLogsPressed,
      style: TextButton.styleFrom(
        backgroundColor: esquema.onPrimary,
        foregroundColor: esquema.primary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      child: const Text(
        "Ver Historial",
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // En pantallas estrechas el botón baja a su propia línea para no
        // desbordar con texto ampliado (RNF-02).
        if (constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              estado,
              const SizedBox(height: AppSpacing.sm),
              Align(alignment: Alignment.centerRight, child: boton),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: estado),
            const SizedBox(width: AppSpacing.sm),
            boton,
          ],
        );
      },
    );
  }
}
