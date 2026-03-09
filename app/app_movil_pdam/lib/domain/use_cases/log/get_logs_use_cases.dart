import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/log_entity.dart';
import 'package:app_movil_pdam/domain/repositories/log_repository.dart';
import 'package:dartz/dartz.dart';

class GetLogsUseCases {
  final LogRepository repository;
  GetLogsUseCases(this.repository);

  Future<Either<Failures, List<LogEntity>>> execute() async {
    return await repository.getLogs();
  }
}
