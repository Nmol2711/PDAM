import 'package:isar/isar.dart';

part 'local_dashboard_summary.g.dart';

/// Último resumen del panel recibido del servidor (RF-7, RF-8, RNF-3).
///
/// Guarda una sola fila identificada por [claveUltimo]: la caché conserva el
/// último resumen y no un histórico. Solo contiene cifras y fechas que el
/// servidor ya devolvió; no guarda datos de la cuenta ni credenciales.
@collection
class LocalDashboardSummary {
  /// Clave fija del único resumen cacheado en el dispositivo.
  static const String claveUltimo = 'ultimo';

  Id id = Isar.autoIncrement;

  /// Identificador de la fila vigente; siempre [claveUltimo].
  @Index(unique: true, replace: true)
  late String clave;

  late int totalPets;
  late int sterilizedPets;
  late double foodDispensedToday;
  late double foodTargetToday;
  late int pendingFeedings;
  late int completedFeedings;
  late List<double> weeklyDispensed;

  /// Posición de hoy en la serie semanal (0 lunes a 6 domingo).
  late int todayIndex;

  /// Instante del cálculo informado por el servidor. Nulo solo si la fila
  /// quedó incompleta; el repositorio descarta la caché en ese caso.
  DateTime? calculatedAt;

  /// Momento en que se escribió la fila en el dispositivo.
  late DateTime cachedAt;
}
