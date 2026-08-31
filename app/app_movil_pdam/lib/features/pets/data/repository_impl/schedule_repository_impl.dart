import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/services/validate_time.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/remote/schedule_remote_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:dartz/dartz.dart';

class ScheduleRepositoryImpl implements ScheduleRepositories {
  final ScheduleRemoteDatasource _scheduleRemoteDatasource;

  const ScheduleRepositoryImpl({
    required ScheduleRemoteDatasource scheduleRemoteDatasource,
  }) : _scheduleRemoteDatasource = scheduleRemoteDatasource;

  @override
  Future<Either<Failures, Schedule>> createShedule(
    String time,
    double amount,
    int petId,
  ) async {
    try {
      if (!validateTime(time)) {
        return Left(UserFailures("Formato de hora incorrecto,  Ej 06:00"));
      }
      final result = await _scheduleRemoteDatasource.createSchedule(
        time,
        amount,
        petId,
      );
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, Schedule>> getShedule(int id, int petId) async {
    try {
      final result = await _scheduleRemoteDatasource.getSchedule(id, petId);
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, List<Schedule>>> getShedules() async {
    try {
      final result = await _scheduleRemoteDatasource.getSchedules();
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, List<Schedule>>> getShedulesByPet(int petId) async {
    try {
      final result = await _scheduleRemoteDatasource.getSchedulesByPet(petId);
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, bool>> deleteShedule(int id) {
    // TODO: implement deleteShedule
    throw UnimplementedError();
  }

  @override
  Future<Either<Failures, Schedule>> updateShedule(
    int id, {
    String? time,
    double? amount,
  }) {
    // TODO: implement updateShedule
    throw UnimplementedError();
  }
}
