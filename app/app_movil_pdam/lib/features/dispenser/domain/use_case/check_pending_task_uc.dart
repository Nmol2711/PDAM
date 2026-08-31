import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dartz/dartz.dart';

class CheckPendingTaskUc {
  final DispenserRepositories repository;

  const CheckPendingTaskUc({required this.repository});

  Future<Either<Failures, Map<String, dynamic>>> call(String macAddress) async {
    return repository.checkPendingTask(macAddress);
  }
}
