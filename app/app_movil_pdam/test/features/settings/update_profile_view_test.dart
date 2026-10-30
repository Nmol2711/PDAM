import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
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
import 'package:app_movil_pdam/features/settings/presentation/views/update_profile_view.dart';
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
  Either<Failures, AccountUpdateResult>? actualizacion;

  AccountUpdate? ultimaActualizacion;
  int llamadasPerfil = 0;
  int llamadasActualizacion = 0;

  /// Permite observar los estados de carga y de envío en curso.
  Completer<void>? blockerPerfil;
  Completer<void>? blockerActualizacion;

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
  ) async {
    llamadasActualizacion++;
    ultimaActualizacion = update;
    final espera = blockerActualizacion;
    if (espera != null) {
      await espera.future;
      blockerActualizacion = null;
    }
    return actualizacion ?? Right(AccountUpdateResult(profile: _perfil));
  }

  @override
  Future<Either<Failures, bool>> deleteAccount(String password) async =>
      Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, UserProfile?>> cachedProfile() async =>
      const Right(null);
}

class _FakeAuthTokenRepositories implements AuthTokenRepositories {
  bool fallarAlGuardar = false;
  int guardados = 0;
  String? tokenGuardado;

  @override
  Future<Either<Failures, AuthToken>> cacheToken(
    String token, {
    String typeToken = 'Bearer',
  }) async {
    if (fallarAlGuardar) {
      return Left(ServerFailures('almacenamiento no disponible'));
    }
    guardados++;
    tokenGuardado = token;
    return Right(AuthToken(token: token, typeToken: typeToken));
  }

  @override
  Future<Either<Failures, void>> deleteToken() async => const Right(null);

  @override
  Future<Either<Failures, AuthToken>> getToken() async =>
      Left(ServerFailures('sin token'));
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

class _FakePendingDeletionStore implements PendingDeletionStore {
  @override
  Future<void> markPending() async {}

  @override
  Future<bool> isPending() async => false;

  @override
  Future<void> clear() async {}
}

class _FakeUserRepository implements UserRepositories {
  User usuario = User(id: 1, email: 'user@x.com');

  @override
  Future<Either<Failures, User>> currentUser() async => Right(usuario);

  @override
  Future<Either<Failures, User>> login(String email, String password) async =>
      Right(usuario);

  @override
  Future<Either<Failures, User>> register(
    String email,
    String password,
    String confirmPassword,
  ) async => Right(usuario);
}

class _Harness {
  final _FakeAccountRepository repo;
  final _FakeAuthTokenRepositories tokenRepo;
  final AccountBloc accountBloc;
  final AuthBloc authBloc;
  final GoRouter router;

  _Harness({
    required this.repo,
    required this.tokenRepo,
    required this.accountBloc,
    required this.authBloc,
    required this.router,
  });
}

/// RF-09 a RF-15: formulario de actualización de perfil.
///
/// El correo se precarga desde el servidor o desde la caché real; las
/// validaciones de cliente se muestran todas a la vez junto a su campo y sin
/// petición; el servidor decide el duplicado; cancelar no aplica nada; sin
/// conexión se conserva lo escrito y se avisa; el éxito guarda el token nuevo
/// y vuelve al menú.
void main() {
  Future<_Harness> pumpForm(
    WidgetTester tester, {
    _FakeAccountRepository? repo,
    _FakeAuthTokenRepositories? tokenRepo,
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

    final fakeRepo = repo ?? _FakeAccountRepository();
    final fakeToken = tokenRepo ?? _FakeAuthTokenRepositories();
    final accountBloc = AccountBloc(
      getProfileUc: GetProfileUc(repository: fakeRepo),
      updateProfileUc: UpdateProfileUc(repository: fakeRepo),
      deleteAccountUc: DeleteAccountUc(repository: fakeRepo),
      registerTokenUc: RegisterTokenUc(repository: fakeToken),
      accountLocalCleaner: _FakeCleaner(),
      sessionEvents: eventos,
      authStates: authBloc.stream,
    );
    addTearDown(accountBloc.close);

    final router = GoRouter(
      initialLocation: '/settings',
      routes: <RouteBase>[
        GoRoute(
          path: '/settings',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/settings/update'),
                child: const Text('Menú de configuración'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/update',
          builder: (context, state) => const UpdateProfileView(),
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

    await tester.tap(find.text('Menú de configuración'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    return _Harness(
      repo: fakeRepo,
      tokenRepo: fakeToken,
      accountBloc: accountBloc,
      authBloc: authBloc,
      router: router,
    );
  }

  TextField campo(WidgetTester tester, String clave) =>
      tester.widget<TextField>(find.byKey(Key(clave)));

  Future<void> escribir(
    WidgetTester tester, {
    String? correo,
    String? password,
    String? confirmacion,
  }) async {
    if (correo != null) {
      await tester.enterText(
        find.byKey(const Key('update_profile_email')),
        correo,
      );
    }
    if (password != null) {
      await tester.enterText(
        find.byKey(const Key('update_profile_password')),
        password,
      );
    }
    if (confirmacion != null) {
      await tester.enterText(
        find.byKey(const Key('update_profile_confirmation')),
        confirmacion,
      );
    }
    await tester.pump();
  }

  Future<void> guardar(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('update_profile_save')));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('RF-09: precarga el correo del servidor y deja las contraseñas '
      'vacías', (tester) async {
    final h = await pumpForm(tester);

    expect(find.byType(UpdateProfileView), findsOneWidget);
    expect(
      campo(tester, 'update_profile_email').controller?.text,
      'user@x.com',
    );
    expect(campo(tester, 'update_profile_password').controller?.text, isEmpty);
    expect(
      campo(tester, 'update_profile_confirmation').controller?.text,
      isEmpty,
    );
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña nueva'), findsOneWidget);
    expect(find.text('Confirmar contraseña nueva'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(h.repo.llamadasPerfil, 1);

    // RF-09: el formulario solo pide correo y contraseña nueva; no hay campos
    // de contraseña actual, nombre visible ni foto de perfil.
    expect(find.text('Contraseña actual'), findsNothing);
    expect(find.text('Nombre'), findsNothing);
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Foto'), findsNothing);
  });

  testWidgets('RF-09: sin conexión precarga el correo del perfil cacheado real '
      'y avisa', (tester) async {
    final repo = _FakeAccountRepository()
      ..perfil = const Right(
        ProfileSnapshot(
          profile: UserProfile(email: 'cache@x.com', isActive: true),
          desdeCache: true,
        ),
      );

    await pumpForm(tester, repo: repo);

    expect(
      campo(tester, 'update_profile_email').controller?.text,
      'cache@x.com',
    );
    expect(find.text(MensajesCuenta.datosGuardados), findsOneWidget);
  });

  testWidgets(
    'RF-09: sin perfil cacheado el correo queda vacío y sin relleno',
    (tester) async {
      final repo = _FakeAccountRepository()
        ..perfil = Left(
          NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado),
        );

      await pumpForm(tester, repo: repo);

      expect(campo(tester, 'update_profile_email').controller?.text, isEmpty);
      expect(find.text(MensajesCuenta.sinPerfilCacheado), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    },
  );

  testWidgets('RF-11 fila 1: correo vacío muestra el error junto al campo y no '
      'envía petición', (tester) async {
    final h = await pumpForm(tester);

    await escribir(tester, correo: '');
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_email')),
        matching: find.text(MensajesCuenta.correoObligatorio),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasActualizacion, 0);
    expect(find.byType(UpdateProfileView), findsOneWidget);
  });

  testWidgets('RF-11 fila 2: correo con formato inválido', (tester) async {
    final h = await pumpForm(tester);

    await escribir(tester, correo: 'mal@correo');
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_email')),
        matching: find.text(MensajesCuenta.correoInvalido),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasActualizacion, 0);
    // Lo escrito se conserva para corregirlo sin volver a teclearlo.
    expect(
      campo(tester, 'update_profile_email').controller?.text,
      'mal@correo',
    );
  });

  testWidgets('RF-11 fila 3: sin cambios muestra el aviso del formulario', (
    tester,
  ) async {
    final h = await pumpForm(tester);

    await guardar(tester);

    expect(find.text(MensajesCuenta.sinCambios), findsOneWidget);
    expect(h.repo.llamadasActualizacion, 0);
    expect(find.byType(UpdateProfileView), findsOneWidget);
  });

  testWidgets('RF-11 fila 4: contraseña rellena sin confirmación', (
    tester,
  ) async {
    final h = await pumpForm(tester);

    await escribir(tester, password: 'unaClaveLarga');
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_confirmation')),
        matching: find.text(MensajesCuenta.confirmacionObligatoria),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasActualizacion, 0);
    expect(
      campo(tester, 'update_profile_password').controller?.text,
      'unaClaveLarga',
    );
  });

  testWidgets('RF-11 fila 5: confirmación rellena sin contraseña nueva', (
    tester,
  ) async {
    final h = await pumpForm(tester);

    await escribir(tester, confirmacion: 'unaClaveLarga');
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_password')),
        matching: find.text(MensajesCuenta.passwordNuevaObligatoria),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasActualizacion, 0);
    expect(
      campo(tester, 'update_profile_confirmation').controller?.text,
      'unaClaveLarga',
    );
  });

  testWidgets('RF-11 fila 6: contraseñas distintas', (tester) async {
    final h = await pumpForm(tester);

    await escribir(
      tester,
      password: 'unaClaveLarga',
      confirmacion: 'otraClaveLarga',
    );
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_confirmation')),
        matching: find.text(MensajesCuenta.passwordsNoCoinciden),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasActualizacion, 0);
    expect(
      campo(tester, 'update_profile_password').controller?.text,
      'unaClaveLarga',
    );
    expect(
      campo(tester, 'update_profile_confirmation').controller?.text,
      'otraClaveLarga',
    );
  });

  testWidgets('RF-11 fila 7: contraseña de menos de 8 caracteres', (
    tester,
  ) async {
    final h = await pumpForm(tester);

    await escribir(tester, password: 'corta12', confirmacion: 'corta12');
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_password')),
        matching: find.text(MensajesCuenta.passwordCorta),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasActualizacion, 0);
    expect(
      campo(tester, 'update_profile_password').controller?.text,
      'corta12',
    );
    expect(
      campo(tester, 'update_profile_confirmation').controller?.text,
      'corta12',
    );
  });

  testWidgets('RF-11 fila 8: contraseña de más de 72 bytes', (tester) async {
    final h = await pumpForm(tester);
    final larga = 'a' * 73;

    await escribir(tester, password: larga, confirmacion: larga);
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_password')),
        matching: find.text(MensajesCuenta.passwordLarga),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasActualizacion, 0);
    expect(campo(tester, 'update_profile_password').controller?.text, larga);
    expect(
      campo(tester, 'update_profile_confirmation').controller?.text,
      larga,
    );
  });

  testWidgets('RF-11 fila 9: solo cambia la contraseña', (tester) async {
    final h = await pumpForm(tester);

    await escribir(
      tester,
      password: 'unaClaveLarga',
      confirmacion: 'unaClaveLarga',
    );
    await guardar(tester);

    expect(h.repo.llamadasActualizacion, 1);
    expect(h.repo.ultimaActualizacion?.correo, isNull);
    expect(h.repo.ultimaActualizacion?.passwordNueva, 'unaClaveLarga');
    expect(find.byType(UpdateProfileView), findsNothing);
  });

  testWidgets('RF-11 fila 10: solo cambia el correo', (tester) async {
    final h = await pumpForm(tester);

    await escribir(tester, correo: 'nuevo@x.com');
    await guardar(tester);

    expect(h.repo.llamadasActualizacion, 1);
    expect(h.repo.ultimaActualizacion?.correo, 'nuevo@x.com');
    expect(h.repo.ultimaActualizacion?.passwordNueva, isNull);
  });

  testWidgets('RF-11 fila 11: correo nuevo con contraseña sin confirmar no '
      'aplica el correo', (tester) async {
    final h = await pumpForm(tester);

    await escribir(tester, correo: 'nuevo@x.com', password: 'unaClaveLarga');
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_confirmation')),
        matching: find.text(MensajesCuenta.confirmacionObligatoria),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasActualizacion, 0);
    expect(
      campo(tester, 'update_profile_email').controller?.text,
      'nuevo@x.com',
    );
    expect(
      campo(tester, 'update_profile_password').controller?.text,
      'unaClaveLarga',
    );
  });

  testWidgets('RF-11 fila 12: correo nuevo con confirmación sin contraseña', (
    tester,
  ) async {
    final h = await pumpForm(tester);

    await escribir(
      tester,
      correo: 'nuevo@x.com',
      confirmacion: 'unaClaveLarga',
    );
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_password')),
        matching: find.text(MensajesCuenta.passwordNuevaObligatoria),
      ),
      findsOneWidget,
    );
    expect(h.repo.llamadasActualizacion, 0);
    expect(
      campo(tester, 'update_profile_email').controller?.text,
      'nuevo@x.com',
    );
    expect(
      campo(tester, 'update_profile_confirmation').controller?.text,
      'unaClaveLarga',
    );
  });

  testWidgets('RF-11 fila 13: cambian correo y contraseña a la vez', (
    tester,
  ) async {
    final h = await pumpForm(tester);

    await escribir(
      tester,
      correo: '  Nuevo@X.com ',
      password: 'unaClaveLarga',
      confirmacion: 'unaClaveLarga',
    );
    await guardar(tester);

    expect(h.repo.llamadasActualizacion, 1);
    expect(h.repo.ultimaActualizacion?.correo, 'nuevo@x.com');
    expect(h.repo.ultimaActualizacion?.passwordNueva, 'unaClaveLarga');
  });

  testWidgets('RF-11 fila 14: el correo ya registrado lo decide el servidor y '
      'se muestra junto al campo', (tester) async {
    final repo = _FakeAccountRepository()
      ..actualizacion = Left(
        AccountFailure(
          CodigosCuenta.emailAlreadyRegistered,
          'El correo electrónico ya está registrado.',
        ),
      );
    final h = await pumpForm(tester, repo: repo);

    await escribir(tester, correo: 'ocupado@x.com');
    await guardar(tester);

    expect(h.repo.llamadasActualizacion, 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_email')),
        matching: find.text('El correo electrónico ya está registrado.'),
      ),
      findsOneWidget,
    );
    expect(
      campo(tester, 'update_profile_email').controller?.text,
      'ocupado@x.com',
    );
    expect(find.byType(UpdateProfileView), findsOneWidget);
  });

  testWidgets('RF-11: invalid_email del servidor se muestra junto al campo de '
      'correo tras el envío', (tester) async {
    final repo = _FakeAccountRepository()
      ..actualizacion = Left(
        AccountFailure(
          CodigosCuenta.invalidEmail,
          MensajesCuenta.correoInvalido,
        ),
      );
    final h = await pumpForm(tester, repo: repo);

    await escribir(tester, correo: 'nuevo@x.com');
    await guardar(tester);

    expect(h.repo.llamadasActualizacion, 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_email')),
        matching: find.text(MensajesCuenta.correoInvalido),
      ),
      findsOneWidget,
    );
    expect(find.byType(UpdateProfileView), findsOneWidget);
  });

  testWidgets('RF-11: muestra a la vez todos los errores aplicables junto a su '
      'campo', (tester) async {
    final h = await pumpForm(tester);

    await escribir(tester, correo: '', password: 'unaClaveLarga');
    await guardar(tester);

    expect(find.text(MensajesCuenta.correoObligatorio), findsOneWidget);
    expect(find.text(MensajesCuenta.confirmacionObligatoria), findsOneWidget);
    expect(h.repo.llamadasActualizacion, 0);
    // La contraseña escrita sigue en su campo tras mostrar los errores.
    expect(
      campo(tester, 'update_profile_password').controller?.text,
      'unaClaveLarga',
    );
  });

  testWidgets('RNF-03: la precarga no muestra el spinner de Guardar', (
    tester,
  ) async {
    final repo = _FakeAccountRepository()..blockerPerfil = Completer<void>();
    // Si una aserción falla antes, la carga pendiente no debe bloquear el
    // cierre del BLoC al terminar la prueba.
    addTearDown(() {
      final espera = repo.blockerPerfil;
      if (espera != null && !espera.isCompleted) espera.complete();
    });

    await pumpForm(tester, repo: repo);

    // Solo se está consultando el perfil: el botón sigue en «Guardar», no
    // finge un envío, y los campos están deshabilitados mientras carga.
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(campo(tester, 'update_profile_email').enabled, isFalse);

    repo.blockerPerfil!.complete();
    await tester.pumpAndSettle();

    expect(campo(tester, 'update_profile_email').enabled, isTrue);
    expect(
      campo(tester, 'update_profile_email').controller?.text,
      'user@x.com',
    );
  });

  testWidgets('RNF-03: el spinner de Guardar aparece solo durante el envío', (
    tester,
  ) async {
    final repo = _FakeAccountRepository()
      ..blockerActualizacion = Completer<void>();
    addTearDown(() {
      final espera = repo.blockerActualizacion;
      if (espera != null && !espera.isCompleted) espera.complete();
    });
    await pumpForm(tester, repo: repo);

    await escribir(tester, correo: 'nuevo@x.com');
    await tester.tap(find.byKey(const Key('update_profile_save')));
    await tester.pump();

    expect(find.text('Guardar'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(campo(tester, 'update_profile_email').enabled, isFalse);

    repo.blockerActualizacion!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(UpdateProfileView), findsNothing);
  });

  testWidgets('RF-11: sin perfil cargado se valida primero el formulario', (
    tester,
  ) async {
    final repo = _FakeAccountRepository()
      ..perfil = Left(NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado));
    final h = await pumpForm(tester, repo: repo);

    // El correo está vacío: el error de cliente va junto al campo y no se
    // sustituye por el aviso de perfil ausente.
    await guardar(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('update_profile_email')),
        matching: find.text(MensajesCuenta.correoObligatorio),
      ),
      findsOneWidget,
    );
    expect(find.text(MensajesCuenta.sinPerfilCacheado), findsOneWidget);
    expect(h.repo.llamadasActualizacion, 0);
  });

  testWidgets('RF-11: sin perfil cargado y datos válidos se avisa de la falta '
      'de perfil sin enviar', (tester) async {
    final repo = _FakeAccountRepository()
      ..perfil = Left(NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado));
    final h = await pumpForm(tester, repo: repo);

    await escribir(
      tester,
      correo: 'nuevo@x.com',
      password: 'unaClaveLarga',
      confirmacion: 'unaClaveLarga',
    );
    await guardar(tester);

    expect(find.text(MensajesCuenta.sinPerfilCacheado), findsOneWidget);
    expect(h.repo.llamadasActualizacion, 0);
    expect(
      campo(tester, 'update_profile_email').controller?.text,
      'nuevo@x.com',
    );
  });

  testWidgets('RF-13: sin conexión no aplica nada, conserva lo escrito y '
      'avisa', (tester) async {
    final repo = _FakeAccountRepository()
      ..actualizacion = Left(
        ConnectivityRequiredFailures(MensajesCuenta.sinConexion),
      );
    final h = await pumpForm(tester, repo: repo);

    await escribir(tester, correo: 'nuevo@x.com');
    await guardar(tester);

    expect(find.text(MensajesCuenta.sinConexion), findsOneWidget);
    expect(
      campo(tester, 'update_profile_email').controller?.text,
      'nuevo@x.com',
    );
    expect(h.tokenRepo.guardados, 0);
    expect(find.byType(UpdateProfileView), findsOneWidget);
  });

  testWidgets('RF-10 y RF-14: el éxito guarda el token nuevo, refresca la '
      'identidad y vuelve al menú', (tester) async {
    final repo = _FakeAccountRepository()
      ..actualizacion = const Right(
        AccountUpdateResult(
          profile: UserProfile(email: 'nuevo@x.com', isActive: true),
          tokenNuevo: 'token-nuevo',
        ),
      );
    final h = await pumpForm(tester, repo: repo);

    await escribir(tester, correo: 'nuevo@x.com');
    await guardar(tester);
    await tester.pumpAndSettle();

    expect(h.tokenRepo.guardados, 1);
    expect(h.tokenRepo.tokenGuardado, 'token-nuevo');
    expect(h.accountBloc.state.profile?.email, 'nuevo@x.com');
    expect(find.byType(UpdateProfileView), findsNothing);
    expect(find.text('Menú de configuración'), findsOneWidget);
    // La confirmación queda visible al volver al menú (RF-10).
    expect(find.text(MensajesCuenta.datosActualizados), findsOneWidget);

    // RF-10: el saludo del panel se construye con la identidad de la sesión.
    final sesion = h.authBloc.state;
    expect(sesion, isA<AuthAuthenticated>());
    expect((sesion as AuthAuthenticated).user.email, 'nuevo@x.com');
  });

  testWidgets('RF-15: cancelar no aplica nada y vuelve al menú', (
    tester,
  ) async {
    final h = await pumpForm(tester);

    await escribir(tester, correo: 'nuevo@x.com', password: 'unaClaveLarga');
    await tester.tap(find.byKey(const Key('update_profile_cancel')));
    await tester.pumpAndSettle();

    expect(h.repo.llamadasActualizacion, 0);
    expect(h.tokenRepo.guardados, 0);
    expect(find.byType(UpdateProfileView), findsNothing);
    expect(find.text('Menú de configuración'), findsOneWidget);
    expect(h.accountBloc.state.profile?.email, 'user@x.com');
  });

  testWidgets(
    'RNF-02: a 320 puntos con texto al 130 % no hay desbordamientos',
    (tester) async {
      await pumpForm(tester, width: 320, height: 640, textScaler: 1.3);

      await escribir(
        tester,
        correo: 'mal@correo',
        password: 'corta',
        confirmacion: 'otra',
      );
      await guardar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(UpdateProfileView), findsOneWidget);
    },
  );

  testWidgets(
    'RNF-02: a 600 puntos con texto al 130 % no hay desbordamientos',
    (tester) async {
      await pumpForm(tester, width: 600, height: 800, textScaler: 1.3);

      await escribir(
        tester,
        correo: 'mal@correo',
        password: 'corta',
        confirmacion: 'otra',
      );
      await guardar(tester);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('RNF-02: a 840 puntos en horizontal no hay desbordamientos', (
    tester,
  ) async {
    await pumpForm(tester, width: 840, height: 400, textScaler: 1.3);

    await guardar(tester);

    expect(tester.takeException(), isNull);
  });
}
