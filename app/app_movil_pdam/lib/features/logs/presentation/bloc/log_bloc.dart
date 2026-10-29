import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_log_catalog_uc.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_logs_uc.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'log_event.dart';
part 'log_state.dart';

/// Estado del historial: filtros, página, totales y avisos (RF-33, RF-34).
class LogBloc extends Bloc<LogEvent, LogState> {
  /// Mismo tamaño de página por defecto que el servidor (RF-32).
  static const int tamanoPagina = 50;

  final GetLogsUc _getLogsUc;
  final GetLogCatalogUc _getLogCatalogUc;

  LogBloc({
    required GetLogsUc getLogsUc,
    required GetLogCatalogUc getLogCatalogUc,
  }) : _getLogsUc = getLogsUc,
       _getLogCatalogUc = getLogCatalogUc,
       super(const LogState()) {
    on<LogsRequested>(_onLogsRequested);
    on<LogFiltersChanged>(_onLogFiltersChanged);
    on<LogFiltersCleared>(_onLogFiltersCleared);
    on<LogPageRequested>(_onLogPageRequested);
    on<LogRetryRequested>(_onLogRetryRequested);
    on<LogCatalogRequested>(_onLogCatalogRequested);
  }

  Future<void> _onLogsRequested(
    LogsRequested event,
    Emitter<LogState> emit,
  ) async {
    await _cargar(emit, filters: event.filters, page: event.page);
  }

  Future<void> _onLogFiltersChanged(
    LogFiltersChanged event,
    Emitter<LogState> emit,
  ) async {
    // Un filtro nuevo siempre vuelve a la primera página (RF-33).
    await _cargar(emit, filters: event.filters, page: 1);
  }

  Future<void> _onLogFiltersCleared(
    LogFiltersCleared event,
    Emitter<LogState> emit,
  ) async {
    await _cargar(emit, filters: LogFilters.empty, page: 1);
  }

  Future<void> _onLogPageRequested(
    LogPageRequested event,
    Emitter<LogState> emit,
  ) async {
    await _cargar(
      emit,
      filters: state.filters,
      page: event.page < 1 ? 1 : event.page,
    );
  }

  Future<void> _onLogRetryRequested(
    LogRetryRequested event,
    Emitter<LogState> emit,
  ) async {
    // El reintento conserva los filtros aplicados (RF-33).
    await _cargar(emit, filters: state.filters, page: state.page);
  }

  Future<void> _onLogCatalogRequested(
    LogCatalogRequested event,
    Emitter<LogState> emit,
  ) async {
    final resultado = await _getLogCatalogUc();
    resultado.fold(
      // Un catálogo vacío no debe impedir ver el historial.
      (_) {},
      (catalogo) => emit(state.copyWith(catalog: catalogo)),
    );
  }

  Future<void> _cargar(
    Emitter<LogState> emit, {
    required LogFilters filters,
    required int page,
  }) async {
    // `isLoading` es una bandera: la lista anterior sigue visible (RF-34).
    emit(
      state.copyWith(
        filters: filters,
        page: page,
        isLoading: true,
        clearError: true,
      ),
    );

    final resultado = await _getLogsUc(
      filters: filters,
      page: page,
      pageSize: tamanoPagina,
    );

    resultado.fold(
      (failure) => emit(
        state.copyWith(
          filters: filters,
          page: page,
          isLoading: false,
          errorMessage: failure.message,
        ),
      ),
      (fetch) => emit(
        state.copyWith(
          items: fetch.page.items,
          filters: filters,
          page: fetch.page.page,
          pageSize: fetch.page.pageSize,
          total: fetch.page.total,
          totalPages: fetch.page.totalPages,
          isLoading: false,
          clearError: true,
          isOffline: fetch.isOffline,
          hasLoaded: true,
        ),
      ),
    );
  }
}
