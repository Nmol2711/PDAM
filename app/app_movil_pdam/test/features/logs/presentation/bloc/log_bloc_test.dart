import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/repository/log_repositories.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_log_catalog_uc.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_logs_uc.dart';
import 'package:app_movil_pdam/features/logs/presentation/bloc/log_bloc.dart';
import 'package:dartz/dartz.dart';
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

class _FakeLogRepository implements LogRepositories {
  Either<Failures, LogFetchResult>? response;
  Either<Failures, LogCatalog>? catalogResponse;
  Completer<void>? completer;
  int calls = 0;
  int catalogCalls = 0;
  LogFilters? lastFilters;
  int? lastPage;
  int? lastPageSize;

  @override
  Future<Either<Failures, LogFetchResult>> getLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  }) async {
    calls++;
    lastFilters = filters;
    lastPage = page;
    lastPageSize = pageSize;
    if (completer != null) {
      await completer!.future;
    }
    return response ??
        Right(
          LogFetchResult(
            page: LogPage(
              items: const [],
              total: 0,
              page: page,
              pageSize: pageSize,
            ),
            isOffline: false,
          ),
        );
  }

  @override
  Future<Either<Failures, LogCatalog>> getCatalog() async {
    catalogCalls++;
    return catalogResponse ?? const Right(LogCatalog());
  }
}

void main() {
  late _FakeLogRepository repository;
  late LogBloc bloc;

  setUp(() {
    repository = _FakeLogRepository();
    bloc = LogBloc(
      getLogsUc: GetLogsUc(repository: repository),
      getLogCatalogUc: GetLogCatalogUc(repository: repository),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  group('carga (RF-32, RF-33)', () {
    test('emite la página con totales y sin aviso offline', () async {
      repository.response = Right(
        LogFetchResult(
          page: LogPage(
            items: [_log(1), _log(2)],
            total: 2,
            page: 1,
            pageSize: 50,
          ),
          isOffline: false,
        ),
      );

      bloc.add(const LogsRequested());
      await pumpEventQueue();

      final state = bloc.state;
      expect(state.items.length, 2);
      expect(state.total, 2);
      expect(state.totalPages, 1);
      expect(state.page, 1);
      expect(state.isLoading, isFalse);
      expect(state.isOffline, isFalse);
      expect(state.errorMessage, isNull);
      expect(repository.lastPageSize, 50);
    });

    test('mantiene la lista previa mientras carga', () async {
      repository.response = Right(
        LogFetchResult(
          page: LogPage(items: [_log(1)], total: 1, page: 1, pageSize: 50),
          isOffline: false,
        ),
      );
      bloc.add(const LogsRequested());
      await pumpEventQueue();
      expect(bloc.state.items.length, 1);

      repository.completer = Completer<void>();
      bloc.add(const LogFiltersChanged(LogFilters(petId: 1)));
      await pumpEventQueue();

      expect(bloc.state.isLoading, isTrue);
      expect(bloc.state.items.length, 1);

      repository.completer!.complete();
      repository.completer = null;
      await pumpEventQueue();
    });

    test(
      'marca la procedencia local cuando el repositorio lo indica',
      () async {
        repository.response = Right(
          LogFetchResult(
            page: LogPage(items: [_log(1)], total: 1, page: 1, pageSize: 50),
            isOffline: true,
          ),
        );

        bloc.add(const LogsRequested());
        await pumpEventQueue();

        expect(bloc.state.isOffline, isTrue);
      },
    );
  });

  group('filtros y paginación (RF-27 a RF-32)', () {
    test('un filtro nuevo vuelve a la primera página', () async {
      bloc.add(const LogsRequested(page: 3));
      await pumpEventQueue();

      bloc.add(const LogFiltersChanged(LogFilters(outcome: 'failure')));
      await pumpEventQueue();

      expect(repository.lastFilters?.outcome, 'failure');
      expect(repository.lastPage, 1);
      expect(bloc.state.filters.outcome, 'failure');
      expect(bloc.state.page, 1);
    });

    test('limpiar filtros restablece la primera página sin filtros', () async {
      bloc.add(const LogsRequested(filters: LogFilters(petId: 2), page: 4));
      await pumpEventQueue();

      bloc.add(const LogFiltersCleared());
      await pumpEventQueue();

      expect(repository.lastFilters, LogFilters.empty);
      expect(repository.lastPage, 1);
      expect(bloc.state.filters.hasActiveFilters, isFalse);
    });

    test('pide la página indicada conservando los filtros', () async {
      bloc.add(
        const LogsRequested(filters: LogFilters(eventType: 'pet_created')),
      );
      await pumpEventQueue();

      bloc.add(const LogPageRequested(2));
      await pumpEventQueue();

      expect(repository.lastFilters?.eventType, 'pet_created');
      expect(repository.lastPage, 2);
      expect(bloc.state.page, 2);
    });

    test('no permite páginas menores que 1', () async {
      bloc.add(const LogPageRequested(0));
      await pumpEventQueue();

      expect(repository.lastPage, 1);
      expect(bloc.state.page, 1);
    });
  });

  group('error y reintento (RF-33)', () {
    test('conserva filtros y lista previa y expone el mensaje', () async {
      repository.response = Right(
        LogFetchResult(
          page: LogPage(
            items: [_log(1), _log(2)],
            total: 2,
            page: 1,
            pageSize: 50,
          ),
          isOffline: false,
        ),
      );
      bloc.add(const LogsRequested(filters: LogFilters(petId: 4)));
      await pumpEventQueue();

      repository.response = Left(ServerFailures('Servidor no disponible'));
      bloc.add(const LogRetryRequested());
      await pumpEventQueue();

      expect(bloc.state.errorMessage, 'Servidor no disponible');
      expect(bloc.state.items.length, 2);
      expect(bloc.state.filters.petId, 4);
      expect(bloc.state.isLoading, isFalse);
    });

    test(
      'el reintento vuelve a consultar con los mismos filtros y página',
      () async {
        repository.response = Left(ServerFailures('Servidor no disponible'));
        bloc.add(const LogsRequested(filters: LogFilters(petId: 4), page: 2));
        await pumpEventQueue();
        final llamadas = repository.calls;

        repository.response = Right(
          LogFetchResult(
            page: LogPage(items: [_log(3)], total: 1, page: 2, pageSize: 50),
            isOffline: false,
          ),
        );
        bloc.add(const LogRetryRequested());
        await pumpEventQueue();

        expect(repository.calls, llamadas + 1);
        expect(repository.lastFilters?.petId, 4);
        expect(repository.lastPage, 2);
        expect(bloc.state.errorMessage, isNull);
        expect(bloc.state.items.single.id, 3);
      },
    );
  });

  group('catálogo (RF-31, RF-41)', () {
    test('guarda los tipos y resultados del catálogo', () async {
      repository.catalogResponse = const Right(
        LogCatalog(
          eventTypes: [
            LogCatalogEntry(code: 'pet_created', label: 'Mascota creada'),
          ],
          outcomes: [LogCatalogEntry(code: 'success', label: 'Éxito')],
        ),
      );

      bloc.add(const LogCatalogRequested());
      await pumpEventQueue();

      expect(bloc.state.catalog.eventTypes.single.code, 'pet_created');
      expect(bloc.state.catalog.outcomes.single.label, 'Éxito');
    });

    test('un fallo del catálogo no marca la lista como error', () async {
      repository.catalogResponse = Left(ServerFailures('sin red'));

      bloc.add(const LogCatalogRequested());
      await pumpEventQueue();

      expect(bloc.state.catalog.eventTypes, isEmpty);
      expect(bloc.state.errorMessage, isNull);
    });
  });
}
