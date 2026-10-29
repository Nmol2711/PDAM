import 'package:isar/isar.dart';

part 'local_log.g.dart';

/// Caché local de los registros del historial (RF-34, RF-35).
///
/// Guarda los códigos **y** las etiquetas de tipo, resultado y causa, de modo
/// que los filtros funcionan sin conexión y la interfaz no duplica el catálogo.
@collection
class LocalLog {
  Id id = Isar.autoIncrement;

  /// Identificador del servidor; es la clave del upsert y evita duplicados.
  @Index(unique: true)
  int? remoteId;

  late String userId;

  @Index()
  int? petRemoteId;

  /// Fecha y hora del servidor en UTC (RNF-8).
  @Index()
  late DateTime timestamp;

  @Index()
  String? eventType;
  String? eventLabel;

  @Index()
  String? outcome;
  String? outcomeLabel;

  String? cause;
  String? causeLabel;

  String description = '';
  String? petName;
  String? dispenserMacMasked;
  int? orderId;
  double? requestedGrams;
  double? measuredGrams;
  double? discountedGrams;
  double? resultingStock;
  int? retryCount;

  /// Contexto del evento serializado como objeto JSON.
  String? contextJson;

  late bool isSynced;
}
