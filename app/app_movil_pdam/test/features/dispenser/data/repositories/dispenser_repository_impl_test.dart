import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart';
import 'package:dio/dio.dart';

class MockDispenserRemoteDatasource implements DispenserRemoteDatasource {
  bool shouldThrow = false;
  Dispenser? mockDispenser;

  @override
  Future<Dispenser> associateDispenser(String macAddress, int petId, String secretKeyQr) async {
    if (shouldThrow) {
      throw DioException(
        requestOptions: RequestOptions(path: '/dispenser'),
        message: 'Connection failed',
        type: DioExceptionType.connectionError,
      );
    }
    return mockDispenser ?? Dispenser(id: 1, macAddress: macAddress, pendingDispensing: false, isActive: true, petId: petId);
  }

  @override
  Future<bool> activateDispenser(int dispenserId, int petId) async => true;

  @override
  Future<Map<String, dynamic>> checkPendingTask(String macAddress) async => {};

  @override
  Future<bool> dasactivateDispenser(int dispenserId, int petId) async => true;

  @override
  Future<bool> deleteDispenserByPet(int petId) async => true;

  @override
  Future<Dispenser> getDispenserByPet(int petId) async {
    if (shouldThrow) {
      throw DioException(
        requestOptions: RequestOptions(path: '/dispenser/$petId'),
        message: 'Connection failed',
        type: DioExceptionType.connectionError,
      );
    }
    return mockDispenser ?? Dispenser(id: 1, macAddress: 'AA:BB:CC:DD:EE:FF', pendingDispensing: false, isActive: true, petId: petId);
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

void main() {
  late DispenserRepositoryImpl repository;
  late MockDispenserRemoteDatasource remoteDatasource;
  late MockLocalDispenserDatasource localDatasource;

  setUp(() {
    remoteDatasource = MockDispenserRemoteDatasource();
    localDatasource = MockLocalDispenserDatasource();
    repository = DispenserRepositoryImpl(
      dispenserRemoteDatasource: remoteDatasource,
      localDispenserDatasource: localDatasource,
    );
  });

  test('associateDispenser online debe guardar localmente con isSynced true', () async {
    final result = await repository.associateDispenser('11:22:33:44:55:66', 1, 'secret');

    expect(result.isRight(), true);
    expect(localDatasource.savedSynced, true);
    expect(localDatasource.savedDispenser?.macAddress, '11:22:33:44:55:66');
  });

  test('associateDispenser offline (DioException) debe interceptar error y guardar localmente con isSynced false', () async {
    remoteDatasource.shouldThrow = true;

    final result = await repository.associateDispenser('AA:BB:CC:DD:EE:FF', 1, 'secret');

    expect(result.isRight(), true);
    expect(localDatasource.savedSynced, false);
    expect(localDatasource.savedDispenser?.macAddress, 'AA:BB:CC:DD:EE:FF');
    result.fold(
      (l) => fail('No debería fallar'),
      (dispenser) => expect(dispenser.macAddress, 'AA:BB:CC:DD:EE:FF'),
    );
  });

  test('getDispenserByPet offline debe hacer fallback al datasource local', () async {
    remoteDatasource.shouldThrow = true;
    localDatasource.localReturn = Dispenser(
      id: 2,
      macAddress: 'CC:DD:EE:FF:AA:BB',
      pendingDispensing: false,
      isActive: true,
      petId: 5,
    );

    final result = await repository.getDispenserByPet(5);

    expect(result.isRight(), true);
    result.fold(
      (l) => fail('No debería fallar'),
      (dispenser) => expect(dispenser.macAddress, 'CC:DD:EE:FF:AA:BB'),
    );
  });
}
