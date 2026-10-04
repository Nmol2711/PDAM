import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dartz/dartz.dart';

class DispenserRepositoryImpl implements DispenserRepositories {
  final DispenserRemoteDatasource _dispenserRemoteDatasource;
  final LocalDispenserDatasource _localDispenserDatasource;

  DispenserRepositoryImpl({
    required DispenserRemoteDatasource dispenserRemoteDatasource,
    required LocalDispenserDatasource localDispenserDatasource,
  }) : _dispenserRemoteDatasource = dispenserRemoteDatasource,
       _localDispenserDatasource = localDispenserDatasource;

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
      await _localDispenserDatasource.saveLocalDispenser(result, isSynced: true, secretKeyQr: secretKeyQr);
      return Right(result);
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Guardar localmente con isSynced = false si no hay red (DioException)
      try {
        final localDispenser = Dispenser(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          macAddress: macAddress,
          pendingDispensing: false,
          isActive: true,
          petId: petId,
        );
        await _localDispenserDatasource.saveLocalDispenser(localDispenser, isSynced: false, secretKeyQr: secretKeyQr);
        return Right(localDispenser);
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
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
      await _localDispenserDatasource.cacheDispenser(result);
      return Right(result);
    } catch (e) {
      try {
        final local = await _localDispenserDatasource.getLocalDispenserByPet(petId);
        if (local != null) {
          return Right(local);
        }
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
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
      await _localDispenserDatasource.deleteLocalDispenser(petId);
      return Right(result);
    } catch (e) {
      try {
        await _localDispenserDatasource.deleteLocalDispenser(petId);
        return const Right(true);
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }
}
