import 'dart:async';

import 'package:app_movil_pdam/features/dispenser/data/services/ble_provisioning_service.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_adapter_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_scan_event.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../support/ble_fakes.dart';

const ScannedDevice device = ScannedDevice(
  name: 'PDAM-Config-[123456]',
  remoteId: 'AA:BB:CC:DD:EE:FF',
  rssi: -50,
);

const ScannedDevice otherDevice = ScannedDevice(
  name: 'PDAM-Config-[654321]',
  remoteId: '11:22:33:44:55:66',
  rssi: -80,
);

const Duration shortCooldown = Duration(milliseconds: 1);

void main() {
  late FakeBleAdapter adapter;
  late FakeBlePermissions permissions;

  setUp(() {
    adapter = FakeBleAdapter();
    permissions = FakeBlePermissions();
  });

  tearDown(() async {
    await adapter.dispose();
  });

  BleProvisioningService buildService({
    Duration window = const Duration(milliseconds: 40),
    Duration cooldown = shortCooldown,
  }) => BleProvisioningService(
    adapter: adapter,
    permissions: permissions,
    window: window,
    cooldown: cooldown,
    pollInterval: const Duration(milliseconds: 5),
  );

  Future<List<BleScanEvent>> collect(
    BleProvisioningService service, {
    required int cycleId,
    Duration window = const Duration(milliseconds: 40),
  }) async {
    final events = <BleScanEvent>[];
    final done = Completer<void>();
    final sub = service
        .scanBleDispensers(cycleId: cycleId, window: window)
        .listen(events.add, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 2));
    await sub.cancel();
    return events;
  }

  group('Ventana del ciclo (RF-01, RF-03, RF-15)', () {
    test('la ventana cuenta desde el escaneo activo y no desde la invocación', () async {
      const cooldown = Duration(milliseconds: 80);
      const window = Duration(milliseconds: 30);
      final service = buildService(cooldown: cooldown);
      final events = <BleScanEvent>[];
      final done = Completer<void>();
      final sub = service
          .scanBleDispensers(cycleId: 7, window: window)
          .listen(events.add, onDone: done.complete);

      // Si la ventana se consumiera durante el cooldown, ya habría cerrado.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(adapter.startScanCalls, 0);
      expect(events.whereType<BleScanWindowClosed>(), isEmpty);

      await done.future.timeout(const Duration(seconds: 1));
      expect(adapter.lastWindow, window);
      final closed = events.single;
      expect(closed, const BleScanWindowClosed(cycleId: 7, hasDevices: false));
      await sub.cancel();
    });

    test('emite los dispositivos recibidos y cierra con hasDevices', () async {
      final service = buildService();
      final events = <BleScanEvent>[];
      final done = Completer<void>();
      final sub = service
          .scanBleDispensers(
            cycleId: 2,
            window: const Duration(milliseconds: 60),
          )
          .listen(events.add, onDone: done.complete);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.isScanning, isTrue);
      adapter.emitResults(const [device]);

      await done.future.timeout(const Duration(seconds: 1));
      final devicesEvents = events.whereType<BleScanDevices>().toList();
      expect(devicesEvents, isNotEmpty);
      expect(devicesEvents.first.cycleId, 2);
      expect(devicesEvents.first.devices, const [device]);
      expect(
        events.last,
        const BleScanWindowClosed(cycleId: 2, hasDevices: true),
      );
      expect(adapter.isScanning, isFalse);
      expect(adapter.stopScanCalls, greaterThan(0));
      await sub.cancel();
    });

    test('el sondeo existe solo mientras la ventana está abierta', () async {
      final service = buildService();
      final events = <BleScanEvent>[];
      final done = Completer<void>();
      final sub = service
          .scanBleDispensers(
            cycleId: 3,
            window: const Duration(milliseconds: 80),
          )
          .listen(events.add, onDone: done.complete);

      await Future<void>.delayed(const Duration(milliseconds: 15));
      adapter.emitResults(const [device]);

      await done.future.timeout(const Duration(seconds: 1));
      final received = events.whereType<BleScanDevices>().toList();
      expect(received.length, greaterThan(1));
      expect(received.every((event) => event.cycleId == 3), isTrue);
      expect(received.last.devices, const [device]);

      final afterClose = events.length;
      adapter.emitResults(const [otherDevice]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events.length, afterClose);
      await sub.cancel();
    });
  });

  group('Sin caché (RF-16)', () {
    test('nunca emite la lista de lastScanResults', () async {
      adapter.setCachedResults(const [device]);
      final service = buildService();

      final events = await collect(service, cycleId: 4);

      expect(events.whereType<BleScanDevices>(), isEmpty);
      expect(
        events.single,
        const BleScanWindowClosed(cycleId: 4, hasDevices: false),
      );
    });

    test('un ciclo nuevo no reutiliza la lista del anterior', () async {
      final service = buildService();
      final first = <BleScanEvent>[];
      final firstDone = Completer<void>();
      final firstSub = service
          .scanBleDispensers(
            cycleId: 5,
            window: const Duration(milliseconds: 40),
          )
          .listen(first.add, onDone: firstDone.complete);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      adapter.emitResults(const [device]);
      await firstDone.future.timeout(const Duration(seconds: 1));
      await firstSub.cancel();
      expect(first.whereType<BleScanDevices>(), isNotEmpty);

      final second = await collect(service, cycleId: 6);

      expect(second.whereType<BleScanDevices>(), isEmpty);
      expect(
        second.single,
        const BleScanWindowClosed(cycleId: 6, hasDevices: false),
      );
    });
  });

  group('Identidad y detención (RF-07, RF-08)', () {
    test('un stop de un ciclo anterior no detiene el ciclo vigente', () async {
      final service = buildService();
      final events1 = <BleScanEvent>[];
      final done1 = Completer<void>();
      final sub1 = service
          .scanBleDispensers(
            cycleId: 1,
            window: const Duration(milliseconds: 200),
          )
          .listen(events1.add, onDone: done1.complete);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.isScanning, isTrue);
      await sub1.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final events2 = <BleScanEvent>[];
      final done2 = Completer<void>();
      final sub2 = service
          .scanBleDispensers(
            cycleId: 2,
            window: const Duration(milliseconds: 200),
          )
          .listen(events2.add, onDone: done2.complete);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.isScanning, isTrue);

      await service.stopBleScan(cycleId: 1);

      expect(adapter.isScanning, isTrue);
      expect(done2.isCompleted, isFalse);
      expect(events2.whereType<BleScanWindowClosed>(), isEmpty);

      await service.stopBleScan(cycleId: 2);
      await done2.future.timeout(const Duration(seconds: 1));
      expect(adapter.isScanning, isFalse);
      await sub2.cancel();
    });

    test('detener es idempotente y no falla sin ciclo', () async {
      final service = buildService();

      await service.stopBleScan();
      await service.stopBleScan(cycleId: 9);
      expect(adapter.isScanning, isFalse);

      final events = <BleScanEvent>[];
      final done = Completer<void>();
      final sub = service
          .scanBleDispensers(
            cycleId: 3,
            window: const Duration(milliseconds: 200),
          )
          .listen(events.add, onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await service.stopBleScan(cycleId: 3);
      await done.future.timeout(const Duration(seconds: 1));
      await service.stopBleScan(cycleId: 3);

      expect(adapter.isScanning, isFalse);
      expect(events, isEmpty);
      await sub.cancel();
    });

    test('detener durante la apertura no abre ventana', () async {
      final service = buildService(cooldown: const Duration(milliseconds: 50));
      final events = <BleScanEvent>[];
      final done = Completer<void>();
      final sub = service
          .scanBleDispensers(
            cycleId: 4,
            window: const Duration(milliseconds: 100),
          )
          .listen(events.add, onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await service.stopBleScan(cycleId: 4);
      await done.future.timeout(const Duration(seconds: 1));

      expect(adapter.startScanCalls, 0);
      expect(events, isEmpty);
      await sub.cancel();
    });
  });

  group('Fallos tipados de apertura (RF-11, RF-17, RF-18, RF-25)', () {
    test('sin soporte BLE devuelve unavailable sin escanear', () async {
      adapter.supported = false;
      final service = buildService();

      final events = await collect(service, cycleId: 1);

      expect(
        events.single,
        const BleScanFailed(
          cycleId: 1,
          failure: BleScanFailure.adapterUnavailable,
        ),
      );
      expect(adapter.startScanCalls, 0);
    });

    test('permiso denegado se tipa y no escanea', () async {
      permissions = FakeBlePermissions(
        bluetoothScan: PermissionStatus.denied,
      );
      final service = buildService();

      final events = await collect(service, cycleId: 2);

      expect(
        events.single,
        const BleScanFailed(
          cycleId: 2,
          failure: BleScanFailure.permissionDenied,
        ),
      );
      expect(adapter.startScanCalls, 0);
    });

    test('permiso permanente se tipa y no escanea', () async {
      permissions = FakeBlePermissions(
        bluetoothConnect: PermissionStatus.permanentlyDenied,
      );
      final service = buildService();

      final events = await collect(service, cycleId: 3);

      expect(
        events.single,
        const BleScanFailed(
          cycleId: 3,
          failure: BleScanFailure.permissionPermanentlyDenied,
        ),
      );
    });

    test('ubicación desactivada en versión que la exige se tipa', () async {
      permissions = FakeBlePermissions(
        locationRequired: true,
        locationEnabled: false,
      );
      final service = buildService();

      final events = await collect(service, cycleId: 4);

      expect(
        events.single,
        const BleScanFailed(
          cycleId: 4,
          failure: BleScanFailure.locationDisabled,
        ),
      );
    });

    test('adaptador apagado se tipa sin encenderlo', () async {
      adapter.emitStatus(BleAdapterStatus.off);
      final service = buildService();

      final events = await collect(service, cycleId: 5);

      expect(
        events.single,
        const BleScanFailed(cycleId: 5, failure: BleScanFailure.adapterOff),
      );
      expect(adapter.startScanCalls, 0);
    });

    test('adaptador no disponible o sin autorización se tipan', () async {
      final service = buildService();

      adapter.emitStatus(BleAdapterStatus.unavailable);
      expect(
        (await collect(service, cycleId: 6)).single,
        const BleScanFailed(
          cycleId: 6,
          failure: BleScanFailure.adapterUnavailable,
        ),
      );

      adapter.emitStatus(BleAdapterStatus.unauthorized);
      expect(
        (await collect(service, cycleId: 7)).single,
        const BleScanFailed(
          cycleId: 7,
          failure: BleScanFailure.adapterUnauthorized,
        ),
      );
    });

    test('un fallo al iniciar el escaneo se tipa como startFailed', () async {
      adapter.startScanError = StateError('sin permiso del sistema');
      final service = buildService();

      final events = await collect(service, cycleId: 8);

      expect(
        events.single,
        const BleScanFailed(cycleId: 8, failure: BleScanFailure.startFailed),
      );
    });
  });

  group('Precedencia del adaptador sobre los permisos (RF-11, RF-24)', () {
    Future<void> expectAdapterFailure({
      required BleAdapterStatus status,
      required BleScanFailure expected,
    }) async {
      adapter.emitStatus(status);
      permissions = FakeBlePermissions(
        bluetoothScan: PermissionStatus.denied,
      );
      final service = buildService();

      final events = await collect(service, cycleId: 1);

      expect(events.single, BleScanFailed(cycleId: 1, failure: expected));
      expect(adapter.startScanCalls, 0);
    }

    test('con el adaptador apagado prevalece adapterOff', () async {
      await expectAdapterFailure(
        status: BleAdapterStatus.off,
        expected: BleScanFailure.adapterOff,
      );
    });

    test('con el adaptador no disponible prevalece adapterUnavailable', () async {
      await expectAdapterFailure(
        status: BleAdapterStatus.unavailable,
        expected: BleScanFailure.adapterUnavailable,
      );
    });

    test('sin autorización prevalece adapterUnauthorized', () async {
      await expectAdapterFailure(
        status: BleAdapterStatus.unauthorized,
        expected: BleScanFailure.adapterUnauthorized,
      );
    });

    test('si solo fallan los permisos el fallo sigue siendo de permisos', () async {
      permissions = FakeBlePermissions(
        bluetoothScan: PermissionStatus.denied,
      );
      final service = buildService();

      final events = await collect(service, cycleId: 1);

      expect(
        events.single,
        const BleScanFailed(
          cycleId: 1,
          failure: BleScanFailure.permissionDenied,
        ),
      );
    });
  });

  test('sin ventana explícita el servicio usa su duración por defecto', () async {
    final service = BleProvisioningService(
      adapter: adapter,
      permissions: permissions,
      window: const Duration(milliseconds: 30),
      cooldown: shortCooldown,
      pollInterval: const Duration(milliseconds: 5),
    );
    final events = <BleScanEvent>[];
    final done = Completer<void>();
    final sub = service
        .scanBleDispensers(cycleId: 12)
        .listen(events.add, onDone: done.complete);

    await done.future.timeout(const Duration(seconds: 1));

    expect(adapter.lastWindow, const Duration(milliseconds: 30));
    expect(BleProvisioningService.scanWindow, const Duration(seconds: 15));

    await sub.cancel();
  });
}
