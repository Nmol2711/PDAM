import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dartz/dartz.dart';

class DispenserRepositoryImpl implements DispenserRepositories {
  final DispenserRemoteDatasource _dispenserRemoteDatasource;

  DispenserRepositoryImpl({
    required DispenserRemoteDatasource dispenserRemoteDatasource,
  }) : _dispenserRemoteDatasource = dispenserRemoteDatasource;

  @override
  Future<Either<Failures, Dispenser>> associateDispenser(
    String macAddress,
    int petId,
    String secretKeyQr,
  ) async {
    try {
      final result = await _dispenserRemoteDatasource.associateDispenser(
        macAddress,
        petId,
        secretKeyQr,
      );
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, Map<String, dynamic>>> checkPendingTask(
    String macAddress,
  ) async {
    try {
      final result = await _dispenserRemoteDatasource.checkPendingTask(
        macAddress,
      );
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, Dispenser>> getDispenserByPet(int petId) async {
    try {
      final result = await _dispenserRemoteDatasource.getDispenserByPet(petId);
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, bool>> dasactivateDispenser(
    int dispenserId,
    int petId,
  ) async {
    try {
      final result = await _dispenserRemoteDatasource.dasactivateDispenser(
        dispenserId,
        petId,
      );
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, bool>> activateDispenser(
    int dispenserId,
    int petId,
  ) async {
    try {
      final result = await _dispenserRemoteDatasource.activateDispenser(
        dispenserId,
        petId,
      );
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, bool>> deleteDispenser(int petId) async {
    try {
      final result = await _dispenserRemoteDatasource.deleteDispenserByPet(
        petId,
      );
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }
}
