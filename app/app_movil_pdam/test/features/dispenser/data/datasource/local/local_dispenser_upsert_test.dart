import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory tempDir;
  late LocalDispenserDatasourceImpl datasource;

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
    datasource = LocalDispenserDatasourceImpl(testDirectory: tempDir.path);
  });

  tearDown(() async {
    try {
      await IsarService.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalDispenserDatasource Upsert Tests (RF-01, RNF-01)', () {
    test('saveLocalDispenser realiza upsert sin lanzar IsarError cuando se guarda un dispensador con la misma MAC o remoteId', () async {
      final dispenser1 = Dispenser(
        id: 100,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 4000.0,
      );

      await datasource.saveLocalDispenser(dispenser1);

      final dispenser2 = Dispenser(
        id: 100,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 3500.0,
      );

      await datasource.saveLocalDispenser(dispenser2);

      final listAfter = await datasource.getLocalDispensers();
      expect(listAfter.length, 1);
      expect(listAfter.first.currentFoodGrams, 3500.0);
    });

    test('saveLocalDispenser con id 0 (aprovisionamiento BLE) hace upsert por MAC', () async {
      final first = const Dispenser(
        id: 0,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        currentFoodGrams: 5000.0,
      );

      await datasource.saveLocalDispenser(first);
      await datasource.saveLocalDispenser(
        first.copyWith(currentFoodGrams: 4500.0),
      );

      final list = await datasource.getLocalDispensers();
      expect(list.length, 1);
      expect(list.first.currentFoodGrams, 4500.0);
    });

    test('getLocalDispensers retorna todos los dispensadores locales incluyendo con petId null (RF-03, RNF-01)', () async {
      final validDispenser = Dispenser(
        id: 101,
        macAddress: '11:22:33:44:55:66',
        isActive: true,
        petId: 5,
        currentFoodGrams: 4000.0,
      );

      final orphanDispenser = Dispenser(
        id: 102,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        currentFoodGrams: 4000.0,
      );

      await datasource.saveLocalDispenser(validDispenser);
      await datasource.saveLocalDispenser(orphanDispenser);

      final dispensers = await datasource.getLocalDispensers();
      expect(dispensers.length, 2);
    });
  });
}
