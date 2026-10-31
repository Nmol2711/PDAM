import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
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
import 'package:app_movil_pdam/features/settings/presentation/views/delete_account_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/profile_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/settings_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/update_profile_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/profile_notice.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/settings_menu_tile.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<Either<Failures, ProfileSnapshot>> getProfile() async => const Right(
    ProfileSnapshot(profile: UserProfile(email: 'user@x.com', isActive: true)),
  );

  @override
  Future<Either<Failures, AccountUpdateResult>> updateProfile(
    AccountUpdate update,
  ) async => Right(
    AccountUpdateResult(
      profile: const UserProfile(email: 'user@x.com', isActive: true),
    ),
  );

  @override
  Future<Either<Failures, bool>> deleteAccount(String password) async =>
      const Right(true);

  @override
  Future<Either<Failures, UserProfile?>> cachedProfile() async =>
      const Right(null);
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

class _FakeUserRepository implements UserRepositories {
  @override
  Future<Either<Failures, User>> currentUser() async =>
      Right(User(id: 1, email: 'user@x.com'));

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

class _Harness {
  final GoRouter router;

  _Harness(this.router);
}

ColorScheme _esquema(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

RoundedRectangleBorder _formaDelMaterial(WidgetTester tester, Finder card) {
  final material = tester.widget<Material>(
    find.descendant(of: card, matching: find.byType(Material)).first,
  );
  return material.shape! as RoundedRectangleBorder;
}

void main() {
  Future<_Harness> pumpApp(
    WidgetTester tester, {
    Size size = const Size(800, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final authBloc = AuthBloc(
      registerUc: RegisterUc(repository: _FakeUserRepository()),
      loginUc: LoginUc(repository: _FakeUserRepository()),
      currentUserUc: CurrentUserUc(repository: _FakeUserRepository()),
      pendingDeletionStore: _FakePendingDeletionStore(),
      sessionEvents: eventos,
      accountLocalCleaner: _FakeCleaner(),
      hayConexion: () async => true,
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

    final router = GoRouter(
      initialLocation: '/settings',
      routes: <RouteBase>[
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsView(),
          routes: <RouteBase>[
            GoRoute(
              path: 'profile',
              builder: (context, state) => const ProfileView(),
            ),
            GoRoute(
              path: 'update',
              builder: (context, state) => const UpdateProfileView(),
            ),
            GoRoute(
              path: 'delete',
              builder: (context, state) => const DeleteAccountView(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<AccountBloc>.value(value: accountBloc),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _Harness(router);
  }

  testWidgets('RF-07 y RF-08: el menú usa tarjeta y radios del tema', (
    tester,
  ) async {
    await pumpApp(tester);
    final esquema = _esquema(tester);

    final card = find.byType(Card).first;
    expect(tester.widget<Card>(card).shape, isNull);

    final material = tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(material.color, esquema.surface);
    expect(material.elevation, 0);
    final forma = _formaDelMaterial(tester, card);
    expect(forma.borderRadius, BorderRadius.circular(8));
    expect(forma.side.color, esquema.outline);

    final relleno = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(SettingsMenuTile).first,
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(
      relleno.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
    );

    final icono = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(SettingsMenuTile).first,
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (icono.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(8),
    );
  });

  testWidgets('RF-09: el menú usa relleno de pantalla 16 y 24', (tester) async {
    await pumpApp(tester, size: const Size(400, 1200));
    var lista = tester.widget<ListView>(
      find.byKey(const Key('settings_scroll')),
    );
    expect(
      lista.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.page,
      ),
    );

    await pumpApp(tester, size: const Size(600, 1200));
    lista = tester.widget<ListView>(find.byKey(const Key('settings_scroll')));
    expect(
      lista.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageWide,
        vertical: AppSpacing.page,
      ),
    );
  });

  testWidgets('RF-07 y RF-08: el perfil usa tarjeta del tema y relleno 16', (
    tester,
  ) async {
    final h = await pumpApp(tester, size: const Size(400, 1200));
    h.router.go('/settings/profile');
    await tester.pumpAndSettle();
    final esquema = _esquema(tester);

    final card = find.byType(Card).first;
    expect(tester.widget<Card>(card).shape, isNull);
    final forma = _formaDelMaterial(tester, card);
    expect(forma.borderRadius, BorderRadius.circular(8));
    expect(forma.side.color, esquema.outline);

    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('profile_scroll')),
    );
    expect(
      scroll.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.page,
      ),
    );
  });

  testWidgets('RF-08: el campo de correo de actualización hereda el radio 8', (
    tester,
  ) async {
    final h = await pumpApp(tester);
    h.router.go('/settings/update');
    await tester.pumpAndSettle();

    final decorador = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byKey(const Key('update_profile_email')),
        matching: find.byType(InputDecorator),
      ),
    );
    final borde = decorador.decoration.border! as OutlineInputBorder;
    expect(borde.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('RF-07 y RF-08: la baja usa tarjeta del tema y su botón error', (
    tester,
  ) async {
    final h = await pumpApp(tester, size: const Size(400, 1200));
    h.router.go('/settings/delete');
    await tester.pumpAndSettle();
    final esquema = _esquema(tester);

    final card = find.byType(Card).first;
    expect(tester.widget<Card>(card).shape, isNull);
    final forma = _formaDelMaterial(tester, card);
    expect(forma.borderRadius, BorderRadius.circular(8));
    expect(forma.side.color, esquema.outline);

    final boton = tester.widget<FilledButton>(
      find.byKey(const Key('delete_account_open')),
    );
    expect(
      boton.style!.backgroundColor!.resolve(<WidgetState>{}),
      esquema.error,
    );
    expect(
      boton.style!.foregroundColor!.resolve(<WidgetState>{}),
      esquema.onError,
    );

    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('delete_account_scroll')),
    );
    expect(
      scroll.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.page,
      ),
    );
  });

  testWidgets('RF-07 y RF-09: el aviso de perfil usa 8 y relleno 16', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: ProfileNotice(message: 'Aviso de prueba')),
      ),
    );

    final contenedor = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ProfileNotice),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(contenedor.padding, const EdgeInsets.all(AppSpacing.cardPadding));
    expect(
      (contenedor.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(8),
    );
  });
}
