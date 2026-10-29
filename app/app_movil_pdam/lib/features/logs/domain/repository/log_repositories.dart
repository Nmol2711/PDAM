import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:dartz/dartz.dart';

abstract class LogRepositories {
  /// Consulta una página del historial. Si el servidor no responde, devuelve la
  /// misma página y filtros desde la caché local (RF-34).
  Future<Either<Failures, LogFetchResult>> getLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  });

  /// Catálogo de tipos de evento y resultados para los filtros (RF-31).
  Future<Either<Failures, LogCatalog>> getCatalog();
}
