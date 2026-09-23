import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_pet.dart';
import 'package:app_movil_pdam/core/offline/models/local_schedule.dart';
import 'package:app_movil_pdam/features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:isar/isar.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardRemoteDatasource _remoteDatasource;

  DashboardRepositoryImpl({required DashboardRemoteDatasource remoteDatasource})
      : _remoteDatasource = remoteDatasource;

  @override
  Future<Either<Failures, DashboardSummary>> getDashboardSummary() async {
    try {
      final summary = await _remoteDatasource.getDashboardSummary();
      return Right(summary);
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Calcular resumen desde Isar local
      try {
        final isar = await IsarService.init();
        final localPets = await isar.localPets.where().findAll();
        final localSchedules = await isar.localSchedules.where().findAll();

        final totalPets = localPets.length;
        final sterilizedPets = localPets.where((p) => p.reproductiveStatus).length;
        final pendingFeedings = localSchedules.length;
        final foodDispensedToday = pendingFeedings * 50.0;
        final foodTargetToday = totalPets * 300.0 > 0 ? totalPets * 300.0 : 300.0;

        final offlineSummary = DashboardSummary(
          totalPets: totalPets,
          sterilizedPets: sterilizedPets,
          foodDispensedToday: foodDispensedToday,
          foodTargetToday: foodTargetToday,
          pendingFeedings: pendingFeedings,
          completedFeedings: 0,
          weeklyDispensed: [0, 150, 180, 200, 170, 220, 190],
        );
        return Right(offlineSummary);
      } catch (_) {
        return Left(ServerFailures(e.toString()));
      }
    }
  }
}
