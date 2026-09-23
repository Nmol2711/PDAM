import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';

abstract class DashboardRepository {
  Future<Either<Failures, DashboardSummary>> getDashboardSummary();
}
