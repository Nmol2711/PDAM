import 'package:app_movil_pdam/domain/entities/schedule_entity.dart';

class ScheduleModel extends ScheduleEntity {
  ScheduleModel({
    required super.id,
    required super.time,
    required super.amount,
    required super.userId,
  });

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    return ScheduleModel(
      id: json['id'],
      time: json['time'],
      amount: json['amount'],
      userId: json['userId'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['time'] = time;
    data['amount'] = amount;
    data['userId'] = userId;
    return data;
  }
}
