import 'package:app_movil_pdam/core/error/api_exception.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/local/local_log_datasource.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/remote/log_remote_datasource.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:dartz/dartz.dart';

/// Historial con estrategia offline-first (RF-34, RF-35).
///
/// El servidor es la fuente de verdad; cada página descargada se cachea. Si la
/// consulta remota falla, se responde con la caché aplicando los mismos filtros
/// y la misma paginación, sin borrar lo ya mostrado.
class LogRepositoryImpl implements LogRepositories {
  final LogRemoteDatasource _remoteDatasource;
  final LocalLogDatasource _localLogDatasource;

  const LogRepositoryImpl({
    required LogRemoteDatasource remoteDatasource,
    required LocalLogDatasource localLogDatasource,
  }) : _remoteDatasource = remoteDatasource,
       _localLogDatasource = localLogDatasource;

  @override
  Future<Either<Failures, LogFetchResult>> getLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  }) async {
    try {
      final remota = await _remoteDatasource.getLogs(
        filters: filters,
        page: page,
        pageSize: pageSize,
      );
      await _cachear(remota.items);
      return Right(LogFetchResult(page: remota, isOffline: false));
    } catch (e) {
      // Un rechazo del cliente es una respuesta definitiva del servidor: la
      // caché no debe disfrazarlo de «sin conexión» ni ocultar que la sesión
      // no está autorizada o que la consulta es inválida (RF-34).
      if (_esRechazoDelCliente(e)) {
        return Left(ServerFailures(_mensaje(e)));
      }
      try {
        final local = await _localLogDatasource.getLocalLogs(
          filters: filters,
          page: page,
          pageSize: pageSize,
        );
        return Right(LogFetchResult(page: local, isOffline: true));
      } catch (_) {
        return Left(ServerFailures(_mensaje(e)));
      }
    }
  }

  /// 400 y 401 son definitivos; los errores de red, los timeouts y los 5xx se
  /// resuelven con la caché local (RF-34).
  bool _esRechazoDelCliente(Object error) {
    return error is ApiException && (error.status == 400 || error.status == 401);
  }

  @override
  Future<Either<Failures, LogCatalog>> getCatalog() async {
    try {
      return Right(await _remoteDatasource.getCatalog());
    } catch (_) {
      try {
        return Right(await _localLogDatasource.getLocalCatalog());
      } catch (_) {
        return Left(
          ServerFailures('No se pudo cargar el catálogo del historial'),
        );
      }
    }
  }

  /// Guardar en caché es best-effort: un fallo de escritura no debe ocultar los
  /// datos que el servidor ya devolvió.
  Future<void> _cachear(List<ActivityLog> items) async {
    if (items.isEmpty) return;
    try {
      await _localLogDatasource.cacheLogs(items);
    } catch (_) {
      // La lista se muestra igual; se reintentará al volver a consultar.
    }
  }

  String _mensaje(Object error) {
    // El mensaje visible es el del servidor, sin el prefijo de diagnóstico.
    if (error is ApiException) return error.message;
    return error.toString().replaceAll('Exception: ', '');
  }
}
