import 'dart:async';

import 'package:app_movil_pdam/features/dispenser/data/services/ble_adapter.dart';
import 'package:app_movil_pdam/features/dispenser/data/services/ble_provisioning_service.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_permission_result.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/provisioning_stage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../support/ble_fakes.dart';

const String deviceId = 'AA:BB:CC:DD:EE:FF';

/// Duraciones cortas: ninguna prueba espera segundos reales.
const ProvisioningTimeouts fastTimeouts = ProvisioningTimeouts(
  connect: Duration(milliseconds: 40),
  discovery: Duration(milliseconds: 40),
  write: Duration(milliseconds: 40),
  disconnect: Duration(milliseconds: 40),
  budget: Duration(seconds: 5),
  settle: Duration(milliseconds: 2),
);

/// Duraciones holgadas para provocar la pérdida de conexión antes del plazo.
const ProvisioningTimeouts patientTimeouts = ProvisioningTimeouts(
  connect: Duration(milliseconds: 200),
  discovery: Duration(milliseconds: 200),
  write: Duration(milliseconds: 200),
  disconnect: Duration(milliseconds: 200),
  budget: Duration(seconds: 5),
  settle: Duration(milliseconds: 300),
);

void main() {
  late FakeBleAdapter adapter;
  late FakeBlePermissions permissions;
  late BleProvisioningService service;

  BleProvisioningService buildService(ProvisioningTimeouts timeouts) =>
      BleProvisioningService(
        adapter: adapter,
        permissions: permissions,
        timeouts: timeouts,
      );

  setUp(() {
    adapter = FakeBleAdapter();
    permissions = FakeBlePermissions();
    service = buildService(fastTimeouts);
  });

  tearDown(() async {
    await adapter.dispose();
  });

  Future<void> provision() => service.connectAndProvision(
    deviceId: deviceId,
    ssid: 'RedCasa',
    password: 'claveWiFi',
  );

  Matcher failsAt(ProvisioningStage stage) => throwsA(
    isA<ProvisioningException>().having((error) => error.stage, 'etapa', stage),
  );

  group('Aprovisionamiento exitoso (RF-19)', () {
    test('conecta, descubre, escribe ambas credenciales y desconecta', () async {
      await provision();

      expect(adapter.connectCalls, 1);
      expect(adapter.discoveryCalls, 1);
      expect(adapter.writes.map((write) => write.field), <BleProvisioningField>[
        BleProvisioningField.ssid,
        BleProvisioningField.password,
      ]);
      expect(adapter.writes.map((write) => write.value), <String>[
        'RedCasa',
        'claveWiFi',
      ]);
      expect(adapter.disconnectCalls, 1);
    });

    test('usa las duraciones de etapa inyectadas', () async {
      await provision();

      expect(adapter.lastConnectTimeout, fastTimeouts.connect);
      expect(adapter.lastDiscoveryTimeout, fastTimeouts.discovery);
      expect(adapter.lastWriteTimeout, fastTimeouts.write);
      expect(adapter.lastDisconnectTimeout, fastTimeouts.disconnect);
    });
  });

  group('Timeouts por etapa (RF-19)', () {
    test('la conexión vence con la etapa conexion', () async {
      adapter.connectCompleter = Completer<void>();

      await expectLater(provision(), failsAt(ProvisioningStage.conexion));

      expect(adapter.discoveryCalls, 0);
      expect(adapter.writes, isEmpty);
      // Intenta desconectar sin exceder su límite.
      expect(adapter.disconnectCalls, greaterThanOrEqualTo(1));
    });

    test('el descubrimiento vence con la etapa descubrimiento', () async {
      adapter.discoveryCompleter = Completer<void>();

      await expectLater(
        provision(),
        failsAt(ProvisioningStage.descubrimiento),
      );

      expect(adapter.connectCalls, 1);
      expect(adapter.writes, isEmpty);
    });

    test('la escritura vence con la etapa escritura', () async {
      adapter.writeCompleter = Completer<void>();

      await expectLater(provision(), failsAt(ProvisioningStage.escritura));

      expect(adapter.writes, hasLength(1));
    });

    test('la desconexión vence con la etapa desconexion', () async {
      adapter.disconnectCompleter = Completer<void>();

      await expectLater(provision(), failsAt(ProvisioningStage.desconexion));

      expect(adapter.writes, hasLength(2));
    });

    test('el presupuesto agotado gana a una etapa sin vencer', () async {
      service = buildService(
        const ProvisioningTimeouts(
          connect: Duration(seconds: 5),
          discovery: Duration(seconds: 5),
          write: Duration(seconds: 5),
          disconnect: Duration(milliseconds: 40),
          budget: Duration(milliseconds: 60),
          settle: Duration(milliseconds: 2),
        ),
      );
      adapter.connectCompleter = Completer<void>();

      await expectLater(
        provision(),
        failsAt(ProvisioningStage.presupuesto_agotado),
      );

      expect(adapter.discoveryCalls, 0);
    });
  });

  group('Pérdida de conexión (RF-21)', () {
    Future<void> loseConnectionDuring(Future<void> future) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      adapter.emitConnection(false);
      await expectLater(future, failsAt(ProvisioningStage.conexion_perdida));
    }

    test('durante el descubrimiento devuelve conexion_perdida', () async {
      service = buildService(patientTimeouts);
      adapter.discoveryCompleter = Completer<void>();

      await loseConnectionDuring(provision());

      expect(adapter.writes, isEmpty);
    });

    test('durante la escritura devuelve conexion_perdida', () async {
      service = buildService(patientTimeouts);
      adapter.writeCompleter = Completer<void>();

      await loseConnectionDuring(provision());

      expect(adapter.writes, hasLength(1));
    });

    test('durante la espera devuelve conexion_perdida', () async {
      service = buildService(patientTimeouts);

      await loseConnectionDuring(provision());

      expect(adapter.writes, hasLength(2));
    });

    test('registrada entre etapas aborta antes de la escritura', () async {
      service = buildService(patientTimeouts);
      adapter.discoveryCompleter = Completer<void>();
      adapter.loseConnectionAfterDiscovery = true;

      final future = provision();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      adapter.discoveryCompleter!.complete();

      await expectLater(future, failsAt(ProvisioningStage.conexion_perdida));

      // La pérdida ocurre justo al terminar el descubrimiento: no se escribe.
      expect(adapter.writes, isEmpty);
    });
  });

  group('Permisos al aprovisionar (RF-17)', () {
    test('denegado no inicia y devuelve la causa tipada', () async {
      permissions = FakeBlePermissions(bluetoothScan: PermissionStatus.denied);
      service = buildService(fastTimeouts);

      await expectLater(
        provision(),
        throwsA(
          isA<ProvisioningException>()
              .having((error) => error.stage, 'etapa', ProvisioningStage.conexion)
              .having(
                (error) => error.permission?.status,
                'permiso',
                BlePermissionStatus.denied,
              )
              .having((error) => error.permission?.canRetry, 'reintento', isTrue),
        ),
      );

      expect(adapter.connectCalls, 0);
    });

    test('permanente no inicia y exige ajustes', () async {
      permissions = FakeBlePermissions(
        bluetoothConnect: PermissionStatus.permanentlyDenied,
      );
      service = buildService(fastTimeouts);

      await expectLater(
        provision(),
        throwsA(
          isA<ProvisioningException>().having(
            (error) => error.permission?.requiresAppSettings,
            'ajustes',
            isTrue,
          ),
        ),
      );

      expect(adapter.connectCalls, 0);
    });

    test('ubicación desactivada en versión que la exige no inicia', () async {
      permissions = FakeBlePermissions(
        locationRequired: true,
        locationEnabled: false,
      );
      service = buildService(fastTimeouts);

      await expectLater(
        provision(),
        throwsA(
          isA<ProvisioningException>().having(
            (error) => error.permission?.requiresLocationSettings,
            'ubicación',
            isTrue,
          ),
        ),
      );

      expect(adapter.connectCalls, 0);
    });
  });

  group('Descubrimiento sin características (RNF-01)', () {
    test('devuelve la etapa descubrimiento sin textos de excepción', () async {
      adapter.discoveryError = const ProvisioningException(
        stage: ProvisioningStage.descubrimiento,
      );

      await expectLater(
        provision(),
        failsAt(ProvisioningStage.descubrimiento),
      );

      expect(adapter.writes, isEmpty);
    });
  });
}
