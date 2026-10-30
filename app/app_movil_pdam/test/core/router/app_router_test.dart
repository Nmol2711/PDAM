import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/router/app_router.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/auth/presentation/views/login_view.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/delete_account_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/profile_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/settings_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/update_profile_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';

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

class _FakeStorage implements StorageService {
  final Map<String, String> valores = <String, String>{};

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    valores[key] = value;
    return const Right(null);
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async =>
      Right(valores[key]);

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    valores.remove(key);
    return const Right(null);
  }
}

class _FakeUserRepository implements UserRepositories {
  _FakeUserRepository({this.autenticado = true});

  final bool autenticado;

  @override
  Future<Either<Failures, User>> currentUser() async => autenticado
      ? Right(User(id: 1, email: 'usuario@test.com'))
      : Left(ServerFailures('sin sesión'));

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

class _FakeDashboardRepository implements DashboardRepository {
  @override
  Future<Either<Failures, DashboardSummary>> getDashboardSummary() async =>
      const Right(
        DashboardSummary(
          totalPets: 0,
          sterilizedPets: 0,
          foodDispensedToday: 0,
          foodTargetToday: 0,
          pendingFeedings: 0,
          completedFeedings: 0,
          weeklyDispensed: <double>[0, 0, 0, 0, 0, 0, 0],
        ),
      );
}

/// RF-05: el guard existente redirige a /login sin sesión y también cuando la
/// sesión termina por un 401 `unauthorized` (`AuthSessionExpired`).
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

  Future<AuthBloc> buildBloc(
    SessionEvents eventos, {
    bool autenticado = true,
  }) async {
    final usuarios = _FakeUserRepository(autenticado: autenticado);
    final bloc = AuthBloc(
      registerUc: RegisterUc(repository: usuarios),
      loginUc: LoginUc(repository: usuarios),
      currentUserUc: CurrentUserUc(repository: usuarios),
      pendingDeletionStore: _FakePendingDeletionStore(),
      sessionEvents: eventos,
      accountLocalCleaner: _FakeCleaner(),
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> pumpRouter(
    WidgetTester tester, {
    required AuthBloc authBloc,
    required ThemeCubit themeCubit,
    required AppRouter appRouter,
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: appRouter.router,
        ),
      ),
    );
    // Sin `pumpAndSettle`: la pantalla de login contiene campos de texto y su
    // cursor puede mantener animaciones indefinidas en las pruebas.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('sin sesión, forzar /settings redirige a /login sin mostrar el '
      'menú', (tester) async {
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final authBloc = await buildBloc(eventos, autenticado: false);
    authBloc.add(AuthCheckStatusRequested());
    await authBloc.stream.firstWhere((state) => state is AuthUnauthenticated);

    final themeCubit = ThemeCubit(storageService: _FakeStorage());
    addTearDown(themeCubit.close);
    final appRouter = AppRouter(authBloc);

    await pumpRouter(
      tester,
      authBloc: authBloc,
      themeCubit: themeCubit,
      appRouter: appRouter,
    );

    appRouter.router.go('/settings');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SettingsView), findsNothing);
    expect(find.byType(LoginView), findsOneWidget);
  });

  testWidgets('sin sesión, forzar /settings/profile redirige a /login sin '
      'mostrar el perfil', (tester) async {
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final authBloc = await buildBloc(eventos, autenticado: false);
    authBloc.add(AuthCheckStatusRequested());
    await authBloc.stream.firstWhere((state) => state is AuthUnauthenticated);

    final themeCubit = ThemeCubit(storageService: _FakeStorage());
    addTearDown(themeCubit.close);
    final appRouter = AppRouter(authBloc);

    await pumpRouter(
      tester,
      authBloc: authBloc,
      themeCubit: themeCubit,
      appRouter: appRouter,
    );

    appRouter.router.go('/settings/profile');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ProfileView), findsNothing);
    expect(find.byType(SettingsView), findsNothing);
    expect(find.byType(LoginView), findsOneWidget);
  });

  testWidgets('sin sesión, forzar /settings/delete redirige a /login sin '
      'mostrar la baja de cuenta', (tester) async {
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final authBloc = await buildBloc(eventos, autenticado: false);
    authBloc.add(AuthCheckStatusRequested());
    await authBloc.stream.firstWhere((state) => state is AuthUnauthenticated);

    final themeCubit = ThemeCubit(storageService: _FakeStorage());
    addTearDown(themeCubit.close);
    final appRouter = AppRouter(authBloc);

    await pumpRouter(
      tester,
      authBloc: authBloc,
      themeCubit: themeCubit,
      appRouter: appRouter,
    );

    appRouter.router.go('/settings/delete');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DeleteAccountView), findsNothing);
    expect(find.byType(SettingsView), findsNothing);
    expect(find.byType(LoginView), findsOneWidget);
  });

  testWidgets(
    'RF-05: sin sesión, forzar /settings/update redirige a /login sin mostrar el formulario',
    (tester) async {
      final eventos = SessionEvents();
      addTearDown(eventos.dispose);
      final authBloc = await buildBloc(eventos, autenticado: false);
      authBloc.add(AuthCheckStatusRequested());
      await authBloc.stream.firstWhere((state) => state is AuthUnauthenticated);

      final themeCubit = ThemeCubit(storageService: _FakeStorage());
      addTearDown(themeCubit.close);
      final appRouter = AppRouter(authBloc);

      await pumpRouter(
        tester,
        authBloc: authBloc,
        themeCubit: themeCubit,
        appRouter: appRouter,
      );

      appRouter.router.go('/settings/update');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(UpdateProfileView), findsNothing);
      expect(find.byType(SettingsView), findsNothing);
      expect(find.byType(LoginView), findsOneWidget);
    },
  );

  testWidgets('si la sesión termina con el menú abierto se cierra y se va a '
      '/login con el mensaje del catálogo', (tester) async {
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final authBloc = await buildBloc(eventos);
    authBloc.add(AuthCheckStatusRequested());
    await authBloc.stream.firstWhere((state) => state is AuthAuthenticated);

    final themeCubit = ThemeCubit(storageService: _FakeStorage());
    addTearDown(themeCubit.close);
    final appRouter = AppRouter(authBloc);

    await pumpRouter(
      tester,
      authBloc: authBloc,
      themeCubit: themeCubit,
      appRouter: appRouter,
    );

    appRouter.router.go('/settings');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SettingsView), findsOneWidget);

    eventos.notify(const SessionEvent.sesionExpirada());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // El refresh de GoRouter navega a /login; hay que avanzar la transición de
    // página para que la vista saliente deje de estar montada.
    await tester.pump(const Duration(milliseconds: 500));

    expect(authBloc.state, isA<AuthSessionExpired>());
    expect(
      (authBloc.state as AuthSessionExpired).message,
      MensajesCuenta.sesionInvalida,
    );
    expect(find.byType(SettingsView), findsNothing);
    expect(find.byType(LoginView), findsOneWidget);
  });
}
