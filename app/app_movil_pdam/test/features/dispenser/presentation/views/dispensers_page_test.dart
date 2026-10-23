import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
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
            child: const DispensersPage(),
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
    expect(find.text('Red: HomeWiFi'), findsOneWidget);
    expect(find.text('No hay dispositivos vinculados'), findsNothing);
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
}
