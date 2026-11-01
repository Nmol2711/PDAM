import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_adapter_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_scan_event.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:dartz/dartz.dart';

/// Contrato único del módulo de dispensadores.
///
/// Reúne las operaciones del flujo de asociación por QR/MAC y las del flujo de
/// aprovisionamiento BLE/WiFi. Así la presentación depende de un solo
/// repositorio y no existen dos implementaciones paralelas.
abstract class DispenserRepositories {
  // --- Flujo QR / MAC (servidor) ---
  Future<Either<Failures, Dispenser>> associateDispenser(
    String macAddress,
    int petId,
    String secretKeyQr,
  );
  Future<Either<Failures, Map<String, dynamic>>> checkPendingTask(
    String macAddress,
  );
  Future<Either<Failures, bool>> dasactivateDispenser(
    int dispenserId,
    int petId,
  );
  Future<Either<Failures, bool>> deleteDispenser(int petId);
  Future<Either<Failures, bool>> activateDispenser(int dispenserId, int petId);
  Future<Either<Failures, Dispenser>> getDispenserByPet(int petId);

  /// Solicita una dispensación rápida manual (spec 020). Requiere conexión: la
  /// solicitud y la cobertura de horarios viven en el servidor. [operationId]
  /// identifica la operación y hace idempotente el reintento (RF-14): debe
  /// reutilizarse mientras la cantidad no cambie.
  Future<Either<Failures, bool>> quickDispense(
    int dispenserId,
    double grams,
    String operationId,
  );

  /// Cambia la dirección MAC de un dispensador ya registrado (RF-04, RF-14).
  /// Requiere conexión: el cambio de MAC solo existe si el servidor lo acepta.
  Future<Either<Failures, Dispenser>> updateDispenserMac(
    int dispenserId,
    int petId,
    String macAddress,
  );

  // --- Flujo local / BLE / WiFi ---
  Future<List<Dispenser>> getLocalDispensers();

  /// Consulta el stock del servidor para cada dispensador vinculado a una
  /// mascota y actualiza la caché local. Si no hay conexión o una consulta
  /// falla, conserva el dato local de ese dispensador (RF-4, RF-10).
  Future<void> refreshDispensers();
  Future<void> saveLocalDispenser(Dispenser dispenser);
  Future<void> refillFood(String dispenserId, double grams);
  Future<void> discountFood(String dispenserId, double grams);

  /// Escaneo de dispensadores en modo configuración. Cada evento viaja
  /// etiquetado con [cycleId] para que un cierre tardío no afecte al ciclo
  /// vigente (RF-07); [window] acota la ventana de escucha (RF-01).
  Stream<BleScanEvent> scanBleDispensers({
    required int cycleId,
    Duration? window,
  });

  /// Detiene el escaneo; [cycleId] limita la detención al ciclo indicado
  /// (RF-07, RF-08).
  Future<void> stopBleScan({int? cycleId});

  /// Estado del adaptador Bluetooth para los avisos de la pantalla
  /// (RF-11, RF-12, RF-25).
  Stream<BleAdapterStatus> get adapterStatus;
  Future<void> connectAndProvisionBle({
    required String deviceId,
    required String ssid,
    required String password,
  });
  Future<void> resetWifiRemote(String dispenserId);
}
