import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/scanned_device.dart';

class BleProvisioningService {
  // Standard or custom UUIDs for ESP32 WiFi Provisioning Service/Characteristics
  static const String provisioningServiceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String ssidCharacteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a6";
  static const String passwordCharacteristicUuid = "1eb67500-8e45-4df9-bffd-a3e973e87c0e";

  StreamSubscription<List<ScanResult>>? _scanSubscription;

  Future<void> stopScan() async {
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Stream<List<ScannedDevice>> scanDevices() async* {
    // Cancel prior subscription and stop active scan before starting new one
    await stopScan();

    // Check if bluetooth is supported
    if (await FlutterBluePlus.isSupported == false) {
      throw Exception('Bluetooth no es soportado en este dispositivo.');
    }

    // Request runtime permissions for BLE scanning and connection FIRST
    await _requestPermissions();

    // Check if bluetooth is on, try to turn on or throw descriptive error
    BluetoothAdapterState currentState = FlutterBluePlus.adapterStateNow;
    if (currentState != BluetoothAdapterState.on) {
      try {
        currentState = await FlutterBluePlus.adapterState
            .timeout(const Duration(seconds: 2))
            .firstWhere((state) => state == BluetoothAdapterState.on)
            .catchError((_) => FlutterBluePlus.adapterStateNow);
      } catch (_) {}
    }

    if (currentState != BluetoothAdapterState.on) {
      try {
        if (Platform.isAndroid) {
          await FlutterBluePlus.turnOn();
          currentState = await FlutterBluePlus.adapterState
              .timeout(const Duration(seconds: 3))
              .firstWhere((state) => state == BluetoothAdapterState.on)
              .catchError((_) => FlutterBluePlus.adapterStateNow);
        }
      } catch (_) {
        throw Exception('El Bluetooth está desactivado. Por favor, actívalo en la configuración de tu teléfono para buscar dispensadores.');
      }
    }

    if (currentState != BluetoothAdapterState.on) {
      throw Exception('El Bluetooth está desactivado. Por favor, enciende el Bluetooth para continuar.');
    }

    // Start scanning
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    try {
      await for (final scanResults in FlutterBluePlus.scanResults) {
        final filtered = <ScannedDevice>[];
        for (final r in scanResults) {
          final name = r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName;
          if (name.startsWith('PDAM-Config-') || name.contains('PDAM-Config')) {
            filtered.add(ScannedDevice(
              name: name.isNotEmpty ? name : 'PDAM-Config-Device',
              remoteId: r.device.remoteId.toString(),
              rssi: r.rssi,
            ));
          }
        }
        yield filtered;
      }
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  Future<void> connectAndProvision({
    required String deviceId,
    required String ssid,
    required String password,
  }) async {
    await _requestPermissions();

    BluetoothDevice? targetDevice;
    
    // Find device in connected or scan results
    final connectedDevices = FlutterBluePlus.connectedDevices;
    for (final d in connectedDevices) {
      if (d.remoteId.toString() == deviceId) {
        targetDevice = d;
        break;
      }
    }

    targetDevice ??= BluetoothDevice(remoteId: DeviceIdentifier(deviceId));

    // Connect
    await targetDevice.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));

    try {
      // Discover services
      List<BluetoothService> services = await targetDevice.discoverServices();
      
      BluetoothCharacteristic? ssidChar;
      BluetoothCharacteristic? passChar;

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == provisioningServiceUuid.toLowerCase()) {
          for (var char in service.characteristics) {
            final uuidStr = char.uuid.toString().toLowerCase();
            if (uuidStr == ssidCharacteristicUuid.toLowerCase()) {
              ssidChar = char;
            } else if (uuidStr == passwordCharacteristicUuid.toLowerCase()) {
              passChar = char;
            }
          }
        }
      }

      // If specific characteristics not found by UUID, fallback to first/second characteristics of the service if available
      if (ssidChar == null || passChar == null) {
        for (var service in services) {
          if (service.characteristics.length >= 2) {
            ssidChar ??= service.characteristics[0];
            passChar ??= service.characteristics[1];
            break;
          }
        }
      }

      if (ssidChar == null || passChar == null) {
        throw Exception('No se encontraron las características GATT de aprovisionamiento WiFi en el dispositivo');
      }

      // Write SSID
      await ssidChar.write(utf8.encode(ssid), withoutResponse: false);

      // Write Password
      await passChar.write(utf8.encode(password), withoutResponse: false);

      // Wait a moment for device to process and disconnect
      await Future.delayed(const Duration(seconds: 2));
    } finally {
      await targetDevice.disconnect();
    }
  }
}
