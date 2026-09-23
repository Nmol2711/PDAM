import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_pet_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/remote/pet_remote_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/pets_repositories.dart';
import 'package:dartz/dartz.dart';

class PetRepositoriesImpl implements PetsRepositories {
  final PetRemoteDatasource _petRemoteDatasource;
  final LocalPetDatasource _localPetDatasource;

  PetRepositoriesImpl({
    required PetRemoteDatasource petRemoteDataosurce,
    required LocalPetDatasource localPetDatasource,
  }) : _petRemoteDatasource = petRemoteDataosurce,
       _localPetDatasource = localPetDatasource;

  @override
  Future<Either<Failures, Pet>> createPet(
    String name,
    TypePest species,
    DateTime birthDate,
    double weight,
    bool reproductiveStatus,
    File? imageFile,
  ) async {
    try {
      final result = await _petRemoteDatasource.createPet(
        name,
        species,
        birthDate,
        weight,
        reproductiveStatus,
        imageFile,
      );
      await _localPetDatasource.saveLocalPet(result, isSynced: true);
      return Right(result);
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Guardar localmente si el servidor está apagado
      try {
        final localPet = Pet(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          name: name,
          species: species,
          birthDate: birthDate,
          weight: weight,
          reproductiveStatus: reproductiveStatus,
          imgUrl: imageFile?.path,
        );
        await _localPetDatasource.saveLocalPet(localPet, isSynced: false);
        return Right(localPet);
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, bool>> deletePet(int petId) async {
    try {
      final result = await _petRemoteDatasource.deletePet(petId);
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, Pet>> getPet(int petId) async {
    try {
      final result = await _petRemoteDatasource.getPet(petId);
      await _localPetDatasource.saveLocalPet(result, isSynced: true);
      return Right(result);
    } catch (e) {
      try {
        final localPets = await _localPetDatasource.getLocalPets();
        final match = localPets.firstWhere((p) => p.id == petId);
        return Right(match);
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, List<Pet>>> getPets() async {
    try {
      final result = await _petRemoteDatasource.getPets();
      await _localPetDatasource.cachePets(result);
      final localPets = await _localPetDatasource.getLocalPets();
      return Right(localPets);
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Si falla la red (servidor apagado/sin internet), leemos de Isar
      try {
        final localPets = await _localPetDatasource.getLocalPets();
        return Right(localPets);
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, Pet>> updatePet(
    int petId, {
    String? name,
    TypePest? species,
    DateTime? birthDate,
    double? weight,
    bool? reproductiveStatus,
    File? imageFile,
  }) async {
    try {
      final result = await _petRemoteDatasource.updatePet(
        petId,
        name: name,
        species: species,
        birthDate: birthDate,
        weight: weight,
        reproductiveStatus: reproductiveStatus,
        imageFile: imageFile,
      );
      await _localPetDatasource.saveLocalPet(result, isSynced: true);
      return Right(result);
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Actualizar localmente si el servidor está apagado
      try {
        final localPets = await _localPetDatasource.getLocalPets();
        final existing = localPets.firstWhere((p) => p.id == petId);
        final updated = Pet(
          id: existing.id,
          name: name ?? existing.name,
          species: species ?? existing.species,
          birthDate: birthDate ?? existing.birthDate,
          weight: weight ?? existing.weight,
          reproductiveStatus: reproductiveStatus ?? existing.reproductiveStatus,
          imgUrl: imageFile?.path ?? existing.imgUrl,
        );
        await _localPetDatasource.saveLocalPet(updated, isSynced: false);
        return Right(updated);
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }
}
