import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/api_exception.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/logs/data/models/activity_log_model.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:dio/dio.dart';

/// Consulta del historial contra la API (§5.3 y §5.4 del plan).
abstract class LogRemoteDatasource {
  Future<LogPage> getLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  });

  Future<LogCatalog> getCatalog();
}

class LogRemoteDatasourceImpl implements LogRemoteDatasource {
  final DioClient _dioClient;

  const LogRemoteDatasourceImpl({required DioClient dioClient})
    : _dioClient = dioClient;

  @override
  Future<LogPage> getLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  }) async {
    try {
      final response = await _dioClient.dio.get(
        ApiConstants.logs,
        queryParameters: _parametros(filters, page, pageSize),
      );

      return LogPageModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _apiExceptionFrom(e, 'Error al obtener el historial de eventos');
    }
  }

  @override
  Future<LogCatalog> getCatalog() async {
    try {
      final response = await _dioClient.dio.get(ApiConstants.logsCatalog);

      return LogCatalogModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _apiExceptionFrom(e, 'Error al obtener el catálogo del historial');
    }
  }

  /// Traduce el fallo de red conservando el código HTTP y el `code` del
  /// catálogo: el repositorio necesita distinguir un rechazo definitivo (400,
  /// 401) de un fallo transitorio para decidir si usa la caché (RF-34).
  ApiException _apiExceptionFrom(DioException e, String porDefecto) {
    final data = e.response?.data;
    final detail = data is Map ? data['detail'] : null;
    final codigo = detail is Map && detail['code'] != null
        ? detail['code'].toString()
        : ApiException.serverErrorCode;

    return ApiException(
      code: codigo,
      message: _mensajeDeError(e, porDefecto),
      status: e.response?.statusCode,
    );
  }

  /// Solo se envían los filtros activos: el servidor rechaza algunos vacíos
  /// (`event_type=""`, `from=""` o `page=""` responden 400).
  Map<String, dynamic> _parametros(LogFilters filters, int page, int pageSize) {
    final parametros = <String, dynamic>{};

    if (filters.petId != null) {
      parametros['pet_id'] = filters.petId!.toString();
    }
    final tipo = filters.eventType;
    if (tipo != null && tipo.isNotEmpty) {
      parametros['event_type'] = tipo;
    }
    final resultado = filters.outcome;
    if (resultado != null && resultado.isNotEmpty) {
      parametros['outcome'] = resultado;
    }
    final desde = filters.fromIso;
    if (desde != null) {
      parametros['from'] = desde;
    }
    final hasta = filters.toIso;
    if (hasta != null) {
      parametros['to'] = hasta;
    }

    parametros['page'] = page;
    parametros['page_size'] = pageSize;
    return parametros;
  }

  /// Los 400 llegan como `detail={code,message}`; se muestra el mensaje.
  String _mensajeDeError(DioException e, String porDefecto) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is Map && detail['message'] != null) {
        return detail['message'].toString();
      }
      if (detail != null && detail is! Map) {
        return detail.toString();
      }
      if (data['message'] != null) {
        return data['message'].toString();
      }
    }
    return e.message ?? porDefecto;
  }
}
