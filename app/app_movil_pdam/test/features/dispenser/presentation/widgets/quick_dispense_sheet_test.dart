import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/quick_dispense_uc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/quick_dispense_cubit.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/quick_dispense_sheet.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeQuickDispenseRepository implements DispenserRepositories {
  Either<Failures, bool> result = const Right(true);
  int calls = 0;
  String? operationId;

  @override
  Future<Either<Failures, bool>> quickDispense(
    int dispenserId,
    double grams,
    String operationId,
  ) async {
    calls++;
    this.operationId = operationId;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _dispenser = Dispenser(
  id: 7,
  macAddress: 'AA:BB:CC:DD:EE:FF',
  isActive: true,
  petId: 1,
  currentFoodGrams: 1200,
);

Future<void> _abrirHoja(
  WidgetTester tester,
  QuickDispenseCubit cubit, {
  double textScaler = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScaler)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => BlocProvider<QuickDispenseCubit>.value(
                  value: cubit,
                  child: const QuickDispenseSheet(dispenser: _dispenser),
                ),
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  late _FakeQuickDispenseRepository repository;
  late QuickDispenseCubit cubit;

  setUp(() {
    repository = _FakeQuickDispenseRepository();
    cubit = QuickDispenseCubit(
      quickDispenseUc: QuickDispenseUc(repository: repository),
    );
    addTearDown(cubit.close);
  });

  testWidgets('solo pide la cantidad y muestra máximo y stock', (tester) async {
    await _abrirHoja(tester, cubit);

    expect(find.text('Dispensar ahora'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.text('Máximo 200 g · Stock disponible: 1200 g'),
      findsOneWidget,
    );
  });

  testWidgets('una cantidad mayor que 200 g no llega al servidor', (
    tester,
  ) async {
    await _abrirHoja(tester, cubit);

    await tester.enterText(
      find.byKey(const Key('quick-dispense-amount')),
      '201',
    );
    await tester.tap(find.text('Dispensar'));
    await tester.pump();

    expect(
      find.text('La cantidad rápida debe ser mayor que 0 y no superar 200 g.'),
      findsOneWidget,
    );
    expect(repository.calls, 0);
    expect(find.byType(QuickDispenseSheet), findsOneWidget);
  });

  testWidgets('una cantidad válida envía y cierra la hoja', (tester) async {
    await _abrirHoja(tester, cubit);

    await tester.enterText(
      find.byKey(const Key('quick-dispense-amount')),
      '50',
    );
    await tester.tap(find.text('Dispensar'));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(find.byType(QuickDispenseSheet), findsNothing);
  });

  testWidgets('un rechazo del servidor se muestra sin cerrar la hoja', (
    tester,
  ) async {
    repository.result = Left(
      ServerFailures('El dispensador está desactivado.'),
    );
    await _abrirHoja(tester, cubit);

    await tester.enterText(
      find.byKey(const Key('quick-dispense-amount')),
      '50',
    );
    await tester.tap(find.text('Dispensar'));
    await tester.pumpAndSettle();

    expect(find.text('El dispensador está desactivado.'), findsOneWidget);
    expect(find.byType(QuickDispenseSheet), findsOneWidget);
  });

  testWidgets('se adapta a 320 dp con texto ampliado', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _abrirHoja(tester, cubit, textScaler: 1.3);

    expect(tester.takeException(), isNull);
  });

  testWidgets('se adapta a 360 dp con texto ampliado', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _abrirHoja(tester, cubit, textScaler: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.byType(QuickDispenseSheet), findsOneWidget);
    expect(find.text('Máximo 200 g · Stock disponible: 1200 g'), findsOneWidget);
  });

  testWidgets('sin conexión muestra el aviso sin cerrar la hoja', (
    tester,
  ) async {
    const mensaje =
        'No hay conexión con el servidor para dispensar la cantidad';
    repository.result = Left(ConnectivityRequiredFailures(mensaje));
    await _abrirHoja(tester, cubit);

    await tester.enterText(
      find.byKey(const Key('quick-dispense-amount')),
      '50',
    );
    await tester.tap(find.text('Dispensar'));
    await tester.pumpAndSettle();

    expect(find.text(mensaje), findsOneWidget);
    expect(find.byType(QuickDispenseSheet), findsOneWidget);
    expect(repository.calls, 1);
  });
}
