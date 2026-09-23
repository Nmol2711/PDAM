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

class AutoGenerateSchedulesRequested extends ScheduleEvent {
  final int petId;
  final double foodKcalPerKg;
  final int bcs;
  final String mcs;
  final String activityLevel;
  final int mealsPerDay;

  const AutoGenerateSchedulesRequested({
    required this.petId,
    required this.foodKcalPerKg,
    required this.bcs,
    required this.mcs,
    required this.activityLevel,
    required this.mealsPerDay,
  });
}

class ScheduleUpdatePressed extends ScheduleEvent {
  final int scheduleId;
  final int petId;
  final String? time;
  final double? amount;

  const ScheduleUpdatePressed({
    required this.scheduleId,
    required this.petId,
    this.time,
    this.amount,
  });
}
