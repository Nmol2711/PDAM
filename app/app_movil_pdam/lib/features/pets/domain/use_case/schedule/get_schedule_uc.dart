import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:dartz/dartz.dart';

class GetScheduleUc {
  final ScheduleRepositories repository;
  const GetScheduleUc({required this.repository});

  Future<Either<Failures, Schedule>> call(int id, int petId) async {
    return await repository.getShedule(id, petId);
  }
}
