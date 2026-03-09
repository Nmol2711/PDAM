import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/schedule_entity.dart';
import 'package:app_movil_pdam/domain/repositories/schedule_repository.dart';
import 'package:dartz/dartz.dart';

class GetTimeSchedules {
  final ScheduleRepository repository;

  GetTimeSchedules(this.repository);

  Future<Either<Failures, List<ScheduleEntity>>> execute(String date) async {
    return await repository.getTimeSchedules(date);
  }
}
