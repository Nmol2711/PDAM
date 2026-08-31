import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:dartz/dartz.dart';

abstract class PetsRepositories {
  Future<Either<Failures, Pet>> createPet(
    String name,
    TypePest species,
    int age,
    double weight,
    File? imageFile,
  );
  Future<Either<Failures, Pet>> getPet(int petId);
  Future<Either<Failures, List<Pet>>> getPets();
  Future<Either<Failures, Pet>> updatePet(
    int petId, {
    String? name,
    TypePest? species,
    int? age,
    double? weight,
    File? imageFile,
  });
  Future<Either<Failures, bool>> deletePet(int petId);
}
