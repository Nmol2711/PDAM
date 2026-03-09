import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/data/data_sources/local/auth_local_data_source.dart';
import 'package:app_movil_pdam/data/data_sources/remote/log_remote_data_source.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/entities/log_entity.dart';
import 'package:app_movil_pdam/domain/repositories/log_repository.dart';
import 'package:dartz/dartz.dart';

class LogRepositoryImpl implements LogRepository {
  final LogRemoteDataSource logRemoteDataSource;
  final AuthLocalDataSource authLocalDataSource;

  LogRepositoryImpl({
    required this.logRemoteDataSource,
    required this.authLocalDataSource,
  });

  @override
  Future<Either<Failures, LogEntity>> createLog(String event) async {
    try {
      final AuthToken? token = await authLocalDataSource.getToken();
      if (token == null) {
        return Left(
          ServerFailures('No hay una sesión activa. Por favor, inicia sesión.'),
        );
      }

      final resp = await logRemoteDataSource.createLog(token, event);
      return Right(resp);
    } on ServerFailures catch (e) {
      return Left(e);
    }
  }

  @override
  Future<Either<Failures, List<LogEntity>>> getLogs() async {
    try {
      final AuthToken? token = await authLocalDataSource.getToken();
      if (token == null) {
        return Left(
          ServerFailures('No hay una sesión activa. Por favor, inicia sesión.'),
        );
      }

      final resp = await logRemoteDataSource.getLogs(token);
      return Right(resp);
    } on ServerFailures catch (e) {
      return Left(e);
    }
  }
}
