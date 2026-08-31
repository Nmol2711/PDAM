import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dartz/dartz.dart';

class DeleteDispenserUc {
  final DispenserRepositories repository;

  const DeleteDispenserUc({required this.repository});

  Future<Either<Failures, bool>> call(int petId) async {
    return repository.deleteDispenser(petId);
  }
}
