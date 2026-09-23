part of 'log_bloc.dart';

sealed class LogEvent {
  const LogEvent();
}

class LogsRequested extends LogEvent {
  final int? petId;
  final String? date;

  const LogsRequested({this.petId, this.date});
}
