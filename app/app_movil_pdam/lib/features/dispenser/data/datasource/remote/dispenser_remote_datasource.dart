import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/dispenser/data/models/dispenser_model.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:dio/dio.dart';

abstract class DispenserRemoteDatasource {
  Future<Dispenser> associateDispenser(
    String macAddress,
    int petId,
    String secretKeyQr,
  );
  Future<Map<String, dynamic>> checkPendingTask(String macAddress);
  Future<bool> dasactivateDispenser(int dispenserId, int petId);
  Future<bool> activateDispenser(int dispenserId, int petId);
  Future<Dispenser> getDispenserByPet(int petId);
  Future<bool> deleteDispenserByPet(int petId);
}

class DispenserRemoteDatasourceImpl implements DispenserRemoteDatasource {
  final DioClient _dioClient;

  DispenserRemoteDatasourceImpl({required DioClient dioClient})
    : _dioClient = dioClient;

  @override
  Future<Dispenser> associateDispenser(
    String macAddress,
    int petId,
    String secretKeyQr,
  ) async {
    try {
      final response = await _dioClient.dio.post(
        ApiConstants.dispenser,
        data: {
          'mac_address': macAddress,
          'pet_id': petId,
          'secret_key_qr': secretKeyQr,
        },
      );
      return DispenserModel.fromJson(response.data);
    } on DioException catch (e) {
      final String message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  String _extractErrorMessage(
    DioException e, {
    String staticMessage = 'Error con el servidor al asociar el dispensador',
  }) {
    if (e.response?.data is Map<String, dynamic>) {
      final data = e.response!.data as Map<String, dynamic>;
      if (data['detail'] != null) {
        return data['detail'].toString();
      }
      if (data['message'] != null) {
        return data['message'].toString();
      }
    }

    if (e.response?.data is String && (e.response!.data as String).isNotEmpty) {
      return e.response!.data.toString();
    }

    return e.message ?? staticMessage;
  }

  @override
  Future<Map<String, dynamic>> checkPendingTask(String macAddress) async {
    try {
      final response = await _dioClient.dio.get(
        '${ApiConstants.dispenser}dispenserscheck-taks/$macAddress',
      );

      return response.data;
    } on DioException catch (e) {
      throw Exception(_extractErrorMessage(e));
    }
  }

  @override
  Future<bool> dasactivateDispenser(int dispenserId, int petId) async {
    try {
      final response = await _dioClient.dio.put(
        "${ApiConstants.dispenser}$dispenserId",
        data: {'pet_id': petId, 'is_active': false},
      );

      return response.data["is_active"] == false;
    } on DioException catch (e) {
      throw Exception(e.message ?? "Error al desactivar el dispensador");
    }
  }

  @override
  Future<Dispenser> getDispenserByPet(int petId) async {
    try {
      final response = await _dioClient.dio.get(
        "${ApiConstants.dispenser}$petId",
      );
      return DispenserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(e.message ?? "Error al obtener el dispensador");
    }
  }

  @override
  Future<bool> activateDispenser(int dispenserId, int petId) async {
    try {
      final response = await _dioClient.dio.put(
        "${ApiConstants.dispenser}$dispenserId",
        data: {'pet_id': petId, 'is_active': true},
      );

      return response.data["is_active"] == true;
    } on DioException catch (e) {
      throw Exception(e.message ?? "Error al activar el dispensador");
    }
  }

  @override
  Future<bool> deleteDispenserByPet(int petId) async {
    try {
      final response = await _dioClient.dio.delete(
        '${ApiConstants.dispenser}$petId',
      );
      return response.data is bool ? response.data : true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 405) {
        try {
          final dispenser = await getDispenserByPet(petId);
          return await dasactivateDispenser(dispenser.id, petId);
        } catch (_) {
          throw Exception(
            'El servidor no permite eliminar el dispensador desde esta ruta. Intenta desactivarlo.',
          );
        }
      }

      throw Exception(
        _extractErrorMessage(
          e,
          staticMessage: "Error al eliminar el dispensador",
        ),
      );
    }
  }
}
