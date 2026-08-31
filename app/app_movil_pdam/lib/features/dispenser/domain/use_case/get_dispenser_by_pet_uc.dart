import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dartz/dartz.dart';

class GetDispenserByPetUc {
  final DispenserRepositories repository;

  const GetDispenserByPetUc({required this.repository});

  Future<Either<Failures, Dispenser>> call(int petId) async {
    return repository.getDispenserByPet(petId);
  }
}
