import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:dartz/dartz.dart';

abstract class ScheduleRepositories {
  Future<Either<Failures, Schedule>> createShedule(
    String time,
    double amount,
    int petId,
  );

  Future<Either<Failures, Schedule>> getShedule(int id, int petId);

  Future<Either<Failures, ScheduleFetchResult>> getShedules();

  Future<Either<Failures, ScheduleFetchResult>> getShedulesByPet(int petId);

  Future<Either<Failures, ScheduleFetchResult>> autoGenerateSchedules(
    int petId,
    double foodKcalPerKg,
    int bcs,
    String mcs,
    String activityLevel,
    int mealsPerDay,
  );

  Future<Either<Failures, Schedule>> updateShedule(
    int id, {
    String? time,
    double? amount,
  });

  Future<Either<Failures, bool>> deleteShedule(int id);
}
