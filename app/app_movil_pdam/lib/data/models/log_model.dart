import 'package:app_movil_pdam/domain/entities/log_entity.dart';

class LogModel extends LogEntity {
  LogModel({
    required super.id,
    required super.event,
    required super.timestamp,
    required super.userId,
  });

  factory LogModel.fromJson(Map<String, dynamic> json) {
    return LogModel(
      id: json['id'],
      event: json['event'],
      timestamp: DateTime.parse(json['timestamp']),
      userId: json['userId'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['event'] = event;
    data['timestamp'] = timestamp;
    data['userId'] = userId;
    return data;
  }
}
