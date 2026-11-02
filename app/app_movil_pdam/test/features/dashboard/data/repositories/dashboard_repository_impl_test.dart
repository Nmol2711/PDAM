import 'dart:io';

import 'package:app_movil_pdam/core/constant/app_aplicacion.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/data/datasources/dashboard_local_datasource.dart';
import 'package:app_movil_pdam/features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import 'package:app_movil_pdam/features/dashboard/data/models/dashboard_summary_model.dart';
import 'package:app_movil_pdam/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/pets/data/datasource/local/local_pet_datasource.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/pet.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

/// Pruebas de la estrategia offline-first del resumen (RF-7, RF-8, RF-12).
///
/// El servidor es la fuente de verdad y cada respuesta se cachea; si el
/// servidor falla se responde con la caché y, si no hay caché utilizable, solo
/// con las mascotas y castradas locales y ceros. Ningún camino inventa cifras
/// ni propaga textos de excepción (RNF-1).
void main() {
  late Directory tempDir;
  late DashboardLocalDatasourceImpl cache;
  late LocalPetDatasourceImpl mascotas;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(download: true);
      final warmupDir = await Directory.systemTemp.createTemp('isar_warmup_');
      await IsarService.init(directory: warmupDir.path);
      await IsarService.close();
      await warmupDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_dashboard_');
    cache = DashboardLocalDatasourceImpl(testDirectory: tempDir.path);
    mascotas = LocalPetDatasourceImpl(testDirectory: tempDir.path);
  });

  tearDown(() async {
    try {
      await IsarService.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DashboardRepositoryImpl repositorio({
    required DashboardRemoteDatasource remoto,
    DashboardLocalDatasource? cacheLocal,
    LocalPetDatasource? mascotasLocales,
  }) {
    return DashboardRepositoryImpl(
      remoteDatasource: remoto,
      localDatasource: cacheLocal ?? cache,
      localPetDatasource: mascotasLocales ?? mascotas,
    );
  }

  Future<void> sembrarMascotas(List<bool> castradas) async {
    var id = 1;
    for (final castrada in castradas) {
      await mascotas.saveLocalPet(
        Pet(
          id: id,
          name: 'Mascota $id',
          species: TypePest.canino,
          birthDate: DateTime(2020, 1, 1),
          weight: 10,
          reproductiveStatus: castrada,
        ),
      );
      id += 1;
    }
  }

  group('Remoto disponible', () {
    test('devuelve el resumen del servidor y lo guarda en la caché', () async {
      final remoto = _RemotoFalso(respuesta: resumenRemoto());

      final resultado = await repositorio(remoto: remoto).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.isFromCache, isFalse);
      expect(resumen, esperado(resumenRemoto()));

      final guardado = await cache.leer();
      expect(guardado, isNotNull);
      expect(guardado!.isFromCache, isTrue);
      expect(guardado, esperado(resumenRemoto(), isFromCache: true));
      expect(guardado.calculatedAt, DateTime.utc(2026, 10, 1, 17));
    });

    test('la caché conserva una sola fila con la clave fija ultimo', () async {
      await repositorio(
        remoto: _RemotoFalso(respuesta: resumenRemoto()),
      ).getDashboardSummary();

      final segundo = resumenRemoto(
        totalPets: 4,
        calculatedAt: DateTime.utc(2026, 10, 2, 9),
      );
      await repositorio(
        remoto: _RemotoFalso(respuesta: segundo),
      ).getDashboardSummary();

      final isar = await IsarService.init(directory: tempDir.path);
      expect(await isar.localDashboardSummarys.count(), 1);

      final guardado = await cache.leer();
      expect(guardado!.totalPets, 4);
      expect(guardado.calculatedAt, DateTime.utc(2026, 10, 2, 9));
    });

    test('un fallo al guardar la caché no rompe la respuesta', () async {
      final cacheRota = _CacheFalsa(errorAlGuardar: const FileSystemException());
      final remoto = _RemotoFalso(respuesta: resumenRemoto());

      final resultado = await repositorio(
        remoto: remoto,
        cacheLocal: cacheRota,
      ).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.isFromCache, isFalse);
      expect(resumen, esperado(resumenRemoto()));
      expect(cacheRota.intentosDeGuardado, 1);
    });
  });

  group('Servidor no disponible con caché', () {
    test('devuelve la caché marcada como tal', () async {
      final guardado = esperado(resumenRemoto(), isFromCache: true);
      final cacheFalsa = _CacheFalsa(resumen: guardado);

      final resultado = await repositorio(
        remoto: _RemotoFalso(error: const SocketException('sin red')),
        cacheLocal: cacheFalsa,
      ).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.isFromCache, isTrue);
      expect(resumen, guardado);
      expect(resumen.calculatedAt, DateTime.utc(2026, 10, 1, 17));
      expect(resumen.todayIndex, 2);
    });

    test('usa la caché escrita por una respuesta anterior del servidor', () async {
      await repositorio(
        remoto: _RemotoFalso(respuesta: resumenRemoto()),
      ).getDashboardSummary();

      final resultado = await repositorio(
        remoto: _RemotoFalso(error: const SocketException('sin red')),
      ).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.isFromCache, isTrue);
      expect(resumen, esperado(resumenRemoto(), isFromCache: true));
      expect(resumen.foodDispensedToday, 120.5);
    });

    test('descarta la caché con una serie distinta de siete posiciones', () async {
      final incompleta = esperado(resumenRemoto(), isFromCache: true).copyWith(
        weeklyDispensed: const <double>[10, 0, 70.5, 0, 0, 0],
      );
      await sembrarMascotas(<bool>[true, false]);

      final resultado = await repositorio(
        remoto: _RemotoFalso(error: const SocketException('sin red')),
        cacheLocal: _CacheFalsa(resumen: incompleta),
      ).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.isFromCache, isFalse);
      expect(resumen.totalPets, 2);
      expect(resumen.weeklyDispensed, <double>[0, 0, 0, 0, 0, 0, 0]);
      expect(resumen.foodDispensedToday, 0);
    });

    test('descarta la caché sin instante de cálculo', () async {
      final sinInstante = esperado(resumenRemoto(), isFromCache: true);
      final sinCalculo = DashboardSummary(
        totalPets: sinInstante.totalPets,
        sterilizedPets: sinInstante.sterilizedPets,
        foodDispensedToday: sinInstante.foodDispensedToday,
        foodTargetToday: sinInstante.foodTargetToday,
        pendingFeedings: sinInstante.pendingFeedings,
        completedFeedings: sinInstante.completedFeedings,
        weeklyDispensed: sinInstante.weeklyDispensed,
        todayIndex: sinInstante.todayIndex,
        isFromCache: true,
      );

      final resultado = await repositorio(
        remoto: _RemotoFalso(error: const SocketException('sin red')),
        cacheLocal: _CacheFalsa(resumen: sinCalculo),
      ).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.calculatedAt, isNull);
      expect(resumen.foodDispensedToday, 0);
      expect(resumen.isFromCache, isFalse);
    });

    test('descarta la caché con today_index fuera de rango', () async {
      final fueraDeRango = esperado(resumenRemoto()).copyWith(
        todayIndex: 7,
        isFromCache: true,
      );

      final resultado = await repositorio(
        remoto: _RemotoFalso(error: const SocketException('sin red')),
        cacheLocal: _CacheFalsa(resumen: fueraDeRango),
      ).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.todayIndex, 0);
      expect(resumen.foodDispensedToday, 0);
      expect(resumen.isFromCache, isFalse);
    });
  });

  group('Servidor no disponible sin caché', () {
    test('usa el total y las castradas locales y deja el resto en cero', () async {
      await sembrarMascotas(<bool>[true, true, false]);

      final resultado = await repositorio(
        remoto: _RemotoFalso(error: const SocketException('sin red')),
      ).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.totalPets, 3);
      expect(resumen.sterilizedPets, 2);
      expect(resumen.foodDispensedToday, 0);
      expect(resumen.foodTargetToday, 0);
      expect(resumen.pendingFeedings, 0);
      expect(resumen.completedFeedings, 0);
      expect(resumen.weeklyDispensed, <double>[0, 0, 0, 0, 0, 0, 0]);
      expect(resumen.todayIndex, 0);
      expect(resumen.calculatedAt, isNull);
      expect(resumen.isFromCache, isFalse);
    });

    test('sin mascotas locales devuelve el resumen vacío, no cifras inventadas', () async {
      final resultado = await repositorio(
        remoto: _RemotoFalso(error: const SocketException('sin red')),
      ).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.totalPets, 0);
      expect(resumen.sterilizedPets, 0);
      expect(resumen.foodTargetToday, 0);
      expect(resumen.weeklyDispensed, <double>[0, 0, 0, 0, 0, 0, 0]);
    });

    test('si la caché es ilegible se usan los datos locales', () async {
      await sembrarMascotas(<bool>[true]);

      final resultado = await repositorio(
        remoto: _RemotoFalso(error: const SocketException('sin red')),
        cacheLocal: _CacheFalsa(
          errorAlLeer: const FileSystemException('base corrupta'),
        ),
      ).getDashboardSummary();

      final resumen = exitoso(resultado);
      expect(resumen.totalPets, 1);
      expect(resumen.sterilizedPets, 1);
      expect(resumen.foodDispensedToday, 0);
    });

    test('si también falla lo local devuelve un fallo con texto fijo', () async {
      final fracaso = fallo(
        await repositorio(
          remoto: _RemotoFalso(error: const SocketException('sin red')),
          cacheLocal: _CacheFalsa(
            errorAlLeer: const FileSystemException('base corrupta'),
          ),
          mascotasLocales: _MascotasRotas(),
        ).getDashboardSummary(),
      );

      expect(fracaso, isA<ServerFailures>());
      expect(fracaso.message, 'No se pudo cargar el resumen del panel');
      expect(fracaso.message.contains('SocketException'), isFalse);
      expect(fracaso.message.contains('FileSystemException'), isFalse);
    });
  });
}

/// Resumen tal como lo entrega el servidor, con los campos del contrato.
DashboardSummaryModel resumenRemoto({
  int totalPets = 2,
  DateTime? calculatedAt,
}) {
  return DashboardSummaryModel(
    totalPets: totalPets,
    sterilizedPets: 1,
    foodDispensedToday: 120.5,
    foodTargetToday: 250,
    pendingFeedings: 3,
    completedFeedings: 1,
    weeklyDispensed: const <double>[10, 0, 70.5, 0, 0, 0, 0],
    todayIndex: 2,
    calculatedAt: calculatedAt ?? DateTime.utc(2026, 10, 1, 17),
  );
}

/// Resumen de dominio esperado con los mismos valores que [base].
DashboardSummary esperado(DashboardSummary base, {bool isFromCache = false}) {
  return DashboardSummary(
    totalPets: base.totalPets,
    sterilizedPets: base.sterilizedPets,
    foodDispensedToday: base.foodDispensedToday,
    foodTargetToday: base.foodTargetToday,
    pendingFeedings: base.pendingFeedings,
    completedFeedings: base.completedFeedings,
    weeklyDispensed: base.weeklyDispensed,
    todayIndex: base.todayIndex,
    calculatedAt: base.calculatedAt,
    isFromCache: isFromCache,
  );
}

DashboardSummary exitoso(Either<Failures, DashboardSummary> resultado) {
  return resultado.fold(
    (fracaso) => fail('Se esperaba el resumen y llegó: ${fracaso.message}'),
    (resumen) => resumen,
  );
}

Failures fallo(Either<Failures, DashboardSummary> resultado) {
  return resultado.fold(
    (fracaso) => fracaso,
    (resumen) => fail('Se esperaba un fallo y llegó un resumen'),
  );
}

/// Servidor remoto con respuesta fija o con error.
class _RemotoFalso implements DashboardRemoteDatasource {
  _RemotoFalso({this.respuesta, this.error});

  final DashboardSummaryModel? respuesta;
  final Object? error;
  int llamadas = 0;

  @override
  Future<DashboardSummaryModel> getDashboardSummary() async {
    llamadas += 1;
    if (error != null) throw error!;
    return respuesta!;
  }
}

/// Caché controlada por la prueba: puede devolver, fallar al leer o fallar al
/// guardar.
class _CacheFalsa implements DashboardLocalDatasource {
  _CacheFalsa({this.resumen, this.errorAlLeer, this.errorAlGuardar});

  DashboardSummary? resumen;
  final Object? errorAlLeer;
  final Object? errorAlGuardar;
  int intentosDeGuardado = 0;

  @override
  Future<void> guardar(DashboardSummary resumen) async {
    intentosDeGuardado += 1;
    if (errorAlGuardar != null) throw errorAlGuardar!;
    this.resumen = resumen;
  }

  @override
  Future<DashboardSummary?> leer() async {
    if (errorAlLeer != null) throw errorAlLeer!;
    return resumen;
  }
}

/// Datos locales de mascotas que no se pueden abrir.
class _MascotasRotas implements LocalPetDatasource {
  @override
  Future<List<Pet>> getLocalPets() async {
    throw const FileSystemException('base local ilegible');
  }

  @override
  Future<void> cachePets(List<Pet> pets) async {}

  @override
  Future<void> saveLocalPet(Pet pet, {bool isSynced = true}) async {}

  @override
  Future<void> deleteLocalPet(int petId) async {}
}
