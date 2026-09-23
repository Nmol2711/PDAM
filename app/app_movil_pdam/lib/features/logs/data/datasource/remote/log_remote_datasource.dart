import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/logs/data/models/activity_log_model.dart';
import 'package:dio/dio.dart';

abstract class LogRemoteDatasource {
  Future<List<ActivityLogModel>> getLogs({int? petId, String? date});
}

class LogRemoteDatasourceImpl implements LogRemoteDatasource {
  final DioClient _dioClient;

  const LogRemoteDatasourceImpl({required DioClient dioClient}) : _dioClient = dioClient;

  @override
  Future<List<ActivityLogModel>> getLogs({int? petId, String? date}) async {
    try {
      final Map<String, dynamic> queryParams = {};
      if (petId != null) queryParams['pet_id'] = petId;
      if (date != null) queryParams['fecha'] = date;

      final response = await _dioClient.dio.get(
        ApiConstants.logs,
        queryParameters: queryParams,
      );

      return (response.data as List)
          .map((e) => ActivityLogModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw Exception(e.message ?? 'Error al obtener el historial de eventos');
    }
  }
}
