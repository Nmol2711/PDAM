import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';

/// Modelo de transferencia del historial (contrato de §5.3 del plan).
class ActivityLogModel extends ActivityLog {
  const ActivityLogModel({
    required super.id,
    required super.createdAt,
    super.eventType,
    super.eventLabel,
    super.outcome,
    super.outcomeLabel,
    super.cause,
    super.causeLabel,
    super.description,
    super.petId,
    super.petName,
    super.dispenserMacMasked,
    super.orderId,
    super.requestedGrams,
    super.measuredGrams,
    super.discountedGrams,
    super.resultingStock,
    super.retryCount,
    super.context,
  });

  factory ActivityLogModel.fromJson(Map<String, dynamic> json) {
    return ActivityLogModel(
      id: _entero(json['id']) ?? 0,
      createdAt:
          _instante(json['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      eventType: _texto(json['event_type']),
      eventLabel: _texto(json['event_label']),
      outcome: _texto(json['outcome']),
      outcomeLabel: _texto(json['outcome_label']),
      cause: _texto(json['cause']),
      causeLabel: _texto(json['cause_label']),
      description: _texto(json['description']) ?? '',
      petId: _entero(json['pet_id']),
      petName: _texto(json['pet_name']),
      dispenserMacMasked: _texto(json['dispenser_mac_masked']),
      orderId: _entero(json['order_id']),
      requestedGrams: _decimal(json['requested_grams']),
      measuredGrams: _decimal(json['measured_grams']),
      discountedGrams: _decimal(json['discounted_grams']),
      resultingStock: _decimal(json['resulting_stock']),
      retryCount: _entero(json['retry_count']),
      context: _contexto(json['context']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toUtc().toIso8601String(),
      'event_type': eventType,
      'event_label': eventLabel,
      'outcome': outcome,
      'outcome_label': outcomeLabel,
      'cause': cause,
      'cause_label': causeLabel,
      'description': description,
      'pet_id': petId,
      'pet_name': petName,
      'dispenser_mac_masked': dispenserMacMasked,
      'order_id': orderId,
      'requested_grams': requestedGrams,
      'measured_grams': measuredGrams,
      'discounted_grams': discountedGrams,
      'resulting_stock': resultingStock,
      'retry_count': retryCount,
      'context': context,
    };
  }
}

/// Sobre paginado de la consulta del historial (RF-32).
class LogPageModel extends LogPage {
  const LogPageModel({
    required super.items,
    required super.total,
    required super.page,
    required super.pageSize,
  });

  factory LogPageModel.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ActivityLogModel.fromJson)
        .toList(growable: false);

    return LogPageModel(
      items: items,
      total: _entero(json['total']) ?? 0,
      page: _entero(json['page']) ?? 1,
      pageSize: _entero(json['page_size']) ?? 50,
    );
  }
}

/// Catálogo cerrado de tipos de evento y resultados (§5.4 del plan).
class LogCatalogModel extends LogCatalog {
  const LogCatalogModel({super.eventTypes, super.outcomes});

  factory LogCatalogModel.fromJson(Map<String, dynamic> json) {
    return LogCatalogModel(
      eventTypes: _entradas(json['event_types']),
      outcomes: _entradas(json['outcomes']),
    );
  }
}

List<LogCatalogEntry> _entradas(Object? valor) {
  if (valor is! List) return const <LogCatalogEntry>[];
  return valor
      .whereType<Map<String, dynamic>>()
      .map(
        (entrada) => LogCatalogEntry(
          code: _texto(entrada['code']) ?? '',
          label: _texto(entrada['label']) ?? '',
        ),
      )
      .toList(growable: false);
}

String? _texto(Object? valor) {
  if (valor == null) return null;
  final texto = valor.toString();
  return texto.isEmpty ? null : texto;
}

int? _entero(Object? valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  if (valor is String) return int.tryParse(valor);
  return null;
}

double? _decimal(Object? valor) {
  if (valor is double) return valor;
  if (valor is num) return valor.toDouble();
  if (valor is String) return double.tryParse(valor);
  return null;
}

DateTime? _instante(Object? valor) {
  if (valor is String && valor.isNotEmpty) {
    final instante = DateTime.tryParse(valor);
    return instante?.toUtc();
  }
  return null;
}

Map<String, dynamic> _contexto(Object? valor) {
  if (valor is Map) return Map<String, dynamic>.from(valor);
  return const <String, dynamic>{};
}
