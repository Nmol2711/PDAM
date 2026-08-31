import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:dartz/dartz.dart';

class DeletePetsUc {
  final PetsRepositories repository;

  const DeletePetsUc({required this.repository});

  Future<Either<Failures, bool>> call(int petId) async {
    return await repository.deletePet(petId);
  }
}
