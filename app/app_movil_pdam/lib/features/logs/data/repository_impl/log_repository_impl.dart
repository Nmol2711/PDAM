import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/local/local_log_datasource.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/remote/log_remote_datasource.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:dartz/dartz.dart';

class LogRepositoryImpl implements LogRepositories {
  final LogRemoteDatasource _remoteDatasource;
  final LocalLogDatasource _localLogDatasource;

  const LogRepositoryImpl({
    required LogRemoteDatasource remoteDatasource,
    required LocalLogDatasource localLogDatasource,
  })  : _remoteDatasource = remoteDatasource,
        _localLogDatasource = localLogDatasource;

  @override
  Future<Either<Failures, LogFetchResult>> getLogs({int? petId, String? date}) async {
    try {
      final result = await _remoteDatasource.getLogs(petId: petId, date: date);
      await _localLogDatasource.cacheLogs(result);
      return Right(LogFetchResult(logs: result, isOffline: false));
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Si falla la red, leemos de Isar
      try {
        final localLogs = await _localLogDatasource.getLocalLogs(petId: petId, date: date);
        return Right(LogFetchResult(logs: localLogs, isOffline: true));
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }
}
