import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/remote/pet_remote_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:dartz/dartz.dart';

class PetRepositoriesImpl implements PetsRepositories {
  final PetRemoteDatasource _petRemoteDataosurce;

  PetRepositoriesImpl({required PetRemoteDatasource petRemoteDataosurce})
    : _petRemoteDataosurce = petRemoteDataosurce;

  @override
  Future<Either<Failures, Pet>> createPet(
    String name,
    TypePest species,
    int age,
    double weight,
    File? imageFile,
  ) async {
    try {
      final result = await _petRemoteDataosurce.createPet(
        name,
        species,
        age,
        weight,
        imageFile,
      );
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, bool>> deletePet(int petId) async {
    try {
      final result = await _petRemoteDataosurce.deletePet(petId);
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, Pet>> getPet(int petId) async {
    try {
      final result = await _petRemoteDataosurce.getPet(petId);
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, List<Pet>>> getPets() async {
    try {
      final result = await _petRemoteDataosurce.getPets();
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, Pet>> updatePet(
    int petId, {
    String? name,
    TypePest? species,
    int? age,
    double? weight,
    File? imageFile,
  }) async {
    try {
      final result = await _petRemoteDataosurce.updatePet(
        petId,
        name: name,
        species: species,
        age: age,
        weight: weight,
        imageFile: imageFile,
      );
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }
}
