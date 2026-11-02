import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_log_catalog_uc.dart';
import 'package:app_movil_pdam/features/logs/domain/use_case/get_logs_uc.dart';
import 'package:app_movil_pdam/features/logs/domain/utils/log_refresh_utils.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'log_event.dart';
part 'log_state.dart';

/// Estado del historial: filtros, página, totales y avisos (RF-33, RF-34).
///
/// También decide los refrescos manuales y automáticos (spec 019): ventana de
/// 4 s, concurrencia, ajuste de página y error frente a sin conexión.
class LogBloc extends Bloc<LogEvent, LogState> {
  /// Mismo tamaño de página por defecto que el servidor (RF-32).
  static const int tamanoPagina = 50;

  /// Separación mínima entre refrescos automáticos (RF-3).
  static const Duration ventanaRefrescoPorDefecto = Duration(seconds: 4);

  final GetLogsUc _getLogsUc;
  final GetLogCatalogUc _getLogCatalogUc;

  /// Reloj inyectable: las pruebas usan un instante mutable (RNF-2).
  final DateTime Function() _ahora;

  /// Ventana mínima entre refrescos automáticos (RF-3).
  final Duration _ventanaRefresco;

  /// Fin del último refresco automático o de la carga inicial (RF-3).
  DateTime? _ultimoFinAutomatico;

  /// Generación vigente: los resultados de una anterior se descartan (RF-4).
  int _generacion = 0;

  /// Hay un refresco pendiente de respuesta; se atiende una consulta a la vez.
  bool _refrescoEnCurso = false;

  LogBloc({
    required GetLogsUc getLogsUc,
    required GetLogCatalogUc getLogCatalogUc,
    DateTime Function()? ahora,
    Duration ventanaRefresco = ventanaRefrescoPorDefecto,
  }) : _getLogsUc = getLogsUc,
       _getLogCatalogUc = getLogCatalogUc,
       _ahora = ahora ?? DateTime.now,
       _ventanaRefresco = ventanaRefresco,
       super(const LogState()) {
    on<LogsRequested>(_onLogsRequested);
    on<LogFiltersChanged>(_onLogFiltersChanged);
    on<LogFiltersCleared>(_onLogFiltersCleared);
    on<LogPageRequested>(_onLogPageRequested);
    on<LogRetryRequested>(_onLogRetryRequested);
    on<LogCatalogRequested>(_onLogCatalogRequested);
    on<LogRefreshRequested>(_onLogRefreshRequested);
  }

  /// Hay un refresco pendiente de respuesta.
  ///
  /// Puede seguir siendo cierto aunque `state.refresco` ya sea `null`, porque
  /// una carga de filtro o página tomó el relevo (RF-4).
  bool get refrescoEnCurso => _refrescoEnCurso;

  Future<void> _onLogsRequested(
    LogsRequested event,
    Emitter<LogState> emit,
  ) async {
    // La primera carga cuenta como el último refresco automático (RF-3).
    await _cargar(
      emit,
      filters: event.filters,
      page: event.page,
      marcarFinAutomatico: !state.hasLoaded,
    );
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

  /// Refresco manual o automático sin vaciar la lista (RF-1, RF-2).
  Future<void> _onLogRefreshRequested(
    LogRefreshRequested event,
    Emitter<LogState> emit,
  ) async {
    // Una sola consulta a la vez: el refresco se descarta (RF-4).
    if (_refrescoEnCurso) return;

    // Dentro de la ventana no se refresca ni se mueve la marca (RF-3, RF-4).
    if (event.origin == LogRefreshOrigin.automatico &&
        !puedeRefrescarAutomatico(
          _ultimoFinAutomatico,
          _ahora(),
          _ventanaRefresco,
        )) {
      return;
    }

    // Instantánea para conservar filtros, página y lista si algo falla (RF-6).
    final instantanea = _InstantaneaLog(
      items: state.items,
      filters: state.filters,
      page: state.page,
      pageSize: state.pageSize,
      total: state.total,
      totalPages: state.totalPages,
      hasLoaded: state.hasLoaded,
    );

    _refrescoEnCurso = true;
    final generacion = ++_generacion;
    emit(
      state.copyWith(
        isLoading: true,
        clearError: true,
        refresco: event.origin,
      ),
    );

    try {
      final resultado = await _getLogsUc(
        filters: instantanea.filters,
        page: instantanea.page,
        pageSize: tamanoPagina,
      );
      // Otra acción (filtro, página o reintento) tomó el relevo (RF-4).
      if (generacion != _generacion) return;

      LogFetchResult? fetch;
      String? error;
      resultado.fold(
        (failure) => error = failure.message,
        (exito) => fetch = exito,
      );

      if (fetch != null) {
        final ajustada = ajustarPagina(fetch!.page.page, fetch!.page.totalPages);
        if (ajustada == fetch!.page.page) {
          _emitirPagina(
            emit,
            fetch!.page,
            instantanea,
            isOffline: fetch!.isOffline,
          );
        } else {
          // Como máximo una consulta extra a la última página disponible
          // (RF-5), dentro del mismo refresco y de la misma generación.
          final extra = await _getLogsUc(
            filters: instantanea.filters,
            page: ajustada,
            pageSize: tamanoPagina,
          );
          if (generacion != _generacion) return;

          LogFetchResult? fetchExtra;
          String? errorExtra;
          extra.fold(
            (failure) => errorExtra = failure.message,
            (exito) => fetchExtra = exito,
          );
          if (fetchExtra != null) {
            _emitirPagina(
              emit,
              fetchExtra!.page,
              instantanea,
              isOffline: fetchExtra!.isOffline,
            );
          } else {
            _emitirFallo(emit, errorExtra!, instantanea);
          }
        }
      } else {
        _emitirFallo(emit, error!, instantanea);
      }
    } finally {
      _refrescoEnCurso = false;
      // La ventana se mide desde el fin, no desde el inicio (RF-3, CP-13).
      if (generacion == _generacion &&
          event.origin == LogRefreshOrigin.automatico) {
        _ultimoFinAutomatico = _ahora();
      }
    }
  }

  void _emitirPagina(
    Emitter<LogState> emit,
    LogPage page,
    _InstantaneaLog instantanea, {
    required bool isOffline,
  }) {
    emit(
      state.copyWith(
        items: page.items,
        filters: instantanea.filters,
        page: page.page,
        pageSize: page.pageSize,
        total: page.total,
        totalPages: page.totalPages,
        isLoading: false,
        clearError: true,
        isOffline: isOffline,
        hasLoaded: true,
        clearRefresco: true,
      ),
    );
  }

  /// Fallo del refresco: conserva lista, filtros y página y muestra el error
  /// con reintento, nunca junto al aviso de sin conexión (RF-6).
  void _emitirFallo(
    Emitter<LogState> emit,
    String mensaje,
    _InstantaneaLog instantanea,
  ) {
    emit(
      state.copyWith(
        items: instantanea.items,
        filters: instantanea.filters,
        page: instantanea.page,
        pageSize: instantanea.pageSize,
        total: instantanea.total,
        totalPages: instantanea.totalPages,
        isLoading: false,
        errorMessage: mensaje,
        isOffline: false,
        hasLoaded: instantanea.hasLoaded,
        clearRefresco: true,
      ),
    );
  }

  Future<void> _cargar(
    Emitter<LogState> emit, {
    required LogFilters filters,
    required int page,
    bool marcarFinAutomatico = false,
  }) async {
    // Toda carga invalida los resultados de la generación anterior (RF-4).
    final generacion = ++_generacion;
    // `isLoading` es una bandera: la lista anterior sigue visible (RF-34).
    emit(
      state.copyWith(
        filters: filters,
        page: page,
        isLoading: true,
        clearError: true,
        clearRefresco: true,
      ),
    );

    final resultado = await _getLogsUc(
      filters: filters,
      page: page,
      pageSize: tamanoPagina,
    );

    // Un resultado obsoleto no se emite ni mueve la marca (RF-4).
    if (generacion != _generacion) return;

    resultado.fold(
      (failure) => emit(
        state.copyWith(
          filters: filters,
          page: page,
          isLoading: false,
          errorMessage: failure.message,
          // El error de consulta sustituye al aviso de sin conexión (RF-6).
          isOffline: false,
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

    if (marcarFinAutomatico) _ultimoFinAutomatico = _ahora();
  }
}

/// Datos previos al refresco que se restauran si la consulta falla.
class _InstantaneaLog {
  final List<ActivityLog> items;
  final LogFilters filters;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasLoaded;

  const _InstantaneaLog({
    required this.items,
    required this.filters,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.hasLoaded,
  });
}
