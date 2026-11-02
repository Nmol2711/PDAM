import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:isar/isar.dart';

/// Caché del último resumen del panel (RF-7, RF-8, RNF-3).
///
/// Solo persiste lo que el servidor devolvió: los siete campos del contrato,
/// `todayIndex`, el instante del cálculo y la fecha de escritura. No calcula
/// nada ni decide qué mostrar; eso corresponde al repositorio.
abstract class DashboardLocalDatasource {
  /// Sustituye el resumen cacheado por [resumen].
  ///
  /// Lanza si el resumen no trae instante de cálculo, porque sin él no hay
  /// medición del servidor que mostrar como respaldo (RF-7).
  Future<void> guardar(DashboardSummary resumen);

  /// Devuelve el último resumen cacheado o nulo si no existe la fila.
  ///
  /// El resultado se marca como proveniente de la caché; validar que sea
  /// utilizable es responsabilidad del repositorio.
  Future<DashboardSummary?> leer();
}

class DashboardLocalDatasourceImpl implements DashboardLocalDatasource {
  final String? testDirectory;

  DashboardLocalDatasourceImpl({this.testDirectory});

  Future<Isar> _getIsar() async {
    return await IsarService.init(directory: testDirectory);
  }

  @override
  Future<void> guardar(DashboardSummary resumen) async {
    final isar = await _getIsar();
    final calculado = resumen.calculatedAt;
    if (calculado == null) {
      throw StateError('El resumen sin instante de cálculo no se cachea');
    }

    await isar.writeTxn(() async {
      // Una sola fila por dispositivo: un resumen nuevo reemplaza al anterior.
      final fila = LocalDashboardSummary()
        ..clave = LocalDashboardSummary.claveUltimo
        ..totalPets = resumen.totalPets
        ..sterilizedPets = resumen.sterilizedPets
        ..foodDispensedToday = resumen.foodDispensedToday
        ..foodTargetToday = resumen.foodTargetToday
        ..pendingFeedings = resumen.pendingFeedings
        ..completedFeedings = resumen.completedFeedings
        ..weeklyDispensed = List<double>.from(resumen.weeklyDispensed)
        ..todayIndex = resumen.todayIndex
        ..calculatedAt = calculado.toUtc()
        ..cachedAt = DateTime.now().toUtc();
      await isar.localDashboardSummarys.put(fila);
    });
  }

  @override
  Future<DashboardSummary?> leer() async {
    final isar = await _getIsar();
    final fila = await isar.localDashboardSummarys
        .filter()
        .claveEqualTo(LocalDashboardSummary.claveUltimo)
        .findFirst();
    if (fila == null) return null;

    return DashboardSummary(
      totalPets: fila.totalPets,
      sterilizedPets: fila.sterilizedPets,
      foodDispensedToday: fila.foodDispensedToday,
      foodTargetToday: fila.foodTargetToday,
      pendingFeedings: fila.pendingFeedings,
      completedFeedings: fila.completedFeedings,
      weeklyDispensed: List<double>.unmodifiable(fila.weeklyDispensed),
      todayIndex: fila.todayIndex,
      calculatedAt: fila.calculatedAt?.toUtc(),
      isFromCache: true,
    );
  }
}
