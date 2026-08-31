import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:dartz/dartz.dart';

class DeleteScheduleUc {
  final ScheduleRepositories repository;

  const DeleteScheduleUc({required this.repository});

  Future<Either<Failures, bool>> call(int id) async {
    return await repository.deleteShedule(id);
  }
}
