import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:dartz/dartz.dart';

class AutoGenerateSchedulesUc {
  final ScheduleRepositories repository;

  const AutoGenerateSchedulesUc({required this.repository});

  Future<Either<Failures, ScheduleFetchResult>> call(
    int petId,
    double foodKcalPerKg,
    int bcs,
    String mcs,
    String activityLevel,
    int mealsPerDay,
  ) async {
    return await repository.autoGenerateSchedules(
      petId,
      foodKcalPerKg,
      bcs,
      mcs,
      activityLevel,
      mealsPerDay,
    );
  }
}
