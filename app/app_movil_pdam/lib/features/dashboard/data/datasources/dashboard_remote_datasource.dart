import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/dashboard/data/models/dashboard_summary_model.dart';
import 'package:dio/dio.dart';

abstract class DashboardRemoteDatasource {
  Future<DashboardSummaryModel> getDashboardSummary();
}

class DashboardRemoteDatasourceImpl implements DashboardRemoteDatasource {
  final DioClient _dioClient;

  DashboardRemoteDatasourceImpl({required DioClient dioClient}) : _dioClient = dioClient;

  @override
  Future<DashboardSummaryModel> getDashboardSummary() async {
    try {
      final response = await _dioClient.dio.get('/dashboard/summary');
      if (response.statusCode == 200) {
        return DashboardSummaryModel.fromJson(response.data);
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Error al obtener resumen del dashboard',
        );
      }
    } catch (e) {
      rethrow;
    }
  }
}
