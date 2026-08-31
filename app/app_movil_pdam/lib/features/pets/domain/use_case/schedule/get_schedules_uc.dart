import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:dartz/dartz.dart';

class GetSchedulesUc {
  final ScheduleRepositories repository;

  const GetSchedulesUc({required this.repository});

  Future<Either<Failures, List<Schedule>>> call() async {
    return await repository.getShedules();
  }
}
