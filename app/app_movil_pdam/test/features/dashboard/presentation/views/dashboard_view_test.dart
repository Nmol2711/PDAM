import 'dart:async';

import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
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
import 'package:app_movil_pdam/features/dashboard/presentation/widgets/dashboard_metrics_grid.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Estado del panel (RF-7, RF-8, RF-12): carga sin cifras, error con reintento,
/// contenido real y avisos de datos sin conexión.
void main() {
  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  testWidgets('la carga muestra un indicador y ninguna cifra', (tester) async {
    final pendiente = Completer<Either<Failures, DashboardSummary>>();
    final repository = _FakeDashboardRepository()..pendiente = pendiente;
    await _montar(tester, repository);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(MetricCard), findsNothing);
    expect(find.textContaining('Alimentaciones para hoy'), findsNothing);
  });

  testWidgets('el error muestra el copy fijo y el reintento carga el panel', (
    tester,
  ) async {
    final repository = _FakeDashboardRepository(
      Left(ServerFailures('SocketException: Connection refused')),
    );
    await _montar(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text(DashboardCubit.mensajeError), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);

    repository.resultado = Right(_resumen());
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardMetricsGrid), findsOneWidget);
    expect(find.text(DashboardCubit.mensajeError), findsNothing);
  });

  testWidgets(
    'el contenido usa las cifras del resumen, no valores prefijados',
    (tester) async {
      await _montar(
        tester,
        _FakeDashboardRepository(
          Right(
            _resumen(
              dispensado: 120,
              programado: 240,
              pendientes: 1,
              completadas: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final metricas = tester
          .widgetList<MetricCard>(find.byType(MetricCard))
          .toList();
      expect(metricas, hasLength(4));
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('2 realizadas de 3'), findsOneWidget);
      expect(find.text('300'), findsNothing);
      expect(find.textContaining('300.0'), findsNothing);
    },
  );

  testWidgets(
    'la caché avisa de datos sin conexión con la fecha del servidor',
    (tester) async {
      await _montar(
        tester,
        _FakeDashboardRepository(
          Right(
            _resumen(
              isFromCache: true,
              calculatedAt: DateTime.utc(2026, 11, 1, 14, 5),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mostrando datos sin conexión'), findsOneWidget);
      expect(
        find.text('Última actualización: 01/11/2026 14:05'),
        findsOneWidget,
      );
    },
  );

  testWidgets('el respaldo local avisa sin fecha', (tester) async {
    await _montar(
      tester,
      _FakeDashboardRepository(Right(_resumen(sinCalculatedAt: true))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión: solo datos locales'), findsOneWidget);
    expect(find.textContaining('Última actualización'), findsNothing);
    expect(find.text('Mostrando datos sin conexión'), findsNothing);
  });

  testWidgets('un refresco fallido avisa y conserva las cifras visibles', (
    tester,
  ) async {
    final repository = _FakeDashboardRepository(Right(_resumen()));
    await _montar(tester, repository);
    await tester.pumpAndSettle();

    final cubit = BlocProvider.of<DashboardCubit>(
      tester.element(find.byType(DashboardMetricsGrid)),
    );
    repository.resultado = Left(ServerFailures('Timeout del servidor'));
    await cubit.loadSummary();
    await tester.pumpAndSettle();

    expect(find.text(DashboardCubit.mensajeError), findsOneWidget);
    expect(
      find.text('Se muestran los últimos datos disponibles.'),
      findsOneWidget,
    );
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('Timeout del servidor'), findsNothing);
  });
}

Future<void> _montar(
  WidgetTester tester,
  _FakeDashboardRepository repository,
) async {
  sl.registerFactory<DashboardCubit>(
    () => DashboardCubit(repository: repository),
  );

  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authBloc = await _authBloc();
  addTearDown(authBloc.close);

  await tester.pumpWidget(
    BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const DashboardView(),
      ),
    ),
  );
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
  bloc.add(AuthCheckStatusRequested());
  await bloc.stream.firstWhere((state) => state is AuthAuthenticated);
  return bloc;
}

DashboardSummary _resumen({
  double dispensado = 120,
  double programado = 240,
  int pendientes = 1,
  int completadas = 2,
  bool isFromCache = false,
  bool sinCalculatedAt = false,
  DateTime? calculatedAt,
}) {
  return DashboardSummary(
    totalPets: 3,
    sterilizedPets: 2,
    foodDispensedToday: dispensado,
    foodTargetToday: programado,
    pendingFeedings: pendientes,
    completedFeedings: completadas,
    weeklyDispensed: const [10, 20, 30, 40, 50, 60, 70],
    todayIndex: 2,
    calculatedAt: sinCalculatedAt
        ? null
        : (calculatedAt ?? DateTime.utc(2026, 11, 1, 9)),
    isFromCache: isFromCache,
  );
}

class _FakeDashboardRepository implements DashboardRepository {
  _FakeDashboardRepository([this.resultado]);

  Either<Failures, DashboardSummary>? resultado;
  Completer<Either<Failures, DashboardSummary>>? pendiente;
  int llamadas = 0;

  @override
  Future<Either<Failures, DashboardSummary>> getDashboardSummary() {
    llamadas++;
    final espera = pendiente;
    if (espera != null) return espera.future;
    return Future.value(resultado);
  }
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
