import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/log_entity.dart';
import 'package:app_movil_pdam/domain/repositories/log_repository.dart';
import 'package:dartz/dartz.dart';

class CreateLogUseCase {
  final LogRepository repository;
  CreateLogUseCase(this.repository);

  Future<Either<Failures, LogEntity>> execute(String event) async {
    return await repository.createLog(event);
  }
}
