import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dartz/dartz.dart';

class AssociateDispenserUc {
  final DispenserRepositories repository;

  const AssociateDispenserUc({required this.repository});

  Future<Either<Failures, Dispenser>> call(
    String macAddress,
    int petId,
    String secretKeyQr,
  ) async {
    return repository.associateDispenser(macAddress, petId, secretKeyQr);
  }
}
