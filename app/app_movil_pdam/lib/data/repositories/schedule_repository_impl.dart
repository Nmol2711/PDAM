import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/data/data_sources/local/auth_local_data_source.dart';
import 'package:app_movil_pdam/data/data_sources/remote/schedule_remote_data_source.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/entities/schedule_entity.dart';
import 'package:app_movil_pdam/domain/repositories/schedule_repository.dart';
import 'package:dartz/dartz.dart';

class ScheduleRepositoryImpl implements ScheduleRepository {
  final ScheduleRemoteDataSource scheduleRemoteDataSource;
  final AuthLocalDataSource authLocalDataSource;

  ScheduleRepositoryImpl({
    required this.scheduleRemoteDataSource,
    required this.authLocalDataSource,
  });

  @override
  Future<Either<Failures, ScheduleEntity>> createSchedule(
    String time,
    int amount,
  ) async {
    try {
      final AuthToken? token = await authLocalDataSource.getToken();
      if (token == null) {
        return left(
          ServerFailures('No hay una sesión activa. Por favor, inicia sesión.'),
        );
      }

      final resp = await scheduleRemoteDataSource.createSchedule(
        token,
        time,
        amount,
      );

      return Right(resp);
    } on ServerFailures catch (e) {
      return Left(e);
    }
  }

  @override
  Future<Either<Failures, List<ScheduleEntity>>> getSchedules() async {
    try {
      final AuthToken? token = await authLocalDataSource.getToken();
      if (token == null) {
        return left(
          ServerFailures('No hay una sesión activa. Por favor, inicia sesión.'),
        );
      }

      final resp = await scheduleRemoteDataSource.getSchedules(token);

      return Right(resp);
    } on ServerFailures catch (e) {
      return Left(e);
    }
  }

  @override
  Future<Either<Failures, List<ScheduleEntity>>> getTimeSchedules(
    String date,
  ) async {
    try {
      final AuthToken? token = await authLocalDataSource.getToken();
      if (token == null) {
        return left(
          ServerFailures('No hay una sesión activa. Por favor, inicia sesión.'),
        );
      }

      final resp = await scheduleRemoteDataSource.getTimeSchedules(token, date);

      return Right(resp);
    } on ServerFailures catch (e) {
      return Left(e);
    }
  }

  @override
  Future<Either<Failures, ScheduleEntity>> updateSchedule(
    int id,
    String time,
    int amount,
  ) async {
    try {
      final AuthToken? token = await authLocalDataSource.getToken();
      if (token == null) {
        return left(
          ServerFailures('No hay una sesión activa. Por favor, inicia sesión.'),
        );
      }

      final resp = await scheduleRemoteDataSource.updateSchedule(
        token,
        id,
        time,
        amount,
      );

      return Right(resp);
    } on ServerFailures catch (e) {
      return Left(e);
    }
  }
}
