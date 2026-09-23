import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:dartz/dartz.dart';

class GetLogsUc {
  final LogRepositories repository;

  const GetLogsUc({required this.repository});

  Future<Either<Failures, LogFetchResult>> call({int? petId, String? date}) async {
    return await repository.getLogs(petId: petId, date: date);
  }
}
