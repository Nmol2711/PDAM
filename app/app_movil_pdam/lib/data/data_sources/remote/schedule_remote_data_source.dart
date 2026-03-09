import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/api_client.dart';

import 'package:app_movil_pdam/data/models/schedule_model.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:dio/dio.dart';

abstract class ScheduleRemoteDataSource {
  Future<List<ScheduleModel>> getSchedules(AuthToken token);
  Future<List<ScheduleModel>> getTimeSchedules(AuthToken token, String date);
  Future<ScheduleModel> createSchedule(
    AuthToken token,
    String time,
    int amount,
  );
  Future<ScheduleModel> updateSchedule(
    AuthToken token,
    int id,
    String time,
    int amount,
  );
}

class ScheduleRemoteDataSourceImpl extends ScheduleRemoteDataSource {
  @override
  Future<ScheduleModel> createSchedule(
    AuthToken token,
    String time,
    int amount,
  ) {
    final dioResult = getDioClient(token);

    return dioResult.fold((failure) => throw ServerFailures(failure.message), (
      dio,
    ) async {
      try {
        final response = await dio.post(
          ApiConstants.schedules,
          data: {'time': time, 'amount': amount},
        );
        return ScheduleModel.fromJson(response.data);
      } on DioException catch (e) {
        throw ServerFailures(
          e.response?.data['detail'] ?? "Error con el servidor",
        );
      }
    });
  }

  @override
  Future<List<ScheduleModel>> getSchedules(AuthToken token) {
    final dioResult = getDioClient(token);

    return dioResult.fold((failure) => throw ServerFailures(failure.message), (
      dio,
    ) async {
      try {
        final response = await dio.get(ApiConstants.schedules);
        return (response.data as List)
            .map((e) => ScheduleModel.fromJson(e))
            .toList();
      } on DioException catch (e) {
        throw ServerFailures(
          e.response?.data['detail'] ?? "Error con el servidor",
        );
      }
    });
  }

  //TODO: aun no esta disponible en la api
  @override
  Future<List<ScheduleModel>> getTimeSchedules(AuthToken token, String date) {
    final dioResult = getDioClient(token);

    return dioResult.fold((failure) => throw ServerFailures(failure.message), (
      dio,
    ) async {
      try {
        final response = await dio.get(ApiConstants.schedules);
        return (response.data as List)
            .map((e) => ScheduleModel.fromJson(e))
            .toList();
      } on DioException catch (e) {
        throw ServerFailures(
          e.response?.data['detail'] ?? "Error con el servidor",
        );
      }
    });
  }

  @override
  Future<ScheduleModel> updateSchedule(
    AuthToken token,
    int id,
    String time,
    int amount,
  ) {
    final dioResult = getDioClient(token);

    return dioResult.fold((failure) => throw ServerFailures(failure.message), (
      dio,
    ) async {
      try {
        final response = await dio.put(
          "${ApiConstants.schedules}$id",
          data: {'time': time, 'amount': amount},
        );

        return ScheduleModel.fromJson(response.data);
      } on DioException catch (e) {
        throw ServerFailures(
          e.response?.data['detail'] ?? "Error con el servidor",
        );
      }
    });
  }
}
