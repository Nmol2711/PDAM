import 'dart:convert';
import 'dart:typed_data';

import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/remote/log_remote_datasource.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
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

/// Adaptador HTTP falso: captura la petición y devuelve el cuerpo preparado.
class _FakeAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Object? body;
  int statusCode = 200;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Map<String, dynamic> _item(int id) => {
  'id': id,
  'created_at': '2026-10-01T17:00:00Z',
  'event_type': 'feeding_dispensed',
  'event_label': 'Comida dispensada',
  'outcome': 'success',
  'outcome_label': 'Éxito',
  'cause': 'objetivo_alcanzado',
  'cause_label': 'Objetivo alcanzado',
  'description': 'Comida dispensada',
  'pet_id': 3,
  'pet_name': 'Milo',
  'dispenser_mac_masked': '**:AB:1F',
  'order_id': 12,
  'requested_grams': 50.0,
  'measured_grams': 50.4,
  'discounted_grams': 50.4,
  'resulting_stock': 1149.6,
  'retry_count': 0,
  'context': <String, dynamic>{'faltante': 0.0},
};

void main() {
  late _FakeAdapter adapter;
  late LogRemoteDatasourceImpl datasource;

  setUp(() {
    adapter = _FakeAdapter();
    final client = DioClient(_FakeStorageService(), sessionEvents: SessionEvents());
    client.dio.interceptors.clear();
    client.dio.httpClientAdapter = adapter;
    datasource = LogRemoteDatasourceImpl(dioClient: client);
  });

  group('getLogs', () {
    test(
      'envía los cuatro filtros y la paginación con el contrato nuevo',
      () async {
        adapter.body = {
          'items': [_item(91)],
          'total': 1,
          'page': 2,
          'page_size': 20,
        };
        final dia = DateTime(2026, 10, 1);
        final filters = LogFilters(
          petId: 3,
          eventType: 'feeding_dispensed',
          outcome: 'success',
          fromDate: dia,
          toDate: dia,
        );

        final page = await datasource.getLogs(
          filters: filters,
          page: 2,
          pageSize: 20,
        );

        final params = adapter.lastRequest!.queryParameters;
        expect(adapter.lastRequest!.uri.path, '/logs/');
        expect(params['pet_id'].toString(), '3');
        expect(params['event_type'], 'feeding_dispensed');
        expect(params['outcome'], 'success');
        expect(params['from'], filters.fromIso);
        expect(params['to'], filters.toIso);
        expect(params['page'].toString(), '2');
        expect(params['page_size'].toString(), '20');
        expect(page.items.single.id, 91);
        expect(page.total, 1);
        expect(page.page, 2);
        expect(page.pageSize, 20);
      },
    );

    test('omite los filtros vacíos o ausentes', () async {
      adapter.body = {
        'items': const [],
        'total': 0,
        'page': 1,
        'page_size': 50,
      };

      await datasource.getLogs(
        filters: const LogFilters(eventType: '', outcome: '', petId: null),
        page: 1,
      );

      final params = adapter.lastRequest!.queryParameters;
      expect(params.containsKey('pet_id'), isFalse);
      expect(params.containsKey('event_type'), isFalse);
      expect(params.containsKey('outcome'), isFalse);
      expect(params.containsKey('from'), isFalse);
      expect(params.containsKey('to'), isFalse);
      expect(params['page'].toString(), '1');
      expect(params['page_size'].toString(), '50');
    });

    test('usa 50 como tamaño de página por defecto', () async {
      adapter.body = {
        'items': const [],
        'total': 0,
        'page': 1,
        'page_size': 50,
      };

      await datasource.getLogs(filters: LogFilters.empty, page: 1);

      expect(
        adapter.lastRequest!.queryParameters['page_size'].toString(),
        '50',
      );
    });

    test('lee el sobre y las etiquetas de cada ítem', () async {
      adapter.body = {
        'items': [_item(91)],
        'total': 1,
        'page': 1,
        'page_size': 50,
      };

      final page = await datasource.getLogs(filters: LogFilters.empty, page: 1);

      final log = page.items.single;
      expect(log.eventLabel, 'Comida dispensada');
      expect(log.outcomeLabel, 'Éxito');
      expect(log.causeLabel, 'Objetivo alcanzado');
      expect(log.dispenserMacMasked, '**:AB:1F');
      expect(log.measuredGrams, 50.4);
    });

    test(
      'traduce el 400 del catálogo a un error con su mensaje en español',
      () async {
        adapter.statusCode = 400;
        adapter.body = {
          'detail': {
            'code': 'rango_fechas_invalido',
            'message':
                'El rango de fechas no es válido: revise el orden de los límites y el desplazamiento horario.',
          },
        };

        await expectLater(
          datasource.getLogs(
            filters: LogFilters(
              fromDate: DateTime(2026, 10, 2),
              toDate: DateTime(2026, 10, 1),
            ),
            page: 1,
          ),
          throwsA(
            predicate<Object>(
              (e) => e.toString().contains('El rango de fechas no es válido'),
            ),
          ),
        );
      },
    );
  });

  group('getCatalog', () {
    test('pide el catálogo y lee tipos y resultados', () async {
      adapter.body = {
        'event_types': [
          {'code': 'pet_created', 'label': 'Mascota creada'},
        ],
        'outcomes': [
          {'code': 'success', 'label': 'Éxito'},
          {'code': 'failure', 'label': 'Fallo'},
        ],
      };

      final catalog = await datasource.getCatalog();

      expect(adapter.lastRequest!.uri.path, '/logs/catalog');
      expect(catalog.eventTypes.single.code, 'pet_created');
      expect(catalog.outcomes.length, 2);
    });

    test('un fallo del servidor lanza una excepción', () async {
      adapter.statusCode = 500;
      adapter.body = {'detail': 'Error interno'};

      await expectLater(datasource.getCatalog(), throwsA(isA<Exception>()));
    });
  });

  test('la ruta del historial sale de ApiConstants', () async {
    adapter.body = {'items': const [], 'total': 0, 'page': 1, 'page_size': 50};

    await datasource.getLogs(filters: LogFilters.empty, page: 1);

    expect(ApiConstants.logs, contains('/logs/'));
    expect(adapter.lastRequest!.uri.path, '/logs/');
  });
}
