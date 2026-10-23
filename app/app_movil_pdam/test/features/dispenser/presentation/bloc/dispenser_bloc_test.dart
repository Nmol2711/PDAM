import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/activate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/associate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/dasactivate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/delete_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/get_dispenser_by_pet_uc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:dartz/dartz.dart';

class MockDispenserRepository implements DispenserRepositories {
  final List<Dispenser> mockDispensers;
  final bool shouldFail;
  final bool failActivate;
  final bool failDeactivate;
  final bool failDelete;

  MockDispenserRepository({
    this.mockDispensers = const [],
    this.shouldFail = false,
    this.failActivate = false,
    this.failDeactivate = false,
    this.failDelete = false,
  });

  @override
  Future<List<Dispenser>> getLocalDispensers() async {
    if (shouldFail) throw Exception('Error al obtener dispensadores');
    return mockDispensers;
  }

  @override
  Future<void> saveLocalDispenser(Dispenser dispenser) async {
    if (shouldFail) throw Exception('Error al guardar');
  }

  @override
  Future<void> refillFood(String dispenserId, double grams) async {
    if (shouldFail) throw Exception('Error al reabastecer');
  }

  @override
  Future<void> discountFood(String dispenserId, double grams) async {
    if (shouldFail) throw Exception('Error al descontar');
  }

  @override
  Stream<List<ScannedDevice>> scanBleDispensers() async* {
    if (shouldFail) {
      throw Exception('Error de escaneo');
    }
    yield [
      const ScannedDevice(
        name: 'PDAM-Config-[123456]',
        remoteId: 'AA:BB:CC:DD:EE:FF',
        rssi: -50,
      ),
    ];
  }

  @override
  Future<void> stopBleScan() async {}

  @override
  Future<void> connectAndProvisionBle({
    required String deviceId,
    required String ssid,
    required String password,
  }) async {
    if (shouldFail) throw Exception('Error de aprovisionamiento');
  }

  @override
  Future<void> resetWifiRemote(String dispenserId) async {
    if (shouldFail) throw Exception('Error al resetear');
  }

  @override
  Future<Either<Failures, Dispenser>> associateDispenser(
    String macAddress,
    int petId,
    String secretKeyQr,
  ) async {
    if (shouldFail) return Left(ServerFailures('Error al asociar'));
    return Right(
      Dispenser(
        id: 1,
        macAddress: macAddress,
        isActive: true,
        petId: petId,
      ),
    );
  }

  @override
  Future<Either<Failures, Map<String, dynamic>>> checkPendingTask(
    String macAddress,
  ) async => const Right(<String, dynamic>{});

  @override
  Future<Either<Failures, bool>> dasactivateDispenser(
    int dispenserId,
    int petId,
  ) async {
    if (shouldFail || failDeactivate) {
      return Left(ServerFailures('Error al desactivar'));
    }
    return const Right(true);
  }

  @override
  Future<Either<Failures, bool>> deleteDispenser(int petId) async {
    if (shouldFail || failDelete) {
      return Left(ServerFailures('Error al eliminar'));
    }
    return const Right(true);
  }

  @override
  Future<Either<Failures, bool>> activateDispenser(
    int dispenserId,
    int petId,
  ) async {
    if (shouldFail || failActivate) {
      return Left(ServerFailures('Error al activar'));
    }
    return const Right(true);
  }

  @override
  Future<Either<Failures, Dispenser>> getDispenserByPet(int petId) async {
    if (shouldFail) return Left(ServerFailures('Error al obtener'));
    return Right(
      Dispenser(
        id: 1,
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        petId: petId,
      ),
    );
  }

  @override
  Future<Either<Failures, Dispenser>> updateDispenserMac(
    int dispenserId,
    int petId,
    String macAddress,
  ) async => Right(
    Dispenser(
      id: dispenserId,
      macAddress: macAddress,
      isActive: true,
      petId: petId,
    ),
  );
}

DispenserBloc buildDispenserBloc(DispenserRepositories repository) {
  return DispenserBloc(
    repository: repository,
    associateUseCase: AssociateDispenserUc(repository: repository),
    getDispenserByPetUseCase: GetDispenserByPetUc(repository: repository),
    activateUseCase: ActivateDispenserUc(repository: repository),
    deactivateUseCase: DesactivateDispenserUc(repository: repository),
    deleteDispenserUseCase: DeleteDispenserUc(repository: repository),
  );
}

void main() {
  group('DispenserBloc Tests', () {
    test('initial state is DispenserInitial', () {
      final repository = MockDispenserRepository();
      final bloc = buildDispenserBloc(repository);
      expect(bloc.state, equals(DispenserInitial()));
      bloc.close();
    });

    test('emits [DispenserListLoading, DispenserListLoaded] when LoadDispensersEvent is added', () async {
      final repository = MockDispenserRepository(
        mockDispensers: [
          const Dispenser(
            id: 1,
            macAddress: 'AA:BB:CC:DD:EE:FF',
            name: 'Dispensador 1',
            isActive: true,
            wifiSsid: 'HomeWiFi',
            petId: 1,
          ),
        ],
      );
      final bloc = buildDispenserBloc(repository);

      expect(
        bloc.stream,
        emitsInOrder([
          DispenserListLoading(),
          const DispenserListLoaded(
            dispensers: [
              Dispenser(
                id: 1,
                macAddress: 'AA:BB:CC:DD:EE:FF',
                name: 'Dispensador 1',
                isActive: true,
                wifiSsid: 'HomeWiFi',
                petId: 1,
              ),
            ],
          ),
        ]),
      );

      bloc.add(LoadDispensersEvent());
      await pumpEventQueue();
      await bloc.close();
    });

    test('emits [BleScanningState] when StartScanBleEvent is added', () async {
      final bloc = buildDispenserBloc(MockDispenserRepository());

      expect(
        bloc.stream,
        emitsInOrder([
          const BleScanningState(scannedDevices: []),
          const BleScanningState(
            scannedDevices: [
              ScannedDevice(
                name: 'PDAM-Config-[123456]',
                remoteId: 'AA:BB:CC:DD:EE:FF',
                rssi: -50,
              ),
            ],
          ),
        ]),
      );

      bloc.add(StartScanBleEvent());
      await Future.delayed(const Duration(milliseconds: 1300));
      await pumpEventQueue();
      await bloc.close();
    });

    test('emits [ProvisioningInProgressState, ProvisioningSuccessState] when ConnectAndProvisionEvent is added', () async {
      final bloc = buildDispenserBloc(MockDispenserRepository());

      expect(
        bloc.stream,
        emitsInOrder([
          ProvisioningInProgressState(),
          ProvisioningSuccessState(),
        ]),
      );

      bloc.add(
        const ConnectAndProvisionEvent(
          deviceId: 'AA:BB:CC:DD:EE:FF',
          ssid: 'MyWiFi',
          password: 'secretpassword',
        ),
      );
      await pumpEventQueue();
      await bloc.close();
    });

    // --- Flujo QR / MAC: asociar, activar, desactivar y eliminar ---

    test('emits [DispenserLoading, DispenserSuccess] when AssociateDispenserEvent succeeds', () async {
      final repository = MockDispenserRepository();
      final bloc = buildDispenserBloc(repository);

      expect(
        bloc.stream,
        emitsInOrder([
          isA<DispenserLoading>(),
          isA<DispenserSuccess>(),
        ]),
      );

      bloc.add(
        AssociateDispenserEvent(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          petId: 7,
          secretKeyQr: 'clave-del-qr',
        ),
      );
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserSuccess>());
      await bloc.close();
    });

    test('emits [DispenserLoading, DispenserFailure] when AssociateDispenserEvent fails', () async {
      final bloc = buildDispenserBloc(MockDispenserRepository(shouldFail: true));

      expect(
        bloc.stream,
        emitsInOrder([
          isA<DispenserLoading>(),
          isA<DispenserFailure>(),
        ]),
      );

      bloc.add(
        AssociateDispenserEvent(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          petId: 7,
          secretKeyQr: 'clave-del-qr',
        ),
      );
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserFailure>());
      await bloc.close();
    });

    test('emits [DispenserLoading, DispenserLoaded] when ActivateDispenserEvent succeeds', () async {
      final repository = MockDispenserRepository();
      final bloc = buildDispenserBloc(repository);

      expect(
        bloc.stream,
        emitsInOrder([
          isA<DispenserLoading>(),
          isA<DispenserLoaded>(),
        ]),
      );

      bloc.add(ActivateDispenserEvent(dispenserId: 1, petId: 7));
      await pumpEventQueue();

      final state = bloc.state;
      expect(state, isA<DispenserLoaded>());
      expect((state as DispenserLoaded).dispenser.petId, 7);
      await bloc.close();
    });

    test('emits [DispenserLoading, DispenserFailure] when ActivateDispenserEvent fails', () async {
      final bloc = buildDispenserBloc(
        MockDispenserRepository(failActivate: true),
      );

      expect(
        bloc.stream,
        emitsInOrder([
          isA<DispenserLoading>(),
          isA<DispenserFailure>(),
        ]),
      );

      bloc.add(ActivateDispenserEvent(dispenserId: 1, petId: 7));
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserFailure>());
      await bloc.close();
    });

    test('emits [DispenserLoading, DispenserLoaded] when DeactivateDispenserEvent succeeds', () async {
      final repository = MockDispenserRepository();
      final bloc = buildDispenserBloc(repository);

      expect(
        bloc.stream,
        emitsInOrder([
          isA<DispenserLoading>(),
          isA<DispenserLoaded>(),
        ]),
      );

      bloc.add(DeactivateDispenserEvent(dispenserId: 1, petId: 7));
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserLoaded>());
      await bloc.close();
    });

    test('emits [DispenserLoading, DispenserFailure] when DeactivateDispenserEvent fails', () async {
      final bloc = buildDispenserBloc(
        MockDispenserRepository(failDeactivate: true),
      );

      expect(
        bloc.stream,
        emitsInOrder([
          isA<DispenserLoading>(),
          isA<DispenserFailure>(),
        ]),
      );

      bloc.add(DeactivateDispenserEvent(dispenserId: 1, petId: 7));
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserFailure>());
      await bloc.close();
    });

    test('emits [DispenserLoading, DispenserEmpty] when DeleteDispenserEvent succeeds', () async {
      final repository = MockDispenserRepository();
      final bloc = buildDispenserBloc(repository);

      expect(
        bloc.stream,
        emitsInOrder([
          isA<DispenserLoading>(),
          isA<DispenserEmpty>(),
        ]),
      );

      bloc.add(DeleteDispenserEvent(petId: 7));
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserEmpty>());
      await bloc.close();
    });

    test('emits [DispenserLoading, DispenserFailure] when DeleteDispenserEvent fails', () async {
      final bloc = buildDispenserBloc(
        MockDispenserRepository(failDelete: true),
      );

      expect(
        bloc.stream,
        emitsInOrder([
          isA<DispenserLoading>(),
          isA<DispenserFailure>(),
        ]),
      );

      bloc.add(DeleteDispenserEvent(petId: 7));
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserFailure>());
      await bloc.close();
    });
  });
}
