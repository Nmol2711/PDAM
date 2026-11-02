import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dashboard/data/datasources/dashboard_local_datasource.dart';
import 'package:app_movil_pdam/features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_pet_datasource.dart';
import 'package:dartz/dartz.dart';

/// Resumen del panel con estrategia offline-first (RF-7, RF-8, RF-12).
///
/// El servidor es la fuente de verdad y cada respuesta se cachea; si el
/// servidor no responde se devuelve la caché marcada como tal y, si no hay
/// caché utilizable, solo las mascotas y castradas locales con el resto en
/// cero. Nunca se multiplican horarios por una cantidad fija ni se arman
/// series simuladas.
class DashboardRepositoryImpl implements DashboardRepository {
  /// Texto fijo del fallo del resumen: no expone mensajes de excepción (RNF-1).
  static const String mensajeSinResumen =
      'No se pudo cargar el resumen del panel';

  static const List<double> _serieVacia = <double>[0, 0, 0, 0, 0, 0, 0];

  final DashboardRemoteDatasource _remoteDatasource;
  final DashboardLocalDatasource _localDatasource;
  final LocalPetDatasource _localPetDatasource;

  const DashboardRepositoryImpl({
    required DashboardRemoteDatasource remoteDatasource,
    required DashboardLocalDatasource localDatasource,
    required LocalPetDatasource localPetDatasource,
  }) : _remoteDatasource = remoteDatasource,
       _localDatasource = localDatasource,
       _localPetDatasource = localPetDatasource;

  @override
  Future<Either<Failures, DashboardSummary>> getDashboardSummary() async {
    try {
      final remoto = await _remoteDatasource.getDashboardSummary();
      // Guardar es de mejor esfuerzo: si Isar falla, el usuario igual ve los
      // datos frescos del servidor (RF-7).
      await _guardarCache(remoto);
      return Right(remoto.copyWith(isFromCache: false));
    } catch (_) {
      // El servidor no respondió: se intenta la caché del último resumen.
    }

    final cache = await _leerCache();
    if (cache != null) return Right(cache);

    try {
      return Right(await _resumenDesdeDatosLocales());
    } catch (_) {
      return Left(ServerFailures(mensajeSinResumen));
    }
  }

  /// Guarda el resumen remoto sin propagar el fallo de escritura.
  Future<void> _guardarCache(DashboardSummary resumen) async {
    try {
      await _localDatasource.guardar(resumen);
    } catch (_) {
      // La caché se reintenta en la siguiente respuesta correcta.
    }
  }

  /// Devuelve la caché si existe y es utilizable; nula en cualquier otro caso.
  Future<DashboardSummary?> _leerCache() async {
    try {
      final cache = await _localDatasource.leer();
      if (cache == null || !_esCacheUtilizable(cache)) return null;
      return cache.copyWith(isFromCache: true);
    } catch (_) {
      // Caché ilegible o corrupta: se trata como inexistente (RF-7).
      return null;
    }
  }

  /// Una caché incompleta no es un respaldo honesto: se descarta y se cae a
  /// los datos locales (RF-7, RF-12).
  bool _esCacheUtilizable(DashboardSummary cache) {
    if (cache.calculatedAt == null) return false;
    if (cache.todayIndex < 0 || cache.todayIndex > 6) return false;
    return cache.weeklyDispensed.length == 7;
  }

  /// Resumen sin conexión y sin caché: solo lo que el dispositivo sabe de sus
  /// mascotas, con el resto en cero (RF-7).
  Future<DashboardSummary> _resumenDesdeDatosLocales() async {
    final mascotas = await _localPetDatasource.getLocalPets();
    return DashboardSummary(
      totalPets: mascotas.length,
      sterilizedPets: mascotas.where((mascota) => mascota.reproductiveStatus).length,
      foodDispensedToday: 0,
      foodTargetToday: 0,
      pendingFeedings: 0,
      completedFeedings: 0,
      weeklyDispensed: _serieVacia,
      todayIndex: 0,
      calculatedAt: null,
    );
  }
}
