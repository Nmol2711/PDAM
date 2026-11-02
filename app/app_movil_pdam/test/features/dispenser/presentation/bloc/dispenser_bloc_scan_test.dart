import 'dart:async';
import 'dart:io';

import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_adapter_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_scan_event.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dispenser_bloc_test.dart';

const ScannedDevice device = ScannedDevice(
  name: 'PDAM-Config-[123456]',
  remoteId: 'AA:BB:CC:DD:EE:FF',
  rssi: -50,
);

const ScannedDevice sameDeviceStrongerSignal = ScannedDevice(
  name: 'PDAM-Config-[123456]',
  remoteId: 'AA:BB:CC:DD:EE:FF',
  rssi: -30,
);

const ScannedDevice otherDevice = ScannedDevice(
  name: 'PDAM-Config-[654321]',
  remoteId: '11:22:33:44:55:66',
  rssi: -80,
);

/// Repositorio con ciclos de escaneo controlables desde la prueba.
class _ControllableScanRepository extends MockDispenserRepository {
  final List<StreamController<BleScanEvent>> controllers =
      <StreamController<BleScanEvent>>[];
  final List<int> openedCycles = <int>[];
  final List<int?> stoppedCycles = <int?>[];

  /// Estados del adaptador simulados por la prueba (RF-11, RF-12, RF-25).
  final StreamController<BleAdapterStatus> statusController =
      StreamController<BleAdapterStatus>.broadcast();

  /// Si se informa, `stopBleScan` no termina hasta completarla (RF-09).
  Completer<void>? stopCompleter;

  /// Si se informa, el aprovisionamiento no termina hasta completarla (RF-22).
  Completer<void>? provisioningCompleter;

  StreamController<BleScanEvent> get lastController => controllers.last;

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
  Future<void> stopBleScan({int? cycleId}) async {
    stoppedCycles.add(cycleId);
    final completer = stopCompleter;
    if (completer != null) await completer.future;
  }

  @override
  Future<void> connectAndProvisionBle({
    required String deviceId,
    required String ssid,
    required String password,
  }) async {
    final completer = provisioningCompleter;
    if (completer != null) await completer.future;
  }

  @override
  Stream<BleAdapterStatus> get adapterStatus => statusController.stream;

  /// Emite un estado del adaptador y deja que el BLoC lo procese.
  Future<void> emitStatus(BleAdapterStatus status) async {
    statusController.add(status);
    await pumpEventQueue();
  }
}

void main() {
  late _ControllableScanRepository repository;
  late DispenserBloc bloc;

  setUp(() {
    repository = _ControllableScanRepository();
    bloc = buildDispenserBloc(repository);
  });

  tearDown(() async {
    await bloc.close();
    for (final controller in repository.controllers) {
      await controller.close();
    }
    await repository.statusController.close();
  });

  Future<void> startScan() async {
    bloc.add(StartScanBleEvent());
    await pumpEventQueue();
  }

  Future<void> emit(BleScanEvent event) async {
    repository.lastController.add(event);
    await pumpEventQueue();
  }

  /// Recorre una ventana vacía y deja el ciclo listo para la siguiente.
  Future<void> emptyWindow() async {
    final cycleId = repository.openedCycles.last;
    await emit(BleScanDevices(cycleId: cycleId, devices: const []));
    await emit(BleScanWindowClosed(cycleId: cycleId, hasDevices: false));
  }

  group('Apertura y renovación (RF-01, RF-03, RF-23)', () {
    test('inicia con estado de apertura sin consumir ventana', () async {
      await startScan();

      expect(bloc.state, isA<BleScanOpeningState>());
      expect(repository.openedCycles, <int>[1]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repository.openedCycles, <int>[1]);
    });

    test('una ventana con dispositivos pasa a resultados conservados', () async {
      await startScan();
      final cycleId = repository.openedCycles.last;

      await emit(
        BleScanDevices(cycleId: cycleId, devices: const [device]),
      );
      expect(bloc.state, const BleScanningState(scannedDevices: [device]));

      await emit(BleScanWindowClosed(cycleId: cycleId, hasDevices: true));

      expect(bloc.state, const BleScanResultsState(scannedDevices: [device]));
      expect(repository.openedCycles, <int>[1]);
    });

    test('renueva hasta tres ventanas consecutivas sin resultados', () async {
      await startScan();

      for (var window = 0; window < 3; window++) {
        final cycleId = repository.openedCycles.last;
        await emit(BleScanDevices(cycleId: cycleId, devices: const []));
        expect(bloc.state, isA<BleScanningState>());

        await emit(BleScanWindowClosed(cycleId: cycleId, hasDevices: false));

        if (window < 2) {
          expect(bloc.state, isA<BleScanOpeningState>());
        }
      }

      expect(repository.openedCycles, hasLength(3));
      expect(bloc.state, isA<BleScanFinishedState>());
    });

    test('cada renovación abre un ciclo con identidad propia', () async {
      await startScan();
      await emptyWindow();
      await emptyWindow();

      expect(repository.openedCycles, <int>[1, 2, 3]);
      expect(bloc.state, isA<BleScanOpeningState>());
    });

    test('un resultado reinicia el contador de ventanas', () async {
      await startScan();
      await emptyWindow();
      await emptyWindow();

      final withDevices = repository.openedCycles.last;
      await emit(
        BleScanDevices(cycleId: withDevices, devices: const [device]),
      );
      await emit(
        BleScanWindowClosed(cycleId: withDevices, hasDevices: true),
      );
      expect(bloc.state, isA<BleScanResultsState>());

      await startScan();
      await emptyWindow();
      await emptyWindow();

      // Dos ventanas vacías tras el resultado: todavía no es el estado final.
      expect(bloc.state, isA<BleScanOpeningState>());
      expect(repository.openedCycles, hasLength(6));

      await emptyWindow();

      expect(bloc.state, isA<BleScanFinishedState>());
    });

    test('una búsqueda manual reinicia el contador tras el estado final', () async {
      await startScan();
      await emptyWindow();
      await emptyWindow();
      await emptyWindow();
      expect(bloc.state, isA<BleScanFinishedState>());

      await startScan();
      expect(bloc.state, isA<BleScanOpeningState>());

      await emptyWindow();
      await emptyWindow();

      expect(bloc.state, isA<BleScanOpeningState>());
      expect(repository.openedCycles, hasLength(6));
    });
  });

  group('Serialización (RF-06, RF-09)', () {
    test('dos inicios solapados no duplican el ciclo', () async {
      bloc.add(StartScanBleEvent());
      bloc.add(StartScanBleEvent());
      await pumpEventQueue();

      expect(repository.openedCycles, <int>[1]);
      expect(bloc.state, isA<BleScanOpeningState>());
    });

    test('inicio y detención se serializan en orden', () async {
      bloc.add(StartScanBleEvent());
      bloc.add(StopScanBleEvent());
      await pumpEventQueue();

      expect(repository.openedCycles, <int>[1]);
      expect(repository.stoppedCycles, <int?>[1]);
      expect(bloc.state, isA<BleScanStoppedState>());
    });

    test('detener durante la apertura cierra el ciclo sin abrir ventana', () async {
      await startScan();
      expect(bloc.state, isA<BleScanOpeningState>());

      bloc.add(StopScanBleEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<BleScanStoppedState>());
      expect(repository.openedCycles, <int>[1]);
    });

    test('detener sin ciclo no falla y emite el estado detenido', () async {
      bloc.add(StopScanBleEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<BleScanStoppedState>());
      expect(repository.openedCycles, isEmpty);
      // Sin ciclo no hay nada que liberar en el adaptador (RF-08).
      expect(repository.stoppedCycles, isEmpty);
    });

    test('un inicio con la ventana abierta se descarta y no reinicia el contador', () async {
      await startScan();
      await emptyWindow();
      await emptyWindow();
      expect(repository.openedCycles, <int>[1, 2, 3]);
      expect(bloc.state, isA<BleScanOpeningState>());

      final cycleId = repository.openedCycles.last;
      await emit(BleScanDevices(cycleId: cycleId, devices: const []));
      expect(bloc.state, const BleScanningState(scannedDevices: []));

      // RF-06: con la ventana abierta el inicio se descarta sin abrir ciclo.
      await startScan();
      expect(repository.openedCycles, <int>[1, 2, 3]);
      expect(bloc.state, const BleScanningState(scannedDevices: []));

      await emit(BleScanWindowClosed(cycleId: cycleId, hasDevices: false));

      // Si el inicio manual hubiera reiniciado el contador, seguiría abriendo
      // ventanas en lugar de terminar.
      expect(bloc.state, isA<BleScanFinishedState>());
      expect(repository.openedCycles, <int>[1, 2, 3]);
    });
  });

  group('Deduplicación de listas (RF-10)', () {
    test('dos listas equivalentes no reemiten estado aunque cambie el RSSI', () async {
      final states = <DispenserState>[];
      final sub = bloc.stream.listen(states.add);
      await startScan();
      final cycleId = repository.openedCycles.last;

      await emit(BleScanDevices(cycleId: cycleId, devices: const [device]));
      final emissions = states.length;

      await emit(
        BleScanDevices(
          cycleId: cycleId,
          devices: const [sameDeviceStrongerSignal],
        ),
      );
      expect(states.length, emissions);

      // Al cerrar, el estado conservado muestra el último RSSI conocido.
      await emit(BleScanWindowClosed(cycleId: cycleId, hasDevices: true));
      final retained = bloc.state;
      expect(retained, isA<BleScanResultsState>());
      expect(
        (retained as BleScanResultsState).scannedDevices.single.rssi,
        sameDeviceStrongerSignal.rssi,
      );

      await sub.cancel();
    });

    test('los mismos identificadores en otro orden sí emiten', () async {
      final states = <DispenserState>[];
      final sub = bloc.stream.listen(states.add);
      await startScan();
      final cycleId = repository.openedCycles.last;

      await emit(
        BleScanDevices(cycleId: cycleId, devices: const [device, otherDevice]),
      );
      final emissions = states.length;

      await emit(
        BleScanDevices(cycleId: cycleId, devices: const [otherDevice, device]),
      );

      expect(states.length, emissions + 1);
      await sub.cancel();
    });
  });

  group('Identidad del ciclo (RF-07)', () {
    test('los eventos tardíos del ciclo anterior no alteran el vigente', () async {
      await startScan();
      final first = repository.openedCycles.single;

      // Renovación automática: el ciclo 2 queda vigente en apertura.
      await emit(BleScanWindowClosed(cycleId: first, hasDevices: false));
      final second = repository.openedCycles.last;
      expect(second, isNot(first));

      await emit(BleScanDevices(cycleId: second, devices: const [device]));
      expect(bloc.state, const BleScanningState(scannedDevices: [device]));

      // Los eventos tardíos llegan por la suscripción VIGENTE con el ciclo
      // anterior: dispositivos, cierre y fallo.
      await emit(BleScanDevices(cycleId: first, devices: const [otherDevice]));
      await emit(BleScanWindowClosed(cycleId: first, hasDevices: false));
      await emit(
        BleScanFailed(cycleId: first, failure: BleScanFailure.adapterOff),
      );

      expect(bloc.state, const BleScanningState(scannedDevices: [device]));
      expect(repository.openedCycles, <int>[first, second]);

      // Los dispositivos del ciclo viejo no se mezclan con los del vigente.
      await emit(BleScanWindowClosed(cycleId: second, hasDevices: true));
      expect(bloc.state, const BleScanResultsState(scannedDevices: [device]));
    });

    test('tras detener se descartan los eventos tardíos del ciclo', () async {
      await startScan();
      final cycleId = repository.openedCycles.last;

      bloc.add(StopScanBleEvent());
      await pumpEventQueue();
      expect(bloc.state, isA<BleScanStoppedState>());

      await emit(BleScanWindowClosed(cycleId: cycleId, hasDevices: false));
      await emit(BleScanDevices(cycleId: cycleId, devices: const [device]));
      await emit(
        BleScanFailed(cycleId: cycleId, failure: BleScanFailure.adapterOff),
      );

      expect(bloc.state, isA<BleScanStoppedState>());
      expect(repository.openedCycles, <int>[1]);
    });
  });

  group('Detención y prelación manual (RF-06, RF-08, RF-09)', () {
    test('doble detención es idempotente y emite un único estado', () async {
      final states = <DispenserState>[];
      final sub = bloc.stream.listen(states.add);
      await startScan();

      bloc.add(StopScanBleEvent());
      bloc.add(StopScanBleEvent());
      await pumpEventQueue();

      expect(states.whereType<BleScanStoppedState>(), hasLength(1));
      expect(repository.stoppedCycles, <int?>[1]);
      await sub.cancel();
    });

    test('inicio durante la detención espera a que se libere el ciclo', () async {
      await startScan();
      repository.stopCompleter = Completer<void>();
      bloc.add(StopScanBleEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<BleScanStoppedState>());
      expect(repository.stoppedCycles, <int?>[1]);

      bloc.add(StartScanBleEvent());
      await pumpEventQueue();
      expect(repository.openedCycles, <int>[1]);

      repository.stopCompleter!.complete();
      repository.stopCompleter = null;
      await pumpEventQueue();

      expect(repository.openedCycles, <int>[1, 2]);
      expect(bloc.state, isA<BleScanOpeningState>());
    });

    test('la búsqueda manual durante la apertura de una renovación abre un solo ciclo', () async {
      await startScan();
      await emptyWindow();
      expect(repository.openedCycles, <int>[1, 2]);
      expect(bloc.state, isA<BleScanOpeningState>());

      await startScan();

      expect(repository.openedCycles, <int>[1, 2, 3]);
      expect(bloc.state, isA<BleScanOpeningState>());

      // Contador a cero: hacen falta tres ventanas vacías para el estado final.
      await emptyWindow();
      await emptyWindow();
      expect(bloc.state, isA<BleScanOpeningState>());
      await emptyWindow();
      expect(bloc.state, isA<BleScanFinishedState>());
    });

    test('la búsqueda manual desde resultados conservados abre un ciclo vacío', () async {
      await startScan();
      final cycleId = repository.openedCycles.last;
      await emit(BleScanDevices(cycleId: cycleId, devices: const [device]));
      await emit(BleScanWindowClosed(cycleId: cycleId, hasDevices: true));
      expect(bloc.state, isA<BleScanResultsState>());

      await startScan();

      expect(bloc.state, isA<BleScanOpeningState>());
      expect(repository.openedCycles, <int>[1, 2]);

      await emptyWindow();
      await emptyWindow();
      expect(bloc.state, isA<BleScanOpeningState>());
      await emptyWindow();
      expect(bloc.state, isA<BleScanFinishedState>());
    });

    test('los eventos de escaneo no pisan el aprovisionamiento (RF-22)', () async {
      final states = <DispenserState>[];
      final sub = bloc.stream.listen(states.add);

      await startScan();
      final cycleId = repository.openedCycles.last;
      await emit(BleScanDevices(cycleId: cycleId, devices: const [device]));

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

      repository.lastController.add(
        BleScanWindowClosed(cycleId: cycleId, hasDevices: false),
      );
      repository.lastController.add(
        BleScanDevices(cycleId: cycleId, devices: const [otherDevice]),
      );
      repository.lastController.add(
        BleScanFailed(cycleId: cycleId, failure: BleScanFailure.adapterOff),
      );
      await pumpEventQueue();

      expect(bloc.state, isA<ProvisioningInProgressState>());
      expect(states.whereType<BleScanNoticeState>(), isEmpty);
      expect(repository.openedCycles, <int>[1]);

      repository.provisioningCompleter!.complete();
      repository.provisioningCompleter = null;
      await pumpEventQueue();

      expect(states.whereType<ProvisioningSuccessState>(), hasLength(1));
      await sub.cancel();
    });

    test('un cierre con detención encolada no renueva el ciclo', () async {
      await startScan();
      final cycleId = repository.openedCycles.last;

      repository.lastController.add(
        BleScanWindowClosed(cycleId: cycleId, hasDevices: false),
      );
      bloc.add(StopScanBleEvent());
      await pumpEventQueue();

      expect(bloc.state, isA<BleScanStoppedState>());
      expect(repository.openedCycles, <int>[1]);
    });
  });

  group('Adaptador (RF-11, RF-12, RF-25)', () {
    /// Deja la ventana abierta con un dispositivo en pantalla.
    Future<int> windowWithDevice() async {
      await startScan();
      final cycleId = repository.openedCycles.last;
      await emit(BleScanDevices(cycleId: cycleId, devices: const [device]));
      expect(bloc.state, const BleScanningState(scannedDevices: [device]));
      return cycleId;
    }

    test('off cierra el ciclo, limpia la lista y muestra el aviso', () async {
      final cycleId = await windowWithDevice();

      await repository.emitStatus(BleAdapterStatus.off);

      // RF-11: aviso tipado, sin lista ni progreso y con el ciclo liberado.
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterOff),
      );
      expect(repository.stoppedCycles, <int?>[cycleId]);
      // RF-14: el aviso no abre otro ciclo ni enciende el adaptador.
      expect(repository.openedCycles, <int>[cycleId]);
    });

    test('off durante la apertura no deja el ciclo abierto', () async {
      await startScan();
      expect(bloc.state, isA<BleScanOpeningState>());

      await repository.emitStatus(BleAdapterStatus.off);

      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterOff),
      );
      expect(repository.openedCycles, <int>[1]);
      expect(repository.stoppedCycles, <int?>[1]);
    });

    test('unavailable informa el aviso sin ciclo', () async {
      await windowWithDevice();

      await repository.emitStatus(BleAdapterStatus.unavailable);

      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterUnavailable),
      );
    });

    test('unauthorized informa el aviso de autorización', () async {
      await windowWithDevice();

      await repository.emitStatus(BleAdapterStatus.unauthorized);

      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterUnauthorized),
      );
    });

    test('turningOn y turningOff no producen aviso', () async {
      await windowWithDevice();

      await repository.emitStatus(BleAdapterStatus.turningOff);
      await repository.emitStatus(BleAdapterStatus.turningOn);

      expect(bloc.state, const BleScanningState(scannedDevices: [device]));
    });

    test('on sustituye el aviso por un ciclo nuevo con contador a cero', () async {
      await windowWithDevice();
      await repository.emitStatus(BleAdapterStatus.off);
      expect(bloc.state, isA<BleScanNoticeState>());

      // turningOn es transitorio: el aviso sigue vigente (RF-11).
      await repository.emitStatus(BleAdapterStatus.turningOn);
      expect(bloc.state, isA<BleScanNoticeState>());

      await repository.emitStatus(BleAdapterStatus.on);

      // RF-12: ciclo nuevo con lista vacía, sin pulsar «Reintentar».
      expect(bloc.state, isA<BleScanOpeningState>());
      expect(repository.openedCycles, <int>[1, 2]);

      // Contador a cero: hacen falta tres ventanas vacías para el final.
      await emptyWindow();
      await emptyWindow();
      expect(bloc.state, isA<BleScanOpeningState>());
      await emptyWindow();
      expect(bloc.state, isA<BleScanFinishedState>());
    });

    test('on sin aviso vigente no abre un ciclo paralelo', () async {
      await windowWithDevice();

      await repository.emitStatus(BleAdapterStatus.on);

      expect(repository.openedCycles, <int>[1]);
      expect(bloc.state, const BleScanningState(scannedDevices: [device]));
    });

    test('una detención tras el aviso no repite stopBleScan ni pisa el aviso', () async {
      await windowWithDevice();
      await repository.emitStatus(BleAdapterStatus.off);
      expect(bloc.state, isA<BleScanNoticeState>());

      bloc.add(StopScanBleEvent());
      await pumpEventQueue();

      // RF-24: el aviso tiene más precedencia que el estado detenido.
      expect(repository.stoppedCycles, <int?>[1]);
      expect(bloc.state, isA<BleScanNoticeState>());
    });

    test('RF-14: ningún archivo invoca el encendido asistido del adaptador', () {
      final rutas = <String>[
        'lib/features/dispenser/presentation/bloc/dispenser_bloc.dart',
        'lib/features/dispenser/presentation/views/ble_scan_page.dart',
        'lib/features/dispenser/data/services/ble_provisioning_service.dart',
        'lib/features/dispenser/data/services/ble_adapter.dart',
      ];

      for (final ruta in rutas) {
        final codigo = File(ruta).readAsStringSync();
        expect(
          codigo.contains('turnOn'),
          isFalse,
          reason: '$ruta pide encender el adaptador (RF-14)',
        );
      }
    });
  });

  group('Causa tipada del ciclo (RF-11, RF-17, RF-18, RF-25)', () {
    Future<void> failOpening(BleScanFailure failure) async {
      await startScan();
      final cycleId = repository.openedCycles.last;
      await emit(BleScanFailed(cycleId: cycleId, failure: failure));
    }

    test('cada causa del adaptador llega al aviso correspondiente', () async {
      await failOpening(BleScanFailure.adapterOff);
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterOff),
      );

      await failOpening(BleScanFailure.adapterUnavailable);
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterUnavailable),
      );

      await failOpening(BleScanFailure.adapterUnauthorized);
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterUnauthorized),
      );
    });

    test('permisos y ubicación conservan su causa', () async {
      await failOpening(BleScanFailure.permissionDenied);
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.permissionDenied),
      );

      await failOpening(BleScanFailure.permissionPermanentlyDenied);
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.permissionPermanentlyDenied),
      );

      await failOpening(BleScanFailure.locationDisabled);
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.locationDisabled),
      );
    });

    test('un fallo de arranque no descarta la causa ni deja progreso', () async {
      await failOpening(BleScanFailure.startFailed);

      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.scanFailed),
      );
      expect(bloc.state, isNot(isA<BleScanOpeningState>()));
    });
  });

  group('Ciclo de vida (RF-13)', () {
    Future<void> lifecycle(AppLifecycleState state) async {
      bloc.add(AppLifecycleChangedBleEvent(state));
      await pumpEventQueue();
    }

    test('paused cierra el ciclo y libera el escaneo', () async {
      await startScan();
      final cycleId = repository.openedCycles.last;
      await emit(BleScanDevices(cycleId: cycleId, devices: const [device]));

      await lifecycle(AppLifecycleState.paused);

      expect(bloc.state, isA<BleScanStoppedState>());
      expect(repository.stoppedCycles, <int?>[cycleId]);
    });

    test('hidden cierra el ciclo', () async {
      await startScan();

      await lifecycle(AppLifecycleState.hidden);

      expect(bloc.state, isA<BleScanStoppedState>());
      expect(repository.stoppedCycles, <int?>[1]);
    });

    test('inactive no cierra el ciclo', () async {
      await startScan();
      final cycleId = repository.openedCycles.last;
      await emit(BleScanDevices(cycleId: cycleId, devices: const [device]));

      await lifecycle(AppLifecycleState.inactive);

      expect(bloc.state, const BleScanningState(scannedDevices: [device]));
      expect(repository.stoppedCycles, isEmpty);
    });

    test('resumed reabre lo que cerró el segundo plano', () async {
      await startScan();
      await lifecycle(AppLifecycleState.paused);
      expect(bloc.state, isA<BleScanStoppedState>());

      await lifecycle(AppLifecycleState.resumed);

      expect(bloc.state, isA<BleScanOpeningState>());
      expect(repository.openedCycles, <int>[1, 2]);

      await emptyWindow();
      await emptyWindow();
      expect(bloc.state, isA<BleScanOpeningState>());
      await emptyWindow();
      expect(bloc.state, isA<BleScanFinishedState>());
    });

    test('resumed no reabre si hay un aviso vigente', () async {
      await startScan();
      await repository.emitStatus(BleAdapterStatus.off);
      expect(bloc.state, isA<BleScanNoticeState>());

      await lifecycle(AppLifecycleState.resumed);

      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterOff),
      );
      expect(repository.openedCycles, <int>[1]);
    });

    test('on en segundo plano espera a resumed para abrir el ciclo', () async {
      await startScan();
      await repository.emitStatus(BleAdapterStatus.off);
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterOff),
      );

      await lifecycle(AppLifecycleState.paused);
      await repository.emitStatus(BleAdapterStatus.on);

      // RF-13: con la app en segundo plano no se abre la ventana.
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterOff),
      );
      expect(repository.openedCycles, <int>[1]);

      await lifecycle(AppLifecycleState.resumed);

      expect(bloc.state, isA<BleScanOpeningState>());
      expect(repository.openedCycles, <int>[1, 2]);

      // Contador a cero: hacen falta tres ventanas vacías hasta el final.
      await emptyWindow();
      await emptyWindow();
      expect(bloc.state, isA<BleScanOpeningState>());
      await emptyWindow();
      expect(bloc.state, isA<BleScanFinishedState>());
    });

    test('resumed no reabre un aviso de permisos con el adaptador encendido', () async {
      await startScan();
      await repository.emitStatus(BleAdapterStatus.on);
      final cycleId = repository.openedCycles.last;
      await emit(
        BleScanFailed(
          cycleId: cycleId,
          failure: BleScanFailure.permissionDenied,
        ),
      );
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.permissionDenied),
      );

      await lifecycle(AppLifecycleState.paused);
      await lifecycle(AppLifecycleState.resumed);

      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.permissionDenied),
      );
      expect(repository.openedCycles, <int>[1]);
    });

    test('resumed no reabre un aviso de ubicación con el adaptador encendido', () async {
      await startScan();
      await repository.emitStatus(BleAdapterStatus.on);
      final cycleId = repository.openedCycles.last;
      await emit(
        BleScanFailed(
          cycleId: cycleId,
          failure: BleScanFailure.locationDisabled,
        ),
      );
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.locationDisabled),
      );

      await lifecycle(AppLifecycleState.paused);
      await lifecycle(AppLifecycleState.resumed);

      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.locationDisabled),
      );
      expect(repository.openedCycles, <int>[1]);
    });

    test('canReopenNoticeOnResume solo admite adaptador y scanFailed', () {
      for (final cause in <BleScanNoticeCause>[
        BleScanNoticeCause.adapterOff,
        BleScanNoticeCause.adapterUnavailable,
        BleScanNoticeCause.adapterUnauthorized,
        BleScanNoticeCause.scanFailed,
      ]) {
        expect(canReopenNoticeOnResume(cause), isTrue, reason: cause.name);
      }
      for (final cause in <BleScanNoticeCause>[
        BleScanNoticeCause.permissionDenied,
        BleScanNoticeCause.permissionPermanentlyDenied,
        BleScanNoticeCause.locationDisabled,
      ]) {
        expect(canReopenNoticeOnResume(cause), isFalse, reason: cause.name);
      }
    });

    test('resumed sin ciclo detenido no abre nada', () async {
      await lifecycle(AppLifecycleState.resumed);

      expect(bloc.state, isA<DispenserInitial>());
      expect(repository.openedCycles, isEmpty);
    });

    test('una detención repetida desde el ciclo de vida es idempotente', () async {
      await startScan();
      await lifecycle(AppLifecycleState.paused);
      await lifecycle(AppLifecycleState.paused);

      expect(repository.stoppedCycles, <int?>[1]);
    });
  });

  group('Precedencia de avisos (RF-24)', () {
    test('permisos y scanFailed no sustituyen un aviso de adaptador', () async {
      await startScan();
      final cycleId = repository.openedCycles.last;
      await repository.emitStatus(BleAdapterStatus.off);
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterOff),
      );

      await emit(
        BleScanFailed(
          cycleId: cycleId,
          failure: BleScanFailure.permissionPermanentlyDenied,
        ),
      );
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterOff),
      );

      await emit(
        BleScanFailed(cycleId: cycleId, failure: BleScanFailure.startFailed),
      );
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterOff),
      );
    });

    test('el aviso de adaptador sustituye al de permisos', () async {
      await startScan();
      final cycleId = repository.openedCycles.last;

      await emit(
        BleScanFailed(
          cycleId: cycleId,
          failure: BleScanFailure.permissionPermanentlyDenied,
        ),
      );
      expect(
        bloc.state,
        const BleScanNoticeState(
          BleScanNoticeCause.permissionPermanentlyDenied,
        ),
      );

      await repository.emitStatus(BleAdapterStatus.unauthorized);
      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.adapterUnauthorized),
      );
    });

    test('canReplaceScanNotice aplica la tabla de avisos', () {
      const adapter = <BleScanNoticeCause>[
        BleScanNoticeCause.adapterOff,
        BleScanNoticeCause.adapterUnavailable,
        BleScanNoticeCause.adapterUnauthorized,
      ];
      const lower = <BleScanNoticeCause>[
        BleScanNoticeCause.permissionDenied,
        BleScanNoticeCause.permissionPermanentlyDenied,
        BleScanNoticeCause.locationDisabled,
        BleScanNoticeCause.scanFailed,
      ];

      for (final current in adapter) {
        for (final next in lower) {
          expect(
            canReplaceScanNotice(current, next),
            isFalse,
            reason: '${current.name} no debe ser sustituido por ${next.name}',
          );
        }
      }

      for (final next in adapter) {
        expect(
          canReplaceScanNotice(BleScanNoticeCause.permissionDenied, next),
          isTrue,
        );
        expect(canReplaceScanNotice(BleScanNoticeCause.scanFailed, next), isTrue);
      }

      expect(
        canReplaceScanNotice(
          BleScanNoticeCause.permissionDenied,
          BleScanNoticeCause.locationDisabled,
        ),
        isTrue,
      );
      expect(
        canReplaceScanNotice(
          BleScanNoticeCause.locationDisabled,
          BleScanNoticeCause.permissionPermanentlyDenied,
        ),
        isTrue,
      );
    });
  });

  group('Errores del stream y capas (RNF-01, Constitución art. 3)', () {
    test('un error del stream emite el aviso tipado, no texto de excepción', () async {
      await startScan();
      final cycleId = repository.openedCycles.last;
      expect(cycleId, 1);

      repository.lastController.addError(StateError('fallo interno'));
      await pumpEventQueue();

      expect(
        bloc.state,
        const BleScanNoticeState(BleScanNoticeCause.scanFailed),
      );
      expect(bloc.state, isNot(isA<DispenserErrorState>()));
    });

    test('el BLoC no importa data/services ni fija la ventana', () {
      final codigo = File(
        'lib/features/dispenser/presentation/bloc/dispenser_bloc.dart',
      ).readAsStringSync();

      expect(codigo.contains('data/services/'), isFalse);
      expect(codigo.contains('Duration(seconds: 15)'), isFalse);
    });
  });
}
