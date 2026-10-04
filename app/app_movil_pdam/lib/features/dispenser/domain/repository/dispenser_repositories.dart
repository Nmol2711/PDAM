import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:dartz/dartz.dart';

abstract class DispenserRepositories {
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

  Future<Either<Failures, bool>> deleteDispenser(int petIf);

  Future<Either<Failures, bool>> activateDispenser(int dispenserId, int petId);
  Future<Either<Failures, Dispenser>> getDispenserByPet(int petId);

  /// Cambia la dirección MAC de un dispensador ya registrado (RF-04, RF-14).
  /// Requiere conexión: el cambio de MAC solo existe si el servidor lo acepta.
  Future<Either<Failures, Dispenser>> updateDispenserMac(
    int dispenserId,
    int petId,
    String macAddress,
  );
}
