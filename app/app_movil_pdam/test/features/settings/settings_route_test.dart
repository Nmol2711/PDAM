import 'package:app_movil_pdam/core/di/injection_container.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/router/app_router.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/core/theme/theme_cubit.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/repository/account_repository.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/delete_account_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/get_profile_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/update_profile_uc.dart';
import 'package:app_movil_pdam/features/account/presentation/bloc/account_bloc.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/register_token_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:app_movil_pdam/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:app_movil_pdam/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/profile_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/settings_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/update_profile_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/delete_account_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _FakeAccountRepository implements AccountRepository {
  int llamadasPerfil = 0;

  @override
  Future<Either<Failures, ProfileSnapshot>> getProfile() async {
    llamadasPerfil++;
    return const Right(
      ProfileSnapshot(
        profile: UserProfile(email: 'usuario@test.com', isActive: true),
      ),
    );
  }

  @override
  Future<Either<Failures, AccountUpdateResult>> updateProfile(
    AccountUpdate update,
  ) async => Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, bool>> deleteAccount(String password) async =>
      Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, UserProfile?>> cachedProfile() async =>
      const Right(null);
}

class _FakeAuthTokenRepositories implements AuthTokenRepositories {
  @override
  Future<Either<Failures, AuthToken>> cacheToken(
    String token, {
    String typeToken = 'Bearer',
  }) async => Right(AuthToken(token: token, typeToken: typeToken));

  @override
  Future<Either<Failures, void>> deleteToken() async => const Right(null);

  @override
  Future<Either<Failures, AuthToken>> getToken() async =>
      Left(ServerFailures('sin token'));
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

/// RF-01, RF-06 y RF-07: la ruta real `/settings/profile` funciona con el
/// `AccountBloc` provisto por encima del enrutador, sin inyectarlo a mano en la
/// vista, y el perfil se recarga al reabrir.
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

  testWidgets('la ruta real /settings/profile pinta el perfil con el BLoC del '
      'árbol y lo recarga al reabrir', (tester) async {
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final authBloc = AuthBloc(
      registerUc: RegisterUc(repository: _FakeUserRepository()),
      loginUc: LoginUc(repository: _FakeUserRepository()),
      currentUserUc: CurrentUserUc(repository: _FakeUserRepository()),
      pendingDeletionStore: _FakePendingDeletionStore(),
      sessionEvents: eventos,
      accountLocalCleaner: _FakeCleaner(),
    );
    addTearDown(authBloc.close);
    authBloc.add(AuthCheckStatusRequested());
    await authBloc.stream.firstWhere((estado) => estado is AuthAuthenticated);

    final repo = _FakeAccountRepository();
    final accountBloc = AccountBloc(
      getProfileUc: GetProfileUc(repository: repo),
      updateProfileUc: UpdateProfileUc(repository: repo),
      deleteAccountUc: DeleteAccountUc(repository: repo),
      registerTokenUc: RegisterTokenUc(
        repository: _FakeAuthTokenRepositories(),
      ),
      accountLocalCleaner: _FakeCleaner(),
      sessionEvents: eventos,
      authStates: authBloc.stream,
    );
    addTearDown(accountBloc.close);

    final themeCubit = ThemeCubit(storageService: _FakeStorage());
    addTearDown(themeCubit.close);

    final appRouter = AppRouter(authBloc);
    addTearDown(appRouter.router.dispose);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<AccountBloc>.value(value: accountBloc),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: appRouter.router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    appRouter.router.go('/settings/profile');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ProfileView), findsOneWidget);
    expect(find.text('usuario@test.com'), findsOneWidget);
    expect(repo.llamadasPerfil, 1);

    appRouter.router.go('/settings');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SettingsView), findsOneWidget);

    appRouter.router.go('/settings/profile');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ProfileView), findsOneWidget);
    expect(repo.llamadasPerfil, 2);

    // RF-03: la ruta real de la segunda fila abre el formulario de
    // actualización con el mismo BLoC del árbol.
    appRouter.router.go('/settings/update');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(UpdateProfileView), findsOneWidget);

    // RF-03: la ruta real de la tercera fila abre la Eliminación de cuenta.
    appRouter.router.go('/settings/delete');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DeleteAccountView), findsOneWidget);
  });
}
