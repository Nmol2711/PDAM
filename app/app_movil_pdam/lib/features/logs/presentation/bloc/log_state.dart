part of 'log_bloc.dart';

class LogState extends Equatable {
  final List<ActivityLog> items;
  final LogFilters filters;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool isLoading;

  /// Mensaje del error de consulta; la lista previa se conserva (RF-33).
  final String? errorMessage;

  /// Los datos mostrados vienen de la caché local (RF-34).
  final bool isOffline;
  final LogCatalog catalog;

  /// Ya se completó al menos una consulta, con o sin datos.
  final bool hasLoaded;

  const LogState({
    this.items = const <ActivityLog>[],
    this.filters = LogFilters.empty,
    this.page = 1,
    this.pageSize = 50,
    this.total = 0,
    this.totalPages = 1,
    this.isLoading = false,
    this.errorMessage,
    this.isOffline = false,
    this.catalog = const LogCatalog(),
    this.hasLoaded = false,
  });

  LogState copyWith({
    List<ActivityLog>? items,
    LogFilters? filters,
    int? page,
    int? pageSize,
    int? total,
    int? totalPages,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? isOffline,
    LogCatalog? catalog,
    bool? hasLoaded,
  }) {
    return LogState(
      items: items ?? this.items,
      filters: filters ?? this.filters,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      total: total ?? this.total,
      totalPages: totalPages ?? this.totalPages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isOffline: isOffline ?? this.isOffline,
      catalog: catalog ?? this.catalog,
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }

  @override
  List<Object?> get props => [
    items,
    filters,
    page,
    pageSize,
    total,
    totalPages,
    isLoading,
    errorMessage,
    isOffline,
    catalog,
    hasLoaded,
  ];
}
