import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
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
import 'package:app_movil_pdam/features/nutrition/domain/usecases/calculate_nutrition_usecase.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/bloc/nutrition_cubit.dart';
import 'package:app_movil_pdam/features/nutrition/presentation/views/nutrition_calculator_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';

/// RF-6: el dashboard expone un punto de entrada visible que navega a la
/// calculadora nutricional sin que el usuario conozca la ruta interna.
void main() {
  setUp(() async {
    await sl.reset();
    sl.registerFactory<DashboardCubit>(
      () => DashboardCubit(repository: _FakeDashboardRepository()),
    );
  });

  tearDown(() async {
    await sl.reset();
  });

  Future<AuthBloc> buildAuthenticatedBloc() async {
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

  testWidgets('la cabecera conserva saludo, cierre de sesión y la entrada al '
      'menú, y el acceso visible navega a NutritionCalculatorView', (
    tester,
  ) async {
    // Menos de 600 puntos: la entrada al menú vive en la cabecera del panel.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authBloc = await buildAuthenticatedBloc();
    addTearDown(authBloc.close);
    final nutritionCubit = NutritionCubit(
      calculateNutritionUsecase: const CalculateNutritionUsecase(),
    );
    addTearDown(nutritionCubit.close);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const DashboardView(),
        ),
        GoRoute(
          path: '/nutrition-calculator',
          name: 'nutrition_calculator',
          builder: (context, state) => const NutritionCalculatorView(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<NutritionCubit>.value(value: nutritionCubit),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // RF-04: la cabecera conserva el saludo y el cierre de sesión, gana la
    // entrada al menú y ya no ofrece el control de tema.
    expect(find.text('Hola, usuario'), findsOneWidget);
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
    expect(find.byTooltip('Abrir configuración'), findsOneWidget);
    expect(find.byTooltip('Cambiar Tema'), findsNothing);
    expect(find.byIcon(Icons.brightness_6_outlined), findsNothing);

    final acceso = find.text('Calculadora Nutricional');
    expect(acceso, findsOneWidget);

    await tester.ensureVisible(acceso);
    await tester.tap(acceso);
    await tester.pumpAndSettle();

    expect(find.byType(NutritionCalculatorView), findsOneWidget);
  });

  testWidgets('a 600 y 840 la cabecera real del panel no dibuja la entrada y '
      'a 320 sí hay exactamente una', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authBloc = await buildAuthenticatedBloc();
    addTearDown(authBloc.close);

    Future<void> pumpDashboard(double ancho) async {
      tester.view.physicalSize = Size(ancho, 1600);
      tester.view.devicePixelRatio = 1.0;
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardView(),
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
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final ancho in <double>[600, 840]) {
      await pumpDashboard(ancho);
      expect(
        find.byTooltip('Abrir configuración'),
        findsNothing,
        reason: 'ancho $ancho',
      );
    }

    await pumpDashboard(320);
    expect(find.byTooltip('Abrir configuración'), findsOneWidget);
  });
}

/// Limpieza de sesión simulada: estas pruebas no ejercitan el 401.
class _FakeCleaner implements AccountLocalCleaner {
  @override
  Future<AccountCleanupResult> limpiarTrasBaja({String? correo}) async =>
      AccountCleanupResult.exito(pasosCompletados: AccountCleanupStep.values);

  @override
  Future<AccountCleanupResult?> limpiarSiPendiente() async => null;

  @override
  Future<void> limpiarPorSesionExpirada() async {}
}

class _FakeDashboardRepository implements DashboardRepository {
  @override
  Future<Either<Failures, DashboardSummary>> getDashboardSummary() async {
    return const Right(
      DashboardSummary(
        totalPets: 0,
        sterilizedPets: 0,
        foodDispensedToday: 0,
        foodTargetToday: 0,
        pendingFeedings: 0,
        completedFeedings: 0,
        weeklyDispensed: [0, 0, 0, 0, 0, 0, 0],
      ),
    );
  }
}

class _FakeUserRepository implements UserRepositories {
  @override
  Future<Either<Failures, User>> currentUser() async {
    return Right(User(id: 1, email: 'usuario@test.com'));
  }

  @override
  Future<Either<Failures, User>> login(String email, String password) async {
    return Right(User(id: 1, email: email));
  }

  @override
  Future<Either<Failures, User>> register(
    String email,
    String password,
    String confirmPassword,
  ) async {
    return Right(User(id: 1, email: email));
  }
}

class _FakePendingDeletionStore implements PendingDeletionStore {
  @override
  Future<void> markPending() async {}

  @override
  Future<bool> isPending() async => false;

  @override
  Future<void> clear() async {}
}
