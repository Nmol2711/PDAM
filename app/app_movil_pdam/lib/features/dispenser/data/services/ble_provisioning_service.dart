import 'dart:async';
import 'dart:convert';
import 'package:app_movil_pdam/features/dispenser/data/services/ble_adapter.dart';
import 'package:app_movil_pdam/features/dispenser/data/services/ble_permissions.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_adapter_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_scan_event.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/provisioning_stage.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';

/// Duraciones del aprovisionamiento (RF-19 a RF-21).
///
/// Son inyectables para que las pruebas no esperen segundos reales; los
/// valores por defecto son los de la spec.
class ProvisioningTimeouts {
  const ProvisioningTimeouts({
    this.connect = const Duration(seconds: 15),
    this.discovery = const Duration(seconds: 10),
    this.write = const Duration(seconds: 10),
    this.disconnect = const Duration(seconds: 5),
    this.budget = const Duration(seconds: 60),
    this.settle = const Duration(seconds: 2),
  });

  /// Conexión con el dispensador.
  final Duration connect;

  /// Descubrimiento de los servicios GATT.
  final Duration discovery;

  /// Escritura de cada credencial.
  final Duration write;

  /// Cierre de la conexión.
  final Duration disconnect;

  /// Presupuesto total hasta un estado terminal.
  final Duration budget;

  /// Espera a que el dispensador procese las credenciales.
  final Duration settle;
}

class BleProvisioningService {
  BleProvisioningService({
    BleAdapter? adapter,
    BlePermissions? permissions,
    Duration window = scanWindow,
    Duration cooldown = scanCooldown,
    Duration pollInterval = scanPollInterval,
    ProvisioningTimeouts timeouts = const ProvisioningTimeouts(),
  }) : _adapter = adapter ?? const FlutterBluePlusBleAdapter(),
       _permissions = permissions ?? const PermissionHandlerBlePermissions(),
       _window = window,
       _cooldown = cooldown,
       _pollInterval = pollInterval,
       _timeouts = timeouts;

  final BleAdapter _adapter;
  final BlePermissions _permissions;
  final Duration _window;
  final Duration _cooldown;
  final Duration _pollInterval;
  final ProvisioningTimeouts _timeouts;

  // UUID del servicio y características de aprovisionamiento (spec 005).
  // La fuente es la frontera del adaptador para no duplicar literales.
  static const String provisioningServiceUuid =
      FlutterBluePlusBleAdapter.provisioningServiceUuid;
  static const String ssidCharacteristicUuid =
      FlutterBluePlusBleAdapter.ssidCharacteristicUuid;
  static const String passwordCharacteristicUuid =
      FlutterBluePlusBleAdapter.passwordCharacteristicUuid;

  static const Duration scanWindow = Duration(seconds: 15);
  static const Duration scanCooldown = Duration(milliseconds: 1200);
  static const Duration scanPollInterval = Duration(milliseconds: 500);

  /// Ciclo dueño del escaneo; `null` si no hay ventana abierta ni apertura.
  int? _activeCycleId;

  /// Cierre del ciclo vigente, usado por [stopBleScan] (RF-08).
  Future<void> Function()? _activeCycleStop;

  /// Estado del adaptador para los avisos de la pantalla (RF-11, RF-12, RF-25).
  Stream<BleAdapterStatus> get adapterStatus => _adapter.statusStream;

  /// Frontera de permisos y ubicación que el ciclo usa al abrirse (T7).
  BlePermissions get permissions => _permissions;

  /// Abre una ventana de escaneo con identidad propia (RF-01, RF-03, RF-07).
  ///
  /// La fase de apertura (cooldown y comprobación de soporte, permisos y
  /// adaptador) se informa con [BleScanFailed]; la ventana solo empieza a
  /// contar cuando el escaneo del adaptador está activo. Al vencer se emite
  /// [BleScanWindowClosed] como último evento. La renovación la decide el
  /// consumidor (T4), no el servicio.
  Stream<BleScanEvent> scanBleDispensers({
    required int cycleId,
    Duration? window,
  }) {
    final effectiveWindow = window ?? _window;
    late StreamController<BleScanEvent> controller;
    StreamSubscription<List<ScannedDevice>>? resultsSubscription;
    Timer? pollTimer;
    Timer? windowTimer;
    List<ScannedDevice> lastDevices = const <ScannedDevice>[];
    var hasDevices = false;
    var finished = false;

    /// Libera los recursos del ciclo. Solo detiene el adaptador si este ciclo
    /// sigue siendo el vigente (RF-07).
    Future<void> release({bool emitClosed = false}) async {
      if (finished) return;
      finished = true;
      pollTimer?.cancel();
      pollTimer = null;
      windowTimer?.cancel();
      windowTimer = null;
      await resultsSubscription?.cancel();
      resultsSubscription = null;

      final ownsAdapter = _activeCycleId == cycleId;
      if (ownsAdapter) {
        _activeCycleId = null;
        _activeCycleStop = null;
      }

      if (!controller.isClosed) {
        if (emitClosed) {
          controller.add(
            BleScanWindowClosed(cycleId: cycleId, hasDevices: hasDevices),
          );
        }
        unawaited(controller.close());
      }

      if (ownsAdapter) {
        try {
          if (_adapter.isScanning) await _adapter.stopScan();
        } catch (_) {}
      }
    }

    void publish(List<ScannedDevice> devices) {
      lastDevices = devices;
      if (devices.isNotEmpty) hasDevices = true;
      if (!controller.isClosed) {
        controller.add(BleScanDevices(cycleId: cycleId, devices: devices));
      }
    }

    Future<void> fail(BleScanFailure failure) async {
      if (finished) return;
      finished = true;
      if (_activeCycleId == cycleId) {
        _activeCycleId = null;
        _activeCycleStop = null;
      }
      if (!controller.isClosed) {
        controller.add(BleScanFailed(cycleId: cycleId, failure: failure));
        unawaited(controller.close());
      }
    }

    Future<void> start() async {
      try {
        if (_adapter.isScanning) await _adapter.stopScan();
      } catch (_) {}
      await Future<void>.delayed(_cooldown);
      if (finished) return;

      final failure = await _openingFailure();
      if (finished) return;
      if (failure != null) {
        await fail(failure);
        return;
      }

      try {
        await _adapter.startScan(window: effectiveWindow);
      } catch (_) {
        await fail(BleScanFailure.startFailed);
        return;
      }

      if (finished) {
        try {
          await _adapter.stopScan();
        } catch (_) {}
        return;
      }

      resultsSubscription = _adapter.scanResults.listen(
        (devices) {
          if (finished) return;
          publish(devices);
        },
        onError: (Object _) {
          // Un error puntual del flujo no cierra la ventana: el cierre lo
          // decide el temporizador de la ventana (RF-01, RF-15).
        },
      );

      // Sondeo ligado a la ventana: solo repite lo recibido en este ciclo y se
      // cancela al cerrarla. Nunca lee la caché del adaptador (RF-15, RF-16).
      pollTimer = Timer.periodic(_pollInterval, (_) {
        if (finished || lastDevices.isEmpty) return;
        publish(lastDevices);
      });

      windowTimer = Timer(effectiveWindow, () {
        unawaited(release(emitClosed: true));
      });
    }

    controller = StreamController<BleScanEvent>(
      onListen: () {
        _activeCycleId = cycleId;
        _activeCycleStop = release;
        unawaited(start());
      },
      onCancel: () => release(),
    );
    return controller.stream;
  }

  /// Detiene el ciclo indicado (RF-07, RF-08).
  ///
  /// Sin [cycleId] detiene el ciclo vigente. Con un identificador ajeno no
  /// toca nada: un cierre tardío no puede detener un ciclo posterior.
  Future<void> stopBleScan({int? cycleId}) async {
    final activeCycleId = _activeCycleId;
    if (activeCycleId == null) return;
    if (cycleId != null && cycleId != activeCycleId) return;

    final stop = _activeCycleStop;
    if (stop != null) await stop();
  }

  /// Traduce la apertura a un fallo tipado, sin textos ni excepciones (RNF-01).
  Future<BleScanFailure?> _openingFailure() async {
    if (!await _adapter.isSupported) {
      return BleScanFailure.adapterUnavailable;
    }

    // RF-11/RF-24: el estado del adaptador manda sobre los permisos. Si ambos
    // fallan, el fallo tipado ya es el del adaptador.
    switch (_adapter.statusNow) {
      case BleAdapterStatus.off:
        return BleScanFailure.adapterOff;
      case BleAdapterStatus.unavailable:
        return BleScanFailure.adapterUnavailable;
      case BleAdapterStatus.unauthorized:
        return BleScanFailure.adapterUnauthorized;
      default:
        break;
    }

    final permission = await _permissions.check();
    if (!permission.canStartScan) {
      if (permission.requiresLocationSettings) {
        return BleScanFailure.locationDisabled;
      }
      if (permission.isPermanentlyDenied) {
        return BleScanFailure.permissionPermanentlyDenied;
      }
      return BleScanFailure.permissionDenied;
    }

    return null;
  }

  /// Aprovisiona las credenciales WiFi con estado terminal garantizado.
  ///
  /// Comprueba permisos antes de conectar (RF-17), acota cada etapa (RF-19),
  /// respeta el presupuesto total (RF-20) y traduce la pérdida de conexión a
  /// `conexion_perdida` (RF-21). Nunca propaga textos de excepción: siempre
  /// lanza [ProvisioningException] con una etapa del catálogo (RNF-01).
  Future<void> connectAndProvision({
    required String deviceId,
    required String ssid,
    required String password,
  }) async {
    final permission = await _permissions.check();
    if (!permission.canStartScan) {
      throw ProvisioningException(
        stage: ProvisioningStage.conexion,
        permission: permission,
      );
    }

    final watch = Stopwatch()..start();
    final lost = Completer<void>();
    StreamSubscription<bool>? connection;
    var stage = ProvisioningStage.conexion;

    try {
      stage = ProvisioningStage.conexion;
      await _runProvisionStage<void>(
        watch: watch,
        stage: stage,
        configured: _timeouts.connect,
        operation: (limit) => _adapter.connect(deviceId, timeout: limit),
      );

      connection = _adapter.connectionState(deviceId).listen((connected) {
        if (!connected && !lost.isCompleted) lost.complete();
      });

      stage = ProvisioningStage.descubrimiento;
      final target = await _runProvisionStage<BleProvisioningTarget>(
        watch: watch,
        stage: stage,
        configured: _timeouts.discovery,
        lost: lost,
        operation: (limit) => _adapter.discoverProvisioningTarget(
          deviceId,
          timeout: limit,
        ),
      );

      stage = ProvisioningStage.escritura;
      await _runProvisionStage<void>(
        watch: watch,
        stage: stage,
        configured: _timeouts.write,
        lost: lost,
        operation: (limit) => _adapter.writeProvisioningField(
          target,
          BleProvisioningField.ssid,
          utf8.encode(ssid),
          timeout: limit,
        ),
      );
      await _runProvisionStage<void>(
        watch: watch,
        stage: stage,
        configured: _timeouts.write,
        lost: lost,
        operation: (limit) => _adapter.writeProvisioningField(
          target,
          BleProvisioningField.password,
          utf8.encode(password),
          timeout: limit,
        ),
      );

      // Espera a que el dispensador procese las credenciales (RF-21).
      await _runProvisionStage<void>(
        watch: watch,
        stage: stage,
        configured: _timeouts.settle,
        lost: lost,
        operation: (_) => Future<void>.delayed(_timeouts.settle),
      );
    } on ProvisioningException {
      await _safeDisconnect(deviceId, watch);
      rethrow;
    } catch (_) {
      await _safeDisconnect(deviceId, watch);
      throw ProvisioningException(stage: stage);
    } finally {
      await connection?.cancel();
    }

    await _runProvisionStage<void>(
      watch: watch,
      stage: ProvisioningStage.desconexion,
      configured: _timeouts.disconnect,
      operation: (limit) => _adapter.disconnect(deviceId, timeout: limit),
    );
  }

  /// Ejecuta una etapa con su plazo, el presupuesto global y la pérdida de
  /// conexión como carreras (RF-19 a RF-21).
  Future<T> _runProvisionStage<T>({
    required Stopwatch watch,
    required ProvisioningStage stage,
    required Duration configured,
    required Future<T> Function(Duration limit) operation,
    Completer<void>? lost,
  }) async {
    final remaining = _timeouts.budget - watch.elapsed;
    if (remaining <= Duration.zero) {
      throw const ProvisioningException(
        stage: ProvisioningStage.presupuesto_agotado,
      );
    }

    // Una pérdida ya registrada aborta la etapa, aunque haya ocurrido en el
    // hueco entre el fin de una etapa y el inicio de la siguiente (RF-21).
    if (lost != null && lost.isCompleted) {
      throw const ProvisioningException(
        stage: ProvisioningStage.conexion_perdida,
      );
    }

    final budgetLimited = remaining < configured;
    final limit = budgetLimited ? remaining : configured;
    final candidates = <Future<T>>[Future<T>.sync(() => operation(limit))];
    if (lost != null) {
      candidates.add(
        lost.future.then<T>((_) {
          throw const ProvisioningException(
            stage: ProvisioningStage.conexion_perdida,
          );
        }),
      );
    }

    try {
      return await Future.any(candidates).timeout(limit);
    } on TimeoutException {
      throw ProvisioningException(
        stage: budgetLimited
            ? ProvisioningStage.presupuesto_agotado
            : stage,
      );
    } on ProvisioningException {
      rethrow;
    } catch (_) {
      throw ProvisioningException(stage: stage);
    }
  }

  /// Desconexión best-effort tras un fallo: nunca sustituye el error original
  /// ni excede el presupuesto restante (RF-19, RF-20).
  Future<void> _safeDisconnect(String deviceId, Stopwatch watch) async {
    final remaining = _timeouts.budget - watch.elapsed;
    if (remaining <= Duration.zero) return;
    final limit = remaining < _timeouts.disconnect
        ? remaining
        : _timeouts.disconnect;
    try {
      await _adapter.disconnect(deviceId, timeout: limit).timeout(limit);
    } catch (_) {
      // Sin reconexión automática ni máscara del fallo original.
    }
  }
}
