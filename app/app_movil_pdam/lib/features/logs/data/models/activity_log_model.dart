import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';

class ActivityLogModel extends ActivityLogEntity {
  const ActivityLogModel({
    required super.id,
    required super.event,
    required super.timestamp,
    super.petId,
  });

  factory ActivityLogModel.fromJson(Map<String, dynamic> json) {
    return ActivityLogModel(
      id: json['id'],
      event: json['event'],
      timestamp: DateTime.parse(json['timestamp']),
      petId: json['pet_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event': event,
      'timestamp': timestamp.toIso8601String(),
      'pet_id': petId,
    };
  }
}
