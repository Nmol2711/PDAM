import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/create_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_by_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_uc.dart';

import 'package:bloc/bloc.dart';

part 'schedule_state.dart';
part 'schedule_event.dart';

class ScheduleBloc extends Bloc<ScheduleEvent, ScheduleState> {
  final CreateScheduleUc _createScheduleUc;
  final GetScheduleUc _getScheduleUc;
  final GetSchedulesUc _getSchedulesUc;
  final GetSchedulesByPetUc _getSchedulesByPetUc;
  ScheduleBloc({
    required CreateScheduleUc createScheduleUc,
    required GetScheduleUc getScheduleUc,
    required GetSchedulesUc getSchedulesUc,
    required GetSchedulesByPetUc getSchedulesByPetUc,
  }) : _createScheduleUc = createScheduleUc,
       _getScheduleUc = getScheduleUc,
       _getSchedulesUc = getSchedulesUc,
       _getSchedulesByPetUc = getSchedulesByPetUc,
       super(ScheduleInicial()) {
    on<ScheduleCreatePressed>(_onScheduleCreatePressed);
    on<ScheduleGetRequested>(_onScheduleDetailRequested);
    on<ScheduleListRequested>(_onScheduleListRequested);
    on<ScheduleListPetRequested>(_onScheduleListByPetRequested);
    on<ScheduleCreateMultipleRequested>(_onScheduleCreateMultipleRequested);
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
      // 🔥 Si TODO salió bien, llamamos a tu manejador para refrescar la lista de la Pet
      await _onScheduleListByPetRequested(
        ScheduleListPetRequested(petId: event.petId),
        emit,
      );
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
      (schedules) => emit(ScheduleLoaded(schedules: schedules)),
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
      (schedules) => emit(ScheduleLoaded(schedules: schedules)),
    );
  }
}
