import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:dartz/dartz.dart';

class GetSchedulesByPetUc {
  final ScheduleRepositories repository;

  const GetSchedulesByPetUc({required this.repository});

  Future<Either<Failures, List<Schedule>>> call(int petId) async {
    return await repository.getShedulesByPet(petId);
  }
}
