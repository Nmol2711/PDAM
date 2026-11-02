import 'dart:io';

import 'package:app_movil_pdam/features/dispenser/data/services/ble_adapter.dart';
import 'package:app_movil_pdam/features/dispenser/data/services/ble_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Construye la política de escaneo con una versión y plataforma inyectadas,
/// sin leer el SDK real (RF-18).
AndroidScanLocationPolicy _policy(String version, {bool isAndroid = true}) =>
    AndroidScanLocationPolicy(
      requirement: AndroidLocationRequirement(
        isAndroid: () => isAndroid,
        operatingSystemVersion: () => version,
      ),
    );

void main() {
  group('Configuración de escaneo Android (RF-18)', () {
    test('en Android 11 y anteriores usa y exige ubicación', () {
      final policy = _policy('Android 11 (API 30)');

      expect(policy.usesFineLocation, isTrue);
      expect(policy.checksLocationService, isTrue);
    });

    test('en Android 12 y posteriores no usa ni exige ubicación', () {
      for (final version in <String>[
        'Android 12 (API 31)',
        'Android 13 (API 33)',
        'Android 15 (API 35)',
      ]) {
        final policy = _policy(version);

        expect(policy.usesFineLocation, isFalse, reason: version);
        expect(policy.checksLocationService, isFalse, reason: version);
      }
    });

    test('fuera de Android o sin versión interpretable no exige ubicación', () {
      expect(
        _policy('iOS 17.2', isAndroid: false).usesFineLocation,
        isFalse,
      );
      expect(
        _policy('Android sin datos').checksLocationService,
        isFalse,
      );
    });
  });

  group('Manifiesto coherente con neverForLocation (RF-18, RNF-08)', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('BLUETOOTH_SCAN se declara con neverForLocation', () {
      expect(
        RegExp(
          r'<uses-permission[^>]*BLUETOOTH_SCAN[^>]*neverForLocation',
        ).hasMatch(manifest),
        isTrue,
      );
    });

    test('la ubicación solo se declara hasta Android 11', () {
      final fine = RegExp(
        r'<uses-permission[^>]*ACCESS_FINE_LOCATION[^>]*>',
      ).firstMatch(manifest)?.group(0);
      final coarse = RegExp(
        r'<uses-permission[^>]*ACCESS_COARSE_LOCATION[^>]*>',
      ).firstMatch(manifest)?.group(0);

      expect(fine, isNotNull);
      expect(coarse, isNotNull);
      expect(fine, contains('maxSdkVersion="30"'));
      expect(coarse, contains('maxSdkVersion="30"'));
    });
  });
}
