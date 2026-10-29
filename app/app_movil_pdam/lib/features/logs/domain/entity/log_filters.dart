import 'package:app_movil_pdam/features/logs/domain/utils/log_time_utils.dart';
import 'package:equatable/equatable.dart';

/// Filtros combinables del historial (RF-27 a RF-31).
///
/// Las fechas son días del calendario local: la app las traduce a instantes
/// ISO 8601 con desplazamiento explícito antes de consultar (RF-30, RNF-4).
class LogFilters extends Equatable {
  final int? petId;
  final String? eventType;
  final String? outcome;

  /// Primer día del rango, en el calendario local del usuario.
  final DateTime? fromDate;

  /// Último día del rango, en el calendario local del usuario.
  final DateTime? toDate;

  const LogFilters({
    this.petId,
    this.eventType,
    this.outcome,
    this.fromDate,
    this.toDate,
  });

  static const LogFilters empty = LogFilters();

  bool get hasActiveFilters =>
      petId != null || eventType != null || outcome != null || hasDateRange;

  bool get hasDateRange => fromDate != null || toDate != null;

  /// Primer instante del rango, como hora de pared del calendario local.
  DateTime? get _desdePared =>
      fromDate == null ? null : DateTime(fromDate!.year, fromDate!.month, fromDate!.day);

  /// Último instante del rango, como hora de pared del calendario local.
  DateTime? get _hastaPared => toDate == null
      ? null
      : DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59, 999);

  /// Rango completo ya traducido cuando los dos extremos existen y están
  /// ordenados: `rangoDiaLocalAInstantes` resuelve el desplazamiento de cada
  /// extremo por su propio instante.
  RangoInstantes? get _rangoCompleto {
    final desde = fromDate;
    final hasta = toDate;
    if (desde == null || hasta == null || hasta.isBefore(desde)) return null;
    return rangoDiaLocalAInstantes(desde, hasta);
  }

  /// Límite inferior como instante con el desplazamiento de su propio instante.
  String? get fromIso {
    final rango = _rangoCompleto;
    if (rango != null) return rango.desde;
    final desde = _desdePared;
    return desde == null ? null : formatearInstanteConDesplazamiento(desde);
  }

  /// Límite superior como instante con el desplazamiento de su propio instante.
  ///
  /// El desplazamiento lo resuelve la hora de pared final y no la de medianoche:
  /// en un día con cambio de horario son distintos y el extremo quedaría
  /// desplazado una hora (RF-30).
  String? get toIso {
    final rango = _rangoCompleto;
    if (rango != null) return rango.hasta;
    final hasta = _hastaPared;
    return hasta == null ? null : formatearInstanteConDesplazamiento(hasta);
  }

  /// Instante UTC del inicio del rango, para filtrar la caché local.
  DateTime? get fromUtc {
    final rango = _rangoCompleto;
    if (rango != null) return rango.desdeUtc;
    final desde = _desdePared;
    return desde == null ? null : instanteUtcDeHoraDePared(desde);
  }

  /// Instante UTC del final del rango, para filtrar la caché local.
  DateTime? get toUtc {
    final rango = _rangoCompleto;
    if (rango != null) return rango.hastaUtc;
    final hasta = _hastaPared;
    return hasta == null ? null : instanteUtcDeHoraDePared(hasta);
  }

  LogFilters copyWith({
    int? petId,
    String? eventType,
    String? outcome,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearPetId = false,
    bool clearEventType = false,
    bool clearOutcome = false,
    bool clearDateRange = false,
  }) {
    return LogFilters(
      petId: clearPetId ? null : (petId ?? this.petId),
      eventType: clearEventType ? null : (eventType ?? this.eventType),
      outcome: clearOutcome ? null : (outcome ?? this.outcome),
      fromDate: clearDateRange ? null : (fromDate ?? this.fromDate),
      toDate: clearDateRange ? null : (toDate ?? this.toDate),
    );
  }

  @override
  List<Object?> get props => [petId, eventType, outcome, fromDate, toDate];
}
