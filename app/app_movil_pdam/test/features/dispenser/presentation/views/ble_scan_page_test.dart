import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/ble_scan_page.dart';

import '../bloc/dispenser_bloc_test.dart';

/// Pruebas de widget del escaneo BLE unificado (RF-5).
///
/// El BLoC real se ejercita con el repositorio falso del módulo para verificar
/// los estados de búsqueda, la lista de dispositivos encontrados, la navegación
/// al aprovisionamiento y la recuperación ante errores.
void main() {
  Future<DispenserBloc> pumpPage(
    WidgetTester tester, {
    required MockDispenserRepository repository,
  }) async {
    final bloc = buildDispenserBloc(repository);
    addTearDown(bloc.close);

    final router = GoRouter(
      initialLocation: '/dispensers/scan',
      routes: <RouteBase>[
        GoRoute(
          path: '/dispensers/scan',
          builder: (context, state) => BlocProvider<DispenserBloc>.value(
            value: bloc,
            child: const BleScanPage(),
          ),
        ),
        GoRoute(
          path: '/dispensers/provision',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Aprovisionamiento WiFi'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    );

    // Deja correr el post-frame que dispara StartScanBleEvent y el cooldown
    // interno del adaptador (1 s) antes de suscribirse al escaneo.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();

    return bloc;
  }

  testWidgets('muestra el mensaje de búsqueda mientras no hay dispositivos', (
    tester,
  ) async {
    // El escaneo falso emite un dispositivo tras el cooldown, así que primero
    // se comprueba el estado inicial con un repositorio sin resultados.
    final repository = MockDispenserRepository();
    final bloc = buildDispenserBloc(repository);
    addTearDown(bloc.close);

    final router = GoRouter(
      initialLocation: '/dispensers/scan',
      routes: <RouteBase>[
        GoRoute(
          path: '/dispensers/scan',
          builder: (context, state) => BlocProvider<DispenserBloc>.value(
            value: bloc,
            child: const BleScanPage(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Buscando dispensadores cercanos (PDAM-Config-*)...'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Completa el cooldown para no dejar temporizadores pendientes.
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('lista los dispositivos encontrados y navega al aprovisionar', (
    tester,
  ) async {
    await pumpPage(tester, repository: MockDispenserRepository());

    expect(find.text('PDAM-Config-[123456]'), findsOneWidget);
    expect(find.textContaining('AA:BB:CC:DD:EE:FF'), findsOneWidget);
    expect(find.text('Conectar'), findsOneWidget);

    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();

    expect(find.text('Aprovisionamiento WiFi'), findsOneWidget);
  });

  testWidgets('muestra el error de escaneo y permite reintentar', (
    tester,
  ) async {
    await pumpPage(
      tester,
      repository: MockDispenserRepository(shouldFail: true),
    );

    expect(find.textContaining('Error:'), findsOneWidget);
    expect(find.text('Reintentar Escaneo'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
