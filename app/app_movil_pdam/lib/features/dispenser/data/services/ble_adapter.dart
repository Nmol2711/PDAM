import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/entity/ble_adapter_status.dart';
import '../../domain/entity/provisioning_stage.dart';
import '../../domain/entity/scanned_device.dart';
import 'ble_permissions.dart';

/// Credencial que se escribe durante el aprovisionamiento (RF-19).
enum BleProvisioningField { ssid, password }

/// Handle opaco del dispensador ya conectado y con sus características GATT
/// resueltas. Lo crea la frontera y solo ella lo consume.
abstract class BleProvisioningTarget {}

/// Frontera de hardware del escaneo y del aprovisionamiento BLE.
///
/// Aísla el plugin para que servicio y pruebas hablen de tipos del proyecto.
abstract class BleAdapter {
  /// Indica si el teléfono tiene soporte BLE.
  Future<bool> get isSupported;

  /// Estado actual del adaptador, sin esperar al flujo.
  BleAdapterStatus get statusNow;

  /// Estados del adaptador desde que se escucha (RF-11, RF-12).
  Stream<BleAdapterStatus> get statusStream;

  /// Inicia un escaneo acotado a [window].
  Future<void> startScan({required Duration window});

  Future<void> stopScan();

  bool get isScanning;

  /// Resultados recibidos durante el escaneo, ya filtrados por prefijo.
  Stream<List<ScannedDevice>> get scanResults;

  /// Última caché del adaptador; el sondeo la usa solo con ventana abierta.
  List<ScannedDevice> get lastScanResults;

  /// Conecta con el dispensador. El plazo lo controla el servicio (RF-19).
  Future<void> connect(String deviceId, {required Duration timeout});

  /// Descubre los servicios y resuelve las características de aprovisionamiento.
  ///
  /// Si el dispensador no expone ambas características lanza una
  /// [ProvisioningException] con etapa `descubrimiento`.
  Future<BleProvisioningTarget> discoverProvisioningTarget(
    String deviceId, {
    required Duration timeout,
  });

  /// Escribe una credencial en la característica correspondiente.
  Future<void> writeProvisioningField(
    BleProvisioningTarget target,
    BleProvisioningField field,
    List<int> value, {
    required Duration timeout,
  });

  /// Cierra la conexión. El plazo lo controla el servicio (RF-19).
  Future<void> disconnect(String deviceId, {required Duration timeout});

  /// Emite `false` cuando se pierde la conexión con el dispensador (RF-21).
  Stream<bool> connectionState(String deviceId);
}

/// Configuración de ubicación del escaneo Android, coherente con
/// `neverForLocation` (RF-18).
///
/// En Android 12+ el escaneo no se declara para ubicación: no se piden
/// permisos de ubicación ni se exige el servicio activo. En Android 11 o
/// anterior sí son necesarios para recibir anuncios.
class AndroidScanLocationPolicy {
  const AndroidScanLocationPolicy({
    AndroidLocationRequirement requirement =
        const AndroidLocationRequirement(),
  }) : _requirement = requirement;

  final AndroidLocationRequirement _requirement;

  /// `androidUsesFineLocation`: pide `ACCESS_FINE_LOCATION` al escanear.
  bool get usesFineLocation => _requirement.isRequired;

  /// `androidCheckLocationServices`: exige el servicio de ubicación activo.
  bool get checksLocationService => _requirement.isRequired;
}

/// Implementación real sobre `flutter_blue_plus`.
class FlutterBluePlusBleAdapter implements BleAdapter {
  const FlutterBluePlusBleAdapter({
    AndroidScanLocationPolicy locationPolicy =
        const AndroidScanLocationPolicy(),
  }) : _locationPolicy = locationPolicy;

  final AndroidScanLocationPolicy _locationPolicy;

  /// Prefijo de los dispensadores en modo configuración (spec 005).
  static const String configNamePrefix = 'PDAM-Config';

  /// UUID del servicio y características de aprovisionamiento (spec 005).
  static const String provisioningServiceUuid =
      '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String ssidCharacteristicUuid =
      'beb5483e-36e1-4688-b7f5-ea07361b26a6';
  static const String passwordCharacteristicUuid =
      '1eb67500-8e45-4df9-bffd-a3e973e87c0e';

  @override
  Future<bool> get isSupported => FlutterBluePlus.isSupported;

  @override
  BleAdapterStatus get statusNow =>
      BleAdapterStatus.fromPlatformName(FlutterBluePlus.adapterStateNow.name);

  @override
  Stream<BleAdapterStatus> get statusStream => FlutterBluePlus.adapterState.map(
    (state) => BleAdapterStatus.fromPlatformName(state.name),
  );

  @override
  Future<void> startScan({required Duration window}) {
    final policy = _locationPolicy;
    return FlutterBluePlus.startScan(
      timeout: window,
      // RF-18: coherente con `neverForLocation`. En Android 12+ no se pide
      // ACCESS_FINE_LOCATION ni se exige el servicio de ubicación.
      androidUsesFineLocation: policy.usesFineLocation,
      androidCheckLocationServices: policy.checksLocationService,
    );
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  bool get isScanning => FlutterBluePlus.isScanningNow;

  @override
  Stream<List<ScannedDevice>> get scanResults =>
      FlutterBluePlus.scanResults.map(_mapResults);

  @override
  List<ScannedDevice> get lastScanResults =>
      _mapResults(FlutterBluePlus.lastScanResults);

  @override
  Future<void> connect(String deviceId, {required Duration timeout}) {
    return _deviceFor(deviceId).connect(
      license: License.nonprofit,
      timeout: timeout,
    );
  }

  @override
  Future<BleProvisioningTarget> discoverProvisioningTarget(
    String deviceId, {
    required Duration timeout,
  }) async {
    final services = await _deviceFor(deviceId).discoverServices();

    BluetoothCharacteristic? ssid;
    BluetoothCharacteristic? password;
    for (final service in services) {
      if (service.uuid.toString().toLowerCase() !=
          provisioningServiceUuid.toLowerCase()) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        final uuid = characteristic.uuid.toString().toLowerCase();
        if (uuid == ssidCharacteristicUuid.toLowerCase()) {
          ssid = characteristic;
        } else if (uuid == passwordCharacteristicUuid.toLowerCase()) {
          password = characteristic;
        }
      }
    }

    // Respaldo histórico: primeras dos características de un servicio.
    if (ssid == null || password == null) {
      for (final service in services) {
        if (service.characteristics.length >= 2) {
          ssid ??= service.characteristics[0];
          password ??= service.characteristics[1];
          break;
        }
      }
    }

    if (ssid == null || password == null) {
      throw const ProvisioningException(
        stage: ProvisioningStage.descubrimiento,
      );
    }
    return _FlutterProvisioningTarget(ssid: ssid, password: password);
  }

  @override
  Future<void> writeProvisioningField(
    BleProvisioningTarget target,
    BleProvisioningField field,
    List<int> value, {
    required Duration timeout,
  }) {
    if (target is! _FlutterProvisioningTarget) {
      throw const ProvisioningException(stage: ProvisioningStage.escritura);
    }
    final characteristic = field == BleProvisioningField.ssid
        ? target.ssid
        : target.password;
    return characteristic.write(value, withoutResponse: false);
  }

  @override
  Future<void> disconnect(String deviceId, {required Duration timeout}) {
    return _deviceFor(deviceId).disconnect();
  }

  @override
  Stream<bool> connectionState(String deviceId) =>
      _deviceFor(deviceId).connectionState.map(
        (state) => state == BluetoothConnectionState.connected,
      );

  BluetoothDevice _deviceFor(String deviceId) {
    for (final device in FlutterBluePlus.connectedDevices) {
      if (device.remoteId.toString() == deviceId) return device;
    }
    return BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
  }

  List<ScannedDevice> _mapResults(List<ScanResult> results) {
    final devices = <ScannedDevice>[];
    for (final result in results) {
      final name = result.device.platformName.isNotEmpty
          ? result.device.platformName
          : result.advertisementData.advName;
      if (!name.contains(configNamePrefix)) continue;

      final remoteId = result.device.remoteId.toString();
      if (devices.any((device) => device.remoteId == remoteId)) continue;

      devices.add(
        ScannedDevice(
          name: name.isNotEmpty ? name : 'PDAM-Config-Device',
          remoteId: remoteId,
          rssi: result.rssi,
        ),
      );
    }
    return devices;
  }
}

/// Handle real del dispensador: características ya resueltas.
class _FlutterProvisioningTarget implements BleProvisioningTarget {
  const _FlutterProvisioningTarget({
    required this.ssid,
    required this.password,
  });

  final BluetoothCharacteristic ssid;
  final BluetoothCharacteristic password;
}
