import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dartz/dartz.dart';

/// Caso de uso de cambio de dirección MAC (RF-04, RF-14).
///
/// No hay modo offline: sin la validación del servidor no se puede garantizar
/// que la nueva MAC sea única, así que la operación exige conexión y su
/// resultado lo decide la capa de datos.
class UpdateDispenserMacUc {
  final DispenserRepositories repository;

  const UpdateDispenserMacUc({required this.repository});

  Future<Either<Failures, Dispenser>> call(
    int dispenserId,
    int petId,
    String macAddress,
  ) {
    return repository.updateDispenserMac(dispenserId, petId, macAddress);
  }
}
