import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:dartz/dartz.dart';

class UpdateScheduleUc {
  final ScheduleRepositories repository;
  const UpdateScheduleUc({required this.repository});

  Future<Either<Failures, Schedule>> call(
    int id, {
    String? time,
    double? amount,
  }) async {
    return await repository.updateShedule(id, time: time, amount: amount);
  }
}
