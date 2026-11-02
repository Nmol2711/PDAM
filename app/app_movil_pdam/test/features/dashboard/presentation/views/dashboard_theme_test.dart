import 'dart:io';

import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/views/dashboard_view.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_chart_card.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_hero_card.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_metrics_grid.dart';
import 'package:dartz/dartz.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const DashboardSummary _resumen = DashboardSummary(
  totalPets: 3,
  sterilizedPets: 1,
  foodDispensedToday: 150,
  foodTargetToday: 300,
  pendingFeedings: 5,
  completedFeedings: 2,
  weeklyDispensed: <double>[10, 20, 30, 40, 50, 60, 70],
  todayIndex: 0,
);

class _FakeDashboardRepository implements DashboardRepository {
  const _FakeDashboardRepository(this.resumen);

  final DashboardSummary resumen;

  @override
  Future<Either<Failures, DashboardSummary>> getDashboardSummary() async =>
      Right(resumen);
}

class _FakeUserRepository implements UserRepositories {
  @override
  Future<Either<Failures, User>> currentUser() async =>
      Right(User(id: 1, email: 'usuario@test.com'));

  @override
  Future<Either<Failures, User>> login(String email, String password) async =>
      Right(User(id: 1, email: email));

  @override
  Future<Either<Failures, User>> register(
    String email,
    String password,
    String confirmPassword,
  ) async => Right(User(id: 1, email: email));
}

class _FakePendingDeletionStore implements PendingDeletionStore {
  @override
  Future<void> markPending() async {}

  @override
  Future<bool> isPending() async => false;

  @override
  Future<void> clear() async {}
}

class _FakeCleaner implements AccountLocalCleaner {
  @override
  Future<AccountCleanupResult> limpiarTrasBaja({String? correo}) async =>
      AccountCleanupResult.exito(pasosCompletados: AccountCleanupStep.values);

  @override
  Future<AccountCleanupResult?> limpiarSiPendiente() async => null;

  @override
  Future<void> limpiarPorSesionExpirada() async {}
}

Future<AuthBloc> _authBloc() async {
  final eventos = SessionEvents();
  addTearDown(eventos.dispose);
  final bloc = AuthBloc(
    registerUc: RegisterUc(repository: _FakeUserRepository()),
    loginUc: LoginUc(repository: _FakeUserRepository()),
    currentUserUc: CurrentUserUc(repository: _FakeUserRepository()),
    pendingDeletionStore: _FakePendingDeletionStore(),
    sessionEvents: eventos,
    accountLocalCleaner: _FakeCleaner(),
  );
  addTearDown(bloc.close);
  bloc.add(AuthCheckStatusRequested());
  await bloc.stream.firstWhere((state) => state is AuthAuthenticated);
  return bloc;
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  double textScaler = 1.0,
  Size tamano = const Size(400, 1600),
  DashboardSummary resumen = _resumen,
}) async {
  await sl.reset();
  addTearDown(sl.reset);
  sl.registerFactory<DashboardCubit>(
    () => DashboardCubit(repository: _FakeDashboardRepository(resumen)),
  );

  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authBloc = await _authBloc();
  final router = GoRouter(
    initialLocation: '/home',
    routes: <RouteBase>[
      GoRoute(
        path: '/home',
        builder: (context, state) => const DashboardView(),
      ),
      GoRoute(
        path: '/dispensers',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Sección de dispensadores'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaler)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ColorScheme _esquema(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(DashboardView))).colorScheme;

double _contraste(Color fondo, Color texto) {
  final l1 = fondo.computeLuminance();
  final l2 = texto.computeLuminance();
  final alto = l1 > l2 ? l1 : l2;
  final bajo = l1 > l2 ? l2 : l1;
  return (alto + 0.05) / (bajo + 0.05);
}

Color _compuesto(Color frente, Color fondo) {
  final alfa = frente.a;
  int canal(double arriba, double abajo) =>
      ((arriba * alfa + abajo * (1 - alfa)) * 255).round().clamp(0, 255);
  return Color.fromARGB(
    255,
    canal(frente.r, fondo.r),
    canal(frente.g, fondo.g),
    canal(frente.b, fondo.b),
  );
}

MetricCard _metrica(WidgetTester tester, String label) =>
    tester.widget<MetricCard>(
      find.byWidgetPredicate(
        (widget) => widget is MetricCard && widget.label == label,
      ),
    );

void main() {
  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  testWidgets('RF-04 y RF-13: las acciones rápidas usan primary', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    final esquema = _esquema(tester);

    for (final icono in <IconData>[
      Icons.add_circle_outline,
      Icons.schedule_outlined,
      Icons.bluetooth_outlined,
    ]) {
      final widget = tester.widget<Icon>(find.byIcon(icono));
      expect(widget.color, esquema.primary, reason: '$icono');
    }
  });

  testWidgets('RF-04: el rótulo de las acciones alcanza 4.5:1 sobre su '
      'fondo', (tester) async {
    await _pumpDashboard(tester);
    final esquema = _esquema(tester);

    for (final etiqueta in <String>[
      'Nueva Mascota',
      'Nuevo Horario',
      'Dispositivos',
    ]) {
      final texto = tester.widget<Text>(find.text(etiqueta));
      expect(texto.style?.color, esquema.onSurface, reason: etiqueta);
    }

    // El tile compone primary al 10 % sobre el fondo de la pantalla.
    final fondo = _compuesto(
      esquema.primary.withValues(alpha: 0.1),
      AppTheme.lightTheme.scaffoldBackgroundColor,
    );
    expect(_contraste(fondo, esquema.onSurface), greaterThanOrEqualTo(4.5));
  });

  testWidgets('RF-04 y RF-13: las métricas informativas usan tertiary', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    final esquema = _esquema(tester);

    final metricas = tester
        .widgetList<MetricCard>(find.byType(MetricCard))
        .toList();
    expect(metricas, hasLength(4));
    for (final metrica in metricas) {
      expect(metrica.iconColor, esquema.tertiary);
      expect(metrica.backgroundColor, esquema.tertiary);
    }

    final contenedor = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(MetricCard),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(contenedor.padding, const EdgeInsets.all(AppSpacing.cardPadding));
    expect((contenedor.decoration! as BoxDecoration).color, esquema.surface);
    expect(
      _contraste(esquema.surface, esquema.tertiary),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('RF-07 y RF-14: el hero va en primary con contenido onPrimary', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    final esquema = _esquema(tester);

    final contenedor = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(DashboardHeroCard),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoracion = contenedor.decoration! as BoxDecoration;
    expect(decoracion.color, esquema.primary);
    expect(decoracion.boxShadow, isNull);
    expect(decoracion.borderRadius, BorderRadius.circular(8));
    expect(contenedor.padding, const EdgeInsets.all(AppSpacing.cardPadding));

    final titulo = tester.widget<Text>(find.text('Alimentaciones para hoy'));
    expect(titulo.style?.color, esquema.onPrimary);

    final boton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Ver Historial'),
    );
    expect(
      boton.style!.backgroundColor!.resolve(<WidgetState>{}),
      esquema.onPrimary,
    );
    expect(
      boton.style!.foregroundColor!.resolve(<WidgetState>{}),
      esquema.primary,
    );
  });

  testWidgets('RF-04: la gráfica pinta sus barras con tertiary', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    final esquema = _esquema(tester);

    final grafica = tester.widget<BarChart>(find.byType(BarChart));
    final barras = grafica.data.barGroups
        .expand((grupo) => grupo.barRods)
        .toList();

    expect(barras, isNotEmpty);
    for (final barra in barras) {
      expect(barra.color!.withValues(alpha: 1), esquema.tertiary);
    }
    expect(barras.any((barra) => barra.color!.a == 1.0), isTrue);
    expect(barras.any((barra) => barra.color!.a < 1.0), isTrue);

    final contenedor = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(DashboardChartCard),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(contenedor.padding, const EdgeInsets.all(AppSpacing.cardPadding));
    expect((contenedor.decoration! as BoxDecoration).color, esquema.surface);
  });

  testWidgets('RF-13: las cifras del panel vienen del estado del Cubit', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    expect(_metrica(tester, 'Total Mascotas').value, '3');
    expect(_metrica(tester, 'Mascotas Castradas').value, '1');
    expect(_metrica(tester, 'Alimento Hoy (g)').value, '150');
    expect(_metrica(tester, 'Cumplimiento de lo programado').value, '50%');
    expect(find.text('2 realizadas de 7'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('RNF-02: a 320 puntos con texto al 130 % no desborda', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      tamano: const Size(320, 2000),
      textScaler: 1.3,
    );

    final error = tester.takeException();
    expect(error, isNull);
    expect(find.text('Acciones Rápidas'), findsOneWidget);
  });

  testWidgets('RF-09: a 400 puntos el relleno de pantalla es 16', (
    tester,
  ) async {
    await _pumpDashboard(tester, tamano: const Size(400, 1600));

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scroll.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.page,
      ),
    );
  });

  testWidgets('RF-09: desde 600 puntos el relleno de pantalla es 24', (
    tester,
  ) async {
    await _pumpDashboard(tester, tamano: const Size(600, 1600));

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scroll.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageWide,
        vertical: AppSpacing.page,
      ),
    );
  });

  test('RF-06: dashboard y nutrición no conservan los HEX anteriores', () {
    const prohibidos = <String>[
      '6C63FF',
      '0066FF',
      '00C853',
      'FFB300',
      '00B8D4',
    ];
    final archivos = <File>[
      for (final raiz in <String>[
        'lib/features/dashboard',
        'lib/features/nutrition',
      ])
        ...Directory(raiz)
            .listSync(recursive: true)
            .whereType<File>()
            .where((archivo) => archivo.path.endsWith('.dart')),
    ];

    expect(archivos, isNotEmpty);
    for (final archivo in archivos) {
      final codigo = archivo.readAsStringSync();
      final codigoMayusculas = codigo.toUpperCase();
      for (final hex in prohibidos) {
        expect(
          codigoMayusculas.contains(hex),
          isFalse,
          reason: '${archivo.path} conserva #$hex',
        );
      }
      expect(
        RegExp(r'\bColors\.(?!transparent)').hasMatch(codigo),
        isFalse,
        reason: '${archivo.path} usa Colors.* fuera de transparent',
      );
    }
  });

  testWidgets('«Dispositivos» abre la sección de dispensadores y no la de mascotas', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    await tester.ensureVisible(find.text('Dispositivos'));
    await tester.tap(find.text('Dispositivos'));
    await tester.pumpAndSettle();

    expect(find.text('Sección de dispensadores'), findsOneWidget);
  });
}
