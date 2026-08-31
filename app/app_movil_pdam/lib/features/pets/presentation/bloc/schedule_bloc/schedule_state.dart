part of 'schedule_bloc.dart';

sealed class ScheduleState {
  const ScheduleState();
}

class ScheduleInicial extends ScheduleState {}

class ScheduleLoading extends ScheduleState {}

class ScheduleLoaded extends ScheduleState {
  final List<Schedule> schedules;
  const ScheduleLoaded({required this.schedules});
}

class ScheduleDetailLoaded extends ScheduleState {
  final Schedule schedule;
  const ScheduleDetailLoaded({required this.schedule});
}

class ScheduleActionSucces extends ScheduleState {
  final String message;
  const ScheduleActionSucces({required this.message});
}

class ScheduleError extends ScheduleState {
  final String message;
  const ScheduleError({required this.message});
}
