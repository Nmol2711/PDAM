import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/quick_dispense_uc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/quick_dispense_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio mínimo: el cubit solo usa `quickDispense`; el resto se delega a
/// `noSuchMethod` porque estas pruebas no tocan otros flujos.
class _FakeQuickDispenseRepository implements DispenserRepositories {
  Either<Failures, bool> result = const Right(true);
  Completer<Either<Failures, bool>>? pending;
  int calls = 0;
  final List<int> dispensers = [];
  final List<double> grams = [];
  final List<String> operationIds = [];

  @override
  Future<Either<Failures, bool>> quickDispense(
    int dispenserId,
    double grams,
    String operationId,
  ) async {
    calls++;
    dispensers.add(dispenserId);
    this.grams.add(grams);
    operationIds.add(operationId);
    if (pending != null) return pending!.future;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeQuickDispenseRepository repository;
  late QuickDispenseCubit cubit;
  late int generadas;

  setUp(() {
    repository = _FakeQuickDispenseRepository();
    generadas = 0;
    cubit = QuickDispenseCubit(
      quickDispenseUc: QuickDispenseUc(repository: repository),
      generarIdentificador: () => 'operacion-${++generadas}',
    );
  });

  tearDown(() => cubit.close());

  test('emite enviando y aceptada al recibir un resultado correcto', () async {
    final estados = <QuickDispenseState>[];
    final suscripcion = cubit.stream.listen(estados.add);

    await cubit.solicitar(7, 50.0);
    await Future<void>.delayed(Duration.zero);
    await suscripcion.cancel();

    expect(estados.whereType<QuickDispenseSending>(), hasLength(1));
    expect(estados.last, isA<QuickDispenseAccepted>());
    expect((estados.last as QuickDispenseAccepted).grams, 50.0);
    expect(repository.calls, 1);
  });

  test('emite el mensaje del fallo cuando el servidor rechaza', () async {
    repository.result = Left(ServerFailures('El dispensador está desactivado.'));

    await cubit.solicitar(7, 50.0);

    expect(cubit.state, isA<QuickDispenseError>());
    expect(
      (cubit.state as QuickDispenseError).message,
      'El dispensador está desactivado.',
    );
  });

  test('no lanza una segunda solicitud mientras la primera está en curso', () async {
    repository.pending = Completer<Either<Failures, bool>>();

    final primera = cubit.solicitar(7, 50.0);
    await cubit.solicitar(7, 80.0);

    expect(repository.calls, 1);
    expect(repository.operationIds, hasLength(1));
    expect(cubit.state, isA<QuickDispenseSending>());

    repository.pending!.complete(const Right(true));
    await primera;

    expect(cubit.state, isA<QuickDispenseAccepted>());
  });

  test('reutiliza el operation_id en dos intentos con la misma cantidad', () async {
    await cubit.solicitar(7, 50.0);
    await cubit.solicitar(7, 50.0);

    expect(repository.calls, 2);
    expect(repository.operationIds, ['operacion-1', 'operacion-1']);
    expect(generadas, 1, reason: 'El identificador se genera una sola vez');
  });

  test('renueva el operation_id cuando cambia la cantidad', () async {
    await cubit.solicitar(7, 50.0);
    await cubit.solicitar(7, 80.0);

    expect(repository.operationIds, ['operacion-1', 'operacion-2']);
    expect(generadas, 2);
  });

  test('un fallo no reutiliza el identificador si cambia la cantidad', () async {
    repository.result = Left(ServerFailures('La cantidad rápida no es válida.'));
    await cubit.solicitar(7, 50.0);
    await cubit.solicitar(7, 50.0);

    expect(repository.operationIds, ['operacion-1', 'operacion-1']);

    await cubit.solicitar(7, 120.0);

    expect(repository.operationIds.last, 'operacion-2');
  });

  test('sin inyección genera un identificador de 32 hexadecimales', () async {
    final otro = QuickDispenseCubit(
      quickDispenseUc: QuickDispenseUc(repository: repository),
    );
    addTearDown(otro.close);

    await otro.solicitar(7, 50.0);

    expect(repository.operationIds.single, matches(RegExp(r'^[0-9a-f]{32}$')));
  });
}
