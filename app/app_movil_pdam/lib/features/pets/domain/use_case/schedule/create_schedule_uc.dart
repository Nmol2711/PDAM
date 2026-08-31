import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:dartz/dartz.dart';

class CreateScheduleUc {
  final ScheduleRepositories repository;
  const CreateScheduleUc({required this.repository});

  Future<Either<Failures, Schedule>> call(
    String time,
    double amount,
    int petId,
  ) async {
    return await repository.createShedule(time, amount, petId);
  }
}
