import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/local/local_log_datasource.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory tempDir;
  late LocalLogDatasource datasource;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore();
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_log_test_');
    datasource = LocalLogDatasourceImpl(testDirectory: tempDir.path);
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

  group('LocalLogDatasource Tests (RF-04, RNF-02)', () {
    test('getLocalLogs debe retornar lista vacía inicialmente en <= 100 ms', () async {
      final stopwatch = Stopwatch()..start();
      final logs = await datasource.getLocalLogs();
      stopwatch.stop();

      expect(logs, isEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(100));
    });

    test('cacheLogs y getLocalLogs deben guardar y recuperar logs con filtrado por petId y fecha en <= 100 ms', () async {
      final now = DateTime(2026, 6, 15, 10, 30);
      final logs = [
        ActivityLogEntity(id: 1, event: 'Alimentación dispensada', timestamp: now, petId: 1),
        ActivityLogEntity(id: 2, event: 'Alerta de comida baja', timestamp: now.add(const Duration(hours: 2)), petId: 2),
      ];

      final cacheWatch = Stopwatch()..start();
      await datasource.cacheLogs(logs);
      cacheWatch.stop();
      expect(cacheWatch.elapsedMilliseconds, lessThanOrEqualTo(100));

      final getWatch = Stopwatch()..start();
      final allLogs = await datasource.getLocalLogs();
      getWatch.stop();
      expect(getWatch.elapsedMilliseconds, lessThanOrEqualTo(100));
      expect(allLogs.length, 2);

      // Filtrar por petId
      final pet1Logs = await datasource.getLocalLogs(petId: 1);
      expect(pet1Logs.length, 1);
      expect(pet1Logs.first.event, 'Alimentación dispensada');

      // Filtrar por fecha
      final dateLogs = await datasource.getLocalLogs(date: '2026-06-15');
      expect(dateLogs.length, 2);
    });

    test('saveLocalLog y deleteLocalLog deben funcionar correctamente', () async {
      final log = ActivityLogEntity(
        id: 10,
        event: 'Test event',
        timestamp: DateTime.now(),
        petId: 1,
      );

      await datasource.saveLocalLog(log);
      var logs = await datasource.getLocalLogs();
      expect(logs.length, 1);

      await datasource.deleteLocalLog(10);
      logs = await datasource.getLocalLogs();
      expect(logs, isEmpty);
    });
  });
}
