part of 'log_bloc.dart';

sealed class LogState {
  const LogState();
}

class LogInitial extends LogState {}

class LogLoading extends LogState {}

class LogLoaded extends LogState {
  final List<ActivityLogEntity> logs;
  final bool isOffline;
  const LogLoaded({required this.logs, this.isOffline = false});
}

class LogError extends LogState {
  final String message;
  const LogError({required this.message});
}
