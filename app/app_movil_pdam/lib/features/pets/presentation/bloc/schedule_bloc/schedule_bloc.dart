import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/create_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_by_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/auto_generate_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/update_schedule_uc.dart';

import 'package:bloc/bloc.dart';

part 'schedule_state.dart';
part 'schedule_event.dart';

class ScheduleBloc extends Bloc<ScheduleEvent, ScheduleState> {
  final CreateScheduleUc _createScheduleUc;
  final GetScheduleUc _getScheduleUc;
  final GetSchedulesUc _getSchedulesUc;
  final GetSchedulesByPetUc _getSchedulesByPetUc;
  final AutoGenerateSchedulesUc _autoGenerateSchedulesUc;
  final UpdateScheduleUc _updateScheduleUc;
  ScheduleBloc({
    required CreateScheduleUc createScheduleUc,
    required GetScheduleUc getScheduleUc,
    required GetSchedulesUc getSchedulesUc,
    required GetSchedulesByPetUc getSchedulesByPetUc,
    required AutoGenerateSchedulesUc autoGenerateSchedulesUc,
    required UpdateScheduleUc updateScheduleUc,
  }) : _createScheduleUc = createScheduleUc,
       _getScheduleUc = getScheduleUc,
       _getSchedulesUc = getSchedulesUc,
       _getSchedulesByPetUc = getSchedulesByPetUc,
       _autoGenerateSchedulesUc = autoGenerateSchedulesUc,
       _updateScheduleUc = updateScheduleUc,
       super(ScheduleInicial()) {
    on<ScheduleCreatePressed>(_onScheduleCreatePressed);
    on<ScheduleGetRequested>(_onScheduleDetailRequested);
    on<ScheduleListRequested>(_onScheduleListRequested);
    on<ScheduleListPetRequested>(_onScheduleListByPetRequested);
    on<ScheduleCreateMultipleRequested>(_onScheduleCreateMultipleRequested);
    on<AutoGenerateSchedulesRequested>(_onAutoGenerateSchedulesRequested);
    on<ScheduleUpdatePressed>(_onScheduleUpdatePressed);
  }

  Future<void> _onScheduleCreatePressed(
    ScheduleCreatePressed event,
    Emitter<ScheduleState> emit,
  ) async {
    emit(ScheduleLoading());
    final result = await _createScheduleUc(
      event.time,
      event.amount,
      event.petId,
    );
    result.fold(
      (failure) => emit(ScheduleError(message: failure.message)),
      (schedule) => emit(ScheduleDetailLoaded(schedule: schedule)),
    );
  }

  Future<void> _onScheduleCreateMultipleRequested(
    ScheduleCreateMultipleRequested event,
    Emitter<ScheduleState> emit,
  ) async {
    emit(ScheduleLoading()); // 💡 Un solo estado de carga al inicio

    // 1. Mapeamos a una lista de Futures tradicionales
    final futures = event.times
        .map((time) => _createScheduleUc(time, event.amount, event.petId))
        .toList();

    // 2. Esperamos a que TODAS las peticiones HTTP terminen en paralelo
    final results = await Future.wait(futures);

    // 3. Verificamos si AL MENOS una de las peticiones devolvió un Left (Failure)
    bool tieneError = false;
    String mensajeError = "Error al automatizar los horarios";

    for (final res in results) {
      res.fold(
        (failure) {
          tieneError = true;
          // Si tu objeto Failure tiene un mensaje descriptivo, lo extraemos aquí:
          // mensajeError = failure.message;
        },
        (schedule) => null, // Éxito individual, no hacemos nada aún
      );
      if (tieneError) break; // Si ya falló uno, salimos del ciclo
    }

    // 4. Decidimos qué estado emitir basándonos en el lote completo
    if (tieneError) {
      emit(ScheduleError(message: mensajeError));
    } else {
      add(ScheduleListPetRequested(petId: event.petId));
    }
  }

  Future<void> _onScheduleDetailRequested(
    ScheduleGetRequested event,
    Emitter<ScheduleState> emit,
  ) async {
    emit(ScheduleLoading());

    final result = await _getScheduleUc(event.sheduleId, event.petId);
    result.fold(
      (failure) => emit(ScheduleError(message: failure.message)),
      (schedule) => emit(ScheduleDetailLoaded(schedule: schedule)),
    );
  }

  Future<void> _onScheduleListRequested(
    ScheduleListRequested event,
    Emitter<ScheduleState> emit,
  ) async {
    emit(ScheduleLoading());
    final result = await _getSchedulesUc();
    result.fold(
      (failure) => emit(ScheduleError(message: failure.message)),
      (fetchResult) => emit(ScheduleLoaded(schedules: fetchResult.schedules, isOffline: fetchResult.isOffline)),
    );
  }

  Future<void> _onScheduleListByPetRequested(
    ScheduleListPetRequested event,
    Emitter<ScheduleState> emit,
  ) async {
    emit(ScheduleLoading());
    final result = await _getSchedulesByPetUc(event.petId);
    result.fold(
      (failure) => emit(ScheduleError(message: failure.message)),
      (fetchResult) => emit(ScheduleLoaded(schedules: fetchResult.schedules, isOffline: fetchResult.isOffline)),
    );
  }

  Future<void> _onAutoGenerateSchedulesRequested(
    AutoGenerateSchedulesRequested event,
    Emitter<ScheduleState> emit,
  ) async {
    emit(ScheduleLoading());
    final result = await _autoGenerateSchedulesUc(
      event.petId,
      event.foodKcalPerKg,
      event.bcs,
      event.mcs,
      event.activityLevel,
      event.mealsPerDay,
    );
    result.fold(
      (failure) => emit(ScheduleError(message: failure.message)),
      (fetchResult) => emit(ScheduleLoaded(schedules: fetchResult.schedules, isOffline: fetchResult.isOffline)),
    );
  }

  Future<void> _onScheduleUpdatePressed(
    ScheduleUpdatePressed event,
    Emitter<ScheduleState> emit,
  ) async {
    emit(ScheduleLoading());
    final result = await _updateScheduleUc(
      event.scheduleId,
      time: event.time,
      amount: event.amount,
    );
    result.fold(
      (failure) => emit(ScheduleError(message: failure.message)),
      (_) {
        add(ScheduleListPetRequested(petId: event.petId));
      },
    );
  }
}
