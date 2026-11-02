import 'dart:async';

import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_adapter_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_scan_event.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dispenser_bloc_test.dart';

const ScannedDevice device = ScannedDevice(
  name: 'PDAM-Config-[123456]',
  remoteId: 'AA:BB:CC:DD:EE:FF',
  rssi: -50,
);

/// Repositorio con escaneo, adaptador y aprovisionamiento controlables.
class _PrecedenceRepository extends MockDispenserRepository {
  final List<StreamController<BleScanEvent>> controllers =
      <StreamController<BleScanEvent>>[];
  final List<int> openedCycles = <int>[];
  final StreamController<BleAdapterStatus> statusController =
      StreamController<BleAdapterStatus>.broadcast();

  Completer<void>? provisioningCompleter;
  Completer<void>? refillCompleter;
  Completer<void>? loadCompleter;
  Object? refillFailure;

  final List<Dispenser> dispensers = <Dispenser>[
    const Dispenser(
      id: 1,
      macAddress: 'AA:BB:CC:DD:EE:FF',
      isActive: true,
      currentFoodGrams: 500,
    ),
  ];

  StreamController<BleScanEvent> get lastController => controllers.last;

  @override
  Future<List<Dispenser>> getLocalDispensers() async {
    final completer = loadCompleter;
    if (completer != null) await completer.future;
    return List<Dispenser>.of(dispensers);
  }

  @override
  Future<void> refillFood(String dispenserId, double grams) async {
    final error = refillFailure;
    if (error != null) throw error;
    final completer = refillCompleter;
    if (completer != null) await completer.future;

    final index = dispensers.indexWhere(
      (dispenser) =>
          dispenser.id.toString() == dispenserId ||
          dispenser.macAddress == dispenserId,
    );
    if (index < 0) return;
    dispensers[index] = dispensers[index].copyWith(
      currentFoodGrams: dispensers[index].currentFoodGrams + grams,
    );
  }

  @override
  Stream<BleScanEvent> scanBleDispensers({
    required int cycleId,
    Duration? window,
  }) {
    final controller = StreamController<BleScanEvent>();
    controllers.add(controller);
    openedCycles.add(cycleId);
    return controller.stream;
  }

  @override
  Stream<BleAdapterStatus> get adapterStatus => statusController.stream;

  @override
  Future<void> connectAndProvisionBle({
    required String deviceId,
    required String ssid,
    required String password,
  }) async {
    final completer = provisioningCompleter;
    if (completer != null) await completer.future;
  }

  Future<void> emitStatus(BleAdapterStatus status) async {
    statusController.add(status);
    await pumpEventQueue();
  }

  Future<void> dispose() async {
    await statusController.close();
    for (final controller in controllers) {
      await controller.close();
    }
  }
}

void main() {
  late _PrecedenceRepository repository;
  late DispenserBloc bloc;

  setUp(() {
    repository = _PrecedenceRepository();
    bloc = buildDispenserBloc(repository);
  });

  tearDown(() async {
    await bloc.close();
    await repository.dispose();
  });

  Future<void> emit(BleScanEvent event) async {
    repository.lastController.add(event);
    await pumpEventQueue();
  }

  Future<void> scanning() async {
    bloc.add(StartScanBleEvent());
    await pumpEventQueue();
    final cycleId = repository.openedCycles.last;
    await emit(BleScanDevices(cycleId: cycleId, devices: const [device]));
    expect(bloc.state, isA<BleScanningState>());
  }

  Future<void> retained() async {
    await scanning();
    final cycleId = repository.openedCycles.last;
    await emit(BleScanWindowClosed(cycleId: cycleId, hasDevices: true));
    expect(bloc.state, isA<BleScanResultsState>());
  }

  Future<void> finished() async {
    bloc.add(StartScanBleEvent());
    await pumpEventQueue();
    for (var window = 0; window < 3; window++) {
      final cycleId = repository.openedCycles.last;
      await emit(BleScanDevices(cycleId: cycleId, devices: const []));
      await emit(BleScanWindowClosed(cycleId: cycleId, hasDevices: false));
    }
    expect(bloc.state, isA<BleScanFinishedState>());
  }

  Future<void> adapterNotice() async {
    bloc.add(StartScanBleEvent());
    await pumpEventQueue();
    await repository.emitStatus(BleAdapterStatus.off);
    expect(bloc.state, isA<BleScanNoticeState>());
  }

  Future<void> permissionNotice() async {
    bloc.add(StartScanBleEvent());
    await pumpEventQueue();
    final cycleId = repository.openedCycles.last;
    await emit(
      BleScanFailed(
        cycleId: cycleId,
        failure: BleScanFailure.permissionPermanentlyDenied,
      ),
    );
    expect(
      bloc.state,
      const BleScanNoticeState(BleScanNoticeCause.permissionPermanentlyDenied),
    );
  }

  Future<void> provisioning() async {
    repository.provisioningCompleter = Completer<void>();
    bloc.add(
      const ConnectAndProvisionEvent(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        ssid: 'RedCasa',
        password: 'claveWiFi',
      ),
    );
    await pumpEventQueue();
    expect(bloc.state, isA<ProvisioningInProgressState>());
  }

  Future<void> stopped() async {
    await scanning();
    bloc.add(StopScanBleEvent());
    await pumpEventQueue();
    expect(bloc.state, isA<BleScanStoppedState>());
  }

  /// Comprueba que ni la carga ni el refresco silencioso pisan un estado de
  /// mayor precedencia (RF-24).
  Future<void> expectListBlocked(Future<void> Function() prepare) async {
    await prepare();
    final before = bloc.state;

    bloc.add(LoadDispensersEvent());
    await pumpEventQueue();
    expect(bloc.state, before);

    bloc.add(RefreshDispensersEvent());
    await pumpEventQueue();
    expect(bloc.state, before);
  }

  group('Precedencia de la lista (RF-24)', () {
    test('la lista no pisa la apertura', () async {
      await expectListBlocked(() async {
        bloc.add(StartScanBleEvent());
        await pumpEventQueue();
        expect(bloc.state, isA<BleScanOpeningState>());
      });
    });

    test('la lista no pisa el escaneo', () async {
      await expectListBlocked(scanning);
    });

    test('la lista no pisa los resultados conservados', () async {
      await expectListBlocked(retained);
    });

    test('la lista no pisa el estado final', () async {
      await expectListBlocked(finished);
    });

    test('la lista no pisa el aviso del adaptador', () async {
      await expectListBlocked(adapterNotice);
    });

    test('la lista no pisa el aviso de permisos', () async {
      await expectListBlocked(permissionNotice);
    });

    test('la lista no pisa el aprovisionamiento', () async {
      await expectListBlocked(provisioning);
      repository.provisioningCompleter!.complete();
      repository.provisioningCompleter = null;
      await pumpEventQueue();
    });
  });

  group('Cesión del estado detenido (RF-08, RF-24)', () {
    test('la carga sustituye el estado detenido por la lista', () async {
      await stopped();

      bloc.add(LoadDispensersEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserListLoaded>());
    });

    test('el refresco silencioso también entra tras detener', () async {
      await stopped();

      bloc.add(RefreshDispensersEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserListLoaded>());
    });

    test('la cesión es transitoria: un ciclo nuevo vuelve a bloquear', () async {
      await stopped();
      bloc.add(LoadDispensersEvent());
      await pumpEventQueue();
      expect(bloc.state, isA<DispenserListLoaded>());

      await scanning();
      final before = bloc.state;
      bloc.add(LoadDispensersEvent());
      await pumpEventQueue();
      expect(bloc.state, before);
    });

    test('el estado detenido no sustituye el aviso del adaptador', () async {
      await adapterNotice();

      bloc.add(StopScanBleEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<BleScanNoticeState>());
    });

    test('el estado detenido no sustituye el aprovisionamiento', () async {
      await provisioning();

      bloc.add(StopScanBleEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<ProvisioningInProgressState>());

      repository.provisioningCompleter!.complete();
      repository.provisioningCompleter = null;
      await pumpEventQueue();
    });
  });

  group('Secuencia de dispose (010 RF-05, RNF-06)', () {
    test('stop + load termina en lista con el stop emitido antes', () async {
      await scanning();
      final states = <DispenserState>[];
      final subscription = bloc.stream.listen(states.add);

      bloc.add(StopScanBleEvent());
      bloc.add(LoadDispensersEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserListLoaded>());

      final stoppedIndex = states.indexWhere(
        (state) => state is BleScanStoppedState,
      );
      final listIndex = states.lastIndexWhere(
        (state) => state is DispenserListLoaded,
      );
      expect(stoppedIndex, isNonNegative);
      expect(listIndex, greaterThan(stoppedIndex));

      await subscription.cancel();
    });

    test('salir durante un aviso restaura la lista', () async {
      await adapterNotice();

      // La página, al destruirse, pide stop y luego la lista.
      bloc.add(StopScanBleEvent());
      bloc.add(LoadDispensersEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserListLoaded>());
    });
  });

  group('Reabastecimiento y carga en vuelo (RF-24, RNF-06)', () {
    test('un reabastecimiento en vuelo no pisa el escaneo y se ve al volver', () async {
      await scanning();
      repository.refillCompleter = Completer<void>();
      bloc.add(
        const RefillFoodEvent(dispenserId: '1', amount: 100, unit: 'g'),
      );
      await pumpEventQueue();
      expect(bloc.state, isA<BleScanningState>());

      repository.refillCompleter!.complete();
      repository.refillCompleter = null;
      await pumpEventQueue();

      expect(bloc.state, isA<BleScanningState>());

      // Al volver a la lista, el stock persistido se refleja.
      bloc.add(StopScanBleEvent());
      bloc.add(LoadDispensersEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<DispenserListLoaded>());
      expect(
        (bloc.state as DispenserListLoaded).dispensers.single.currentFoodGrams,
        600,
      );
    });

    test('un reabastecimiento en vuelo no pisa el aviso', () async {
      await adapterNotice();
      repository.refillCompleter = Completer<void>();
      bloc.add(
        const RefillFoodEvent(dispenserId: '1', amount: 100, unit: 'g'),
      );
      await pumpEventQueue();

      repository.refillCompleter!.complete();
      repository.refillCompleter = null;
      await pumpEventQueue();

      expect(bloc.state, isA<BleScanNoticeState>());
    });

    test('el rechazo por límite tampoco pisa el escaneo', () async {
      await scanning();
      bloc.add(
        const RefillFoodEvent(dispenserId: '1', amount: 6000, unit: 'g'),
      );
      await pumpEventQueue();

      expect(bloc.state, isA<BleScanningState>());
    });

    test('un fallo inesperado del reabastecimiento tampoco pisa el escaneo', () async {
      await scanning();
      repository.refillFailure = StateError('fallo de almacenamiento');
      bloc.add(
        const RefillFoodEvent(dispenserId: '1', amount: 100, unit: 'g'),
      );
      await pumpEventQueue();

      expect(bloc.state, isA<BleScanningState>());
    });

    test('la carga en vuelo no pisa el aprovisionamiento', () async {
      repository.loadCompleter = Completer<void>();
      bloc.add(LoadDispensersEvent());
      await pumpEventQueue();
      expect(bloc.state, isA<DispenserListLoading>());

      repository.provisioningCompleter = Completer<void>();
      bloc.add(
        const ConnectAndProvisionEvent(
          deviceId: 'AA:BB:CC:DD:EE:FF',
          ssid: 'RedCasa',
          password: 'claveWiFi',
        ),
      );
      await pumpEventQueue();
      expect(bloc.state, isA<ProvisioningInProgressState>());

      repository.loadCompleter!.complete();
      repository.loadCompleter = null;
      await pumpEventQueue();

      // La guarda posterior al await impide que la lista pise el progreso.
      expect(bloc.state, isA<ProvisioningInProgressState>());

      repository.provisioningCompleter!.complete();
      repository.provisioningCompleter = null;
      await pumpEventQueue();
    });
  });
}
