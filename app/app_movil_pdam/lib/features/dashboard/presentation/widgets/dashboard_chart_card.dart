import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Tarjeta del gráfico semanal de dispensación (RF-9, RNF-2).
///
/// Recibe la serie de siete posiciones y la posición de hoy calculada por el
/// servidor. No consulta el reloj del dispositivo, no inventa barras y no pinta
/// barra ni fondo en los días con 0 gramos.
class DashboardChartCard extends StatelessWidget {
  /// Etiquetas de la semana, de lunes a domingo (índice 0 a 6).
  static const List<String> _dias = [
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  static const int _posiciones = 7;

  final List<double> weeklyDispensed;
  final int todayIndex;

  const DashboardChartCard({
    super.key,
    required this.weeklyDispensed,
    required this.todayIndex,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final serie = _serieSegura(weeklyDispensed);
    final semanaVacia = serie.every((gramos) => gramos <= 0);
    final maxY = _maxYSeguro(serie);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: esquema.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: esquema.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Dispensación Semanal (g)",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (semanaVacia)
            _buildSemanaVacia(context, esquema)
          else
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  minY: 0,
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => esquema.tertiary,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${rod.toY.toInt()} g',
                          TextStyle(
                            color: esquema.onTertiary,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < _dias.length) {
                            return SideTitleWidget(
                              meta: meta,
                              space: AppSpacing.xs,
                              child: Text(
                                _dias[index],
                                style: TextStyle(
                                  color: esquema.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) {
                          return SideTitleWidget(
                            meta: meta,
                            space: AppSpacing.xs,
                            child: Text(
                              value.toInt().toString(),
                              style: TextStyle(
                                color: esquema.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: esquema.outlineVariant, strokeWidth: 1),
                  ),
                  barGroups: _buildGrupos(esquema, serie, maxY),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Siete grupos fijos; un día sin gramos queda sin barra ni fondo.
  List<BarChartGroupData> _buildGrupos(
    ColorScheme esquema,
    List<double> serie,
    double maxY,
  ) {
    return List.generate(_posiciones, (index) {
      final gramos = serie[index];
      if (gramos <= 0) {
        return BarChartGroupData(x: index, barRods: const <BarChartRodData>[]);
      }
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: gramos,
            width: 16,
            color: index == todayIndex
                ? esquema.tertiary
                : esquema.tertiary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadii.chip),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxY,
              color: esquema.surfaceContainerHighest,
            ),
          ),
        ],
      );
    });
  }

  /// Mensaje de reemplazo cuando no hubo dispensaciones en la semana.
  Widget _buildSemanaVacia(BuildContext context, ColorScheme esquema) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Text(
          'Sin dispensaciones esta semana',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: esquema.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  /// Una serie que no trae siete posiciones se trata como semana vacía.
  static List<double> _serieSegura(List<double> serie) {
    if (serie.length != _posiciones) {
      return List<double>.filled(_posiciones, 0);
    }
    return serie;
  }

  /// Máximo con margen del 30 % y suelo de 1 para evitar divisiones por cero.
  static double _maxYSeguro(List<double> serie) {
    final maximo = serie.fold<double>(
      0,
      (mayor, gramos) => gramos > mayor ? gramos : mayor,
    );
    final conMargen = maximo * 1.3;
    return conMargen < 1 ? 1 : conMargen;
  }
}
