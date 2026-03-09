import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/schedule_entity.dart';
import 'package:app_movil_pdam/domain/repositories/schedule_repository.dart';
import 'package:dartz/dartz.dart';

class GetSchedulesUseCase {
  final ScheduleRepository repository;

  GetSchedulesUseCase(this.repository);

  Future<Either<Failures, List<ScheduleEntity>>> execute() async {
    return await repository.getSchedules();
  }
}
