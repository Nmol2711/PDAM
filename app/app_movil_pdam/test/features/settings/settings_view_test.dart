import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
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
import 'package:app_movil_pdam/features/account/presentation/utils/appearance_mode_theme.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/register_token_uc.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/settings_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/appearance_mode_dialog.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/settings_menu_tile.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Almacenamiento cifrado simulado para el modo de apariencia.
class _FakeStorage implements StorageService {
  _FakeStorage({Map<String, String>? valores}) : valores = {...?valores};

  final Map<String, String> valores;

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

/// Repositorio de cuenta que devuelve siempre el perfil indicado.
class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository(this.perfil);

  final UserProfile perfil;

  @override
  Future<Either<Failures, ProfileSnapshot>> getProfile() async =>
      Right(ProfileSnapshot(profile: perfil));

  @override
  Future<Either<Failures, AccountUpdateResult>> updateProfile(
    AccountUpdate update,
  ) async => Right(AccountUpdateResult(profile: perfil));

  @override
  Future<Either<Failures, bool>> deleteAccount(String password) async =>
      const Right(true);

  @override
  Future<Either<Failures, UserProfile?>> cachedProfile() async => Right(perfil);
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

/// RF-02, RF-03 y RF-24: menú con el título «Configuración» y exactamente
/// cuatro filas en el orden fijado, sin cierre de sesión ni las tres opciones
/// de apariencia como filas. La cuarta fila muestra el modo activo y abre el
/// diálogo; la segunda abre la actualización de perfil.
void main() {
  Future<ThemeCubit> pumpMenu(
    WidgetTester tester, {
    ThemeMode? modo,
    double width = 800,
    double height = 800,
    double textScaler = 1.0,
    AccountBloc? accountBloc,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final themeCubit = ThemeCubit(
      storageService: _FakeStorage(
        valores: modo == null
            ? null
            : <String, String>{'user_theme_mode': codigoDeModo(modo)},
      ),
    );
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
              builder: (context, state) => const Scaffold(
                body: Center(child: Text('Destino de perfil')),
              ),
            ),
            GoRoute(
              path: 'update',
              builder: (context, state) => const Scaffold(
                body: Center(child: Text('Destino de actualización')),
              ),
            ),
            GoRoute(
              path: 'delete',
              builder: (context, state) => const Scaffold(
                body: Center(child: Text('Destino de eliminación')),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    Widget app = BlocProvider<ThemeCubit>.value(
      value: themeCubit,
      // Igual que `main.dart`: el tema de la aplicación sale del cubit
      // (RF-22), no de un valor fijo del arnés.
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) => MaterialApp.router(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
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

    if (accountBloc != null) {
      // El menú se monta dentro del estado real de la cuenta para demostrar
      // que no lee el perfil ni oculta filas por su estado (RF-02).
      app = BlocProvider<AccountBloc>.value(value: accountBloc, child: app);
    }

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    return themeCubit;
  }

  List<SettingsMenuTile> filas(WidgetTester tester) => tester
      .widgetList<SettingsMenuTile>(find.byType(SettingsMenuTile))
      .toList();

  testWidgets('muestra el título y las cuatro filas en el orden de RF-02', (
    tester,
  ) async {
    await pumpMenu(tester);

    expect(find.text('Configuración'), findsOneWidget);
    expect(filas(tester).map((fila) => fila.title), <String>[
      'Perfil',
      'Actualización de perfil',
      'Eliminación de cuenta',
      'Modo claro y oscuro',
    ]);
    expect(find.text('Cerrar sesión'), findsNothing);
    expect(filas(tester).map((fila) => fila.trailingIcon), <IconData>[
      Icons.chevron_right,
      Icons.chevron_right,
      Icons.chevron_right,
      Icons.tune,
    ]);
  });

  testWidgets('no despliega las tres opciones de apariencia como filas', (
    tester,
  ) async {
    await pumpMenu(tester, modo: ThemeMode.dark);

    expect(find.text('Claro'), findsNothing);
    expect(find.text('Automático'), findsNothing);
    expect(find.text('Oscuro'), findsOneWidget);
    expect(filas(tester).last.subtitle, 'Oscuro');
  });

  testWidgets(
    'RF-02: una cuenta inactiva sigue mostrando las cuatro filas sin ocultar ninguna',
    (tester) async {
      final eventos = SessionEvents();
      addTearDown(eventos.dispose);
      final perfil = const UserProfile(
        email: 'inactiva@x.com',
        isActive: false,
      );
      final repositorio = _FakeAccountRepository(perfil);
      final accountBloc = AccountBloc(
        getProfileUc: GetProfileUc(repository: repositorio),
        updateProfileUc: UpdateProfileUc(repository: repositorio),
        deleteAccountUc: DeleteAccountUc(repository: repositorio),
        registerTokenUc: RegisterTokenUc(
          repository: _FakeAuthTokenRepositories(),
        ),
        accountLocalCleaner: _FakeCleaner(),
        sessionEvents: eventos,
      );
      addTearDown(accountBloc.close);

      accountBloc.add(const ProfileRequested());
      await accountBloc.stream.firstWhere((estado) => estado.profile != null);
      expect(accountBloc.state.profile?.isActive, isFalse);

      await pumpMenu(tester, accountBloc: accountBloc);

      expect(find.text('Configuración'), findsOneWidget);
      expect(filas(tester).map((fila) => fila.title), <String>[
        'Perfil',
        'Actualización de perfil',
        'Eliminación de cuenta',
        'Modo claro y oscuro',
      ]);
      expect(filas(tester), hasLength(4));
      expect(filas(tester).every((fila) => fila.onTap != null), isTrue);
      // El menú no incluye el cierre de sesión ni cambia por el estado inactivo.
      expect(find.text('Cerrar sesión'), findsNothing);
    },
  );

  testWidgets('la cuarta fila indica el modo activo y se actualiza al volver', (
    tester,
  ) async {
    final themeCubit = await pumpMenu(tester, modo: ThemeMode.light);

    expect(filas(tester).last.subtitle, 'Claro');

    await themeCubit.setTheme(ThemeMode.system);
    await tester.pumpAndSettle();

    expect(filas(tester).last.subtitle, 'Automático');
    expect(filas(tester), hasLength(4));
  });

  testWidgets('la primera fila abre Perfil y al volver el menú conserva las '
      'cuatro filas', (tester) async {
    await pumpMenu(tester, modo: ThemeMode.dark);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Destino de perfil'), findsOneWidget);

    final router = GoRouter.of(tester.element(find.text('Destino de perfil')));
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Configuración'), findsOneWidget);
    expect(filas(tester), hasLength(4));
    expect(filas(tester).last.subtitle, 'Oscuro');
  });

  testWidgets('RF-03: la segunda fila abre Actualización de perfil y al '
      'volver el menú conserva las cuatro filas', (tester) async {
    await pumpMenu(tester);

    await tester.tap(find.text('Actualización de perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Destino de actualización'), findsOneWidget);

    final router = GoRouter.of(
      tester.element(find.text('Destino de actualización')),
    );
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Configuración'), findsOneWidget);
    expect(filas(tester), hasLength(4));
  });

  testWidgets('RF-03: la tercera fila abre la Eliminación de cuenta', (
    tester,
  ) async {
    await pumpMenu(tester);

    await tester.tap(find.text('Eliminación de cuenta'));
    await tester.pumpAndSettle();

    expect(find.text('Destino de eliminación'), findsOneWidget);

    final router = GoRouter.of(
      tester.element(find.text('Destino de eliminación')),
    );
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Configuración'), findsOneWidget);
    expect(filas(tester), hasLength(4));
  });

  testWidgets('RF-24: la cuarta fila abre el diálogo, marca el modo activo y '
      'aplica el cambio al volver al menú', (tester) async {
    final themeCubit = await pumpMenu(tester, modo: ThemeMode.light);

    await tester.tap(find.text('Modo claro y oscuro'));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceModeDialog), findsOneWidget);
    expect(find.text('Modo de apariencia'), findsOneWidget);
    expect(find.text('Claro'), findsNWidgets(2));
    expect(find.text('Oscuro'), findsOneWidget);
    expect(find.text('Automático'), findsOneWidget);

    final activa = tester.widget<ListTile>(
      find.byKey(const Key('appearance_mode_light')),
    );
    expect(activa.selected, isTrue);

    // El menú se pinta con el tema claro antes de elegir.
    expect(
      Theme.of(tester.element(find.byType(SettingsView))).brightness,
      Brightness.light,
    );

    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(find.text('Oscuro'), findsNWidgets(2));

    // RF-22: el cambio se aplica a toda la aplicación con el diálogo abierto.
    expect(themeCubit.state, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(SettingsView))).brightness,
      Brightness.dark,
    );
    expect(
      Theme.of(tester.element(find.byType(AppearanceModeDialog))).brightness,
      Brightness.dark,
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceModeDialog), findsNothing);
    expect(filas(tester), hasLength(4));
    expect(filas(tester).last.subtitle, 'Oscuro');
    expect(
      Theme.of(tester.element(find.byType(SettingsView))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('RF-22: cerrar el diálogo sin elegir no cambia el modo', (
    tester,
  ) async {
    await pumpMenu(tester, modo: ThemeMode.light);

    await tester.tap(find.text('Modo claro y oscuro'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceModeDialog), findsNothing);
    expect(filas(tester).last.subtitle, 'Claro');
  });

  testWidgets('a 320 puntos con texto al 130 % no hay desbordamientos', (
    tester,
  ) async {
    await pumpMenu(tester, width: 320, height: 640, textScaler: 1.3);

    expect(tester.takeException(), isNull);
    expect(filas(tester), hasLength(4));
    expect(find.text('Configuración'), findsOneWidget);
  });

  testWidgets('a 840 puntos en horizontal no hay desbordamientos', (
    tester,
  ) async {
    await pumpMenu(tester, width: 840, height: 400, textScaler: 1.3);

    expect(tester.takeException(), isNull);
    expect(filas(tester), hasLength(4));
  });
}
