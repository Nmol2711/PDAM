import 'dart:async';
import 'dart:convert';

import 'package:app_movil_pdam/features/dispenser/data/services/ble_adapter.dart';
import 'package:app_movil_pdam/features/dispenser/data/services/ble_permissions.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_adapter_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_permission_result.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:permission_handler/permission_handler.dart';

/// Doble de la frontera de permisos: fija el estado de plataforma y la
/// ubicación sin tocar los canales del plugin (T2, T3, T7).
class FakeBlePermissions implements BlePermissions {
  FakeBlePermissions({
    this.bluetoothScan = PermissionStatus.granted,
    this.bluetoothConnect = PermissionStatus.granted,
    this.location = PermissionStatus.granted,
    this.locationRequired = false,
    this.locationEnabled = true,
  });

  final PermissionStatus bluetoothScan;
  final PermissionStatus bluetoothConnect;
  final PermissionStatus location;
  final bool locationRequired;
  final bool locationEnabled;

  int checkCalls = 0;

  @override
  Future<BlePermissionResult> check() async {
    checkCalls++;
    return buildBlePermissionResult(
      bluetoothScan: bluetoothScan,
      bluetoothConnect: bluetoothConnect,
      location: location,
      locationRequired: locationRequired,
      locationEnabled: locationEnabled,
    );
  }
}

/// Doble del adaptador BLE: controla soporte, estado, resultados y fallos de
/// arranque sin tocar el plugin (T3, T4, T7).
class FakeBleAdapter implements BleAdapter {
  FakeBleAdapter({
    this.supported = true,
    BleAdapterStatus status = BleAdapterStatus.on,
    List<ScannedDevice> cachedResults = const <ScannedDevice>[],
    this.startScanError,
  }) : _status = status,
       _lastScanResults = cachedResults;

  bool supported;

  /// Si se informa, `startScan` falla con este error.
  Object? startScanError;

  BleAdapterStatus _status;
  List<ScannedDevice> _lastScanResults;

  final StreamController<BleAdapterStatus> _statusController =
      StreamController<BleAdapterStatus>.broadcast();
  final StreamController<List<ScannedDevice>> _resultsController =
      StreamController<List<ScannedDevice>>.broadcast();

  int startScanCalls = 0;
  int stopScanCalls = 0;
  Duration? lastWindow;

  // --- Aprovisionamiento (T7) ---

  /// Si se informan, la operación queda pendiente hasta completarlas.
  Completer<void>? connectCompleter;
  Completer<void>? discoveryCompleter;
  Completer<void>? writeCompleter;
  Completer<void>? disconnectCompleter;

  /// Si se informan, la operación falla con ese error.
  Object? connectError;
  Object? discoveryError;
  Object? writeError;
  Object? disconnectError;

  int connectCalls = 0;
  int discoveryCalls = 0;
  int disconnectCalls = 0;
  Duration? lastConnectTimeout;
  Duration? lastDiscoveryTimeout;
  Duration? lastWriteTimeout;
  Duration? lastDisconnectTimeout;
  final List<({BleProvisioningField field, String value})> writes =
      <({BleProvisioningField field, String value})>[];

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast(sync: true);

  /// Simula que la conexión se pierde justo al terminar el descubrimiento, en
  /// el hueco entre etapas (RF-21).
  bool loseConnectionAfterDiscovery = false;

  @override
  bool isScanning = false;

  @override
  Future<bool> get isSupported async => supported;

  @override
  BleAdapterStatus get statusNow => _status;

  @override
  Stream<BleAdapterStatus> get statusStream => _statusController.stream;

  @override
  Future<void> startScan({required Duration window}) async {
    startScanCalls++;
    lastWindow = window;
    final error = startScanError;
    if (error != null) throw error;
    isScanning = true;
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls++;
    isScanning = false;
  }

  @override
  Stream<List<ScannedDevice>> get scanResults => _resultsController.stream;

  @override
  List<ScannedDevice> get lastScanResults => _lastScanResults;

  void emitStatus(BleAdapterStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void emitResults(List<ScannedDevice> devices) {
    _resultsController.add(devices);
  }

  void setCachedResults(List<ScannedDevice> devices) {
    _lastScanResults = devices;
  }

  @override
  Future<void> connect(String deviceId, {required Duration timeout}) async {
    connectCalls++;
    lastConnectTimeout = timeout;
    final error = connectError;
    if (error != null) throw error;
    final completer = connectCompleter;
    if (completer != null) await completer.future;
  }

  @override
  Future<BleProvisioningTarget> discoverProvisioningTarget(
    String deviceId, {
    required Duration timeout,
  }) async {
    discoveryCalls++;
    lastDiscoveryTimeout = timeout;
    final error = discoveryError;
    if (error != null) throw error;
    final completer = discoveryCompleter;
    if (completer != null) await completer.future;
    if (loseConnectionAfterDiscovery) emitConnection(false);
    return const _FakeProvisioningTarget();
  }

  @override
  Future<void> writeProvisioningField(
    BleProvisioningTarget target,
    BleProvisioningField field,
    List<int> value, {
    required Duration timeout,
  }) async {
    lastWriteTimeout = timeout;
    writes.add((field: field, value: utf8.decode(value)));
    final error = writeError;
    if (error != null) throw error;
    final completer = writeCompleter;
    if (completer != null) await completer.future;
  }

  @override
  Future<void> disconnect(String deviceId, {required Duration timeout}) async {
    disconnectCalls++;
    lastDisconnectTimeout = timeout;
    final error = disconnectError;
    if (error != null) throw error;
    final completer = disconnectCompleter;
    if (completer != null) await completer.future;
  }

  @override
  Stream<bool> connectionState(String deviceId) =>
      _connectionController.stream;

  /// Simula que la conexión con el dispensador se pierde (RF-21).
  void emitConnection(bool connected) {
    _connectionController.add(connected);
  }

  Future<void> dispose() async {
    await _resultsController.close();
    await _statusController.close();
    await _connectionController.close();
  }
}

/// Handle falso del dispensador aprovisionado.
class _FakeProvisioningTarget implements BleProvisioningTarget {
  const _FakeProvisioningTarget();
}
