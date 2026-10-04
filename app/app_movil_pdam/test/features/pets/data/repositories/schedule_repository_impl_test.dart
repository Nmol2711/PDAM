import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/remote/schedule_remote_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_schedule_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/repository_impl/schedule_repository_impl.dart';

class MockScheduleRemoteDatasource implements ScheduleRemoteDatasource {
  bool shouldThrow = false;
  Schedule? mockSchedule;
  List<Schedule> mockSchedules = [];

  @override
  Future<List<Schedule>> autoGenerateSchedules(int petId, double foodKcalPerKg, int bcs, String mcs, String activityLevel, int mealsPerDay) async {
    if (shouldThrow) throw Exception('Server offline');
    return mockSchedules;
  }

  @override
  Future<Schedule> createSchedule(String time, double amount, int petId) async {
    if (shouldThrow) throw Exception('Server offline');
    return mockSchedule ?? Schedule(id: 1, time: time, amount: amount, petId: petId);
  }

  @override
  Future<bool> deleteSchedule(int id) async {
    if (shouldThrow) throw Exception('Server offline');
    return true;
  }

  @override
  Future<Schedule> getSchedule(int id, int petId) async {
    if (shouldThrow) throw Exception('Server offline');
    return mockSchedule ?? Schedule(id: id, time: '08:00', amount: 100.0, petId: petId);
  }

  @override
  Future<List<Schedule>> getSchedules() async {
    if (shouldThrow) throw Exception('Server offline');
    return mockSchedules;
  }

  @override
  Future<List<Schedule>> getSchedulesByPet(int petId) async {
    if (shouldThrow) throw Exception('Server offline');
    return mockSchedules;
  }

  @override
  Future<Schedule> updateSchedule(int id, {String? time, double? amount}) async {
    if (shouldThrow) throw Exception('Server offline');
    return mockSchedule ?? Schedule(id: id, time: time ?? '09:00', amount: amount ?? 50.0, petId: 1);
  }
}

class MockLocalScheduleDatasource implements LocalScheduleDatasource {
  List<Schedule> localSchedules = [];
  bool savedSynced = true;

  @override
  Future<void> cacheSchedules(List<Schedule> schedules) async {
    localSchedules = List.from(schedules);
  }

  @override
  Future<void> deleteLocalSchedule(int scheduleId) async {
    localSchedules.removeWhere((s) => s.id == scheduleId);
  }

  @override
  Future<List<Schedule>> getLocalSchedules({int? petId}) async {
    if (petId != null) {
      return localSchedules.where((s) => s.petId == petId).toList();
    }
    return localSchedules;
  }

  @override
  Future<void> saveLocalSchedule(Schedule schedule, {bool isSynced = true}) async {
    savedSynced = isSynced;
    final index = localSchedules.indexWhere((s) => s.id == schedule.id);
    if (index >= 0) {
      localSchedules[index] = schedule;
    } else {
      localSchedules.add(schedule);
    }
  }
}

void main() {
  late ScheduleRepositoryImpl repository;
  late MockScheduleRemoteDatasource remoteDatasource;
  late MockLocalScheduleDatasource localDatasource;

  setUp(() {
    remoteDatasource = MockScheduleRemoteDatasource();
    localDatasource = MockLocalScheduleDatasource();
    repository = ScheduleRepositoryImpl(
      scheduleRemoteDatasource: remoteDatasource,
      localScheduleDatasource: localDatasource,
    );
  });

  test('createShedule falla si el formato de hora es inválido', () async {
    final result = await repository.createShedule('invalid-time', 100.0, 1);
    expect(result.isLeft(), true);
  });

  test('createShedule con formato válido guarda localmente y remoto', () async {
    final result = await repository.createShedule('08:00', 100.0, 1);
    expect(result.isRight(), true);
    expect(localDatasource.savedSynced, true);
  });

  test('getShedulesByPet hace fallback local cuando falla la red', () async {
    localDatasource.localSchedules = [
      Schedule(id: 1, time: '07:00', amount: 80.0, petId: 1)
    ];
    remoteDatasource.shouldThrow = true;

    final result = await repository.getShedulesByPet(1);

    expect(result.isRight(), true);
    result.fold(
      (l) => fail('No debería fallar'),
      (fetchResult) {
        expect(fetchResult.isOffline, true);
        expect(fetchResult.schedules.length, 1);
      },
    );
  });
}
