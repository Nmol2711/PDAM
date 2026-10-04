import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/api_exception.dart';
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

  /// Cambia la dirección MAC del dispensador (RF-04, RF-14). El servidor
  /// valida formato y unicidad por forma normalizada, así que un conflicto
  /// llega como `ApiException` con `code` `mac_in_use` o `mac_invalid_format`.
  Future<Dispenser> updateDispenserMac(int dispenserId, int petId, String macAddress);
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
      throw _apiExceptionFrom(
        e,
        staticMessage: 'Error con el servidor al asociar el dispensador',
      );
    }
  }

  /// Traduce el contrato de DO-5 a `ApiException`.
  ///
  /// Cuando `detail` ya es un objeto se toma su `code`, que es el identificador
  /// estable (AC-4). Cuando sigue siendo texto (403, 404, 422 de esquema o
  /// endpoints no migrados) se cae en [ApiException.serverErrorCode] con el
  /// texto que ya se mostraba, para no romper los flujos existentes.
  ApiException _apiExceptionFrom(DioException e, {required String staticMessage}) {
    final Object? detail = e.response?.data is Map<String, dynamic>
        ? (e.response!.data as Map<String, dynamic>)['detail']
        : null;

    if (detail is Map<String, dynamic> && detail['code'] != null) {
      return ApiException(
        code: detail['code'].toString(),
        message: detail['message']?.toString() ?? staticMessage,
        status: e.response?.statusCode,
      );
    }

    return ApiException(
      code: ApiException.serverErrorCode,
      message: _extractErrorMessage(e, staticMessage: staticMessage),
      status: e.response?.statusCode,
    );
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
      throw _apiExceptionFrom(
        e,
        staticMessage: 'Error con el servidor al consultar la tarea pendiente',
      );
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
  Future<Dispenser> updateDispenserMac(int dispenserId, int petId, String macAddress) async {
    try {
      final response = await _dioClient.dio.put(
        '${ApiConstants.dispenser}$dispenserId',
        data: {'pet_id': petId, 'mac_address': macAddress},
      );

      return DispenserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _apiExceptionFrom(
        e,
        staticMessage: 'Error con el servidor al cambiar la dirección del dispensador',
      );
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
          throw ApiException(
            code: ApiException.serverErrorCode,
            message: 'El servidor no permite eliminar el dispensador desde esta ruta. Intenta desactivarlo.',
            status: e.response?.statusCode,
          );
        }
      }

      throw _apiExceptionFrom(
        e,
        staticMessage: "Error al eliminar el dispensador",
      );
    }
  }
}
