import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser_food_status.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/dispensers_page.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/device_card_widget.dart';

import '../bloc/dispenser_bloc_test.dart';

/// Pruebas de widget del módulo unificado de dispensadores (RF-5).
///
/// Comprueban que [DispensersPage] pinta el estado vacío, lista los dispositivos
/// con la tarjeta reutilizable y navega al escaneo BLE o al diálogo de reseteo
/// de WiFi sin lógica de negocio incrustada en la vista.
void main() {
  Future<DispenserBloc> pumpPage(
    WidgetTester tester, {
    required MockDispenserRepository repository,
    Duration? refreshInterval,
    bool tickerEnabled = true,
  }) async {
    final bloc = buildDispenserBloc(repository);
    addTearDown(bloc.close);

    final router = GoRouter(
      initialLocation: '/dispensers',
      routes: <RouteBase>[
        GoRoute(
          path: '/dispensers',
          builder: (context, state) => BlocProvider<DispenserBloc>.value(
            value: bloc,
            child: TickerMode(
              enabled: tickerEnabled,
              child: DispensersPage(refreshInterval: refreshInterval),
            ),
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'scan',
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('Escaneo BLE'))),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    );
    bloc.add(LoadDispensersEvent());
    await tester.pumpAndSettle();

    return bloc;
  }

  testWidgets('muestra el estado vacío cuando no hay dispositivos vinculados', (
    tester,
  ) async {
    await pumpPage(tester, repository: MockDispenserRepository());

    expect(find.text('No hay dispositivos vinculados'), findsOneWidget);
    expect(find.text('Buscar y Configurar Dispositivo'), findsOneWidget);
    expect(find.byType(DeviceCardWidget), findsNothing);
  });

  testWidgets('lista los dispensadores con la tarjeta reutilizable', (
    tester,
  ) async {
    await pumpPage(
      tester,
      repository: MockDispenserRepository(
        mockDispensers: const [
          Dispenser(
            id: 1,
            macAddress: 'AA:BB:CC:DD:EE:FF',
            name: 'Dispensador Sala',
            isActive: true,
            wifiSsid: 'HomeWiFi',
          ),
        ],
      ),
    );

    expect(find.byType(DeviceCardWidget), findsOneWidget);
    expect(find.text('Dispensador Sala'), findsOneWidget);
    expect(find.textContaining('Red:'), findsNothing);
    expect(find.text('Estado de WiFi:'), findsNothing);
    expect(find.text('Resetear WiFi'), findsOneWidget);
    expect(find.textContaining('5.000 g'), findsOneWidget);
    expect(find.textContaining('de 5 kg'), findsOneWidget);
    expect(find.text('No hay dispositivos vinculados'), findsNothing);
  });

  testWidgets('deslizar hacia abajo refresca el stock desde el repositorio (RF-5)', (
    tester,
  ) async {
    final repository = MockDispenserRepository(
      mockDispensers: const [
        Dispenser(
          id: 1,
          macAddress: 'AA:BB:CC:DD:EE:FF',
          name: 'Dispensador Sala',
          isActive: true,
          petId: 1,
        ),
      ],
    );
    await pumpPage(tester, repository: repository);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(repository.refreshCalls, greaterThan(0));
  });

  testWidgets('el sondeo no consulta si la pestaña no está visible (RNF-1)', (
    tester,
  ) async {
    final repository = MockDispenserRepository(
      mockDispensers: const [
        Dispenser(
          id: 1,
          macAddress: 'AA:BB:CC:DD:EE:FF',
          name: 'Dispensador Sala',
          isActive: true,
          petId: 1,
        ),
      ],
    );
    await pumpPage(
      tester,
      repository: repository,
      refreshInterval: const Duration(milliseconds: 100),
      tickerEnabled: false,
    );

    await tester.pump(const Duration(milliseconds: 350));

    expect(repository.refreshCalls, 0);
  });

  testWidgets('muestra el aviso de reabastecimiento exitoso una sola vez (RF-7)', (
    tester,
  ) async {
    final bloc = await pumpPage(
      tester,
      repository: MockDispenserRepository(
        mockDispensers: const [
          Dispenser(
            id: 1,
            macAddress: 'AA:BB:CC:DD:EE:FF',
            name: 'Dispensador Sala',
            isActive: true,
            petId: 1,
            currentFoodGrams: 1500.0,
          ),
        ],
      ),
    );

    bloc.add(
      const RefillFoodEvent(dispenserId: '1', amount: 500.0, unit: 'g'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Reabastecimiento con éxito'), findsOneWidget);
  });

  testWidgets('muestra el aviso de límite cuando el servidor rechaza (RF-8)', (
    tester,
  ) async {
    final bloc = await pumpPage(
      tester,
      repository: MockDispenserRepository(
        mockDispensers: const [
          Dispenser(
            id: 1,
            macAddress: 'AA:BB:CC:DD:EE:FF',
            name: 'Dispensador Sala',
            isActive: true,
            petId: 1,
            currentFoodGrams: 4900.0,
          ),
        ],
        refillError: const RefillLimitException(),
      ),
    );

    bloc.add(
      const RefillFoodEvent(dispenserId: '1', amount: 500.0, unit: 'g'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('El reabastecimiento supera el límite de 5 kg'),
      findsOneWidget,
    );
  });

  testWidgets('el diálogo rechaza el exceso sin modificar ni cerrar (RF-8)', (
    tester,
  ) async {
    await pumpPage(
      tester,
      repository: MockDispenserRepository(
        mockDispensers: const [
          Dispenser(
            id: 1,
            macAddress: 'AA:BB:CC:DD:EE:FF',
            name: 'Dispensador Sala',
            isActive: true,
            petId: 1,
            currentFoodGrams: 4900.0,
          ),
        ],
      ),
    );

    await tester.tap(find.text('Reabastecer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '500');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(
      find.text('El reabastecimiento supera el límite de 5 kg'),
      findsOneWidget,
    );
    expect(find.text('Reabastecer Alimento'), findsOneWidget);
  });

  testWidgets('el botón del AppBar navega al escaneo BLE', (tester) async {
    await pumpPage(tester, repository: MockDispenserRepository());

    await tester.tap(find.byTooltip('Buscar dispensadores BLE'));
    await tester.pumpAndSettle();

    expect(find.text('Escaneo BLE'), findsOneWidget);
  });

  testWidgets('pide confirmación antes de resetear el WiFi del dispositivo', (
    tester,
  ) async {
    await pumpPage(
      tester,
      repository: MockDispenserRepository(
        mockDispensers: const [
          Dispenser(
            id: 1,
            macAddress: 'AA:BB:CC:DD:EE:FF',
            name: 'Dispensador Sala',
            isActive: true,
            wifiSsid: 'HomeWiFi',
          ),
        ],
      ),
    );

    await tester.tap(find.text('Resetear WiFi'));
    await tester.pumpAndSettle();

    expect(find.text('Eliminar credenciales WiFi'), findsOneWidget);
    expect(find.textContaining('Dispensador Sala'), findsWidgets);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Eliminar credenciales WiFi'), findsNothing);
    expect(find.byType(DeviceCardWidget), findsOneWidget);
  });

  testWidgets('a 600 y 840 la cabecera real no dibuja la entrada y a 320 sí '
      'hay exactamente una', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final ancho in <double>[600, 840]) {
      tester.view.physicalSize = Size(ancho, 800);
      tester.view.devicePixelRatio = 1.0;
      await pumpPage(
        tester,
        repository: MockDispenserRepository(),
        refreshInterval: null,
      );

      expect(
        find.byTooltip('Abrir configuración'),
        findsNothing,
        reason: 'ancho $ancho',
      );
    }

    tester.view.physicalSize = const Size(320, 640);
    await pumpPage(
      tester,
      repository: MockDispenserRepository(),
      refreshInterval: null,
    );

    expect(find.byTooltip('Abrir configuración'), findsOneWidget);
  });
}
