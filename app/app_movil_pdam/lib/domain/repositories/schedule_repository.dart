import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/schedule_entity.dart';
import 'package:dartz/dartz.dart';

abstract class ScheduleRepository {
  Future<Either<Failures, List<ScheduleEntity>>> getSchedules();
  Future<Either<Failures, List<ScheduleEntity>>> getTimeSchedules(String date);

  Future<Either<Failures, ScheduleEntity>> createSchedule(
    String time,
    int amount,
  );

  Future<Either<Failures, ScheduleEntity>> updateSchedule(
    int id,
    String time,
    int amount,
  );
}
