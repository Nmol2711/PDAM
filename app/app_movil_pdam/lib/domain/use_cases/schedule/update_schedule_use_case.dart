import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/schedule_entity.dart';
import 'package:app_movil_pdam/domain/repositories/schedule_repository.dart';
import 'package:dartz/dartz.dart';

class UpdateScheduleUseCase {
  final ScheduleRepository repository;

  UpdateScheduleUseCase(this.repository);

  Future<Either<Failures, ScheduleEntity>> execute(
    int id,
    String time,
    int amount,
  ) async {
    return await repository.updateSchedule(id, time, amount);
  }
}
