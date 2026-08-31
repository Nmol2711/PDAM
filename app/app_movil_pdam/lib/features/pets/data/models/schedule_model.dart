import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';

class ScheduleModel extends Schedule {
  const ScheduleModel({
    required super.id,
    required super.time,
    required super.amount,
    required super.petId,
  });

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    return ScheduleModel(
      id: json['id'],
      time: json['time'],
      amount: json['amount'],
      petId: json['pet_id'],
    );
  }
}
