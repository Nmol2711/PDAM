import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
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
import 'package:app_movil_pdam/features/settings/presentation/views/delete_account_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/profile_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/settings_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/update_profile_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/appearance_mode_dialog.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/delete_account_dialog.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/settings_menu_tile.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// RNF-02: las cuatro pantallas del menú y los diálogos de modo y de baja se
/// ven sin desbordamientos, sin recortes y sin desplazamiento horizontal en
/// 320, 600 y 840 puntos, en vertical y horizontal, con escalado 1.3.
void main() {
  /// RNF-02: comprueba que el texto indicado se pinta completo. Falla si el
  /// `Text` recorta con `TextOverflow` o `maxLines`, si el párrafo renderizado
  /// no coincide con el esperado o si no cabe en su caja.
  void comprobarTextoCompleto(WidgetTester tester, String esperado) {
    final textos = tester.widgetList<Text>(find.text(esperado)).toList();
    expect(textos, isNotEmpty, reason: 'no se encontró el texto «$esperado»');
    for (final texto in textos) {
      expect(texto.data, esperado);
      expect(
        texto.maxLines,
        isNull,
        reason: '«$esperado» limita sus líneas con maxLines',
      );
      expect(
        texto.overflow == null ||
            (texto.overflow != TextOverflow.ellipsis &&
                texto.overflow != TextOverflow.fade),
        isTrue,
        reason: '«$esperado» se recorta con ${texto.overflow}',
      );
      final parrafo = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byWidget(texto),
          matching: find.byType(RichText),
        ),
      );
      expect(parrafo.text.toPlainText(), esperado);
      expect(
        parrafo.didExceedMaxLines,
        isFalse,
        reason: '«$esperado» no cabe completo',
      );
    }
  }

  Future<_Harness> pumpApp(WidgetTester tester, {required Size size}) async {
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
          darkTheme: AppTheme.darkTheme,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _Harness(router);
  }

  Future<void> irA(WidgetTester tester, _Harness h, String ruta) async {
    h.router.go(ruta);
    await tester.pumpAndSettle();
  }

  Future<void> abrirModo(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Modo claro y oscuro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modo claro y oscuro'));
    await tester.pumpAndSettle();
  }

  Future<void> cerrarDialogo(WidgetTester tester) async {
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
  }

  Future<void> abrirBaja(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('delete_account_open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_account_open')));
    await tester.pumpAndSettle();
  }

  Future<void> comprobarPantallas(WidgetTester tester, _Harness h) async {
    // Menú: cuatro filas accionables y desplazamiento solo vertical.
    await irA(tester, h, '/settings');
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<Scrollable>(
            find.descendant(
              of: find.byKey(const Key('settings_scroll')),
              matching: find.byType(Scrollable),
            ),
          )
          .axisDirection,
      AxisDirection.down,
    );
    final filas = tester
        .widgetList<SettingsMenuTile>(find.byType(SettingsMenuTile))
        .toList();
    expect(filas, hasLength(4));
    expect(filas.every((fila) => fila.onTap != null), isTrue);
    for (final titulo in <String>[
      'Perfil',
      'Actualización de perfil',
      'Eliminación de cuenta',
      'Modo claro y oscuro',
    ]) {
      comprobarTextoCompleto(tester, titulo);
    }

    // Perfil: etiquetas legibles.
    await irA(tester, h, '/settings/profile');
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('profile_scroll')),
          )
          .scrollDirection,
      Axis.vertical,
    );
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Estado de la cuenta'), findsOneWidget);
    expect(find.text('user@x.com'), findsOneWidget);
    for (final etiqueta in <String>[
      'Correo electrónico',
      'Estado de la cuenta',
      'user@x.com',
      'Activa',
    ]) {
      comprobarTextoCompleto(tester, etiqueta);
    }

    // Actualización: acciones del formulario presentes y accionables.
    await irA(tester, h, '/settings/update');
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('update_profile_scroll')),
          )
          .scrollDirection,
      Axis.vertical,
    );
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    comprobarTextoCompleto(tester, 'Guardar');
    comprobarTextoCompleto(tester, 'Cancelar');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('update_profile_save')))
          .onPressed,
      isNotNull,
    );

    // Baja: advertencia, listado y acción accionable.
    await irA(tester, h, '/settings/delete');
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('delete_account_scroll')),
          )
          .scrollDirection,
      Axis.vertical,
    );
    expect(
      find.text('Esta acción es irreversible y no se puede deshacer.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('delete_account_open')), findsOneWidget);

    // Diálogo de modo: tres opciones accionables.
    await irA(tester, h, '/settings');
    await abrirModo(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppearanceModeDialog), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
    for (final etiqueta in <String>['Claro', 'Oscuro', 'Automático']) {
      comprobarTextoCompleto(tester, etiqueta);
    }
    for (final codigo in <String>['light', 'dark', 'system']) {
      final opcion = find.byKey(Key('appearance_mode_$codigo'));
      await tester.ensureVisible(opcion);
      expect(tester.widget<ListTile>(opcion).enabled, isTrue);
    }
    await cerrarDialogo(tester);

    // Diálogo de baja: textos, campo y acción deshabilitada sin contraseña.
    await irA(tester, h, '/settings/delete');
    await abrirBaja(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(DeleteAccountDialog), findsOneWidget);
    expect(
      find.text('Escribe tu contraseña actual para confirmar la eliminación.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('delete_account_password')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('delete_account_confirm')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('delete_account_password')),
      'claveActual',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('delete_account_confirm')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('delete_account_confirm')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('delete_account_cancel')));
    await tester.pumpAndSettle();
  }

  final combinaciones = <String, Size>{
    '320 vertical': const Size(320, 640),
    '320 horizontal': const Size(640, 320),
    '600 vertical': const Size(600, 800),
    '600 horizontal': const Size(800, 600),
    '840 vertical': const Size(840, 900),
    '840 horizontal': const Size(900, 840),
  };

  for (final entrada in combinaciones.entries) {
    testWidgets(
      'RNF-02: ${entrada.key} con escalado 1.3 sin recortes de texto',
      (tester) async {
        final h = await pumpApp(tester, size: entrada.value);
        await comprobarPantallas(tester, h);
      },
    );
  }
}
