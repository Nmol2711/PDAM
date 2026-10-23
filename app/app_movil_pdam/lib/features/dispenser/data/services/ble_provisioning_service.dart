import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';

class BleProvisioningService {
  // Standard or custom UUIDs for ESP32 WiFi Provisioning Service/Characteristics
  static const String provisioningServiceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String ssidCharacteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a6";
  static const String passwordCharacteristicUuid = "1eb67500-8e45-4df9-bffd-a3e973e87c0e";

  StreamSubscription<List<ScanResult>>? _scanSubscription;

  static const Duration scanCooldown = Duration(milliseconds: 1200);

  Future<void> stopScan() async {
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      await Future.delayed(scanCooldown);
    } catch (_) {
      try {
        await FlutterBluePlus.stopScan();
        await Future.delayed(scanCooldown);
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
    // Ensure any previous scan is fully stopped and respected cooldown
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      await Future.delayed(scanCooldown);
    } catch (_) {}

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

    // Start scanning with robust error handling for already scanning state
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      try {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 500));
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15),
          androidUsesFineLocation: true,
        );
      } catch (e2) {
        throw Exception('No se pudo iniciar el escaneo Bluetooth: ${e2.toString()}');
      }
    }

    List<ScannedDevice> filterResults(List<ScanResult> results) {
      final filtered = <ScannedDevice>[];
      for (final r in results) {
        final name = r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName;
        if (name.startsWith('PDAM-Config-') || name.contains('PDAM-Config')) {
          if (!filtered.any((d) => d.remoteId == r.device.remoteId.toString())) {
            filtered.add(ScannedDevice(
              name: name.isNotEmpty ? name : 'PDAM-Config-Device',
              remoteId: r.device.remoteId.toString(),
              rssi: r.rssi,
            ));
          }
        }
      }
      return filtered;
    }

    // Yield lastScanResults immediately
    try {
      final initialFiltered = filterResults(FlutterBluePlus.lastScanResults);
      if (initialFiltered.isNotEmpty) {
        yield initialFiltered;
      }
    } catch (_) {}

    final controller = StreamController<List<ScannedDevice>>();

    final sub = FlutterBluePlus.scanResults.listen((results) {
      final filtered = filterResults(results);
      if (!controller.isClosed) {
        controller.add(filtered);
      }
    }, onError: (err) {
      if (!controller.isClosed) {
        controller.addError(err);
      }
    });

    Timer? pollTimer;
    pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      try {
        final results = FlutterBluePlus.lastScanResults;
        final filtered = filterResults(results);
        if (filtered.isNotEmpty && !controller.isClosed) {
          controller.add(filtered);
        }
      } catch (_) {}
    });

    try {
      await for (final devices in controller.stream) {
        yield devices;
      }
    } finally {
      pollTimer?.cancel();
      await sub.cancel();
      await controller.close();
      try {
        if (FlutterBluePlus.isScanningNow) {
          await FlutterBluePlus.stopScan();
        }
      } catch (_) {}
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
