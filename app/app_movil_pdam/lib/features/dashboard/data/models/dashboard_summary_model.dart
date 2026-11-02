import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';

/// Texto fijo del error de formato. No expone datos de la respuesta ni
/// mensajes de excepción (RNF-1).
const String _mensajeContratoInvalido = 'Respuesta del resumen inválida';

/// Modelo de transferencia del resumen del panel (contrato de RF-6).
///
/// `fromJson` exige `today_index` y `calculated_at`: sin ellos no hay posición
/// de hoy ni instante del servidor, y la app no los suple con el reloj del
/// dispositivo (RF-6). `calculatedAt` solo queda nulo si se construye a mano el
/// resumen local sin caché. `weekly_dispensed` debe traer exactamente siete
/// posiciones. Los siete campos numéricos clásicos ausentes valen 0; nunca se
/// rellena la meta con 300 ni con otra estimación (RF-12).
class DashboardSummaryModel extends DashboardSummary {
  const DashboardSummaryModel({
    required super.totalPets,
    required super.sterilizedPets,
    required super.foodDispensedToday,
    required super.foodTargetToday,
    required super.pendingFeedings,
    required super.completedFeedings,
    required super.weeklyDispensed,
    required super.todayIndex,
    super.calculatedAt,
    super.isFromCache,
  });

  factory DashboardSummaryModel.fromJson(Map<String, dynamic> json) {
    return DashboardSummaryModel(
      totalPets: _entero(json['total_pets']),
      sterilizedPets: _entero(json['sterilized_pets']),
      foodDispensedToday: _decimal(json['food_dispensed_today']),
      foodTargetToday: _decimal(json['food_target_today']),
      pendingFeedings: _entero(json['pending_feedings']),
      completedFeedings: _entero(json['completed_feedings']),
      weeklyDispensed: _serieSemanal(json['weekly_dispensed']),
      todayIndex: _indiceHoy(json['today_index']),
      calculatedAt: _instante(json['calculated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_pets': totalPets,
      'sterilized_pets': sterilizedPets,
      'food_dispensed_today': foodDispensedToday,
      'food_target_today': foodTargetToday,
      'pending_feedings': pendingFeedings,
      'completed_feedings': completedFeedings,
      'weekly_dispensed': weeklyDispensed,
      'today_index': todayIndex,
      // El resumen local sin caché no tiene instante del servidor: la clave se
      // omite en vez de serializar `null`, porque el contrato exige texto ISO
      // 8601 con zona (RF-6).
      if (calculatedAt != null)
        'calculated_at': calculatedAt!.toUtc().toIso8601String(),
    };
  }
}

/// Campo numérico ausente o desconocido: 0 (RF-12).
int _entero(Object? valor) => valor is num ? valor.toInt() : 0;

/// Campo decimal ausente o desconocido: 0 (RF-12).
double _decimal(Object? valor) => valor is num ? valor.toDouble() : 0;

/// Serie semanal de exactamente siete posiciones; ausente equivale a siete
/// ceros. Una longitud distinta o un valor no numérico rompe el contrato.
List<double> _serieSemanal(Object? valor) {
  if (valor == null) {
    return const <double>[0, 0, 0, 0, 0, 0, 0];
  }
  if (valor is! List || valor.length != 7) {
    throw const FormatException(_mensajeContratoInvalido);
  }

  final serie = <double>[];
  for (final elemento in valor) {
    if (elemento is! num) {
      throw const FormatException(_mensajeContratoInvalido);
    }
    serie.add(elemento.toDouble());
  }
  return List<double>.unmodifiable(serie);
}

/// Posición de hoy en la serie: entero de 0 (lunes) a 6 (domingo).
int _indiceHoy(Object? valor) {
  if (valor is! int || valor < 0 || valor > 6) {
    throw const FormatException(_mensajeContratoInvalido);
  }
  return valor;
}

/// Indica que el texto ISO 8601 ancla la zona con `Z` o con un desplazamiento
/// `±HH:MM` o `±HHMM`. Sin anclaje, `DateTime.tryParse` usaría la zona del
/// dispositivo y el instante dejaría de ser el del servidor (RF-6, RF-11).
final RegExp _zonaExplicita = RegExp(r'(?:[Zz]|[+-]\d{2}:?\d{2})$');

/// Instante del cálculo: ISO 8601 con `Z`, desplazamiento y microsegundos
/// opcionales, normalizado a UTC.
DateTime _instante(Object? valor) {
  if (valor is! String || !_zonaExplicita.hasMatch(valor)) {
    throw const FormatException(_mensajeContratoInvalido);
  }
  final instante = DateTime.tryParse(valor);
  if (instante == null) {
    throw const FormatException(_mensajeContratoInvalido);
  }
  return instante.toUtc();
}
