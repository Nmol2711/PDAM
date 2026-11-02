import 'package:equatable/equatable.dart';

/// Resumen del panel que la app muestra o cachea (RF-6, RF-7, RF-12).
///
/// Los siete campos clásicos conservan nombre y tipo. `todayIndex` es la
/// posición de hoy en la serie semanal (0 lunes a 6 domingo) y `calculatedAt`
/// el instante del cálculo informado por el servidor o por la caché; solo es
/// nulo en el resumen local sin caché. Ninguno de los dos se deriva del reloj
/// del dispositivo.
class DashboardSummary extends Equatable {
  final int totalPets;
  final int sterilizedPets;
  final double foodDispensedToday;
  final double foodTargetToday;
  final int pendingFeedings;
  final int completedFeedings;
  final List<double> weeklyDispensed;

  /// Posición de hoy en la serie semanal (0 lunes a 6 domingo). Obligatoria:
  /// la aporta el servidor o la caché, nunca el reloj del dispositivo.
  final int todayIndex;

  /// Instante del cálculo en UTC. Nulo únicamente en el resumen local sin
  /// caché, donde no existe una medición del servidor que mostrar.
  final DateTime? calculatedAt;

  /// Indica que el resumen proviene de la caché local y no del servidor.
  final bool isFromCache;

  const DashboardSummary({
    required this.totalPets,
    required this.sterilizedPets,
    required this.foodDispensedToday,
    required this.foodTargetToday,
    required this.pendingFeedings,
    required this.completedFeedings,
    required this.weeklyDispensed,
    required this.todayIndex,
    this.calculatedAt,
    this.isFromCache = false,
  });

  DashboardSummary copyWith({
    int? totalPets,
    int? sterilizedPets,
    double? foodDispensedToday,
    double? foodTargetToday,
    int? pendingFeedings,
    int? completedFeedings,
    List<double>? weeklyDispensed,
    int? todayIndex,
    DateTime? calculatedAt,
    bool? isFromCache,
  }) {
    return DashboardSummary(
      totalPets: totalPets ?? this.totalPets,
      sterilizedPets: sterilizedPets ?? this.sterilizedPets,
      foodDispensedToday: foodDispensedToday ?? this.foodDispensedToday,
      foodTargetToday: foodTargetToday ?? this.foodTargetToday,
      pendingFeedings: pendingFeedings ?? this.pendingFeedings,
      completedFeedings: completedFeedings ?? this.completedFeedings,
      weeklyDispensed: weeklyDispensed ?? this.weeklyDispensed,
      todayIndex: todayIndex ?? this.todayIndex,
      calculatedAt: calculatedAt ?? this.calculatedAt,
      isFromCache: isFromCache ?? this.isFromCache,
    );
  }

  @override
  List<Object?> get props => [
        totalPets,
        sterilizedPets,
        foodDispensedToday,
        foodTargetToday,
        pendingFeedings,
        completedFeedings,
        weeklyDispensed,
        todayIndex,
        calculatedAt,
        isFromCache,
      ];
}
