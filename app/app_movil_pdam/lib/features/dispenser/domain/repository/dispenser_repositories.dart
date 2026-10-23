import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
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

  /// Cambia la dirección MAC de un dispensador ya registrado (RF-04, RF-14).
  /// Requiere conexión: el cambio de MAC solo existe si el servidor lo acepta.
  Future<Either<Failures, Dispenser>> updateDispenserMac(
    int dispenserId,
    int petId,
    String macAddress,
  );

  // --- Flujo local / BLE / WiFi ---
  Future<List<Dispenser>> getLocalDispensers();
  Future<void> saveLocalDispenser(Dispenser dispenser);
  Future<void> refillFood(String dispenserId, double grams);
  Future<void> discountFood(String dispenserId, double grams);
  Stream<List<ScannedDevice>> scanBleDispensers();
  Future<void> stopBleScan();
  Future<void> connectAndProvisionBle({
    required String deviceId,
    required String ssid,
    required String password,
  });
  Future<void> resetWifiRemote(String dispenserId);
}
