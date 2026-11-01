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

/// Página de historial con su sobre completo, para las pruebas de refresco.
Either<Failures, LogFetchResult> _fetch({
  required int page,
  required int total,
  List<ActivityLog> items = const [],
  bool isOffline = false,
  int pageSize = 50,
}) {
  return Right(
    LogFetchResult(
      page: LogPage(
        items: items,
        total: total,
        page: page,
        pageSize: pageSize,
      ),
      isOffline: isOffline,
    ),
  );
}

class _FakeLogRepository implements LogRepositories {
  Either<Failures, LogFetchResult>? response;

  /// Respuesta específica por página; tiene prioridad sobre [response].
  Map<int, Either<Failures, LogFetchResult>> responsesPorPagina = {};

  /// Respuesta por número de llamada (1-based); tiene prioridad sobre el resto.
  List<Either<Failures, LogFetchResult>> respuestasPorLlamada = [];

  /// Completer por número de llamada, para terminar consultas en orden propio.
  List<Completer<void>> completersPorLlamada = [];
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
    final llamada = ++calls;
    lastFilters = filters;
    lastPage = page;
    lastPageSize = pageSize;
    final pendiente = llamada <= completersPorLlamada.length
        ? completersPorLlamada[llamada - 1]
        : completer;
    if (pendiente != null) {
      await pendiente.future;
    }
    if (llamada <= respuestasPorLlamada.length) {
      return respuestasPorLlamada[llamada - 1];
    }
    final porPagina = responsesPorPagina[page];
    if (porPagina != null) return porPagina;
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

  group('refresco (RF-1 a RF-6, CP-6 a CP-13)', () {
    late DateTime ahora;
    late LogBloc blocRefresco;

    setUp(() {
      ahora = DateTime.utc(2026, 10, 31, 12);
      blocRefresco = LogBloc(
        getLogsUc: GetLogsUc(repository: repository),
        getLogCatalogUc: GetLogCatalogUc(repository: repository),
        ahora: () => ahora,
        ventanaRefresco: const Duration(seconds: 4),
      );
    });

    tearDown(() async {
      await blocRefresco.close();
    });

    test(
      'CP-6: la carga inicial no se duplica al mostrarse la pestaña',
      () async {
        repository.response = _fetch(page: 1, total: 1, items: [_log(1)]);
        blocRefresco.add(const LogsRequested());
        await pumpEventQueue();
        expect(repository.calls, 1);

        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();

        expect(repository.calls, 1);
        expect(blocRefresco.state.items.single.id, 1);
        expect(blocRefresco.state.isLoading, isFalse);
        expect(blocRefresco.state.refresco, isNull);
      },
    );

    test(
      'CP-7: volver a la pestaña dentro de la ventana no encadena y la '
      'solicitud ignorada no mueve la marca',
      () async {
        blocRefresco.add(const LogsRequested());
        await pumpEventQueue();
        expect(repository.calls, 1);

        // 3,5 s desde el fin de la carga inicial: dentro de la ventana.
        ahora = ahora.add(const Duration(milliseconds: 3500));
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();
        expect(repository.calls, 1);

        // 4,5 s desde la carga inicial: fuera de la ventana. Solo se permite
        // si la solicitud ignorada no actualizó la marca.
        ahora = ahora.add(const Duration(seconds: 1));
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();

        expect(repository.calls, 2);
      },
    );

    test(
      'CP-8: un refresco manual dentro de la ventana se ejecuta y no la '
      'reinicia',
      () async {
        repository.response = _fetch(
          page: 1,
          total: 1,
          items: [_log(1)],
        );
        blocRefresco.add(const LogsRequested(filters: LogFilters(petId: 2)));
        await pumpEventQueue();
        expect(repository.calls, 1);

        ahora = ahora.add(const Duration(seconds: 1));
        blocRefresco.add(const LogRefreshRequested(LogRefreshOrigin.manual));
        await pumpEventQueue();

        expect(repository.calls, 2);
        expect(repository.lastFilters?.petId, 2);
        expect(repository.lastPage, 1);
        expect(blocRefresco.state.refresco, isNull);
        expect(blocRefresco.state.isLoading, isFalse);

        // 4 s desde la carga inicial: si el manual hubiera reiniciado la
        // ventana, este automático se ignoraría.
        ahora = ahora.add(const Duration(seconds: 3));
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();

        expect(repository.calls, 3);
        // El refresco no pide el catálogo de filtros.
        expect(repository.catalogCalls, 0);
      },
    );

    test(
      'CP-9: cambiar el filtro durante un refresco descarta el refresco',
      () async {
        repository.response = _fetch(page: 1, total: 1, items: [_log(1)]);
        blocRefresco.add(const LogsRequested(filters: LogFilters(petId: 1)));
        await pumpEventQueue();
        expect(repository.calls, 1);

        ahora = ahora.add(const Duration(seconds: 5));
        // La llamada 1 ya terminó; las 2 y 3 quedan pendientes por separado.
        repository.completersPorLlamada = [
          Completer<void>(),
          Completer<void>(),
          Completer<void>(),
        ];
        repository.respuestasPorLlamada = [
          _fetch(page: 1, total: 1, items: [_log(1)]),
          _fetch(page: 1, total: 1, items: [_log(9)]),
          _fetch(page: 1, total: 1, items: [_log(10)]),
        ];
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();
        expect(repository.calls, 2);
        expect(blocRefresco.state.isLoading, isTrue);
        expect(blocRefresco.state.refresco, LogRefreshOrigin.automatico);

        blocRefresco.add(const LogFiltersChanged(LogFilters(petId: 7)));
        await pumpEventQueue();
        expect(repository.calls, 3);
        expect(blocRefresco.state.isLoading, isTrue);
        expect(blocRefresco.state.refresco, isNull);
        expect(blocRefresco.state.filters.petId, 7);

        // La acción nueva termina primero.
        repository.completersPorLlamada[2].complete();
        await pumpEventQueue();
        expect(blocRefresco.state.items.single.id, 10);
        expect(blocRefresco.state.filters.petId, 7);

        // El refresco descartado termina después y no debe sobrescribir nada.
        repository.completersPorLlamada[1].complete();
        await pumpEventQueue();

        expect(blocRefresco.state.items.single.id, 10);
        expect(blocRefresco.state.filters.petId, 7);
        expect(blocRefresco.state.page, 1);
        expect(blocRefresco.state.isLoading, isFalse);
        expect(blocRefresco.state.refresco, isNull);
        expect(repository.calls, 3);
      },
    );

    test(
      'CP-9: cambiar de página durante un refresco descarta el refresco',
      () async {
        repository.response = _fetch(page: 1, total: 60, items: [_log(1)]);
        blocRefresco.add(const LogsRequested());
        await pumpEventQueue();

        ahora = ahora.add(const Duration(seconds: 5));
        repository.completersPorLlamada = [
          Completer<void>(),
          Completer<void>(),
          Completer<void>(),
        ];
        repository.respuestasPorLlamada = [
          _fetch(page: 1, total: 60, items: [_log(1)]),
          _fetch(page: 1, total: 60, items: [_log(9)]),
          _fetch(page: 2, total: 60, items: [_log(10)]),
        ];
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();
        expect(repository.calls, 2);

        blocRefresco.add(const LogPageRequested(2));
        await pumpEventQueue();
        expect(repository.calls, 3);

        // La acción nueva termina primero; el refresco descartado, después.
        repository.completersPorLlamada[2].complete();
        await pumpEventQueue();
        repository.completersPorLlamada[1].complete();
        await pumpEventQueue();

        expect(blocRefresco.state.page, 2);
        expect(blocRefresco.state.items.single.id, 10);
        expect(blocRefresco.state.isLoading, isFalse);
      },
    );

    test('RF-4: un refresco en curso descarta el siguiente', () async {
      repository.response = _fetch(page: 1, total: 1, items: [_log(1)]);
      blocRefresco.add(const LogsRequested());
      await pumpEventQueue();

      ahora = ahora.add(const Duration(seconds: 5));
      repository.completer = Completer<void>();
      blocRefresco.add(const LogRefreshRequested(LogRefreshOrigin.manual));
      await pumpEventQueue();
      expect(repository.calls, 2);

      // Fuera de la ventana, pero hay una consulta en curso.
      ahora = ahora.add(const Duration(seconds: 5));
      blocRefresco.add(
        const LogRefreshRequested(LogRefreshOrigin.automatico),
      );
      await pumpEventQueue();
      expect(repository.calls, 2);

      repository.completer!.complete();
      repository.completer = null;
      await pumpEventQueue();
      expect(blocRefresco.state.isLoading, isFalse);
      expect(repository.calls, 2);
    });

    test(
      'CP-10: una página conservada inexistente consulta una sola vez la '
      'última disponible',
      () async {
        repository.response = _fetch(
          page: 2,
          total: 60,
          items: [_log(1), _log(2)],
        );
        blocRefresco.add(const LogsRequested(page: 2));
        await pumpEventQueue();
        expect(blocRefresco.state.page, 2);
        expect(blocRefresco.state.totalPages, 2);

        ahora = ahora.add(const Duration(seconds: 5));
        repository.responsesPorPagina = {
          2: _fetch(page: 2, total: 10),
          1: _fetch(page: 1, total: 10, items: [_log(5)]),
        };
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();

        // Carga inicial + consulta de la página conservada + una sola extra.
        expect(repository.calls, 3);
        expect(blocRefresco.state.page, 1);
        expect(blocRefresco.state.items.single.id, 5);
        expect(blocRefresco.state.total, 10);
        expect(blocRefresco.state.isLoading, isFalse);
      },
    );

    test(
      'CP-11: si la consulta extra falla conserva página, lista y filtros con '
      'error y reintento',
      () async {
        repository.response = _fetch(
          page: 2,
          total: 60,
          items: [_log(1), _log(2)],
        );
        blocRefresco.add(
          const LogsRequested(filters: LogFilters(petId: 3), page: 2),
        );
        await pumpEventQueue();

        ahora = ahora.add(const Duration(seconds: 5));
        repository.responsesPorPagina = {
          2: _fetch(page: 2, total: 10),
          1: Left(ServerFailures('Servidor no disponible')),
        };
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();

        expect(repository.calls, 3);
        expect(blocRefresco.state.page, 2);
        expect(blocRefresco.state.items.length, 2);
        expect(blocRefresco.state.filters.petId, 3);
        expect(blocRefresco.state.errorMessage, 'Servidor no disponible');
        expect(blocRefresco.state.isOffline, isFalse);
        expect(blocRefresco.state.isLoading, isFalse);
        expect(blocRefresco.state.refresco, isNull);

        // El aviso de error permite reintentar con los datos conservados.
        repository.responsesPorPagina = {};
        repository.response = _fetch(
          page: 2,
          total: 60,
          items: [_log(4)],
        );
        blocRefresco.add(const LogRetryRequested());
        await pumpEventQueue();

        expect(repository.lastPage, 2);
        expect(repository.lastFilters?.petId, 3);
        expect(blocRefresco.state.items.single.id, 4);
        expect(blocRefresco.state.errorMessage, isNull);
      },
    );

    test(
      'CP-12: un fallo del refresco conserva la lista y muestra el error',
      () async {
        repository.response = _fetch(page: 1, total: 1, items: [_log(1)]);
        blocRefresco.add(const LogsRequested());
        await pumpEventQueue();

        ahora = ahora.add(const Duration(seconds: 5));
        repository.response = Left(ServerFailures('Servidor no disponible'));
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();

        expect(blocRefresco.state.errorMessage, 'Servidor no disponible');
        expect(blocRefresco.state.isOffline, isFalse);
        expect(blocRefresco.state.items.single.id, 1);

        // Un refresco posterior con éxito limpia el aviso de error.
        ahora = ahora.add(const Duration(seconds: 5));
        repository.response = _fetch(page: 1, total: 1, items: [_log(3)]);
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();

        expect(blocRefresco.state.errorMessage, isNull);
        expect(blocRefresco.state.items.single.id, 3);
      },
    );

    test(
      'CP-12: sin conexión muestra el aviso local y nunca el error de consulta',
      () async {
        repository.response = _fetch(
          page: 1,
          total: 1,
          items: [_log(1)],
          isOffline: true,
        );
        blocRefresco.add(const LogsRequested());
        await pumpEventQueue();
        expect(blocRefresco.state.isOffline, isTrue);

        ahora = ahora.add(const Duration(seconds: 5));
        repository.response = _fetch(
          page: 1,
          total: 1,
          items: [_log(2)],
          isOffline: true,
        );
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();

        expect(blocRefresco.state.isOffline, isTrue);
        expect(blocRefresco.state.errorMessage, isNull);
        expect(blocRefresco.state.items.single.id, 2);

        // Un fallo de consulta sustituye el aviso local por el de error.
        ahora = ahora.add(const Duration(seconds: 5));
        repository.response = Left(ServerFailures('Servidor no disponible'));
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();

        expect(blocRefresco.state.errorMessage, 'Servidor no disponible');
        expect(blocRefresco.state.isOffline, isFalse);
      },
    );

    test(
      'RF-6: un fallo de consulta sustituye el aviso local en cualquier carga',
      () async {
        repository.response = _fetch(
          page: 1,
          total: 1,
          items: [_log(1)],
          isOffline: true,
        );
        blocRefresco.add(const LogsRequested());
        await pumpEventQueue();
        expect(blocRefresco.state.isOffline, isTrue);

        // El reintento falla: el error sustituye al aviso de datos locales.
        repository.response = Left(ServerFailures('Servidor no disponible'));
        blocRefresco.add(const LogRetryRequested());
        await pumpEventQueue();

        expect(blocRefresco.state.errorMessage, 'Servidor no disponible');
        expect(blocRefresco.state.isOffline, isFalse);
      },
    );

    test(
      'CP-13: la ventana se mide desde el fin del refresco aunque dure más de '
      '4 s',
      () async {
        blocRefresco.add(const LogsRequested());
        await pumpEventQueue();
        expect(repository.calls, 1);

        ahora = ahora.add(const Duration(seconds: 10));
        repository.completer = Completer<void>();
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();
        expect(repository.calls, 2);

        // La consulta tarda 10 s: el fin del refresco es 20 s después del
        // inicio de la prueba.
        ahora = ahora.add(const Duration(seconds: 10));
        repository.completer!.complete();
        repository.completer = null;
        await pumpEventQueue();
        expect(blocRefresco.state.isLoading, isFalse);

        // 2 s desde el fin: dentro de la ventana.
        ahora = ahora.add(const Duration(seconds: 2));
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();
        expect(repository.calls, 2);

        // 4 s desde el fin: la ventana ya se cumplió.
        ahora = ahora.add(const Duration(seconds: 2));
        blocRefresco.add(
          const LogRefreshRequested(LogRefreshOrigin.automatico),
        );
        await pumpEventQueue();
        expect(repository.calls, 3);
      },
    );
  });
}
