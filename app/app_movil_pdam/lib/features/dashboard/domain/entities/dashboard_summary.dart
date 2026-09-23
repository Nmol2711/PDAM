import 'package:equatable/equatable.dart';

class DashboardSummary extends Equatable {
  final int totalPets;
  final int sterilizedPets;
  final double foodDispensedToday;
  final double foodTargetToday;
  final int pendingFeedings;
  final int completedFeedings;
  final List<double> weeklyDispensed;

  const DashboardSummary({
    required this.totalPets,
    required this.sterilizedPets,
    required this.foodDispensedToday,
    required this.foodTargetToday,
    required this.pendingFeedings,
    required this.completedFeedings,
    required this.weeklyDispensed,
  });

  @override
  List<Object?> get props => [
        totalPets,
        sterilizedPets,
        foodDispensedToday,
        foodTargetToday,
        pendingFeedings,
        completedFeedings,
        weeklyDispensed,
      ];
}
