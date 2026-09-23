import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:dartz/dartz.dart';

abstract class LogRepositories {
  Future<Either<Failures, LogFetchResult>> getLogs({int? petId, String? date});
}
