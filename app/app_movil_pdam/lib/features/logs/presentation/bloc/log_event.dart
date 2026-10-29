part of 'log_bloc.dart';

sealed class LogEvent {
  const LogEvent();
}

/// Carga una página concreta, normalmente la primera apertura de la pantalla.
class LogsRequested extends LogEvent {
  final LogFilters filters;
  final int page;

  const LogsRequested({this.filters = LogFilters.empty, this.page = 1});
}

class LogFiltersChanged extends LogEvent {
  final LogFilters filters;

  const LogFiltersChanged(this.filters);
}

class LogFiltersCleared extends LogEvent {
  const LogFiltersCleared();
}

class LogPageRequested extends LogEvent {
  final int page;

  const LogPageRequested(this.page);
}

class LogRetryRequested extends LogEvent {
  const LogRetryRequested();
}

class LogCatalogRequested extends LogEvent {
  const LogCatalogRequested();
}
