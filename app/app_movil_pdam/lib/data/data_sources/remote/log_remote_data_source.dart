import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/api_client.dart';
import 'package:app_movil_pdam/data/models/log_model.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:dio/dio.dart';

abstract class LogRemoteDataSource {
  Future<List<LogModel>> getLogs(AuthToken token);
  Future<LogModel> createLog(AuthToken token, String event);
}

class LogRemoteDataSourceImpl extends LogRemoteDataSource {
  @override
  Future<LogModel> createLog(AuthToken token, String event) async {
    final dioResult = getDioClient(token);

    return await dioResult.fold(
      (failure) => throw ServerFailures(failure.message),
      (dio) async {
        try {
          final response = await dio.post(
            ApiConstants.logs,
            data: {'event': event},
          );
          return LogModel.fromJson(response.data);
        } on DioException catch (e) {
          throw ServerFailures(
            e.response?.data['detail'] ?? "Error con el servidor",
          );
        }
      },
    );
  }

  @override
  Future<List<LogModel>> getLogs(AuthToken token) async {
    final dioResult = getDioClient(token);

    return await dioResult.fold(
      (failure) => throw ServerFailures(failure.message),
      (dio) async {
        try {
          final response = await dio.get(ApiConstants.logs);
          return (response.data as List)
              .map((e) => LogModel.fromJson(e))
              .toList();
        } on DioException catch (e) {
          throw ServerFailures(
            e.response?.data['detail'] ?? "Error con el servidor",
          );
        }
      },
    );
  }
}
