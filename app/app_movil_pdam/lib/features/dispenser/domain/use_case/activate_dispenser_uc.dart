import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dartz/dartz.dart';

class ActivateDispenserUc {
  final DispenserRepositories repository;

  const ActivateDispenserUc({required this.repository});

  Future<Either<Failures, bool>> call(int dispenserId, int petId) async {
    return repository.activateDispenser(dispenserId, petId);
  }
}
