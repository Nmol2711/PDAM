import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory tempDir;
  late LocalDispenserDatasource datasource;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore();
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_dispenser_test_');
    datasource = LocalDispenserDatasourceImpl(testDirectory: tempDir.path);
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

  group('LocalDispenserDatasource Tests (RF-07, RNF-02)', () {
    test('getLocalDispenserByPet debe retornar null si no existe', () async {
      final dispenser = await datasource.getLocalDispenserByPet(1);
      expect(dispenser, isNull);
    });

    test('saveLocalDispenser y getLocalDispenserByPet deben guardar y recuperar dispensador en <= 100 ms', () async {
      final dispenser = Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        pendingDispensing: false,
        isActive: true,
        petId: 1,
      );

      final watch = Stopwatch()..start();
      await datasource.saveLocalDispenser(dispenser, isSynced: false, secretKeyQr: 'secret123');
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThanOrEqualTo(100));

      final retrieved = await datasource.getLocalDispenserByPet(1);
      expect(retrieved, isNotNull);
      expect(retrieved!.macAddress, 'AA:BB:CC:DD:EE:FF');
    });

    test('deleteLocalDispenser debe eliminar dispensador local', () async {
      final dispenser = Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        pendingDispensing: false,
        isActive: true,
        petId: 2,
      );

      await datasource.saveLocalDispenser(dispenser);
      var retrieved = await datasource.getLocalDispenserByPet(2);
      expect(retrieved, isNotNull);

      await datasource.deleteLocalDispenser(2);
      retrieved = await datasource.getLocalDispenserByPet(2);
      expect(retrieved, isNull);
    });
  });
}
