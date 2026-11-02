import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_adapter_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_permission_result.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_scan_event.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/provisioning_stage.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BleAdapterStatus (RF-11, RF-12, RF-25)', () {
    test('el catálogo cubre los siete estados del adaptador', () {
      expect(BleAdapterStatus.values, hasLength(7));
      expect(
        BleAdapterStatus.values.map((status) => status.name),
        containsAll(<String>[
          'unknown',
          'unavailable',
          'unauthorized',
          'turningOn',
          'on',
          'turningOff',
          'off',
        ]),
      );
    });

    test('solo el estado on permite escanear', () {
      for (final status in BleAdapterStatus.values) {
        expect(
          status.isUsable,
          status == BleAdapterStatus.on,
          reason: 'estado ${status.name}',
        );
      }
      expect(BleAdapterStatus.on.isUsable, isTrue);
    });

    test('traduce cada nombre de estado de la plataforma', () {
      expect(
        BleAdapterStatus.fromPlatformName('unknown'),
        BleAdapterStatus.unknown,
      );
      expect(
        BleAdapterStatus.fromPlatformName('unavailable'),
        BleAdapterStatus.unavailable,
      );
      expect(
        BleAdapterStatus.fromPlatformName('unauthorized'),
        BleAdapterStatus.unauthorized,
      );
      expect(
        BleAdapterStatus.fromPlatformName('turningOn'),
        BleAdapterStatus.turningOn,
      );
      expect(BleAdapterStatus.fromPlatformName('on'), BleAdapterStatus.on);
      expect(
        BleAdapterStatus.fromPlatformName('turningOff'),
        BleAdapterStatus.turningOff,
      );
      expect(BleAdapterStatus.fromPlatformName('off'), BleAdapterStatus.off);
    });

    test('un nombre desconocido se traduce como unknown', () {
      expect(
        BleAdapterStatus.fromPlatformName('encendiendo'),
        BleAdapterStatus.unknown,
      );
    });
  });

  group('BlePermissionResult (RF-17, RF-18)', () {
    test('concedido sin ubicación exigida permite iniciar', () {
      const result = BlePermissionResult.granted();

      expect(result.status, BlePermissionStatus.granted);
      expect(result.isGranted, isTrue);
      expect(result.canStartScan, isTrue);
      expect(result.canRetry, isFalse);
      expect(result.requiresLocationSettings, isFalse);
      expect(result.requiresAppSettings, isFalse);
    });

    test('denegado no inicia y ofrece reintentar sin ajustes', () {
      const result = BlePermissionResult.denied();

      expect(result.status, BlePermissionStatus.denied);
      expect(result.isGranted, isFalse);
      expect(result.canStartScan, isFalse);
      expect(result.canRetry, isTrue);
      expect(result.requiresAppSettings, isFalse);
    });

    test('denegación permanente no inicia, no reintenta y exige ajustes', () {
      const result = BlePermissionResult.permanentlyDenied();

      expect(result.status, BlePermissionStatus.permanentlyDenied);
      expect(result.isPermanentlyDenied, isTrue);
      expect(result.canStartScan, isFalse);
      expect(result.canRetry, isFalse);
      expect(result.requiresAppSettings, isTrue);
    });

    test('concedido con ubicación exigida y desactivada no inicia', () {
      const result = BlePermissionResult.granted(
        locationRequired: true,
        locationEnabled: false,
      );

      expect(result.isGranted, isTrue);
      expect(result.requiresLocationSettings, isTrue);
      expect(result.canStartScan, isFalse);
    });

    test('concedido con ubicación exigida y activa inicia', () {
      const result = BlePermissionResult.granted(
        locationRequired: true,
        locationEnabled: true,
      );

      expect(result.requiresLocationSettings, isFalse);
      expect(result.canStartScan, isTrue);
    });

    test('igualdad por estado, ubicación exigida y ubicación activa', () {
      expect(
        const BlePermissionResult.granted(),
        const BlePermissionResult.granted(),
      );
      expect(
        const BlePermissionResult.granted(),
        isNot(const BlePermissionResult.denied()),
      );
      expect(
        const BlePermissionResult.granted(locationRequired: true),
        isNot(
          const BlePermissionResult.granted(
            locationRequired: true,
            locationEnabled: false,
          ),
        ),
      );
    });
  });

  group('ProvisioningStage y ProvisioningException (RF-19 a RF-21, RNF-01)', () {
    test('el catálogo enumera las seis etapas de aprovisionamiento', () {
      expect(ProvisioningStage.values, hasLength(6));
      expect(
        ProvisioningStage.values.map((stage) => stage.name),
        containsAll(<String>[
          'conexion',
          'descubrimiento',
          'escritura',
          'desconexion',
          'conexion_perdida',
          'presupuesto_agotado',
        ]),
      );
    });

    test('la excepción es tipada y transporta etapa y permiso', () {
      const exception = ProvisioningException(
        stage: ProvisioningStage.escritura,
        permission: BlePermissionResult.denied(),
      );

      expect(exception, isA<Exception>());
      expect(exception.stage, ProvisioningStage.escritura);
      expect(exception.permission?.status, BlePermissionStatus.denied);
      expect(
        exception,
        const ProvisioningException(
          stage: ProvisioningStage.escritura,
          permission: BlePermissionResult.denied(),
        ),
      );
      expect(
        exception,
        isNot(const ProvisioningException(stage: ProvisioningStage.conexion)),
      );
    });

    test('la excepción compara también la etapa sin permiso', () {
      expect(
        const ProvisioningException(stage: ProvisioningStage.conexion_perdida),
        const ProvisioningException(stage: ProvisioningStage.conexion_perdida),
      );
      expect(
        const ProvisioningException(stage: ProvisioningStage.conexion_perdida),
        isNot(const ProvisioningException(stage: ProvisioningStage.conexion)),
      );
    });

    test('toString es técnico y no lleva copy de interfaz', () {
      const exception = ProvisioningException(
        stage: ProvisioningStage.conexion_perdida,
      );

      expect(exception.toString(), contains('conexion_perdida'));
      expect(exception.toString(), isNot(contains('Vuelve a intentarlo')));
    });
  });

  group('ScannedDevice (RF-10)', () {
    test('iguala por remoteId aunque cambien nombre y RSSI', () {
      const previo = ScannedDevice(
        name: 'PDAM-Config-01',
        remoteId: 'AA:BB:CC:DD:EE:FF',
        rssi: -70,
      );
      const actual = ScannedDevice(
        name: 'PDAM-Config-01 (2)',
        remoteId: 'AA:BB:CC:DD:EE:FF',
        rssi: -30,
      );

      expect(actual, previo);
      expect(actual.hashCode, previo.hashCode);
      expect(
        actual,
        isNot(
          const ScannedDevice(
            name: 'PDAM-Config-01',
            remoteId: '11:22:33:44:55:66',
            rssi: -70,
          ),
        ),
      );
    });
  });

  group('BleScanEvent (RF-01 a RF-04, RF-07)', () {
    const device = ScannedDevice(
      name: 'PDAM-Config-01',
      remoteId: 'AA:BB:CC:DD:EE:FF',
      rssi: -52,
    );
    const other = ScannedDevice(
      name: 'PDAM-Config-02',
      remoteId: '11:22:33:44:55:66',
      rssi: -80,
    );

    test('BleScanDevices iguala por ciclo y dispositivos', () {
      const event = BleScanDevices(cycleId: 3, devices: [device]);

      expect(event, isA<BleScanEvent>());
      expect(event, const BleScanDevices(cycleId: 3, devices: [device]));
      expect(
        event,
        isNot(const BleScanDevices(cycleId: 4, devices: [device])),
      );
      expect(event, isNot(const BleScanDevices(cycleId: 3, devices: [other])));
      expect(event, isNot(const BleScanDevices(cycleId: 3, devices: [])));
    });

    test('BleScanDevices no cambia por RSSI ni por nombre del dispositivo', () {
      const refrescado = ScannedDevice(
        name: 'PDAM-Config-01 (actualizado)',
        remoteId: 'AA:BB:CC:DD:EE:FF',
        rssi: -30,
      );

      expect(
        const BleScanDevices(cycleId: 3, devices: [device]),
        const BleScanDevices(cycleId: 3, devices: [refrescado]),
      );
    });

    test('BleScanWindowClosed iguala por ciclo y presencia de dispositivos', () {
      const event = BleScanWindowClosed(cycleId: 3, hasDevices: false);

      expect(event, isA<BleScanEvent>());
      expect(event, const BleScanWindowClosed(cycleId: 3, hasDevices: false));
      expect(
        event,
        isNot(const BleScanWindowClosed(cycleId: 3, hasDevices: true)),
      );
      expect(
        event,
        isNot(const BleScanWindowClosed(cycleId: 2, hasDevices: false)),
      );
    });

    test('BleScanFailed iguala por ciclo y causa tipada', () {
      expect(
        const BleScanFailed(
          cycleId: 3,
          failure: BleScanFailure.permissionDenied,
        ),
        const BleScanFailed(
          cycleId: 3,
          failure: BleScanFailure.permissionDenied,
        ),
      );
      expect(
        const BleScanFailed(
          cycleId: 3,
          failure: BleScanFailure.permissionDenied,
        ),
        isNot(
          const BleScanFailed(
            cycleId: 4,
            failure: BleScanFailure.permissionDenied,
          ),
        ),
      );
      expect(
        const BleScanFailed(
          cycleId: 3,
          failure: BleScanFailure.permissionDenied,
        ),
        isNot(const BleScanFailed(cycleId: 3, failure: BleScanFailure.startFailed)),
      );
      expect(
        const BleScanFailed(cycleId: 3, failure: BleScanFailure.startFailed),
        isA<BleScanEvent>(),
      );
    });

    test('eventos de distinto tipo nunca son iguales', () {
      const devices = BleScanDevices(cycleId: 3, devices: [device]);
      const closed = BleScanWindowClosed(cycleId: 3, hasDevices: true);

      expect(devices, isNot(closed));
      expect(
        closed,
        isNot(
          const BleScanFailed(cycleId: 3, failure: BleScanFailure.startFailed),
        ),
      );
    });
  });
}
