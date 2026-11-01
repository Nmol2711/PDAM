import 'package:app_movil_pdam/features/dispenser/data/services/ble_permissions.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_permission_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../support/ble_fakes.dart';

AndroidLocationRequirement _requirement(
  String version, {
  bool isAndroid = true,
}) => AndroidLocationRequirement(
  isAndroid: () => isAndroid,
  operatingSystemVersion: () => version,
);

void main() {
  group('BlePermissions (RF-17, RF-18)', () {
    test('traduce permisos concedidos sin ubicación exigida', () async {
      final result = await FakeBlePermissions().check();

      expect(result.status, BlePermissionStatus.granted);
      expect(result.canStartScan, isTrue);
      expect(result.canRetry, isFalse);
      expect(result.requiresLocationSettings, isFalse);
      expect(result.requiresAppSettings, isFalse);
    });

    test('traduce una denegación recuperable', () async {
      final result = await FakeBlePermissions(
        bluetoothScan: PermissionStatus.denied,
      ).check();

      expect(result.status, BlePermissionStatus.denied);
      expect(result.canStartScan, isFalse);
      expect(result.canRetry, isTrue);
      expect(result.requiresAppSettings, isFalse);
    });

    test('traduce una denegación permanente', () async {
      final result = await FakeBlePermissions(
        bluetoothConnect: PermissionStatus.permanentlyDenied,
      ).check();

      expect(result.status, BlePermissionStatus.permanentlyDenied);
      expect(result.canStartScan, isFalse);
      expect(result.canRetry, isFalse);
      expect(result.requiresAppSettings, isTrue);
    });

    test('concedido con ubicación exigida y desactivada no inicia', () async {
      final result = await FakeBlePermissions(
        locationRequired: true,
        locationEnabled: false,
      ).check();

      expect(result.status, BlePermissionStatus.granted);
      expect(result.requiresLocationSettings, isTrue);
      expect(result.canStartScan, isFalse);
    });

    test('concedido con ubicación exigida y activa inicia', () async {
      final result = await FakeBlePermissions(
        locationRequired: true,
        locationEnabled: true,
      ).check();

      expect(result.requiresLocationSettings, isFalse);
      expect(result.canStartScan, isTrue);
    });

    test('la ubicación denegada en una versión que la exige no inicia', () async {
      final result = await FakeBlePermissions(
        location: PermissionStatus.denied,
        locationRequired: true,
        locationEnabled: true,
      ).check();

      expect(result.status, BlePermissionStatus.denied);
      expect(result.canStartScan, isFalse);
      expect(result.canRetry, isTrue);
    });

    test('sin ubicación exigida la frontera inyecta el valor activo', () {
      final result = buildBlePermissionResult(
        bluetoothScan: PermissionStatus.granted,
        bluetoothConnect: PermissionStatus.granted,
        locationRequired: false,
        locationEnabled: false,
      );

      expect(result.locationRequired, isFalse);
      expect(result.locationEnabled, isTrue);
      expect(result.canStartScan, isTrue);
    });

    test('con ubicación exigida y desactivada conserva el valor real', () {
      final result = buildBlePermissionResult(
        bluetoothScan: PermissionStatus.granted,
        bluetoothConnect: PermissionStatus.granted,
        location: PermissionStatus.granted,
        locationRequired: true,
        locationEnabled: false,
      );

      expect(result.locationRequired, isTrue);
      expect(result.locationEnabled, isFalse);
      expect(result.canStartScan, isFalse);
    });
  });

  group('AndroidLocationRequirement (RF-18)', () {
    test('Android 10 y 11 exigen ubicación', () {
      expect(_requirement('Android 10 (API 29)').isRequired, isTrue);
      expect(_requirement('Android 11 (API 30)').isRequired, isTrue);
    });

    test('Android 12 y posteriores no exigen ubicación', () {
      expect(_requirement('Android 12 (API 31)').isRequired, isFalse);
      expect(_requirement('Android 13 (API 33)').isRequired, isFalse);
      expect(_requirement('Android 15 (API 35)').isRequired, isFalse);
    });

    test('interpreta versiones sin paréntesis', () {
      expect(_requirement('Android 10').isRequired, isTrue);
      expect(_requirement('Android 12').isRequired, isFalse);
      expect(_requirement('Android 5.1.1').isRequired, isTrue);
    });

    test('una versión no interpretable no exige ubicación', () {
      expect(_requirement('').isRequired, isFalse);
      expect(_requirement('Android sin datos').isRequired, isFalse);
      expect(_requirement('Android 9 (sin API)').isRequired, isTrue);
    });

    test('fuera de Android nunca exige ubicación', () {
      expect(
        _requirement('Android 9 (API 28)', isAndroid: false).isRequired,
        isFalse,
      );
      expect(_requirement('iOS 17.2', isAndroid: false).isRequired, isFalse);
    });

    test('androidApiLevel extrae la API de los formatos reales', () {
      expect(androidApiLevel('Android 13 (API 33)'), 33);
      expect(androidApiLevel('API 30'), 30);
      expect(androidApiLevel('API level 28'), 28);
      expect(androidApiLevel('Android 14'), 34);
      expect(androidApiLevel('iOS 17.2'), isNull);
      expect(androidApiLevel(''), isNull);
    });
  });
}
