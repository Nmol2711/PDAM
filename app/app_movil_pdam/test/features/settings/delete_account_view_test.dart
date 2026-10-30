import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/router/bloc_refresh_listenable.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/repository/account_repository.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/delete_account_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/get_profile_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/update_profile_uc.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
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
import 'package:app_movil_pdam/features/auth/presentation/views/login_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/delete_account_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/delete_account_dialog.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const UserProfile _perfil = UserProfile(email: 'user@x.com', isActive: true);

class _FakeAccountRepository implements AccountRepository {
  Either<Failures, ProfileSnapshot> perfil = const Right(
    ProfileSnapshot(profile: _perfil),
  );
  Either<Failures, bool>? baja;

  int llamadasPerfil = 0;
  int llamadasBaja = 0;
  String? ultimaPassword;
  Completer<void>? blockerPerfil;

  @override
  Future<Either<Failures, ProfileSnapshot>> getProfile() async {
    llamadasPerfil++;
    final espera = blockerPerfil;
    if (espera != null) {
      await espera.future;
      blockerPerfil = null;
    }
    return perfil;
  }

  @override
  Future<Either<Failures, AccountUpdateResult>> updateProfile(
    AccountUpdate update,
  ) async => Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, bool>> deleteAccount(String password) async {
    llamadasBaja++;
    ultimaPassword = password;
    return baja ?? const Right(true);
  }

  @override
  Future<Either<Failures, UserProfile?>> cachedProfile() async =>
      const Right(null);
}

class _FakeCleaner implements AccountLocalCleaner {
  AccountCleanupResult resultado = AccountCleanupResult.exito(
    pasosCompletados: AccountCleanupStep.values,
  );
  int llamadas = 0;
  String? correo;
  bool marcaPendiente = false;

  @override
  Future<AccountCleanupResult> limpiarTrasBaja({String? correo}) async {
    llamadas++;
    this.correo = correo;
    marcaPendiente = !resultado.exitoso;
    return resultado;
  }

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
  bool pendiente = false;

  @override
  Future<void> markPending() async => pendiente = true;

  @override
  Future<bool> isPending() async => pendiente;

  @override
  Future<void> clear() async => pendiente = false;
}

class _Harness {
  final _FakeAccountRepository repo;
  final _FakeCleaner cleaner;
  final _FakePendingDeletionStore store;
  final AccountBloc accountBloc;
  final AuthBloc authBloc;
  final GoRouter router;

  _Harness({
    required this.repo,
    required this.cleaner,
    required this.store,
    required this.accountBloc,
    required this.authBloc,
    required this.router,
  });
}

/// RF-16 a RF-21, RNF-02, RNF-06 y RNF-10: baja de cuenta desde la app.
///
/// La pantalla compone widgets y emite eventos; el diálogo destructivo exige la
/// contraseña actual y no permite confirmar con el campo vacío. La contraseña
/// no se muestra ni se persiste. Un fallo de la limpieza local conserva la marca
/// y cierra la sesión con el mensaje de RNF-10.
void main() {
  Future<_Harness> pumpDelete(
    WidgetTester tester, {
    _FakeAccountRepository? repo,
    _FakeCleaner? cleaner,
    _FakePendingDeletionStore? store,
    double width = 420,
    double height = 900,
    double textScaler = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final fakeStore = store ?? _FakePendingDeletionStore();
    final authBloc = AuthBloc(
      registerUc: RegisterUc(repository: _FakeUserRepository()),
      loginUc: LoginUc(repository: _FakeUserRepository()),
      currentUserUc: CurrentUserUc(repository: _FakeUserRepository()),
      pendingDeletionStore: fakeStore,
      sessionEvents: eventos,
      accountLocalCleaner: _FakeCleaner(),
      hayConexion: () async => true,
    );
    addTearDown(authBloc.close);
    authBloc.add(AuthCheckStatusRequested());
    await authBloc.stream.firstWhere((estado) => estado is AuthAuthenticated);

    final fakeRepo = repo ?? _FakeAccountRepository();
    final fakeCleaner = cleaner ?? _FakeCleaner();
    final accountBloc = AccountBloc(
      getProfileUc: GetProfileUc(repository: fakeRepo),
      updateProfileUc: UpdateProfileUc(repository: fakeRepo),
      deleteAccountUc: DeleteAccountUc(repository: fakeRepo),
      registerTokenUc: RegisterTokenUc(
        repository: _FakeAuthTokenRepositories(),
      ),
      accountLocalCleaner: fakeCleaner,
      sessionEvents: eventos,
      authStates: authBloc.stream,
    );
    addTearDown(accountBloc.close);

    final router = GoRouter(
      initialLocation: '/settings/delete',
      refreshListenable: BlocRefreshListenable(authBloc),
      redirect: (context, state) {
        final auth = context.read<AuthBloc>().state;
        if (auth is AuthAccountDeleted && state.matchedLocation != '/login') {
          return '/login';
        }
        return null;
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/settings/delete',
          builder: (context, state) => const DeleteAccountView(),
        ),
        GoRoute(path: '/login', builder: (context, state) => const LoginView()),
        GoRoute(
          path: '/home',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Inicio'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<AccountBloc>.value(value: accountBloc),
        ],
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    return _Harness(
      repo: fakeRepo,
      cleaner: fakeCleaner,
      store: fakeStore,
      accountBloc: accountBloc,
      authBloc: authBloc,
      router: router,
    );
  }

  Future<void> abrirDialogo(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('delete_account_open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_account_open')));
    await tester.pumpAndSettle();
  }

  Future<void> escribir(WidgetTester tester, String password) async {
    await tester.enterText(
      find.byKey(const Key('delete_account_password')),
      password,
    );
    await tester.pump();
  }

  Future<void> confirmar(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('delete_account_confirm')));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  FilledButton botonConfirmar(WidgetTester tester) => tester
      .widget<FilledButton>(find.byKey(const Key('delete_account_confirm')));

  testWidgets('RF-16: muestra la advertencia, el listado literal y la acción '
      'que abre el diálogo', (tester) async {
    await pumpDelete(tester);

    expect(find.text(MensajesCuenta.avisoIrreversible), findsOneWidget);
    expect(find.text(MensajesCuenta.datosEnRiesgo), findsOneWidget);
    expect(find.text(MensajesCuenta.eliminarMiCuenta), findsOneWidget);
    expect(find.byType(DeleteAccountDialog), findsNothing);
  });

  testWidgets('RF-16: el diálogo muestra los textos, el campo y la acción '
      'deshabilitada con el campo vacío', (tester) async {
    final h = await pumpDelete(tester);
    await abrirDialogo(tester);

    expect(find.byType(DeleteAccountDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DeleteAccountDialog),
        matching: find.text(MensajesCuenta.avisoIrreversible),
      ),
      findsOneWidget,
    );
    // RF-16: la confirmación destructiva enumera los datos que se pierden.
    expect(
      find.descendant(
        of: find.byType(DeleteAccountDialog),
        matching: find.text(MensajesCuenta.datosEnRiesgo),
      ),
      findsOneWidget,
    );
    expect(find.text(MensajesCuenta.indicacionPasswordActual), findsOneWidget);
    expect(find.text(MensajesCuenta.passwordActual), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('delete_account_confirm')),
        matching: find.text(MensajesCuenta.eliminarCuenta),
      ),
      findsOneWidget,
    );
    expect(botonConfirmar(tester).onPressed, isNull);

    await escribir(tester, 'claveActual');

    expect(botonConfirmar(tester).onPressed, isNotNull);
    // RNF-06: la contraseña reingresada no aparece como texto visible.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'claveActual',
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('delete_account_password')))
          .obscureText,
      isTrue,
    );
    expect(h.repo.llamadasBaja, 0);
  });

  testWidgets(
    'RF-17: cancelar deja la cuenta, los datos y la sesión intactos',
    (tester) async {
      final h = await pumpDelete(tester);
      await abrirDialogo(tester);
      await escribir(tester, 'claveActual');

      await tester.tap(find.byKey(const Key('delete_account_cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(DeleteAccountDialog), findsNothing);
      expect(h.repo.llamadasBaja, 0);
      expect(h.cleaner.llamadas, 0);
      expect(h.authBloc.state, isA<AuthAuthenticated>());
      expect(h.store.pendiente, isFalse);
    },
  );

  testWidgets('RNF-06: al cerrar el diálogo la contraseña reingresada se '
      'limpia', (tester) async {
    await pumpDelete(tester);
    await abrirDialogo(tester);
    await escribir(tester, 'claveActual');

    await tester.tap(find.byKey(const Key('delete_account_cancel')));
    await tester.pumpAndSettle();
    await abrirDialogo(tester);

    final campo = tester.widget<TextField>(
      find.byKey(const Key('delete_account_password')),
    );
    expect(campo.controller?.text, isEmpty);
  });

  testWidgets('RF-17: invalid_password se muestra junto al campo y no cierra '
      'el diálogo ni limpia nada', (tester) async {
    final repo = _FakeAccountRepository()
      ..baja = Left(
        AccountFailure(
          CodigosCuenta.invalidPassword,
          MensajesCuenta.passwordIncorrecta,
        ),
      );
    final h = await pumpDelete(tester, repo: repo);
    await abrirDialogo(tester);
    await escribir(tester, 'incorrecta');

    await confirmar(tester);

    expect(find.byType(DeleteAccountDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('delete_account_password')),
        matching: find.text(MensajesCuenta.passwordIncorrecta),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasBaja, 1);
    expect(h.cleaner.llamadas, 0);
    expect(h.authBloc.state, isA<AuthAuthenticated>());
    expect(h.store.pendiente, isFalse);
  });

  testWidgets('RF-20: sin conexión avisa, cierra el diálogo y no cambia nada', (
    tester,
  ) async {
    final repo = _FakeAccountRepository()
      ..baja = Left(ConnectivityRequiredFailures(MensajesCuenta.sinConexion));
    final h = await pumpDelete(tester, repo: repo);
    await abrirDialogo(tester);
    await escribir(tester, 'claveActual');

    await confirmar(tester);

    expect(find.byType(DeleteAccountDialog), findsNothing);
    expect(find.text(MensajesCuenta.sinConexion), findsOneWidget);
    expect(h.cleaner.llamadas, 0);
    expect(h.authBloc.state, isA<AuthAuthenticated>());
    expect(h.store.pendiente, isFalse);
  });

  testWidgets('RF-21: el error del servidor ofrece un reintento real', (
    tester,
  ) async {
    final repo = _FakeAccountRepository()
      ..baja = Left(
        AccountFailure(CodigosCuenta.serverError, MensajesCuenta.errorServidor),
      );
    final h = await pumpDelete(tester, repo: repo);
    await abrirDialogo(tester);
    await escribir(tester, 'claveActual');

    await confirmar(tester);

    expect(find.byType(DeleteAccountDialog), findsNothing);
    expect(find.text(MensajesCuenta.errorServidor), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(h.cleaner.llamadas, 0);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.byType(DeleteAccountDialog), findsOneWidget);

    repo.baja = const Right(true);
    await escribir(tester, 'claveActual');
    await confirmar(tester);

    expect(h.repo.llamadasBaja, 2);
    expect(h.cleaner.llamadas, 1);
    expect(h.authBloc.state, isA<AuthAccountDeleted>());
  });

  testWidgets('RF-18: el éxito limpia, cierra la sesión y lleva al login con '
      'el mensaje definitivo', (tester) async {
    final h = await pumpDelete(tester);
    await abrirDialogo(tester);
    await escribir(tester, 'claveActual');

    await confirmar(tester);

    expect(h.repo.llamadasBaja, 1);
    expect(h.repo.ultimaPassword, 'claveActual');
    expect(h.cleaner.llamadas, 1);
    expect(h.cleaner.correo, isNull);
    expect(h.store.pendiente, isFalse);

    final sesion = h.authBloc.state;
    expect(sesion, isA<AuthAccountDeleted>());
    expect(
      (sesion as AuthAccountDeleted).message,
      MensajesCuenta.cuentaEliminada,
    );
    expect(find.byType(LoginView), findsOneWidget);
    expect(find.text(MensajesCuenta.cuentaEliminada), findsOneWidget);
  });

  testWidgets('RNF-10: si la limpieza falla, la marca sobrevive y la sesión se '
      'cierra con el aviso de protección', (tester) async {
    final cleaner = _FakeCleaner()
      ..resultado = const AccountCleanupResult.fallo(
        pasoFallido: AccountCleanupStep.token,
        pasosCompletados: <AccountCleanupStep>[AccountCleanupStep.marca],
      );
    final h = await pumpDelete(tester, cleaner: cleaner);
    await abrirDialogo(tester);
    await escribir(tester, 'claveActual');

    await confirmar(tester);

    expect(h.cleaner.llamadas, 1);
    expect(h.cleaner.marcaPendiente, isTrue);
    final sesion = h.authBloc.state;
    expect(sesion, isA<AuthAccountDeleted>());
    expect(
      (sesion as AuthAccountDeleted).message,
      MensajesCuenta.limpiezaLocalFallida,
    );
    expect(find.byType(LoginView), findsOneWidget);
    expect(find.text(MensajesCuenta.limpiezaLocalFallida), findsOneWidget);
  });

  testWidgets(
    'RNF-03: la precarga del perfil no deshabilita la confirmación ni '
    'apaga el indicador de la baja',
    (tester) async {
      final repo = _FakeAccountRepository()..blockerPerfil = Completer<void>();
      addTearDown(() {
        final espera = repo.blockerPerfil;
        if (espera != null && !espera.isCompleted) espera.complete();
      });
      final h = await pumpDelete(tester, repo: repo);
      await abrirDialogo(tester);

      h.accountBloc.add(const ProfileRequested());
      await h.accountBloc.stream.firstWhere(
        (estado) => estado.isLoadingProfile,
      );

      await escribir(tester, 'claveActual');

      // La precarga no se solapa con el indicador de la baja: el botón sigue
      // habilitado por contraseña, no por `isLoadingProfile`.
      expect(botonConfirmar(tester).onPressed, isNotNull);

      repo.blockerPerfil!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'RNF-02: a 320 puntos con texto al 130 % no hay desbordamientos',
    (tester) async {
      await pumpDelete(tester, width: 320, height: 640, textScaler: 1.3);
      await abrirDialogo(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DeleteAccountDialog), findsOneWidget);

      // RF-16 + RNF-02: con la advertencia, el listado de datos y el campo el
      // contenido del diálogo sigue siendo desplazable en vertical.
      final contenido = find.descendant(
        of: find.byType(DeleteAccountDialog),
        matching: find.byType(SingleChildScrollView),
      );
      expect(contenido, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(contenido).scrollDirection,
        Axis.vertical,
      );
      await tester.drag(contenido, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await escribir(tester, 'claveActual');
      expect(botonConfirmar(tester).onPressed, isNotNull);
    },
  );
}
