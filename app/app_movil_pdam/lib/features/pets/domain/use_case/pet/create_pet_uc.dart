import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:dartz/dartz.dart';

class CreatePetUc {
  final PetsRepositories repository;

  const CreatePetUc({required this.repository});

  Future<Either<Failures, Pet>> call(
    String name,
    TypePest species,
    int age,
    double weight,
    File? imageFile,
  ) async {
    return await repository.createPet(name, species, age, weight, imageFile);
  }
}
