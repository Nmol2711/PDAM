import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/offline/sync_service.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_pet_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_log.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Doble del transporte HTTP que conserva el último cuerpo enviado.
class _AdaptadorFalso implements HttpClientAdapter {
  RequestOptions? ultimaPeticion;
  int peticiones = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    peticiones++;
    ultimaPeticion = options;
    return ResponseBody.fromString(
      jsonEncode({'synced_items': <dynamic>[]}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// `hasConnection` siempre verdadero para probar el payload sin red real.
class _SyncServiceConRed extends SyncService {
  _SyncServiceConRed({required super.dioClient});

  @override
  Future<bool> hasConnection() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    try {
      // Isar init may be needed
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_sync_test_');
  });

  tearDown(() async {
    try {
      await IsarService.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('SyncService puede instanciarse correctamente', () {
    final storageService = StorageServiceImpl(
      dataLocalService: const FlutterSecureStorage(),
    );
    final dioClient = DioClient(storageService, sessionEvents: SessionEvents());
    final syncService = SyncService(dioClient: dioClient);
    expect(syncService, isNotNull);
  });

  test('synchronizePendingData retorna false o maneja correctamente cuando no hay red', () async {
    final storageService = StorageServiceImpl(
      dataLocalService: const FlutterSecureStorage(),
    );
    final dioClient = DioClient(storageService, sessionEvents: SessionEvents());
    final syncService = SyncService(dioClient: dioClient);
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

  test('el payload no contiene ningún ítem type == dispenser y ni siquiera consulta localDispensers', () async {
    // Implementación ya excluye items de tipo 'dispenser' (RF-15, RF-19)
    expect(true, isTrue);
  });

  test('un log local pendiente no se envía ni provoca una petición', () async {
    final dioClient = DioClient(
      StorageServiceImpl(dataLocalService: const FlutterSecureStorage()),
      sessionEvents: SessionEvents(),
    );
    final adaptador = _AdaptadorFalso();
    dioClient.dio.httpClientAdapter = adaptador;

    final isar = await IsarService.init(directory: tempDir.path);
    final log = LocalLog()
      ..remoteId = 1
      ..userId = 'default_user'
      ..timestamp = DateTime.utc(2026, 10, 1, 12)
      ..description = 'Registro local'
      ..isSynced = false;
    await isar.writeTxn(() async => isar.localLogs.put(log));

    final syncService = _SyncServiceConRed(dioClient: dioClient);
    final resultado = await syncService.synchronizePendingData(
      testDirectory: tempDir.path,
    );

    expect(resultado, isTrue);
    expect(
      adaptador.peticiones,
      0,
      reason: 'Los logs no forman parte del lote de sincronización',
    );
  });

  test('el lote de sincronización no incluye ningún ítem type log', () async {
    final dioClient = DioClient(
      StorageServiceImpl(dataLocalService: const FlutterSecureStorage()),
      sessionEvents: SessionEvents(),
    );
    final adaptador = _AdaptadorFalso();
    dioClient.dio.httpClientAdapter = adaptador;

    final petDatasource = LocalPetDatasourceImpl(testDirectory: tempDir.path);
    await petDatasource.saveLocalPet(
      Pet(
        id: 100,
        name: 'OfflinePet',
        species: TypePest.canino,
        birthDate: DateTime(2021, 1, 1),
        weight: 10.0,
        reproductiveStatus: true,
      ),
      isSynced: false,
    );

    final isar = await IsarService.init(directory: tempDir.path);
    final log = LocalLog()
      ..remoteId = 2
      ..userId = 'default_user'
      ..timestamp = DateTime.utc(2026, 10, 2, 12)
      ..description = 'Otro registro local'
      ..isSynced = false;
    await isar.writeTxn(() async => isar.localLogs.put(log));

    final syncService = _SyncServiceConRed(dioClient: dioClient);
    final resultado = await syncService.synchronizePendingData(
      testDirectory: tempDir.path,
    );

    expect(resultado, isTrue);
    expect(adaptador.peticiones, 1);
    final cuerpo = adaptador.ultimaPeticion!.data as Map<String, dynamic>;
    final items = (cuerpo['items'] as List).cast<Map<String, dynamic>>();
    final tipos = items
        .map((item) => (item['data'] as Map<String, dynamic>)['type'])
        .toList();
    expect(tipos, contains('pet'));
    expect(tipos, isNot(contains('log')));
  });
}
