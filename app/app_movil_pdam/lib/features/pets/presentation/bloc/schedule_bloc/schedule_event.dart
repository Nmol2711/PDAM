part of 'schedule_bloc.dart';

sealed class ScheduleEvent {
  const ScheduleEvent();
}

class ScheduleCreatePressed extends ScheduleEvent {
  final String time;
  final double amount;
  final int petId;

  const ScheduleCreatePressed({
    required this.time,
    required this.amount,
    required this.petId,
  });
}

class ScheduleGetRequested extends ScheduleEvent {
  final int sheduleId;
  final int petId;

  const ScheduleGetRequested({required this.sheduleId, required this.petId});
}

class ScheduleCreateMultipleRequested extends ScheduleEvent {
  final List<String> times;
  final double amount;
  final int petId;

  const ScheduleCreateMultipleRequested({
    required this.times,
    required this.amount,
    required this.petId,
  });
}

class ScheduleListRequested extends ScheduleEvent {}

class ScheduleListPetRequested extends ScheduleEvent {
  final int petId;

  const ScheduleListPetRequested({required this.petId});
}
