import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:dartz/dartz.dart';

class GetLogCatalogUc {
  final LogRepositories repository;

  const GetLogCatalogUc({required this.repository});

  Future<Either<Failures, LogCatalog>> call() async {
    return await repository.getCatalog();
  }
}
