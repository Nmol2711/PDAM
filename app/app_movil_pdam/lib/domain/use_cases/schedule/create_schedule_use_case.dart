import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/schedule_entity.dart';
import 'package:app_movil_pdam/domain/repositories/schedule_repository.dart';
import 'package:dartz/dartz.dart';

class CreateScheduleUseCase {
  final ScheduleRepository repository;

  CreateScheduleUseCase(this.repository);

  Future<Either<Failures, ScheduleEntity>> execute(
    String time,
    int amount,
  ) async {
    return await repository.createSchedule(time, amount);
  }
}
