import 'package:app_movil_pdam/core/error/api_exception.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/offline/sync_service.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart';

class DispenserRepositoryImpl implements DispenserRepositories {
  final DispenserRemoteDatasource _dispenserRemoteDatasource;
  final LocalDispenserDatasource _localDispenserDatasource;
  final SyncService _syncService;

  DispenserRepositoryImpl({
    required DispenserRemoteDatasource dispenserRemoteDatasource,
    required LocalDispenserDatasource localDispenserDatasource,
    required SyncService syncService,
  }) : _dispenserRemoteDatasource = dispenserRemoteDatasource,
       _localDispenserDatasource = localDispenserDatasource,
       _syncService = syncService;

  /// Registra el dispensador. Solo es posible con conexión (RF-13, DO-3): es el
  /// servidor quien valida que la MAC sea única, así que mientras no acepte no se
  /// escribe nada en Isar y no queda ningún registro pendiente de enviar.
  @override
  Future<Either<Failures, Dispenser>> associateDispenser(
    String macAddress,
    int petId,
    String secretKeyQr,
  ) async {
    if (!await _syncService.hasConnection()) {
      return Left(ConnectivityRequiredFailures(_sinConexionAlRegistrar));
    }

    try {
      final result = await _dispenserRemoteDatasource.associateDispenser(
        macAddress,
        petId,
        secretKeyQr,
      );
      await _localDispenserDatasource.saveLocalDispenser(
        result,
        isSynced: true,
        secretKeyQr: secretKeyQr,
      );
      return Right(result);
    } catch (e) {
      return Left(_failureFrom(e));
    }
  }

  /// Cambia la dirección MAC con la misma política que el alta (RF-14): si
  /// falla, el datasource local no se toca y la fila conserva la MAC anterior.
  @override
  Future<Either<Failures, Dispenser>> updateDispenserMac(
    int dispenserId,
    int petId,
    String macAddress,
  ) async {
    if (!await _syncService.hasConnection()) {
      return Left(ConnectivityRequiredFailures(_sinConexionAlCambiarMac));
    }

    try {
      final result = await _dispenserRemoteDatasource.updateDispenserMac(
        dispenserId,
        petId,
        macAddress,
      );
      await _localDispenserDatasource.saveLocalDispenser(result, isSynced: true);
      return Right(result);
    } catch (e) {
      return Left(_failureFrom(e));
    }
  }

  @override
  Future<Either<Failures, Map<String, dynamic>>> checkPendingTask(
    String macAddress,
  ) async {
    try {
      final result = await _dispenserRemoteDatasource.checkPendingTask(
        macAddress,
      );
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, Dispenser>> getDispenserByPet(int petId) async {
    try {
      final result = await _dispenserRemoteDatasource.getDispenserByPet(petId);
      await _localDispenserDatasource.cacheDispenser(result);
      return Right(result);
    } catch (e) {
      try {
        final local = await _localDispenserDatasource.getLocalDispenserByPet(petId);
        if (local != null) {
          return Right(local);
        }
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, bool>> dasactivateDispenser(
    int dispenserId,
    int petId,
  ) async {
    if (!await _syncService.hasConnection()) {
      return Left(ConnectivityRequiredFailures(_sinConexionAlDesactivar));
    }
    try {
      final result = await _dispenserRemoteDatasource.dasactivateDispenser(
        dispenserId,
        petId,
      );
      return Right(result);
    } catch (e) {
      return Left(_failureFrom(e));
    }
  }

  @override
  Future<Either<Failures, bool>> activateDispenser(
    int dispenserId,
    int petId,
  ) async {
    if (!await _syncService.hasConnection()) {
      return Left(ConnectivityRequiredFailures(_sinConexionAlActivar));
    }
    try {
      final result = await _dispenserRemoteDatasource.activateDispenser(
        dispenserId,
        petId,
      );
      return Right(result);
    } catch (e) {
      return Left(_failureFrom(e));
    }
  }

  @override
  Future<Either<Failures, bool>> deleteDispenser(int petId) async {
    if (!await _syncService.hasConnection()) {
      return Left(ConnectivityRequiredFailures(_sinConexionAlEliminar));
    }
    try {
      final result = await _dispenserRemoteDatasource.deleteDispenserByPet(
        petId,
      );
      await _localDispenserDatasource.deleteLocalDispenser(petId);
      return Right(result);
    } catch (e) {
      return Left(_failureFrom(e));
    }
  }

  static const String _sinConexionAlRegistrar =
      'No hay conexión con el servidor para registrar el dispensador';
  static const String _sinConexionAlCambiarMac =
      'No hay conexión con el servidor para cambiar la dirección del dispensador';
  static const String _sinConexionAlActivar =
      'No hay conexión con el servidor para activar el dispensador';
  static const String _sinConexionAlDesactivar =
      'No hay conexión con el servidor para desactivar el dispensador';
  static const String _sinConexionAlEliminar =
      'No hay conexión con el servidor para eliminar el dispensador';
  static const String _falloDeRed =
      'No se pudo completar la operación porque no hay conexión con el servidor';

  /// Tipos de `DioException` que son fallo de red y no del servidor.
  static const Set<DioExceptionType> _networkTypes = {
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
    DioExceptionType.badCertificate,
  };

  /// Traduce una excepción a `Failures` tipado sin mirar el texto del servidor
  /// (RF-03, RF-04, RF-06): el `code` de DO-5 es el identificador estable.
  Failures _failureFrom(Object error) {
    final apiError = _apiExceptionOrNull(error);
    if (apiError != null) {
      return _failureForCode(apiError.code, apiError.message);
    }
    if (_isNetworkError(error)) {
      return ConnectivityRequiredFailures(_falloDeRed);
    }
    return ServerFailures(error.toString().replaceAll('Exception: ', ''));
  }

  Failures _failureForCode(String code, String message) {
    switch (code) {
      case 'mac_already_registered':
        return MacAlreadyRegisteredFailures(message);
      case 'mac_in_use':
        return MacInUseFailures(message);
      case 'mac_invalid_format':
        return InvalidMacFormatFailures(message);
      // `pet_already_has_dispenser` y `server_error` conservan el copy actual.
      case 'pet_already_has_dispenser':
      case ApiException.serverErrorCode:
        return ServerFailures(message);
      default:
        return ServerFailures(message);
    }
  }

  /// Normaliza a `ApiException` lo que lanza el datasource. El datasource real
  /// ya lanza ese tipo; se acepta además un `DioException` crudo para no perder
  /// la clasificación por `code` cuando la capa remota no llega a mapearla.
  ApiException? _apiExceptionOrNull(Object error) {
    if (error is ApiException) {
      return error;
    }

    if (error is DioException &&
        error.response?.data is Map<String, dynamic>) {
      final detail = (error.response!.data as Map<String, dynamic>)['detail'];
      if (detail is Map<String, dynamic> && detail['code'] != null) {
        return ApiException(
          code: detail['code'].toString(),
          message: detail['message']?.toString() ?? '',
          status: error.response?.statusCode,
        );
      }
    }

    return null;
  }

  bool _isNetworkError(Object error) {
    if (error is! DioException) {
      return false;
    }
    return error.response == null || _networkTypes.contains(error.type);
  }
}
