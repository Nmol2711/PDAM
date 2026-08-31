import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:dartz/dartz.dart';

class GetPetsUc {
  final PetsRepositories repository;

  const GetPetsUc({required this.repository});

  Future<Either<Failures, List<Pet>>> call() async {
    return await repository.getPets();
  }
}
