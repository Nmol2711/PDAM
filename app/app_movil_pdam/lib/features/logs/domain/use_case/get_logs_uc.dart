import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:dartz/dartz.dart';

class GetLogsUc {
  final LogRepositories repository;

  const GetLogsUc({required this.repository});

  Future<Either<Failures, LogFetchResult>> call({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  }) async {
    return await repository.getLogs(
      filters: filters,
      page: page,
      pageSize: pageSize,
    );
  }
}
