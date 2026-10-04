import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/create_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/get_schedules_by_pet_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/auto_generate_schedules_uc.dart';
import 'package:app_movil_pdam/features/pets/domain/use_case/schedule/update_schedule_uc.dart';
import 'package:app_movil_pdam/features/pets/presentation/bloc/schedule_bloc/schedule_bloc.dart';

class MockScheduleRepository implements ScheduleRepositories {
  bool shouldFail = false;
  List<Schedule> schedules = [];

  @override
  Future<Either<Failures, Schedule>> createShedule(String time, double amount, int petId) async {
    if (shouldFail) {
      return Left(ServerFailures('Error al crear horario'));
    }
    final newSchedule = Schedule(id: DateTime.now().millisecondsSinceEpoch, time: time, amount: amount, petId: petId);
    schedules.add(newSchedule);
    return Right(newSchedule);
  }

  @override
  Future<Either<Failures, Schedule>> getShedule(int id, int petId) async {
    try {
      final s = schedules.firstWhere((element) => element.id == id);
      return Right(s);
    } catch (_) {
      return Left(ServerFailures('No encontrado'));
    }
  }

  @override
  Future<Either<Failures, ScheduleFetchResult>> getShedules() async {
    if (shouldFail) {
      return Left(ServerFailures('Error de red'));
    }
    return Right(ScheduleFetchResult(schedules: schedules, isOffline: false));
  }

  @override
  Future<Either<Failures, ScheduleFetchResult>> getShedulesByPet(int petId) async {
    if (shouldFail) {
      return Left(ServerFailures('Error de red'));
    }
    final petSchedules = schedules.where((s) => s.petId == petId).toList();
    return Right(ScheduleFetchResult(schedules: petSchedules, isOffline: false));
  }

  @override
  Future<Either<Failures, ScheduleFetchResult>> autoGenerateSchedules(int petId, double foodKcalPerKg, int bcs, String mcs, String activityLevel, int mealsPerDay) async {
    return Right(ScheduleFetchResult(schedules: schedules, isOffline: false));
  }

  @override
  Future<Either<Failures, bool>> deleteShedule(int id) async {
    schedules.removeWhere((s) => s.id == id);
    return const Right(true);
  }

  @override
  Future<Either<Failures, Schedule>> updateShedule(int id, {String? time, double? amount}) async {
    final index = schedules.indexWhere((s) => s.id == id);
    if (index >= 0) {
      final existing = schedules[index];
      final updated = Schedule(
        id: existing.id,
        time: time ?? existing.time,
        amount: amount ?? existing.amount,
        petId: existing.petId,
      );
      schedules[index] = updated;
      return Right(updated);
    }
    return Left(ServerFailures('No encontrado'));
  }
}

void main() {
  late ScheduleBloc scheduleBloc;
  late MockScheduleRepository mockRepository;

  setUp(() {
    mockRepository = MockScheduleRepository();
    scheduleBloc = ScheduleBloc(
      createScheduleUc: CreateScheduleUc(repository: mockRepository),
      getScheduleUc: GetScheduleUc(repository: mockRepository),
      getSchedulesUc: GetSchedulesUc(repository: mockRepository),
      getSchedulesByPetUc: GetSchedulesByPetUc(repository: mockRepository),
      autoGenerateSchedulesUc: AutoGenerateSchedulesUc(repository: mockRepository),
      updateScheduleUc: UpdateScheduleUc(repository: mockRepository),
    );
  });

  test('estado inicial debe ser ScheduleInicial', () {
    expect(scheduleBloc.state, isA<ScheduleInicial>());
  });

  test('ScheduleCreatePressed añade horario exitosamente y emite ScheduleLoaded con actualización optimista', () async {
    mockRepository.schedules = [
      Schedule(id: 1, time: '08:00', amount: 100.0, petId: 1)
    ];

    final expectedStates = [
      isA<ScheduleLoading>(),
      isA<ScheduleLoaded>(),
    ];

    expectLater(scheduleBloc.stream, emitsInOrder(expectedStates));

    scheduleBloc.add(const ScheduleCreatePressed(time: '12:00', amount: 150.0, petId: 1));
  });

  test('ScheduleCreatePressed emite ScheduleError cuando falla la creación', () async {
    mockRepository.shouldFail = true;

    final expectedStates = [
      isA<ScheduleLoading>(),
      isA<ScheduleError>(),
    ];

    expectLater(scheduleBloc.stream, emitsInOrder(expectedStates));

    scheduleBloc.add(const ScheduleCreatePressed(time: '12:00', amount: 150.0, petId: 1));
  });

  test('ScheduleListPetRequested carga horarios por mascota correctamente', () async {
    mockRepository.schedules = [
      Schedule(id: 1, time: '08:00', amount: 100.0, petId: 1)
    ];

    final expectedStates = [
      isA<ScheduleLoading>(),
      isA<ScheduleLoaded>(),
    ];

    expectLater(scheduleBloc.stream, emitsInOrder(expectedStates));

    scheduleBloc.add(const ScheduleListPetRequested(petId: 1));
  });
}
