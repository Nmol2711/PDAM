import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_entity.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/scanned_device.dart';
import 'package:app_movil_pdam/features/dispensers/domain/repositories/dispensers_repository.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_bloc.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_event.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_state.dart';

class MockDispensersRepository implements DispensersRepository {
  final List<DispenserEntity> mockDispensers;
  final bool shouldFail;

  MockDispensersRepository({
    this.mockDispensers = const [],
    this.shouldFail = false,
  });

  @override
  Future<List<DispenserEntity>> getLocalDispensers() async {
    if (shouldFail) throw Exception('Error al obtener dispensadores');
    return mockDispensers;
  }

  @override
  Future<void> saveLocalDispenser(DispenserEntity dispenser) async {
    if (shouldFail) throw Exception('Error al guardar');
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
}

void main() {
  group('DispensersBloc Tests', () {
    test('initial state is DispensersInitial', () {
      final repository = MockDispensersRepository();
      final bloc = DispensersBloc(repository: repository);
      expect(bloc.state, equals(DispensersInitial()));
      bloc.close();
    });

    test('emits [DispensersLoading, DispensersLoaded] when LoadDispensersEvent is added', () async {
      final bloc = DispensersBloc(
        repository: MockDispensersRepository(
          mockDispensers: [
            const DispenserEntity(
              id: '1',
              macAddress: 'AA:BB:CC:DD:EE:FF',
              name: 'Dispensador 1',
              isConnected: true,
              wifiSsid: 'HomeWiFi',
            ),
          ],
        ),
      );

      expect(
        bloc.stream,
        emitsInOrder([
          DispensersLoading(),
          const DispensersLoaded(
            dispensers: [
              DispenserEntity(
                id: '1',
                macAddress: 'AA:BB:CC:DD:EE:FF',
                name: 'Dispensador 1',
                isConnected: true,
                wifiSsid: 'HomeWiFi',
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
      final bloc = DispensersBloc(repository: MockDispensersRepository());

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
      await pumpEventQueue();
      await bloc.close();
    });

    test('emits [ProvisioningInProgressState, ProvisioningSuccessState] when ConnectAndProvisionEvent is added', () async {
      final bloc = DispensersBloc(repository: MockDispensersRepository());

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
  });
}
