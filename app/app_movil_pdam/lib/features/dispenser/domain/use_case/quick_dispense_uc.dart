import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dartz/dartz.dart';

class QuickDispenseUc {
  final DispenserRepositories repository;

  const QuickDispenseUc({required this.repository});

  Future<Either<Failures, bool>> call(
    int dispenserId,
    double grams,
    String operationId,
  ) {
    return repository.quickDispense(dispenserId, grams, operationId);
  }
}
