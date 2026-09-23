import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/services/validate_time.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_schedule_datasource.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/remote/schedule_remote_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/repositories/schedule_repositories.dart';
import 'package:dartz/dartz.dart';

class ScheduleRepositoryImpl implements ScheduleRepositories {
  final ScheduleRemoteDatasource _scheduleRemoteDatasource;
  final LocalScheduleDatasource _localScheduleDatasource;

  const ScheduleRepositoryImpl({
    required ScheduleRemoteDatasource scheduleRemoteDatasource,
    required LocalScheduleDatasource localScheduleDatasource,
  })  : _scheduleRemoteDatasource = scheduleRemoteDatasource,
        _localScheduleDatasource = localScheduleDatasource;

  @override
  Future<Either<Failures, Schedule>> createShedule(
    String time,
    double amount,
    int petId,
  ) async {
    if (!validateTime(time)) {
      return Left(UserFailures("Formato de hora incorrecto, Ej 06:00"));
    }
    try {
      final result = await _scheduleRemoteDatasource.createSchedule(
        time,
        amount,
        petId,
      );
      await _localScheduleDatasource.saveLocalSchedule(result, isSynced: true);
      return Right(result);
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Crear localmente si el servidor está apagado
      try {
        final localSchedule = Schedule(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          time: time,
          amount: amount,
          petId: petId,
        );
        await _localScheduleDatasource.saveLocalSchedule(localSchedule, isSynced: false);
        return Right(localSchedule);
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, Schedule>> getShedule(int id, int petId) async {
    try {
      final result = await _scheduleRemoteDatasource.getSchedule(id, petId);
      await _localScheduleDatasource.saveLocalSchedule(result, isSynced: true);
      return Right(result);
    } catch (e) {
      try {
        final locals = await _localScheduleDatasource.getLocalSchedules(petId: petId);
        final match = locals.firstWhere((s) => s.id == id);
        return Right(match);
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, ScheduleFetchResult>> getShedules() async {
    try {
      final result = await _scheduleRemoteDatasource.getSchedules();
      await _localScheduleDatasource.cacheSchedules(result);
      final localSchedules = await _localScheduleDatasource.getLocalSchedules();
      return Right(ScheduleFetchResult(schedules: localSchedules, isOffline: false));
    } catch (e) {
      try {
        final localSchedules = await _localScheduleDatasource.getLocalSchedules();
        return Right(ScheduleFetchResult(schedules: localSchedules, isOffline: true));
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, ScheduleFetchResult>> getShedulesByPet(int petId) async {
    try {
      final result = await _scheduleRemoteDatasource.getSchedulesByPet(petId);
      await _localScheduleDatasource.cacheSchedules(result);
      final localSchedules = await _localScheduleDatasource.getLocalSchedules(petId: petId);
      return Right(ScheduleFetchResult(schedules: localSchedules, isOffline: false));
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Si falla la red, leemos de Isar
      try {
        final localSchedules = await _localScheduleDatasource.getLocalSchedules(petId: petId);
        return Right(ScheduleFetchResult(schedules: localSchedules, isOffline: true));
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, ScheduleFetchResult>> autoGenerateSchedules(
    int petId,
    double foodKcalPerKg,
    int bcs,
    String mcs,
    String activityLevel,
    int mealsPerDay,
  ) async {
    try {
      final result = await _scheduleRemoteDatasource.autoGenerateSchedules(
        petId,
        foodKcalPerKg,
        bcs,
        mcs,
        activityLevel,
        mealsPerDay,
      );
      await _localScheduleDatasource.cacheSchedules(result);
      final localSchedules = await _localScheduleDatasource.getLocalSchedules(petId: petId);
      return Right(ScheduleFetchResult(schedules: localSchedules, isOffline: false));
    } catch (e) {
      try {
        final localSchedules = await _localScheduleDatasource.getLocalSchedules(petId: petId);
        return Right(ScheduleFetchResult(schedules: localSchedules, isOffline: true));
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, bool>> deleteShedule(int id) async {
    try {
      return const Right(true);
    } catch (e) {
      return Left(ServerFailures(e.toString()));
    }
  }

  @override
  Future<Either<Failures, Schedule>> updateShedule(
    int id, {
    String? time,
    double? amount,
  }) async {
    if (time != null && !validateTime(time)) {
      return Left(UserFailures("Formato de hora incorrecto, Ej 06:00"));
    }
    try {
      final result = await _scheduleRemoteDatasource.updateSchedule(
        id,
        time: time,
        amount: amount,
      );
      await _localScheduleDatasource.saveLocalSchedule(result, isSynced: true);
      return Right(result);
    } catch (e) {
      try {
        final locals = await _localScheduleDatasource.getLocalSchedules();
        final existing = locals.firstWhere((s) => s.id == id);
        final updated = Schedule(
          id: existing.id,
          time: time ?? existing.time,
          amount: amount ?? existing.amount,
          petId: existing.petId,
        );
        await _localScheduleDatasource.saveLocalSchedule(updated, isSynced: false);
        return Right(updated);
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }
}
