import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/dispensers/data/datasources/dispensers_local_datasource.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory tempDir;
  late DispensersLocalDatasource datasource;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(download: true);
      final warmupDir = await Directory.systemTemp.createTemp('isar_warmup_');
      await IsarService.init(directory: warmupDir.path);
      await IsarService.close();
      await warmupDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_dispensers_test_');
    datasource = DispensersLocalDatasource(testDirectory: tempDir.path);
  });

  tearDown(() async {
    try {
      await IsarService.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DispensersLocalDatasource Upsert Tests (RF-01, RNF-01)', () {
    test('saveLocalDispenser realiza upsert sin lanzar IsarError cuando se guarda un dispensador con la misma MAC o remoteId', () async {
      final dispenser1 = LocalDispenser()
        ..remoteId = 100
        ..petRemoteId = 1
        ..macAddress = 'AA:BB:CC:DD:EE:FF'
        ..isActive = true
        ..pendingDispensing = false
        ..currentFoodGrams = 4000.0
        ..updatedAt = DateTime.now()
        ..isSynced = true;

      await datasource.saveLocalDispenser(dispenser1);

      final dispenser2 = LocalDispenser()
        ..remoteId = 100
        ..petRemoteId = 1
        ..macAddress = 'AA:BB:CC:DD:EE:FF'
        ..isActive = true
        ..pendingDispensing = false
        ..currentFoodGrams = 3500.0
        ..updatedAt = DateTime.now()
        ..isSynced = true;

      await datasource.saveLocalDispenser(dispenser2);

      final listAfter = await datasource.getLocalDispensers();
      expect(listAfter.length, 1);
      expect(listAfter.first.currentFoodGrams, 3500.0);
    });

    test('getLocalDispensers retorna todos los dispensadores locales incluyendo con petRemoteId null (RF-03, RNF-01)', () async {
      final validDispenser = LocalDispenser()
        ..remoteId = 101
        ..petRemoteId = 5
        ..macAddress = '11:22:33:44:55:66'
        ..isActive = true
        ..pendingDispensing = false
        ..currentFoodGrams = 4000.0
        ..updatedAt = DateTime.now()
        ..isSynced = true;

      final orphanDispenser = LocalDispenser()
        ..remoteId = 102
        ..petRemoteId = null
        ..macAddress = 'AA:BB:CC:DD:EE:FF'
        ..isActive = true
        ..pendingDispensing = false
        ..currentFoodGrams = 4000.0
        ..updatedAt = DateTime.now()
        ..isSynced = true;

      await datasource.saveLocalDispenser(validDispenser);
      await datasource.saveLocalDispenser(orphanDispenser);

      final dispensers = await datasource.getLocalDispensers();
      expect(dispensers.length, 2);
    });
  });
}
