import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio mínimo escrito a mano: cada llamada devuelve el resultado
/// configurado y cuenta las consultas para comprobar reintentos. Las respuestas
/// encoladas permiten resolver cargas solapadas en un orden controlado.
class _FakeDashboardRepository implements DashboardRepository {
  _FakeDashboardRepository(this.resultado);

  Either<Failures, DashboardSummary> resultado;
  int llamadas = 0;
  final List<Future<Either<Failures, DashboardSummary>>> _pendientes = [];

  void encolarRespuesta(Future<Either<Failures, DashboardSummary>> respuesta) {
    _pendientes.add(respuesta);
  }

  @override
  Future<Either<Failures, DashboardSummary>> getDashboardSummary() {
    llamadas++;
    if (_pendientes.isNotEmpty) return _pendientes.removeAt(0);
    return Future.value(resultado);
  }
}

DashboardSummary _resumen({
  double foodDispensedToday = 120,
  int todayIndex = 2,
}) {
  return DashboardSummary(
    totalPets: 2,
    sterilizedPets: 1,
    foodDispensedToday: foodDispensedToday,
    foodTargetToday: 240,
    pendingFeedings: 1,
    completedFeedings: 2,
    weeklyDispensed: const [10, 20, 30, 40, 50, 60, 70],
    todayIndex: todayIndex,
    calculatedAt: DateTime.utc(2026, 11, 1, 12),
  );
}

/// Respaldo de la caché local: lo devuelve el repositorio si falla el servidor
/// y conserva la fecha del cálculo del servidor.
DashboardSummary _respaldoCache({double foodDispensedToday = 0}) {
  return _resumen(foodDispensedToday: foodDispensedToday, todayIndex: 1)
      .copyWith(isFromCache: true);
}

/// Respaldo con datos locales sin caché: no hay fecha del servidor.
DashboardSummary _respaldoLocal({double foodDispensedToday = 0}) {
  return DashboardSummary(
    totalPets: 1,
    sterilizedPets: 1,
    foodDispensedToday: foodDispensedToday,
    foodTargetToday: 0,
    pendingFeedings: 0,
    completedFeedings: 0,
    weeklyDispensed: const [0, 0, 0, 0, 0, 0, 0],
    todayIndex: 0,
  );
}

void main() {
  late _FakeDashboardRepository repository;
  late DashboardCubit cubit;

  setUp(() {
    repository = _FakeDashboardRepository(Right(_resumen()));
    cubit = DashboardCubit(repository: repository);
  });

  tearDown(() => cubit.close());

  Future<List<DashboardState>> escucharEstados(
    Future<void> Function() accion,
  ) async {
    final estados = <DashboardState>[];
    final suscripcion = cubit.stream.listen(estados.add);
    await accion();
    await Future<void>.delayed(Duration.zero);
    await suscripcion.cancel();
    return estados;
  }

  test('carga inicial correcta emite carga y resumen', () async {
    final resumen = _resumen();

    final estados = await escucharEstados(cubit.loadSummary);

    expect(estados.whereType<DashboardLoading>(), hasLength(1));
    expect(estados.last, isA<DashboardLoaded>());
    final cargado = estados.last as DashboardLoaded;
    expect(cargado.summary, resumen);
    expect(cargado.errorMessage, isNull);
    expect(cubit.state, isA<DashboardLoaded>());
    expect(repository.llamadas, 1);
  });

  test('error inicial usa copy fijo y no el texto del fallo', () async {
    repository.resultado = Left(
      ServerFailures('No se pudo cargar el resumen del panel'),
    );

    final estados = await escucharEstados(cubit.loadSummary);

    expect(estados.first, isA<DashboardLoading>());
    expect(estados.last, isA<DashboardError>());
    final error = estados.last as DashboardError;
    expect(error.message, DashboardCubit.mensajeError);
    expect(error.message, 'No se pudo cargar el panel.');
    expect(error.message, isNot(contains('No se pudo cargar el resumen')));
    expect(error.message, isNot(contains('ServerFailures')));
  });

  test('refresco fallido conserva el resumen y expone el aviso', () async {
    final resumen = _resumen();
    await cubit.loadSummary();

    repository.resultado = Left(
      ServerFailures('No se pudo cargar el resumen del panel'),
    );
    final estados = await escucharEstados(cubit.loadSummary);

    expect(estados.whereType<DashboardLoading>(), isEmpty);
    expect(estados.whereType<DashboardError>(), isEmpty);
    expect(estados.single, isA<DashboardLoaded>());
    final cargado = estados.single as DashboardLoaded;
    expect(cargado.summary, resumen);
    expect(cargado.errorMessage, DashboardCubit.mensajeError);
    expect(cargado.errorMessage, isNot(contains('No se pudo cargar el resumen')));
    expect(repository.llamadas, 2);
  });

  test('reintento exitoso limpia el error y actualiza el resumen', () async {
    await cubit.loadSummary();
    repository.resultado = Left(ServerFailures('Fallo de red'));
    await cubit.loadSummary();
    expect((cubit.state as DashboardLoaded).errorMessage, isNotNull);

    final nuevo = _resumen(foodDispensedToday: 180, todayIndex: 3);
    repository.resultado = Right(nuevo);
    final estados = await escucharEstados(cubit.reintentar);

    expect(estados.whereType<DashboardLoading>(), isEmpty);
    final cargado = estados.single as DashboardLoaded;
    expect(cargado.summary, nuevo);
    expect(cargado.errorMessage, isNull);
    expect(cubit.state, isA<DashboardLoaded>());
    expect((cubit.state as DashboardLoaded).errorMessage, isNull);
    expect(repository.llamadas, 3);
  });

  test('reintento fallido mantiene el resumen visible', () async {
    final resumen = _resumen();
    await cubit.loadSummary();
    repository.resultado = Left(ServerFailures('Fallo de red'));
    await cubit.loadSummary();

    final estados = await escucharEstados(cubit.reintentar);

    expect(estados.whereType<DashboardLoading>(), isEmpty);
    expect(estados.whereType<DashboardError>(), isEmpty);
    expect(cubit.state, isA<DashboardLoaded>());
    final cargado = cubit.state as DashboardLoaded;
    expect(cargado.summary, resumen);
    expect(cargado.errorMessage, DashboardCubit.mensajeError);
    expect(repository.llamadas, 3);
  });

  test('el éxito tras un error inicial emite el resumen sin error', () async {
    repository.resultado = Left(ServerFailures('Fallo de red'));
    await cubit.loadSummary();
    expect(cubit.state, isA<DashboardError>());

    repository.resultado = Right(_resumen(foodDispensedToday: 90));
    final estados = await escucharEstados(cubit.reintentar);

    expect(estados.first, isA<DashboardLoading>());
    final cargado = estados.last as DashboardLoaded;
    expect(cargado.summary.foodDispensedToday, 90);
    expect(cargado.errorMessage, isNull);
  });

  test('refresco con caché conserva el resumen visible y avisa', () async {
    final visible = _resumen();
    await cubit.loadSummary();

    repository.resultado = Right(_respaldoCache(foodDispensedToday: 5));
    final estados = await escucharEstados(cubit.loadSummary);

    expect(estados.whereType<DashboardLoading>(), isEmpty);
    expect(estados.whereType<DashboardError>(), isEmpty);
    expect(estados.single, isA<DashboardLoaded>());
    final cargado = estados.single as DashboardLoaded;
    expect(cargado.summary, visible);
    expect(cargado.summary.isFromCache, isFalse);
    expect(cargado.errorMessage, DashboardCubit.mensajeError);
  });

  test('refresco con datos locales conserva el resumen visible y avisa', () async {
    final visible = _resumen();
    await cubit.loadSummary();

    repository.resultado = Right(_respaldoLocal(foodDispensedToday: 30));
    final estados = await escucharEstados(cubit.loadSummary);

    expect(estados.whereType<DashboardLoading>(), isEmpty);
    expect(estados.whereType<DashboardError>(), isEmpty);
    final cargado = estados.single as DashboardLoaded;
    expect(cargado.summary, visible);
    expect(cargado.summary.calculatedAt, isNotNull);
    expect(cargado.errorMessage, DashboardCubit.mensajeError);
  });

  test('la carga inicial con caché muestra el respaldo sin aviso', () async {
    final cache = _respaldoCache(foodDispensedToday: 10);
    repository.resultado = Right(cache);

    final estados = await escucharEstados(cubit.loadSummary);

    expect(estados.whereType<DashboardLoading>(), hasLength(1));
    final cargado = estados.last as DashboardLoaded;
    expect(cargado.summary, cache);
    expect(cargado.errorMessage, isNull);
  });

  test('tras un error, los datos locales se muestran como respaldo sin aviso', () async {
    repository.resultado = Left(ServerFailures('Fallo de red'));
    await cubit.loadSummary();
    expect(cubit.state, isA<DashboardError>());

    final local = _respaldoLocal(foodDispensedToday: 25);
    repository.resultado = Right(local);
    final estados = await escucharEstados(cubit.reintentar);

    expect(estados.first, isA<DashboardLoading>());
    final cargado = estados.last as DashboardLoaded;
    expect(cargado.summary, local);
    expect(cargado.summary.calculatedAt, isNull);
    expect(cargado.summary.isFromCache, isFalse);
    expect(cargado.errorMessage, isNull);
  });

  test('el reintento con respaldo conserva lo visible y mantiene el aviso', () async {
    final visible = _resumen();
    await cubit.loadSummary();
    repository.resultado = Left(ServerFailures('Fallo de red'));
    await cubit.loadSummary();
    expect((cubit.state as DashboardLoaded).errorMessage, isNotNull);

    repository.resultado = Right(_respaldoCache(foodDispensedToday: 5));
    final estados = await escucharEstados(cubit.reintentar);

    expect(estados.whereType<DashboardLoading>(), isEmpty);
    expect(estados.whereType<DashboardError>(), isEmpty);
    final cargado = cubit.state as DashboardLoaded;
    expect(cargado.summary, visible);
    expect(cargado.errorMessage, DashboardCubit.mensajeError);
  });

  test('una carga vieja que falla no borra el resumen nuevo', () async {
    final vieja = Completer<Either<Failures, DashboardSummary>>();
    final nueva = Completer<Either<Failures, DashboardSummary>>();
    repository.encolarRespuesta(vieja.future);
    repository.encolarRespuesta(nueva.future);

    final primera = cubit.loadSummary();
    final segunda = cubit.loadSummary();
    expect(repository.llamadas, 2);

    nueva.complete(Right(_resumen(foodDispensedToday: 300)));
    await segunda;
    expect((cubit.state as DashboardLoaded).summary.foodDispensedToday, 300);

    vieja.complete(Left(ServerFailures('Fallo viejo')));
    await primera;

    expect(cubit.state, isA<DashboardLoaded>());
    final actual = cubit.state as DashboardLoaded;
    expect(actual.summary.foodDispensedToday, 300);
    expect(actual.errorMessage, isNull);
  });
}
