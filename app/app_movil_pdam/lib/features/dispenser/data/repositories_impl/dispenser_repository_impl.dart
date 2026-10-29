import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/api_exception.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/offline/sync_service.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/services/ble_provisioning_service.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser_food_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:app_movil_pdam/features/logs/domain/utils/operation_id_utils.dart';
import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart';

/// Implementación única del módulo: reúne el flujo QR/MAC y el flujo BLE/WiFi.
class DispenserRepositoryImpl implements DispenserRepositories {
  final DispenserRemoteDatasource _dispenserRemoteDatasource;
  final LocalDispenserDatasource _localDispenserDatasource;
  final SyncService _syncService;
  final BleProvisioningService _bleService;
  final DioClient _dioClient;
  final StorageService _storageService;

  DispenserRepositoryImpl({
    required DispenserRemoteDatasource dispenserRemoteDatasource,
    required LocalDispenserDatasource localDispenserDatasource,
    required SyncService syncService,
    required BleProvisioningService bleService,
    required DioClient dioClient,
    required StorageService storageService,
  }) : _dispenserRemoteDatasource = dispenserRemoteDatasource,
       _localDispenserDatasource = localDispenserDatasource,
       _syncService = syncService,
       _bleService = bleService,
       _dioClient = dioClient,
       _storageService = storageService;

  // --- Flujo QR / MAC ---

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
      await _localDispenserDatasource.saveLocalDispenser(
        result,
        isSynced: true,
      );
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
        final local = await _localDispenserDatasource.getLocalDispenserByPet(
          petId,
        );
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

  // --- Flujo local / BLE / WiFi ---

  @override
  Future<List<Dispenser>> getLocalDispensers() async {
    final localList = await _localDispenserDatasource.getLocalDispensers();
    final result = <Dispenser>[];
    for (final local in localList) {
      // Solo se listan los dispensadores vinculados a una mascota.
      if (local.petId == null) continue;
      final deviceId = local.deviceId.toUpperCase();
      final mac = local.macAddress.toUpperCase();

      String? ssid = await _readSsid(mac);
      ssid ??= await _readSsid(deviceId);

      result.add(
        local.copyWith(
          macAddress: mac,
          name: 'Dispensador $mac',
          wifiSsid: ssid,
        ),
      );
    }
    return result;
  }

  /// Refresco silencioso del stock (RF-4, RF-10). El servidor es la fuente de
  /// verdad: se consulta dispensador por mascota y se sobrescribe la caché.
  /// Antes de consultar se intenta sincronizar el reabastecimiento pendiente
  /// (RF-12); cualquier fallo individual conserva el dato local.
  @override
  Future<void> refreshDispensers() async {
    if (!await _syncService.hasConnection()) {
      return;
    }

    final localList = await _localDispenserDatasource.getLocalDispensers();
    for (final local in localList) {
      final petId = local.petId;
      if (petId == null) continue;
      final pending = local.pendingRefillGrams;

      if (pending > 0) {
        final remoteId = await _localDispenserDatasource.getRemoteIdByDeviceId(
          local.deviceId,
        );
        if (remoteId != null) {
          final operationId = _operationIdPara(local);
          if (local.pendingRefillId != operationId) {
            // Se persiste antes de enviar: si la app se cierra o se corta la
            // red, el reenvío lleva el mismo identificador y el servidor
            // deduplica (RF-11).
            await _localDispenserDatasource.saveLocalDispenser(
              local,
              pendingRefillId: operationId,
            );
          }
          try {
            final updated = await _dispenserRemoteDatasource.refillDispenser(
              remoteId,
              pending,
              'g',
              operationId: operationId,
              origen: _origenSincronizacion,
            );
            await _localDispenserDatasource.saveLocalDispenser(
              updated,
              pendingRefillGrams: 0.0,
              pendingRefillId: '',
            );
          } catch (e) {
            final apiError = _apiExceptionOrNull(e);
            if (apiError?.code == _codeRefillExceedsCapacity) {
              // Carrera de stock: el servidor no admite el delta pendiente.
              // Se reconcilia con su stock real y se descarta el pendiente.
              await _reconcileWithServer(petId);
            }
            // Otro fallo (red/servidor): se conserva el pendiente, su
            // identificador y el stock.
          }
          // No se hace un GET adicional: la respuesta del refill ya es
          // autoritativa, o bien se conserva la vista optimista local.
          continue;
        }
      }

      try {
        final remote = await _dispenserRemoteDatasource.getDispenserByPet(
          petId,
        );
        await _localDispenserDatasource.cacheDispenser(remote);
      } catch (_) {
        // Sin conexión o error puntual: se mantiene el stock local.
      }
    }
  }

  Future<void> _reconcileWithServer(int petId) async {
    try {
      final remote = await _dispenserRemoteDatasource.getDispenserByPet(petId);
      await _localDispenserDatasource.saveLocalDispenser(
        remote,
        pendingRefillGrams: 0.0,
        pendingRefillId: '',
      );
    } catch (_) {
      // No se pudo reconciliar; el pendiente se reintentará en el próximo ciclo.
    }
  }

  @override
  Future<void> saveLocalDispenser(Dispenser dispenser) async {
    await _localDispenserDatasource.saveLocalDispenser(dispenser);
    if (dispenser.wifiSsid != null && dispenser.wifiSsid!.isNotEmpty) {
      await _storageService.saveString(
        'wifi_ssid_${dispenser.macAddress.toUpperCase()}',
        dispenser.wifiSsid!,
      );
      await _storageService.saveString(
        'wifi_ssid_${dispenser.deviceId.toUpperCase()}',
        dispenser.wifiSsid!,
      );
    }
  }

  /// Reabastece respetando la capacidad del depósito (RF-7, RF-8) y
  /// funcionando sin conexión (RF-11). El servidor es autoritativo cuando hay
  /// red; si no, se aplica el stock local y se guarda el delta pendiente junto
  /// a su identificador de operación.
  @override
  Future<void> refillFood(String dispenserId, double grams) async {
    final localList = await _localDispenserDatasource.getLocalDispensers();
    final local = localList
        .where((dispenser) => _matchesId(dispenser, dispenserId))
        .firstOrNull;

    final hasConnection = await _syncService.hasConnection();
    final remoteId = await _localDispenserDatasource.getRemoteIdByDeviceId(
      dispenserId,
    );

    if (local == null) {
      if (!hasConnection || remoteId == null) {
        throw Exception(_dispensadorSinRegistroRemoto);
      }
      final updated = await _dispenserRemoteDatasource.refillDispenser(
        remoteId,
        grams,
        'g',
        operationId: generarIdentificadorOperacion(),
        origen: _origenServidor,
      );
      await _localDispenserDatasource.saveLocalDispenser(
        updated,
        pendingRefillGrams: 0.0,
        pendingRefillId: '',
      );
      return;
    }

    // Valida contra el stock local; lanza RefillLimitException si la suma
    // supera 5000 g, sin tocar Isar (RF-8).
    final newStock = applyRefill(local.currentFoodGrams, grams);
    final pending = local.pendingRefillGrams + grams;
    final operationId = _operationIdPara(local);

    if (!hasConnection || remoteId == null) {
      await _savePendingRefill(local, newStock, pending, operationId);
      return;
    }

    try {
      final updated = await _dispenserRemoteDatasource.refillDispenser(
        remoteId,
        pending,
        'g',
        operationId: operationId,
        origen: _origenServidor,
      );
      await _localDispenserDatasource.saveLocalDispenser(
        updated,
        pendingRefillGrams: 0.0,
        pendingRefillId: '',
      );
    } catch (e) {
      final apiError = _apiExceptionOrNull(e);
      if (apiError?.code == _codeRefillExceedsCapacity) {
        throw const RefillLimitException();
      }
      // Un fallo no relacionado con el límite se trata como offline: se
      // conserva el stock local, el delta pendiente y su identificador para
      // que el reenvío se deduplique (RF-11, RF-13).
      await _savePendingRefill(local, newStock, pending, operationId);
    }
  }

  /// Reutiliza el identificador del pendiente o genera uno nuevo (RF-11).
  ///
  /// Un pendiente acumulado se envía como una sola operación, así que conserva
  /// el identificador que ya tenía hasta recibir una respuesta definitiva.
  String _operationIdPara(Dispenser local) {
    final guardado = local.pendingRefillId;
    if (guardado != null && guardado.isNotEmpty) return guardado;
    return generarIdentificadorOperacion();
  }

  Future<void> _savePendingRefill(
    Dispenser local,
    double newStock,
    double pending,
    String operationId,
  ) async {
    await _localDispenserDatasource.saveLocalDispenser(
      local.copyWith(
        currentFoodGrams: newStock,
        pendingRefillGrams: pending,
        pendingRefillId: operationId,
      ),
      pendingRefillGrams: pending,
      pendingRefillId: operationId,
    );
  }

  @override
  Future<void> discountFood(String dispenserId, double grams) async {
    final localList = await _localDispenserDatasource.getLocalDispensers();
    for (final local in localList) {
      if (_matchesId(local, dispenserId)) {
        await _localDispenserDatasource.saveLocalDispenser(
          local.copyWith(
            currentFoodGrams: (local.currentFoodGrams - grams)
                .clamp(0.0, 5000.0)
                .toDouble(),
          ),
        );
      }
    }
  }

  @override
  Stream<List<ScannedDevice>> scanBleDispensers() {
    return _bleService.scanDevices();
  }

  @override
  Future<void> stopBleScan() async {
    await _bleService.stopScan();
  }

  @override
  Future<void> connectAndProvisionBle({
    required String deviceId,
    required String ssid,
    required String password,
  }) async {
    await _bleService.connectAndProvision(
      deviceId: deviceId,
      ssid: ssid,
      password: password,
    );
    // RF-01 & RNF-02: guarda las credenciales WiFi de forma segura.
    final resSsid = await _storageService.saveString(
      'wifi_ssid_$deviceId',
      ssid,
    );
    resSsid.fold(
      (f) => throw Exception(
        'Error al guardar SSID de forma segura: ${f.message}',
      ),
      (_) {},
    );
    final resPass = await _storageService.saveString(
      'wifi_pass_$deviceId',
      password,
    );
    resPass.fold(
      (f) => throw Exception(
        'Error al guardar contraseña de forma segura: ${f.message}',
      ),
      (_) {},
    );
  }

  @override
  Future<void> resetWifiRemote(String dispenserId) async {
    try {
      await _dioClient.dio.post(
        '${ApiConstants.dispenser}$dispenserId/reset-wifi',
      );
    } catch (e) {
      throw Exception('Error al solicitar reseteo de WiFi: ${e.toString()}');
    }
    await _storageService.deleteString('wifi_ssid_$dispenserId');
    await _storageService.deleteString('wifi_pass_$dispenserId');
  }

  bool _matchesId(Dispenser local, String dispenserId) {
    return local.id.toString() == dispenserId ||
        local.macAddress == dispenserId ||
        local.deviceId == dispenserId;
  }

  Future<String?> _readSsid(String key) async {
    final result = await _storageService.getString('wifi_ssid_$key');
    return result.fold((_) => null, (value) => value);
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
  static const String _codeRefillExceedsCapacity = 'supera_capacidad';
  static const String _origenServidor = 'servidor';
  static const String _origenSincronizacion = 'sincronizacion_sin_conexion';
  static const String _dispensadorSinRegistroRemoto =
      'El dispensador no está registrado en el servidor. Configúralo desde la app antes de reabastecer.';
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

    if (error is DioException && error.response?.data is Map<String, dynamic>) {
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
