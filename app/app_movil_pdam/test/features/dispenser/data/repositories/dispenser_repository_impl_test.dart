import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/offline/sync_service.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart';

class MockDispenserRemoteDatasource implements DispenserRemoteDatasource {
  bool shouldThrow = false;
  Object? throwObject;
  Dispenser? mockDispenser;

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
  Dispenser? localReturn;

  @override
  Future<void> cacheDispenser(Dispenser dispenser) async {
    savedDispenser = dispenser;
  }

  @override
  Future<void> deleteLocalDispenser(int petId) async {
    savedDispenser = null;
  }

  @override
  Future<Dispenser?> getLocalDispenserByPet(int petId) async {
    return localReturn ?? savedDispenser;
  }

  @override
  Future<void> saveLocalDispenser(Dispenser dispenser, {bool isSynced = true, String? secretKeyQr}) async {
    savedDispenser = dispenser;
    savedSynced = isSynced;
    savedSecret = secretKeyQr;
  }
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
    repository = DispenserRepositoryImpl(
      dispenserRemoteDatasource: remoteDatasource,
      localDispenserDatasource: localDatasource,
      syncService: syncService,
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
}
