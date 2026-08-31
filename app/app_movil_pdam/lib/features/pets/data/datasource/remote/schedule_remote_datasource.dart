import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/pets/data/models/schedule_model.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:dio/dio.dart';

abstract class ScheduleRemoteDatasource {
  Future<Schedule> createSchedule(String time, double amount, int petId);
  Future<Schedule> getSchedule(int id, int petId);
  Future<List<Schedule>> getSchedules();
  Future<List<Schedule>> getSchedulesByPet(int petId);
  Future<Schedule> updateSchedule(int id);
  Future<bool> deleteSchedule(int id);
}

class ScheduleTemoteDatasourceImp implements ScheduleRemoteDatasource {
  final DioClient _dioClient;

  ScheduleTemoteDatasourceImp({required DioClient dioClient})
    : _dioClient = dioClient;

  @override
  Future<Schedule> createSchedule(String time, double amount, int petId) async {
    try {
      final response = await _dioClient.dio.post(
        ApiConstants.schedules,
        queryParameters: {"pet_id": petId},
        data: {'time': time, 'amount': amount},
      );

      return ScheduleModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(e.message ?? "Error con el servidor al crear el horario");
    }
  }

  @override
  Future<Schedule> getSchedule(int id, int petId) async {
    try {
      final response = await _dioClient.dio.get(
        '${ApiConstants.schedules}id',
        queryParameters: {'pet_id': petId},
      );
      return ScheduleModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(
        e.message ?? "Error con el servidor al obtener el horario",
      );
    }
  }

  @override
  Future<List<Schedule>> getSchedules() async {
    try {
      final response = await _dioClient.dio.get(ApiConstants.schedules);
      return (response.data as List)
          .map((e) => ScheduleModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw Exception(
        e.message ?? "Error con el servidor al obtener los horarios",
      );
    }
  }

  @override
  Future<List<Schedule>> getSchedulesByPet(int petId) async {
    try {
      final response = await _dioClient.dio.get(
        '${ApiConstants.schedules}pet/$petId',
      );
      return (response.data as List)
          .map((e) => ScheduleModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw Exception(
        e.message ?? "Error con el servidor al obtener los horarios",
      );
    }
  }

  @override
  Future<bool> deleteSchedule(int id) {
    // TODO: implement deleteSchedule
    throw UnimplementedError();
  }

  @override
  Future<Schedule> updateSchedule(int id) {
    // TODO: implement updateSchedule
    throw UnimplementedError();
  }
}
