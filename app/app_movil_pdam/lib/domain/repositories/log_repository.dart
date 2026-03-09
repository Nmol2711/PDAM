import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/log_entity.dart';
import 'package:dartz/dartz.dart';

abstract class LogRepository {
  Future<Either<Failures, List<LogEntity>>> getLogs();
  Future<Either<Failures, LogEntity>> createLog(String event);
}
