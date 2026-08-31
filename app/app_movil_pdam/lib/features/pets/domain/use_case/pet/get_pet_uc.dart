import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:dartz/dartz.dart';

class GetPetUc {
  final PetsRepositories repository;

  const GetPetUc({required this.repository});

  Future<Either<Failures, Pet>> call(int petId) async {
    return await repository.getPet(petId);
  }
}
