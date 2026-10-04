import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/offline/sync_service.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_pet_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore();
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_sync_test_');
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

  test('SyncService puede instanciarse correctamente', () {
    final storageService = StorageServiceImpl(
      dataLocalService: const FlutterSecureStorage(),
    );
    final dioClient = DioClient(storageService);
    final syncService = SyncService(dioClient: dioClient);

    expect(syncService, isNotNull);
  });

  test('synchronizePendingData retorna false o maneja correctamente cuando no hay red', () async {
    final storageService = StorageServiceImpl(
      dataLocalService: const FlutterSecureStorage(),
    );
    final dioClient = DioClient(storageService);
    final syncService = SyncService(dioClient: dioClient);

    // Guardar una mascota no sincronizada localmente
    final petDatasource = LocalPetDatasourceImpl(testDirectory: tempDir.path);
    final pet = Pet(
      id: 100,
      name: 'OfflinePet',
      species: TypePest.canino,
      birthDate: DateTime(2021, 1, 1),
      weight: 10.0,
      reproductiveStatus: true,
    );
    await petDatasource.saveLocalPet(pet, isSynced: false);

    final result = await syncService.synchronizePendingData(testDirectory: tempDir.path);
    expect(result, isFalse);
  });
}
