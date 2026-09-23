import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:dartz/dartz.dart';

class UpdatePetUc {
  final PetsRepositories repository;

  const UpdatePetUc({required this.repository});

  Future<Either<Failures, Pet>> call(
    int petId, {
    String? name,
    TypePest? species,
    DateTime? birthDate,
    double? weight,
    bool? reproductiveStatus,
    File? imageFile,
  }) async {
    return await repository.updatePet(
      petId,
      name: name,
      species: species,
      birthDate: birthDate,
      weight: weight,
      reproductiveStatus: reproductiveStatus,
      imageFile: imageFile,
    );
  }
}
