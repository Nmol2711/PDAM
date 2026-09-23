import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';

class DashboardSummaryModel extends DashboardSummary {
  const DashboardSummaryModel({
    required super.totalPets,
    required super.sterilizedPets,
    required super.foodDispensedToday,
    required super.foodTargetToday,
    required super.pendingFeedings,
    required super.completedFeedings,
    required super.weeklyDispensed,
  });

  factory DashboardSummaryModel.fromJson(Map<String, dynamic> json) {
    return DashboardSummaryModel(
      totalPets: json['total_pets'] ?? 0,
      sterilizedPets: json['sterilized_pets'] ?? 0,
      foodDispensedToday: (json['food_dispensed_today'] as num?)?.toDouble() ?? 0.0,
      foodTargetToday: (json['food_target_today'] as num?)?.toDouble() ?? 300.0,
      pendingFeedings: json['pending_feedings'] ?? 0,
      completedFeedings: json['completed_feedings'] ?? 0,
      weeklyDispensed: (json['weekly_dispensed'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [0, 0, 0, 0, 0, 0, 0],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_pets': totalPets,
      'sterilized_pets': sterilizedPets,
      'food_dispensed_today': foodDispensedToday,
      'food_target_today': foodTargetToday,
      'pending_feedings': pendingFeedings,
      'completed_feedings': completedFeedings,
      'weekly_dispensed': weeklyDispensed,
    };
  }
}
