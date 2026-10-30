import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/error/api_exception.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/offline/sync_service.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart';
import 'package:app_movil_pdam/features/dispenser/data/services/ble_provisioning_service.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser_food_status.dart';

/// Almacenamiento seguro en memoria para no tocar `flutter_secure_storage`
/// en las pruebas del repositorio.
class _FakeStorageService implements StorageService {
  final Map<String, String> _values = {};

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    _values.remove(key);
    return const Right(null);
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async {
    return Right(_values[key]);
  }

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    _values[key] = value;
    return const Right(null);
  }
}

class MockDispenserRemoteDatasource implements DispenserRemoteDatasource {
  bool shouldThrow = false;
  Object? throwObject;
  Dispenser? mockDispenser;

  int? refillDispenserId;
  double? refillAmount;
  String? refillUnit;
  String? refillOperationId;
  String? refillOrigen;
  Dispenser? refillResult;
  Object? refillThrowObject;

  @override
  Future<Dispenser> associateDispenser(String macAddress, int petId, String secretKeyQr) async {
    if (shouldThrow) {
      if (throwObject != null) {
        throw throwObject!;
      }
      throw DioException(
        requestOptions: RequestOptions(path: '/dispenser'),
        message: 'Connection failed',
        type: DioExceptionType.connectionError,
      );
    }
    return mockDispenser ?? Dispenser(id: 1, macAddress: macAddress, pendingDispensing: false, isActive: true, petId: petId);
  }

  @override
  Future<bool> activateDispenser(int dispenserId, int petId) async {
    if (shouldThrow) {
      if (throwObject != null) {
        throw throwObject!;
      }
      throw DioException(
        requestOptions: RequestOptions(path: '/dispenser/$dispenserId/activate'),
        message: 'Connection failed',
        type: DioExceptionType.connectionError,
      );
    }
    return true;
  }

  @override
  Future<Map<String, dynamic>> checkPendingTask(String macAddress) async => {};

  @override
  Future<bool> dasactivateDispenser(int dispenserId, int petId) async {
    if (shouldThrow) {
      if (throwObject != null) {
        throw throwObject!;
      }
      throw DioException(
        requestOptions: RequestOptions(path: '/dispenser/$dispenserId/deactivate'),
        message: 'Connection failed',
        type: DioExceptionType.connectionError,
      );
    }
    return true;
  }

  @override
  Future<bool> deleteDispenserByPet(int petId) async => true;

  @override
  Future<Dispenser> refillDispenser(
    int dispenserId,
    double amount,
    String unit, {
    required String operationId,
    String origen = 'servidor',
  }) async {
    if (refillThrowObject != null) {
      throw refillThrowObject!;
    }
    if (shouldThrow) {
      if (throwObject != null) {
        throw throwObject!;
      }
      throw DioException(
        requestOptions: RequestOptions(path: '/dispenser/$dispenserId/refill'),
        message: 'Connection failed',
        type: DioExceptionType.connectionError,
      );
    }
    refillDispenserId = dispenserId;
    refillAmount = amount;
    refillUnit = unit;
    refillOperationId = operationId;
    refillOrigen = origen;
    return refillResult ??
        Dispenser(
          id: dispenserId,
          macAddress: 'AA:BB:CC:DD:EE:FF',
          pendingDispensing: false,
          isActive: true,
          petId: 1,
          currentFoodGrams: amount,
        );
  }

  @override
  Future<Dispenser> getDispenserByPet(int petId) async {
    if (shouldThrow) {
      if (throwObject != null) {
        throw throwObject!;
      }
      throw DioException(
        requestOptions: RequestOptions(path: '/dispenser/$petId'),
        message: 'Connection failed',
        type: DioExceptionType.connectionError,
      );
    }
    return mockDispenser ?? Dispenser(id: 1, macAddress: 'AA:BB:CC:DD:EE:FF', pendingDispensing: false, isActive: true, petId: petId);
  }

  @override
  Future<Dispenser> updateDispenserMac(int dispenserId, int petId, String macAddress) async {
    if (shouldThrow) {
      if (throwObject != null) {
        throw throwObject!;
      }
      throw DioException(
        requestOptions: RequestOptions(path: '/dispenser/$dispenserId/mac'),
        message: 'Connection failed',
        type: DioExceptionType.connectionError,
      );
    }
    return mockDispenser ?? Dispenser(id: dispenserId, macAddress: macAddress, pendingDispensing: false, isActive: true, petId: petId);
  }
}

class MockLocalDispenserDatasource implements LocalDispenserDatasource {
  Dispenser? savedDispenser;
  bool savedSynced = true;
  String? savedSecret;
  double? savedPendingRefillGrams;
  String? savedPendingRefillId;
  final List<String?> savedPendingRefillIds = [];
  Dispenser? localReturn;
  int? remoteId;
  int saveCount = 0;

  @override
  Future<void> cacheDispenser(Dispenser dispenser) async {
    await saveLocalDispenser(dispenser);
  }

  @override
  Future<void> deleteLocalDispenser(int petId) async {
    savedDispenser = null;
  }

  @override
  Future<List<Dispenser>> getLocalDispensers() async {
    return savedDispenser == null ? <Dispenser>[] : <Dispenser>[savedDispenser!];
  }

  @override
  Future<Dispenser?> getLocalDispenserByPet(int petId) async {
    return localReturn ?? savedDispenser;
  }

  @override
  Future<void> saveLocalDispenser(
    Dispenser dispenser, {
    bool isSynced = true,
    String? secretKeyQr,
    double? pendingRefillGrams,
    String? pendingRefillId,
  }) async {
    final resolvedPending = pendingRefillGrams ??
        savedDispenser?.pendingRefillGrams ??
        dispenser.pendingRefillGrams;
    final resolvedId = pendingRefillId == null
        ? (savedDispenser?.pendingRefillId ?? dispenser.pendingRefillId)
        : (pendingRefillId.isEmpty ? null : pendingRefillId);
    savedDispenser = dispenser.copyWith(
      pendingRefillGrams: resolvedPending,
      pendingRefillId: resolvedId,
      clearPendingRefillId: resolvedId == null,
    );
    savedPendingRefillGrams = resolvedPending;
    savedPendingRefillId = resolvedId;
    savedPendingRefillIds.add(resolvedId);
    savedSynced = isSynced;
    savedSecret = secretKeyQr;
    saveCount++;
  }

  @override
  Future<int?> getRemoteIdByDeviceId(String deviceId) async => remoteId;
}

class MockSyncService implements SyncService {
  bool _hasConnection = true;
  final DioClient? _dioClient;

  MockSyncService({DioClient? dioClient}) : _dioClient = dioClient;

  void setHasConnection(bool value) => _hasConnection = value;

  @override
  Future<bool> hasConnection() async => _hasConnection;

  @override
  Future<bool> synchronizeBatch({required double lastSyncTimestamp, required List<Map<String, dynamic>> localItems}) async {
    return false;
  }

  @override
  Future<bool> synchronizePendingData({String? testDirectory, double lastSyncTimestamp = 0.0}) async {
    return false;
  }

  @override
  DioClient get dioClient => _dioClient!;
}

void main() {
  late DispenserRepositoryImpl repository;
  late MockDispenserRemoteDatasource remoteDatasource;
  late MockLocalDispenserDatasource localDatasource;
  late MockSyncService syncService;

  setUp(() {
    remoteDatasource = MockDispenserRemoteDatasource();
    localDatasource = MockLocalDispenserDatasource();
    syncService = MockSyncService();
    final storageService = _FakeStorageService();
    repository = DispenserRepositoryImpl(
      dispenserRemoteDatasource: remoteDatasource,
      localDispenserDatasource: localDatasource,
      syncService: syncService,
      bleService: BleProvisioningService(),
      dioClient: DioClient(storageService, sessionEvents: SessionEvents()),
      storageService: storageService,
    );
  });

  group('associateDispenser', () {
    test('online debe guardar localmente con isSynced true', () async {
      syncService.setHasConnection(true);
      final result = await repository.associateDispenser('11:22:33:44:55:66', 1, 'secret');

      expect(result.isRight(), true);
      expect(localDatasource.savedSynced, true);
      expect(localDatasource.savedDispenser?.macAddress, '11:22:33:44:55:66');
    });

    test('offline guarda con isSynced: false - debe quedar en Left(ConnectivityRequiredFailures) y con localDatasource.savedDispenser == null', () async {
      syncService.setHasConnection(false);

      final result = await repository.associateDispenser('AA:BB:CC:DD:EE:FF', 1, 'secret');

      expect(result.isLeft(), true);
      result.fold(
        (l) => expect(l, isA<ConnectivityRequiredFailures>()),
        (r) => fail('No debería devolver Right'),
      );
      expect(localDatasource.savedDispenser, isNull);
    });
  });

  group('conflictos y formato - associateDispenser', () {
    test('conflicto mac_already_registered - retorna Left(MacAlreadyRegisteredFailures)', () async {
      syncService.setHasConnection(true);
      remoteDatasource.shouldThrow = true;
      remoteDatasource.throwObject = DioException(
        requestOptions: RequestOptions(path: '/dispenser'),
        response: Response(
          requestOptions: RequestOptions(path: '/dispenser'),
          statusCode: 409,
          data: {
            'detail': {'code': 'mac_already_registered', 'message': 'La dirección MAC ya está registrada'}
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final result = await repository.associateDispenser('AA:BB:CC:DD:EE:FF', 1, 'secret');
      expect(result.isLeft(), true);
      result.fold((l) => expect(l, isA<MacAlreadyRegisteredFailures>()), (r) => fail('fail'));
      expect(localDatasource.savedDispenser, isNull);
    });

    test('formato inválido - retorna Left(InvalidMacFormatFailures)', () async {
      syncService.setHasConnection(true);
      remoteDatasource.shouldThrow = true;
      remoteDatasource.throwObject = DioException(
        requestOptions: RequestOptions(path: '/dispenser'),
        response: Response(
          requestOptions: RequestOptions(path: '/dispenser'),
          statusCode: 400,
          data: {
            'detail': {'code': 'mac_invalid_format', 'message': 'Formato de MAC inválido'}
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final result = await repository.associateDispenser('ZZ:ZZ:ZZ:ZZ:ZZ:ZZ', 1, 'secret');
      expect(result.isLeft(), true);
      result.fold((l) => expect(l, isA<InvalidMacFormatFailures>()), (r) => fail('fail'));
      expect(localDatasource.savedDispenser, isNull);
    });

    test('éxito con isSynced = true', () async {
      syncService.setHasConnection(true);
      remoteDatasource.mockDispenser = Dispenser(id: 5, macAddress: 'AA:BB:CC:DD:EE:FF', pendingDispensing: false, isActive: true, petId: 1);
      final result = await repository.associateDispenser('AA:BB:CC:DD:EE:FF', 1, 'secret');
      expect(result.isRight(), true);
      expect(localDatasource.savedSynced, true);
      expect(localDatasource.savedDispenser?.id, 5);
    });
  });

  group('updateDispenserMac', () {
    test('offline sin escritura en el datasource local - retorna Left(ConnectivityRequiredFailures)', () async {
      syncService.setHasConnection(false);
      localDatasource.savedDispenser = Dispenser(id: 1, macAddress: 'AA:BB:CC:DD:EE:FF', pendingDispensing: false, isActive: true, petId: 1);

      final result = await repository.updateDispenserMac(1, 1, '11:22:33:44:55:66');
      expect(result.isLeft(), true);
      result.fold((l) => expect(l, isA<ConnectivityRequiredFailures>()), (r) => fail('fail'));
      expect(localDatasource.savedDispenser?.macAddress, 'AA:BB:CC:DD:EE:FF');
    });

    test('online éxito guarda local con isSynced true', () async {
      syncService.setHasConnection(true);
      remoteDatasource.mockDispenser = Dispenser(id: 1, macAddress: '11:22:33:44:55:66', pendingDispensing: false, isActive: true, petId: 1);
      final result = await repository.updateDispenserMac(1, 1, '11:22:33:44:55:66');
      expect(result.isRight(), true);
      expect(localDatasource.savedSynced, true);
      expect(localDatasource.savedDispenser?.macAddress, '11:22:33:44:55:66');
    });
  });

  group('otros métodos sin conexión - conservación de comportamiento', () {
    test('getDispenserByPet sin conexión conserva comportamiento (fallback a local)', () async {
      syncService.setHasConnection(true); // el método get podría no chequear conexión igual? según T8 no toca get
      remoteDatasource.shouldThrow = true;
      localDatasource.localReturn = Dispenser(id: 2, macAddress: 'CC:DD:EE:FF:AA:BB', pendingDispensing: false, isActive: true, petId: 5);
      final result = await repository.getDispenserByPet(5);
      expect(result.isRight(), true);
      result.fold((l) => fail('fail'), (d) => expect(d.macAddress, 'CC:DD:EE:FF:AA:BB'));
    });

    test('activate sin conexión - retorna Left(ConnectivityRequiredFailures)', () async {
      syncService.setHasConnection(false);
      localDatasource.savedDispenser = Dispenser(id: 1, macAddress: 'AA:BB:CC:DD:EE:FF', pendingDispensing: false, isActive: false, petId: 1);
      final result = await repository.activateDispenser(1, 1);
      expect(result.isLeft(), true);
      result.fold((l) => expect(l, isA<ConnectivityRequiredFailures>()), (r) => fail('fail'));
      expect(localDatasource.savedDispenser?.isActive, false);
    });

    test('dasactivate sin conexión - retorna Left(ConnectivityRequiredFailures)', () async {
      syncService.setHasConnection(false);
      localDatasource.savedDispenser = Dispenser(id: 1, macAddress: 'AA:BB:CC:DD:EE:FF', pendingDispensing: false, isActive: true, petId: 1);
      final result = await repository.dasactivateDispenser(1, 1);
      expect(result.isLeft(), true);
      result.fold((l) => expect(l, isA<ConnectivityRequiredFailures>()), (r) => fail('fail'));
      expect(localDatasource.savedDispenser?.isActive, true);
    });

    test('delete sin conexión - retorna Left(ConnectivityRequiredFailures)', () async {
      syncService.setHasConnection(false);
      localDatasource.savedDispenser = Dispenser(id: 1, macAddress: 'AA:BB:CC:DD:EE:FF', pendingDispensing: false, isActive: true, petId: 1);
      final result = await repository.deleteDispenser(1);
      expect(result.isLeft(), true);
      result.fold((l) => expect(l, isA<ConnectivityRequiredFailures>()), (r) => fail('fail'));
      expect(localDatasource.savedDispenser, isNotNull);
    });
  });

  group('refreshDispensers', () {
    test('online actualiza el stock local con la respuesta del servidor (RF-4)', () async {
      syncService.setHasConnection(true);
      localDatasource.savedDispenser = Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );
      remoteDatasource.mockDispenser = Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 800.0,
      );

      await repository.refreshDispensers();

      expect(localDatasource.savedDispenser?.currentFoodGrams, 800.0);
    });

    test('offline conserva el stock local sin consultar (RF-10)', () async {
      syncService.setHasConnection(false);
      localDatasource.savedDispenser = Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );

      await repository.refreshDispensers();

      expect(localDatasource.savedDispenser?.currentFoodGrams, 1000.0);
      expect(remoteDatasource.refillDispenserId, isNull);
    });

    test('si la consulta falla conserva el stock local', () async {
      syncService.setHasConnection(true);
      remoteDatasource.shouldThrow = true;
      localDatasource.savedDispenser = Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );

      await repository.refreshDispensers();

      expect(localDatasource.savedDispenser?.currentFoodGrams, 1000.0);
    });

    test('envía el reabastecimiento pendiente y limpia el delta (RF-12)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
        pendingRefillGrams: 500.0,
      );
      remoteDatasource.refillResult = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1500.0,
      );

      await repository.refreshDispensers();

      expect(remoteDatasource.refillDispenserId, 7);
      expect(remoteDatasource.refillAmount, 500.0);
      expect(localDatasource.savedDispenser?.currentFoodGrams, 1500.0);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 0.0);
    });

    test('envía el identificador guardado y el origen de sincronización (RF-11)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
        pendingRefillGrams: 500.0,
        pendingRefillId: 'operacion-guardada',
      );
      remoteDatasource.refillResult = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1500.0,
      );

      await repository.refreshDispensers();

      expect(remoteDatasource.refillOperationId, 'operacion-guardada');
      expect(remoteDatasource.refillOrigen, 'sincronizacion_sin_conexion');
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 0.0);
      expect(localDatasource.savedDispenser?.pendingRefillId, isNull);
    });

    test('genera y persiste el identificador si el pendiente no lo tiene (RF-11)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
        pendingRefillGrams: 500.0,
      );
      remoteDatasource.refillResult = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1500.0,
      );

      await repository.refreshDispensers();

      expect(remoteDatasource.refillOperationId, isNotNull);
      expect(remoteDatasource.refillOperationId, isNotEmpty);
      expect(
        localDatasource.savedPendingRefillIds,
        contains(remoteDatasource.refillOperationId),
      );
    });

    test('si el servidor rechaza el pendiente reconcilia y lo limpia (RF-12)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 4900.0,
        pendingRefillGrams: 500.0,
      );
      remoteDatasource.refillThrowObject = const ApiException(
        code: 'supera_capacidad',
        message: 'El reabastecimiento supera el límite de 5 kg',
        status: 400,
      );
      remoteDatasource.mockDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 4950.0,
      );

      await repository.refreshDispensers();

      expect(localDatasource.savedDispenser?.currentFoodGrams, 4950.0);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 0.0);
    });

    test('si falla la red conserva el delta pendiente (RF-12)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1500.0,
        pendingRefillGrams: 500.0,
      );
      remoteDatasource.shouldThrow = true;

      await repository.refreshDispensers();

      expect(localDatasource.savedDispenser?.currentFoodGrams, 1500.0);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 500.0);
    });
  });

  group('refillFood', () {
    test('online suma en el servidor y limpia el pendiente (RF-7)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );
      remoteDatasource.refillResult = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1500.0,
      );

      await repository.refillFood('7', 500.0);

      expect(remoteDatasource.refillDispenserId, 7);
      expect(remoteDatasource.refillAmount, 500.0);
      expect(remoteDatasource.refillUnit, 'g');
      expect(localDatasource.savedDispenser?.currentFoodGrams, 1500.0);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 0.0);
    });

    test('envía siempre un identificador de operación con conexión (RF-11)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );

      await repository.refillFood('7', 500.0);

      expect(remoteDatasource.refillOperationId, isNotNull);
      expect(remoteDatasource.refillOperationId, isNotEmpty);
      expect(remoteDatasource.refillOrigen, 'servidor');
    });

    test('offline persiste el identificador junto al pendiente (RF-11)', () async {
      syncService.setHasConnection(false);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );

      await repository.refillFood('7', 500.0);

      final id = localDatasource.savedDispenser?.pendingRefillId;
      expect(id, isNotNull);
      expect(id, isNotEmpty);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 500.0);
    });

    test('un segundo reabastecimiento offline reutiliza el identificador (RF-11)', () async {
      syncService.setHasConnection(false);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );

      await repository.refillFood('7', 200.0);
      final primero = localDatasource.savedDispenser?.pendingRefillId;
      await repository.refillFood('7', 300.0);

      expect(primero, isNotNull);
      expect(localDatasource.savedDispenser?.pendingRefillId, primero);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 500.0);
    });

    test('un fallo no-límite conserva el mismo identificador para reenviar (RF-11)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );
      remoteDatasource.shouldThrow = true;

      await repository.refillFood('7', 500.0);

      final id = localDatasource.savedDispenser?.pendingRefillId;
      expect(id, isNotNull);
      expect(id, isNotEmpty);
      expect(id, localDatasource.savedPendingRefillId);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 500.0);
    });

    test('online envía también el pendiente acumulado (RF-12)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
        pendingRefillGrams: 500.0,
      );
      remoteDatasource.refillResult = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 2000.0,
      );

      await repository.refillFood('7', 500.0);

      expect(remoteDatasource.refillAmount, 1000.0);
      expect(localDatasource.savedDispenser?.currentFoodGrams, 2000.0);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 0.0);
    });

    test('online con un pendiente previo reutiliza su identificador (RF-11)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
        pendingRefillGrams: 500.0,
        pendingRefillId: 'operacion-previa',
      );

      await repository.refillFood('7', 500.0);

      expect(remoteDatasource.refillOperationId, 'operacion-previa');
      expect(remoteDatasource.refillAmount, 1000.0);
    });

    test('offline aplica el stock local y deja el delta pendiente (RF-11)', () async {
      syncService.setHasConnection(false);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );

      await repository.refillFood('7', 500.0);

      expect(localDatasource.savedDispenser?.currentFoodGrams, 1500.0);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 500.0);
      expect(remoteDatasource.refillDispenserId, isNull);
    });

    test('offline rechaza si la suma supera la capacidad (RF-8)', () async {
      syncService.setHasConnection(false);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 4900.0,
      );

      await expectLater(
        repository.refillFood('7', 200.0),
        throwsA(isA<RefillLimitException>()),
      );
      expect(localDatasource.savedDispenser?.currentFoodGrams, 4900.0);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 0.0);
    });

    test('sin identificador remoto guarda local y deja pendiente (RF-11)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = null;
      localDatasource.savedDispenser = Dispenser(
        id: 0,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );

      await repository.refillFood('AA:BB:CC:DD:EE:FF', 500.0);

      expect(localDatasource.savedDispenser?.currentFoodGrams, 1500.0);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 500.0);
      expect(remoteDatasource.refillDispenserId, isNull);
    });

    test('si el servidor rechaza por límite lanza RefillLimitException (RF-8)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );
      remoteDatasource.refillThrowObject = const ApiException(
        code: 'supera_capacidad',
        message: 'El reabastecimiento supera el límite de 5 kg',
        status: 400,
      );

      await expectLater(
        repository.refillFood('7', 500.0),
        throwsA(isA<RefillLimitException>()),
      );
      expect(localDatasource.savedDispenser?.currentFoodGrams, 1000.0);
    });

    test('un fallo no-límite se guarda como pendiente y no lanza (RF-11, RF-13)', () async {
      syncService.setHasConnection(true);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );
      remoteDatasource.shouldThrow = true;

      await repository.refillFood('7', 500.0);

      expect(localDatasource.savedDispenser?.currentFoodGrams, 1500.0);
      expect(localDatasource.savedDispenser?.pendingRefillGrams, 500.0);
    });

    test('rechaza cantidad cero o negativa con RefillLimitException (RF-8)', () async {
      syncService.setHasConnection(false);
      localDatasource.remoteId = 7;
      localDatasource.savedDispenser = Dispenser(
        id: 7,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: 1,
        currentFoodGrams: 1000.0,
      );

      await expectLater(
        repository.refillFood('7', 0.0),
        throwsA(isA<RefillLimitException>()),
      );
      await expectLater(
        repository.refillFood('7', -10.0),
        throwsA(isA<RefillLimitException>()),
      );
    });
  });
}
