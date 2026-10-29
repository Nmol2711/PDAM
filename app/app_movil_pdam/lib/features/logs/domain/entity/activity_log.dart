import 'package:app_movil_pdam/features/logs/domain/utils/log_pagination_utils.dart';
import 'package:equatable/equatable.dart';

/// Registro de actividad tal como lo devuelve la consulta del historial.
///
/// Los registros históricos anteriores a la spec 014 llegan sin tipo, resultado
/// ni causa; su etiqueta de presentación es «Sin clasificar» (RF-41).
class ActivityLog extends Equatable {
  final int id;

  /// Instante del servidor en UTC (RNF-8).
  final DateTime createdAt;

  final String? eventType;
  final String? eventLabel;
  final String? outcome;
  final String? outcomeLabel;
  final String? cause;
  final String? causeLabel;
  final String description;
  final int? petId;
  final String? petName;
  final String? dispenserMacMasked;
  final int? orderId;
  final double? requestedGrams;
  final double? measuredGrams;
  final double? discountedGrams;
  final double? resultingStock;
  final int? retryCount;
  final Map<String, dynamic> context;

  const ActivityLog({
    required this.id,
    required this.createdAt,
    this.eventType,
    this.eventLabel,
    this.outcome,
    this.outcomeLabel,
    this.cause,
    this.causeLabel,
    this.description = '',
    this.petId,
    this.petName,
    this.dispenserMacMasked,
    this.orderId,
    this.requestedGrams,
    this.measuredGrams,
    this.discountedGrams,
    this.resultingStock,
    this.retryCount,
    this.context = const <String, dynamic>{},
  });

  /// Etiqueta visible del evento; los históricos sin clasificación no son un
  /// tipo del catálogo (RF-41).
  String get etiquetaEvento {
    final etiqueta = eventLabel;
    if (etiqueta == null || etiqueta.isEmpty) return 'Sin clasificar';
    return etiqueta;
  }

  /// Solo los dispensados muestran gramos (RF-33).
  bool get esDispensado => eventType == 'feeding_dispensed';

  @override
  List<Object?> get props => [
    id,
    createdAt,
    eventType,
    eventLabel,
    outcome,
    outcomeLabel,
    cause,
    causeLabel,
    description,
    petId,
    petName,
    dispenserMacMasked,
    orderId,
    requestedGrams,
    measuredGrams,
    discountedGrams,
    resultingStock,
    retryCount,
    context,
  ];
}

/// Página del historial con el sobre `{items,total,page,page_size}` (RF-32).
class LogPage extends Equatable {
  final List<ActivityLog> items;
  final int total;
  final int page;
  final int pageSize;

  const LogPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  int get totalPages => calcularTotalPaginas(total, pageSize);

  @override
  List<Object?> get props => [items, total, page, pageSize];
}

/// Resultado de una consulta: la página y si salió de la caché local (RF-34).
class LogFetchResult extends Equatable {
  final LogPage page;
  final bool isOffline;

  const LogFetchResult({required this.page, required this.isOffline});

  @override
  List<Object?> get props => [page, isOffline];
}

/// Entrada del catálogo cerrado de tipos de evento o de resultados (RF-31).
class LogCatalogEntry extends Equatable {
  final String code;
  final String label;

  const LogCatalogEntry({required this.code, required this.label});

  @override
  List<Object?> get props => [code, label];
}

/// Catálogo de tipos de evento y resultados que puebla los filtros.
///
/// No incluye causas: se muestran desde la etiqueta de cada ítem. Tampoco
/// incluye «Sin clasificar», que no es filtrable (RF-41).
class LogCatalog extends Equatable {
  final List<LogCatalogEntry> eventTypes;
  final List<LogCatalogEntry> outcomes;

  const LogCatalog({
    this.eventTypes = const <LogCatalogEntry>[],
    this.outcomes = const <LogCatalogEntry>[],
  });

  bool get isEmpty => eventTypes.isEmpty && outcomes.isEmpty;

  String? labelForEventType(String? code) => _label(eventTypes, code);

  String? labelForOutcome(String? code) => _label(outcomes, code);

  String? _label(List<LogCatalogEntry> entries, String? code) {
    if (code == null) return null;
    for (final entry in entries) {
      if (entry.code == code) return entry.label;
    }
    return null;
  }

  @override
  List<Object?> get props => [eventTypes, outcomes];
}
