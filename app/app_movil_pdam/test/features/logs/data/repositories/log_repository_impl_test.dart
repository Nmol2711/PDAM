import 'package:app_movil_pdam/core/error/api_exception.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/local/local_log_datasource.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/remote/log_remote_datasource.dart';
import 'package:app_movil_pdam/features/logs/data/repository_impl/log_repository_impl.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:flutter_test/flutter_test.dart';

ActivityLog _log(int id) => ActivityLog(
  id: id,
  createdAt: DateTime.utc(2026, 10, 1, 12),
  eventType: 'pet_created',
  eventLabel: 'Mascota creada',
  description: 'Mascota creada',
  petId: 1,
  context: const {},
);

LogPage _page(List<ActivityLog> items, {int total = 1, int page = 1}) =>
    LogPage(items: items, total: total, page: page, pageSize: 50);

class _FakeRemote implements LogRemoteDatasource {
  LogPage? page;
  Object? error;
  LogCatalog? catalog;
  Object? catalogError;
  LogFilters? lastFilters;
  int? lastPage;
  int? lastPageSize;
  int catalogCalls = 0;

  @override
  Future<LogPage> getLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  }) async {
    lastFilters = filters;
    lastPage = page;
    lastPageSize = pageSize;
    if (error != null) throw error!;
    return this.page ?? _page(const []);
  }

  @override
  Future<LogCatalog> getCatalog() async {
    catalogCalls++;
    if (catalogError != null) throw catalogError!;
    return catalog ?? const LogCatalog();
  }
}

class _FakeLocal implements LocalLogDatasource {
  LogPage? page;
  Object? error;
  LogCatalog? catalog;
  Object? catalogError;
  List<ActivityLog> cached = const [];
  LogFilters? lastFilters;
  int? lastPage;
  int? lastPageSize;

  @override
  Future<void> cacheLogs(List<ActivityLog> logs) async {
    cached = logs;
  }

  @override
  Future<void> deleteLocalLog(int logId) async {
    cached = cached.where((log) => log.id != logId).toList();
  }

  @override
  Future<LogCatalog> getLocalCatalog() async {
    if (catalogError != null) throw catalogError!;
    return catalog ?? const LogCatalog();
  }

  @override
  Future<LogPage> getLocalLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  }) async {
    lastFilters = filters;
    lastPage = page;
    lastPageSize = pageSize;
    if (error != null) throw error!;
    return this.page ?? _page(cached);
  }

  @override
  Future<void> saveLocalLog(ActivityLog log, {bool isSynced = true}) async {
    cached = [...cached.where((item) => item.id != log.id), log];
  }
}

void main() {
  late LogRepositoryImpl repository;
  late _FakeRemote remote;
  late _FakeLocal local;

  setUp(() {
    remote = _FakeRemote();
    local = _FakeLocal();
    repository = LogRepositoryImpl(
      remoteDatasource: remote,
      localLogDatasource: local,
    );
  });

  group('getLogs (RF-34, RF-35)', () {
    test('con red devuelve la página remota y la cachea', () async {
      remote.page = _page([_log(1), _log(2)], total: 2);

      final result = await repository.getLogs(
        filters: const LogFilters(petId: 3),
        page: 2,
      );

      result.fold((failure) => fail('No debería fallar: ${failure.message}'), (
        fetch,
      ) {
        expect(fetch.isOffline, isFalse);
        expect(fetch.page.items.length, 2);
        expect(fetch.page.total, 2);
      });
      expect(remote.lastFilters?.petId, 3);
      expect(remote.lastPage, 2);
      expect(remote.lastPageSize, 50);
      expect(local.cached.length, 2);
    });

    test(
      'si falla la red devuelve la caché con los mismos filtros y página',
      () async {
        remote.error = Exception('sin red');
        local.page = _page([_log(9)], total: 1, page: 2);

        final result = await repository.getLogs(
          filters: const LogFilters(outcome: 'failure'),
          page: 2,
        );

        result.fold(
          (failure) => fail('No debería fallar: ${failure.message}'),
          (fetch) {
            expect(fetch.isOffline, isTrue);
            expect(fetch.page.items.single.id, 9);
            expect(fetch.page.page, 2);
          },
        );
        expect(local.lastFilters?.outcome, 'failure');
        expect(local.lastPage, 2);
      },
    );

    test(
      'si fallan la red y la caché devuelve un fallo del servidor',
      () async {
        remote.error = Exception('sin red');
        local.error = Exception('error de caché');

        final result = await repository.getLogs(
          filters: LogFilters.empty,
          page: 1,
        );

        result.fold(
          (failure) => expect(failure, isA<ServerFailures>()),
          (_) => fail('No debería devolver datos'),
        );
      },
    );

    test('no vacía la caché cuando la consulta remota falla', () async {
      local.cached = [_log(1), _log(2)];
      local.page = _page(local.cached, total: 2);
      remote.error = Exception('sin red');

      await repository.getLogs(filters: LogFilters.empty, page: 1);

      expect(local.cached.length, 2);
    });

    test('un 400 del servidor no cae a la caché', () async {
      remote.error = const ApiException(
        code: 'rango_fechas_invalido',
        message:
            'El rango de fechas no es válido: revise el orden de los límites y el desplazamiento horario.',
        status: 400,
      );
      local.page = _page([_log(9)], total: 1);

      final result = await repository.getLogs(
        filters: LogFilters.empty,
        page: 1,
      );

      result.fold(
        (failure) => expect(failure.message, contains('rango de fechas')),
        (_) => fail('No debería devolver la caché ante un 400'),
      );
      expect(local.lastPage, isNull);
    });

    test('un 401 no cae a la caché: la sesión no está autorizada', () async {
      remote.error = const ApiException(
        code: 'unauthorized',
        message: 'No autorizado',
        status: 401,
      );
      local.page = _page([_log(9)], total: 1);

      final result = await repository.getLogs(
        filters: LogFilters.empty,
        page: 1,
      );

      result.fold(
        (failure) => expect(failure, isA<ServerFailures>()),
        (_) => fail('No debería devolver la caché ante un 401'),
      );
      expect(local.lastPage, isNull);
    });

    test('un 5xx sí cae a la caché', () async {
      remote.error = const ApiException(
        code: ApiException.serverErrorCode,
        message: 'Error interno',
        status: 500,
      );
      local.page = _page([_log(9)], total: 1);

      final result = await repository.getLogs(
        filters: LogFilters.empty,
        page: 1,
      );

      result.fold(
        (failure) => fail('No debería fallar: ${failure.message}'),
        (fetch) => expect(fetch.isOffline, isTrue),
      );
      expect(local.lastPage, 1);
    });
  });

  group('getCatalog (RF-31, RF-41)', () {
    test('con red devuelve el catálogo del servidor', () async {
      remote.catalog = const LogCatalog(
        eventTypes: [
          LogCatalogEntry(code: 'pet_created', label: 'Mascota creada'),
        ],
        outcomes: [LogCatalogEntry(code: 'success', label: 'Éxito')],
      );

      final result = await repository.getCatalog();

      result.fold((failure) => fail('No debería fallar: ${failure.message}'), (
        catalog,
      ) {
        expect(catalog.eventTypes.single.code, 'pet_created');
        expect(catalog.outcomes.single.label, 'Éxito');
      });
      expect(remote.catalogCalls, 1);
    });

    test('sin red devuelve el catálogo derivado de la caché', () async {
      remote.catalogError = Exception('sin red');
      local.catalog = const LogCatalog(
        eventTypes: [
          LogCatalogEntry(
            code: 'feeding_dispensed',
            label: 'Comida dispensada',
          ),
        ],
        outcomes: [LogCatalogEntry(code: 'failure', label: 'Fallo')],
      );

      final result = await repository.getCatalog();

      result.fold((failure) => fail('No debería fallar: ${failure.message}'), (
        catalog,
      ) {
        expect(catalog.eventTypes.single.label, 'Comida dispensada');
        expect(catalog.outcomes.single.label, 'Fallo');
      });
    });

    test('sin red y sin caché devuelve el fallo del servidor', () async {
      remote.catalogError = Exception('sin red');
      local.catalogError = Exception('error de caché');

      final result = await repository.getCatalog();

      result.fold(
        (failure) => expect(failure, isA<ServerFailures>()),
        (_) => fail('No debería devolver catálogo'),
      );
    });
  });
}
