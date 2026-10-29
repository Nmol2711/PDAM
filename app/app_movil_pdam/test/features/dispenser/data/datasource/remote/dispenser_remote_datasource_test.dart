import 'dart:convert';
import 'dart:typed_data';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/offline/sync_service.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/local/local_dispenser_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/datasource/remote/dispenser_remote_datasource.dart';
import 'package:app_movil_pdam/features/dispenser/data/repositories_impl/dispenser_repository_impl.dart';
import 'package:app_movil_pdam/features/dispenser/data/services/ble_provisioning_service.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorageService implements StorageService {
  @override
  Future<Either<Failures, void>> deleteString(String key) async =>
      const Right(null);

  @override
  Future<Either<Failures, String?>> getString(String key) async =>
      const Right(null);

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async =>
      const Right(null);
}

/// Adaptador HTTP falso: captura el cuerpo de cada petición y permite forzar
/// un fallo de red puntual antes de responder.
class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  /// Respuestas ya codificadas que se devuelven en orden.
  final List<({int status, Object body})> respuestas = [];

  /// Si es true, la siguiente petición falla como error de red.
  bool fallarProxima = false;

  List<Map<String, dynamic>> get cuerpos =>
      requests.map(_cuerpo).toList(growable: false);

  /// El cuerpo llega como mapa o ya serializado según el transformador de Dio.
  Map<String, dynamic> _cuerpo(RequestOptions peticion) {
    final data = peticion.data;
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return Map<String, dynamic>.from(data as Map);
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (fallarProxima) {
      fallarProxima = false;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'sin red',
      );
    }
    final respuesta = respuestas.isEmpty
        ? (status: 200, body: const <String, dynamic>{})
        : respuestas.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(respuesta.body),
      respuesta.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _FakeLocalDispenserDatasource implements LocalDispenserDatasource {
  Dispenser? saved;
  int? remoteId;

  @override
  Future<void> cacheDispenser(Dispenser dispenser) async => saved = dispenser;

  @override
  Future<void> deleteLocalDispenser(int petId) async => saved = null;

  @override
  Future<Dispenser?> getLocalDispenserByPet(int petId) async => saved;

  @override
  Future<List<Dispenser>> getLocalDispensers() async =>
      saved == null ? const [] : [saved!];

  @override
  Future<int?> getRemoteIdByDeviceId(String deviceId) async => remoteId;

  @override
  Future<void> saveLocalDispenser(
    Dispenser dispenser, {
    bool isSynced = true,
    String? secretKeyQr,
    double? pendingRefillGrams,
    String? pendingRefillId,
  }) async {
    final pendiente =
        pendingRefillGrams ?? saved?.pendingRefillGrams ?? dispenser.pendingRefillGrams;
    final identificador = pendingRefillId == null
        ? (saved?.pendingRefillId ?? dispenser.pendingRefillId)
        : (pendingRefillId.isEmpty ? null : pendingRefillId);
    saved = dispenser.copyWith(
      pendingRefillGrams: pendiente,
      pendingRefillId: identificador,
      clearPendingRefillId: identificador == null,
    );
  }
}

class _FakeSyncService implements SyncService {
  @override
  Future<bool> hasConnection() async => true;

  @override
  Future<bool> synchronizeBatch({
    required double lastSyncTimestamp,
    required List<Map<String, dynamic>> localItems,
  }) async => false;

  @override
  Future<bool> synchronizePendingData({
    String? testDirectory,
    double lastSyncTimestamp = 0.0,
  }) async => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _dispenserJson({double stock = 1500}) => {
  'id': 7,
  'mac_address': 'AA:BB:CC:DD:EE:FF',
  'pending_dispensing': false,
  'is_active': true,
  'pet_id': 1,
  'name': 'Dispensador',
  'current_food_grams': stock,
};

void main() {
  late _FakeAdapter adapter;
  late DioClient client;
  late DispenserRemoteDatasourceImpl datasource;

  setUp(() {
    adapter = _FakeAdapter();
    client = DioClient(_FakeStorageService());
    client.dio.interceptors.clear();
    client.dio.httpClientAdapter = adapter;
    datasource = DispenserRemoteDatasourceImpl(dioClient: client);
  });

  group('refillDispenser (RF-11, RF-12)', () {
    test('el POST envía solo amount, unit, operation_id y origen', () async {
      adapter.respuestas.add((status: 200, body: _dispenserJson()));

      final dispenser = await datasource.refillDispenser(
        7,
        500.0,
        'g',
        operationId: 'operacion-123',
        origen: 'sincronizacion_sin_conexion',
      );

      final peticion = adapter.requests.single;
      expect(peticion.method, 'POST');
      expect(peticion.uri.path, '/dispensers/7/refill');
      expect(adapter.cuerpos.single, {
        'amount': 500.0,
        'unit': 'g',
        'operation_id': 'operacion-123',
        'origen': 'sincronizacion_sin_conexion',
      });
      expect(dispenser.currentFoodGrams, 1500.0);
    });

    test('origen vale servidor por defecto', () async {
      adapter.respuestas.add((status: 200, body: _dispenserJson()));

      await datasource.refillDispenser(
        7,
        500.0,
        'g',
        operationId: 'operacion-123',
      );

      expect(adapter.cuerpos.single['origen'], 'servidor');
    });

    test(
      'un reintento del reabastecimiento reenvía el mismo operation_id',
      () async {
        // Primer intento: falla la red. El repositorio conserva el pendiente y
        // su identificador; la sincronización siguiente reenvía el mismo.
        adapter.fallarProxima = true;
        final localDatasource = _FakeLocalDispenserDatasource()
          ..remoteId = 7
          ..saved = const Dispenser(
            id: 7,
            macAddress: 'AA:BB:CC:DD:EE:FF',
            isActive: true,
            petId: 1,
            currentFoodGrams: 1000.0,
          );
        final repository = DispenserRepositoryImpl(
          dispenserRemoteDatasource: datasource,
          localDispenserDatasource: localDatasource,
          syncService: _FakeSyncService(),
          bleService: BleProvisioningService(),
          dioClient: client,
          storageService: _FakeStorageService(),
        );

        await repository.refillFood('7', 500.0);

        final guardado = localDatasource.saved!;
        expect(guardado.pendingRefillGrams, 500.0);
        expect(guardado.pendingRefillId, isNotNull);

        adapter.respuestas.add((status: 200, body: _dispenserJson()));
        await repository.refreshDispensers();

        final cuerpos = adapter.cuerpos;
        expect(cuerpos, hasLength(2));
        expect(cuerpos[0]['amount'], 500.0);
        expect(cuerpos[1]['amount'], 500.0);
        expect(cuerpos[0]['unit'], 'g');
        expect(cuerpos[1]['unit'], 'g');
        expect(cuerpos[0]['origen'], 'servidor');
        expect(cuerpos[1]['origen'], 'sincronizacion_sin_conexion');
        expect(cuerpos[0]['operation_id'], isNotNull);
        expect(cuerpos[0]['operation_id'], isNotEmpty);
        expect(cuerpos[1]['operation_id'], cuerpos[0]['operation_id']);
        expect(localDatasource.saved?.pendingRefillId, isNull);
      },
    );
  });
}
