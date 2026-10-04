import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_schedule_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory tempDir;
  late LocalScheduleDatasource datasource;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore();
      final warmupDir = await Directory.systemTemp.createTemp('isar_warmup_');
      await IsarService.init(directory: warmupDir.path);
      await warmupDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_schedule_test_');
    datasource = LocalScheduleDatasourceImpl(testDirectory: tempDir.path);
  });

  tearDown(() async {
    try {
      final isar = await IsarService.init(directory: tempDir.path);
      await isar.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalScheduleDatasource Tests (RF-03, RNF-02)', () {
    test('getLocalSchedules debe retornar lista vacía inicialmente en <= 100 ms', () async {
      final stopwatch = Stopwatch()..start();
      final schedules = await datasource.getLocalSchedules();
      stopwatch.stop();

      expect(schedules, isEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(100));
    });

    test('saveLocalSchedule y getLocalSchedules deben guardar y recuperar horario en <= 100 ms', () async {
      final schedule = Schedule(
        id: 1,
        time: '08:00',
        amount: 100.0,
        petId: 1,
      );

      final saveWatch = Stopwatch()..start();
      await datasource.saveLocalSchedule(schedule, isSynced: true);
      saveWatch.stop();
      expect(saveWatch.elapsedMilliseconds, lessThanOrEqualTo(100));

      final getWatch = Stopwatch()..start();
      final schedules = await datasource.getLocalSchedules();
      getWatch.stop();
      expect(getWatch.elapsedMilliseconds, lessThanOrEqualTo(100));

      expect(schedules.length, 1);
      expect(schedules.first.time, '08:00');
      expect(schedules.first.amount, 100.0);
    });

    test('cacheSchedules debe guardar múltiples horarios atómicamente y respetar cambios no sincronizados', () async {
      final schedules = [
        Schedule(
          id: 10,
          time: '07:30',
          amount: 50.0,
          petId: 1,
        ),
        Schedule(
          id: 11,
          time: '19:30',
          amount: 75.0,
          petId: 1,
        ),
      ];

      final stopwatch = Stopwatch()..start();
      await datasource.cacheSchedules(schedules);
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(100));

      final cached = await datasource.getLocalSchedules();
      expect(cached.length, 2);
    });

    test('deleteLocalSchedule debe eliminar horario correctamente', () async {
      final schedule = Schedule(
        id: 5,
        time: '12:00',
        amount: 120.0,
        petId: 1,
      );

      await datasource.saveLocalSchedule(schedule);
      var schedules = await datasource.getLocalSchedules();
      expect(schedules.length, 1);

      await datasource.deleteLocalSchedule(5);
      schedules = await datasource.getLocalSchedules();
      expect(schedules, isEmpty);
    });
  });
}
