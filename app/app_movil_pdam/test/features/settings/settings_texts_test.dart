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
import 'package:app_movil_pdam/features/settings/presentation/views/profile_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/settings_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/views/update_profile_view.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/appearance_mode_dialog.dart';
import 'package:app_movil_pdam/features/settings/presentation/widgets/settings_menu_tile.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// RNF-01: recorrido de los textos visibles nuevos del menú y de la gestión de
/// usuario. Todos están en español, sin emojis, y cada mensaje de error nombra
/// el campo afectado y la acción que debe realizar el usuario.
///
/// El catálogo (`MensajesCuenta`) es la fuente de los mensajes y sus literales
/// se declaran una sola vez en `_literalesPermitidos`: cualquier texto visible
/// que no sea un literal del catálogo o una etiqueta declarada de estas
/// pantallas hace fallar el recorrido, incluidas las traducciones al inglés.
const UserProfile _perfil = UserProfile(email: 'user@x.com', isActive: true);

/// Bloques Unicode de emojis y de sus selectores o uniones.
final RegExp _emojis = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
  unicode: true,
);

/// Literales exactos admitidos en las pantallas nuevas (RNF-01).
///
/// Cualquier texto visible fuera de esta lista hace fallar el recorrido,
/// incluidas las traducciones al inglés que una heurística de palabras dejaría
/// pasar («Saved», «Your data was updated successfully»). Un texto nuevo debe
/// declararse aquí de forma consciente, junto a su pantalla.
final Set<String> _literalesPermitidos = <String>{
  // Títulos, etiquetas y acciones de las pantallas.
  'Configuración',
  'Perfil',
  'Actualización de perfil',
  'Eliminación de cuenta',
  'Modo claro y oscuro',
  'Modo de apariencia',
  'Correo electrónico',
  'Estado de la cuenta',
  'Contraseña nueva',
  'Confirmar contraseña nueva',
  'Guardar',
  'Cancelar',
  'Reintentar',
  'Claro',
  'Oscuro',
  'Automático',
  // Login: el aviso de cuenta eliminada se muestra en esa pantalla.
  'Bienvenido a PDAM',
  'Gestión nutricional y dispensador inteligente',
  'Correo Electrónico',
  'Contraseña',
  'Iniciar Sesión',
  '¿No tienes una cuenta? Regístrate aquí',
  // Datos reales del perfil usado en la prueba.
  _perfil.email,
  _perfil.inicial,
  // Catálogo de mensajes de la cuenta.
  MensajesCuenta.correoObligatorio,
  MensajesCuenta.correoInvalido,
  MensajesCuenta.passwordNuevaObligatoria,
  MensajesCuenta.confirmacionObligatoria,
  MensajesCuenta.passwordsNoCoinciden,
  MensajesCuenta.passwordCorta,
  MensajesCuenta.passwordLarga,
  MensajesCuenta.sinCambios,
  MensajesCuenta.estadoActiva,
  MensajesCuenta.estadoInactiva,
  MensajesCuenta.sesionInvalida,
  MensajesCuenta.errorServidor,
  MensajesCuenta.sinConexion,
  MensajesCuenta.sinPerfilCacheado,
  MensajesCuenta.datosGuardados,
  MensajesCuenta.datosActualizados,
  MensajesCuenta.credencialesInvalidas,
  MensajesCuenta.cuentaEliminada,
  MensajesCuenta.limpiezaLocalFallida,
  MensajesCuenta.avisoIrreversible,
  MensajesCuenta.datosEnRiesgo,
  MensajesCuenta.eliminarMiCuenta,
  MensajesCuenta.indicacionPasswordActual,
  MensajesCuenta.passwordActual,
  MensajesCuenta.eliminarCuenta,
  MensajesCuenta.passwordIncorrecta,
  MensajesCuenta.passwordRegistroObligatoria,
  'El correo electrónico ya está registrado.',
};

/// Cualquier letra latina, acentuada o eñe.
final RegExp _letras = RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]');

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
  Either<Failures, ProfileSnapshot> perfil = const Right(
    ProfileSnapshot(profile: _perfil),
  );

  @override
  Future<Either<Failures, ProfileSnapshot>> getProfile() async => perfil;

  @override
  Future<Either<Failures, AccountUpdateResult>> updateProfile(
    AccountUpdate update,
  ) async => Right(AccountUpdateResult(profile: _perfil));

  @override
  Future<Either<Failures, bool>> deleteAccount(String password) async =>
      Left(ServerFailures('no usado'));

  @override
  Future<Either<Failures, UserProfile?>> cachedProfile() async =>
      const Right(null);
}

class _FakeUserRepository implements UserRepositories {
  @override
  Future<Either<Failures, User>> currentUser() async =>
      Left(ServerFailures('sin sesión'));

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

class _FakeCleaner implements AccountLocalCleaner {
  @override
  Future<AccountCleanupResult> limpiarTrasBaja({String? correo}) async =>
      AccountCleanupResult.exito(pasosCompletados: AccountCleanupStep.values);

  @override
  Future<AccountCleanupResult?> limpiarSiPendiente() async => null;

  @override
  Future<void> limpiarPorSesionExpirada() async {}
}

void _verificarTextoVisible(String texto) {
  expect(texto.trim(), isNotEmpty, reason: 'Hay un texto visible vacío');
  expect(
    _emojis.hasMatch(texto),
    isFalse,
    reason: 'El texto visible «$texto» lleva un emoji (RNF-01)',
  );
  expect(
    _literalesPermitidos,
    contains(texto),
    reason:
        'El texto visible «$texto» no es un literal del catálogo ni una '
        'etiqueta declarada de las pantallas nuevas (RNF-01)',
  );
  expect(
    _letras.hasMatch(texto),
    isTrue,
    reason: 'El texto visible «$texto» no contiene ninguna letra',
  );
}

/// Verifica un mensaje de error: español, sin emojis, campo y acción.
void _verificarMensaje(
  String mensaje, {
  required String accion,
  String? campo,
}) {
  _verificarTextoVisible(mensaje);
  final minusculas = mensaje.toLowerCase();
  if (campo != null) {
    expect(
      minusculas,
      contains(campo),
      reason: '«$mensaje» no nombra el campo afectado ($campo)',
    );
  }
  expect(
    minusculas,
    contains(accion),
    reason: '«$mensaje» no indica la acción para continuar ($accion)',
  );
}

/// Textos realmente pintados por el árbol de widgets.
Set<String> _textosVisibles(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data)
    .whereType<String>()
    .where((texto) => texto.trim().isNotEmpty)
    .toSet();

void _verificarTextosVisibles(WidgetTester tester) {
  final textos = _textosVisibles(tester);
  expect(textos, isNotEmpty, reason: 'La pantalla no pintó ningún texto');
  for (final texto in textos) {
    _verificarTextoVisible(texto);
  }
}

void main() {
  Future<void> ajustarVentana(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  AccountBloc crearBlocCuenta(
    _FakeAccountRepository repo, {
    SessionEvents? eventos,
    Stream<AuthState>? authStates,
  }) {
    final canal = eventos ?? SessionEvents();
    if (eventos == null) addTearDown(canal.dispose);
    final bloc = AccountBloc(
      getProfileUc: GetProfileUc(repository: repo),
      updateProfileUc: UpdateProfileUc(repository: repo),
      deleteAccountUc: DeleteAccountUc(repository: repo),
      registerTokenUc: RegisterTokenUc(
        repository: _FakeAuthTokenRepositories(),
      ),
      accountLocalCleaner: _FakeCleaner(),
      sessionEvents: canal,
      authStates: authStates,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  AuthBloc crearBlocSesion(SessionEvents eventos) {
    final bloc = AuthBloc(
      registerUc: RegisterUc(repository: _FakeUserRepository()),
      loginUc: LoginUc(repository: _FakeUserRepository()),
      currentUserUc: CurrentUserUc(repository: _FakeUserRepository()),
      pendingDeletionStore: _FakePendingDeletionStore(),
      sessionEvents: eventos,
      accountLocalCleaner: _FakeCleaner(),
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> montarMenu(WidgetTester tester) async {
    await ajustarVentana(tester);
    // Desmonta el árbol anterior para que las vistas vuelvan a ejecutar su
    // `initState` y emitan sus eventos al BLoC recién creado.
    await tester.pumpWidget(const SizedBox.shrink());
    final themeCubit = ThemeCubit(storageService: _FakeStorage());
    addTearDown(themeCubit.close);
    await tester.pumpWidget(
      BlocProvider<ThemeCubit>.value(
        value: themeCubit,
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) => MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: const SettingsView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> montarConBloc(
    WidgetTester tester,
    Widget vista,
    _FakeAccountRepository repo,
  ) async {
    await ajustarVentana(tester);
    // Desmonta el árbol anterior para que las vistas vuelvan a ejecutar su
    // `initState` y emitan sus eventos al BLoC recién creado.
    await tester.pumpWidget(const SizedBox.shrink());
    final bloc = crearBlocCuenta(repo);
    await tester.pumpWidget(
      BlocProvider<AccountBloc>.value(
        value: bloc,
        child: MaterialApp(theme: AppTheme.lightTheme, home: vista),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Monta el formulario con el enrutador y la sesión que exige el éxito de
  /// RF-10: la confirmación se muestra y la vista vuelve al menú.
  Future<void> montarFormularioActualizacion(
    WidgetTester tester,
    _FakeAccountRepository repo,
  ) async {
    await ajustarVentana(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final authBloc = crearBlocSesion(eventos);
    final accountBloc = crearBlocCuenta(
      repo,
      eventos: eventos,
      authStates: authBloc.stream,
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: '/update',
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
        ),
      ),
    );
    // Se entra al formulario desde el menú: así el regreso del éxito tiene
    // una ruta anterior a la que volver (RF-10).
    router.push('/update');
    await tester.pumpAndSettle();
  }

  /// Monta el login con el aviso de cuenta eliminada del catálogo (RF-18).
  Future<void> montarLoginConCuentaEliminada(WidgetTester tester) async {
    await ajustarVentana(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final authBloc = crearBlocSesion(eventos);
    eventos.notify(const SessionEvent.cuentaEliminada());
    await authBloc.stream.firstWhere((estado) => estado is AuthAccountDeleted);

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp(theme: AppTheme.lightTheme, home: const LoginView()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'recorre el menú, el perfil, la actualización y la baja sin emojis y en '
    'español',
    (tester) async {
      // Menú y diálogo de apariencia.
      await montarMenu(tester);
      _verificarTextosVisibles(tester);
      // La cuarta fila abre el diálogo de apariencia (RF-24).
      await tester.tap(find.byType(SettingsMenuTile).last);
      await tester.pumpAndSettle();
      expect(
        find.byType(AppearanceModeDialog),
        findsOneWidget,
        reason: 'La cuarta fila debe abrir el diálogo de apariencia',
      );
      _verificarTextosVisibles(tester);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      // Perfil con datos reales.
      await montarConBloc(
        tester,
        const ProfileView(),
        _FakeAccountRepository(),
      );
      _verificarTextosVisibles(tester);

      // Perfil desde la caché local: aviso de datos guardados (RF-07).
      final desdeCache = _FakeAccountRepository()
        ..perfil = const Right(
          ProfileSnapshot(profile: _perfil, desdeCache: true),
        );
      await montarConBloc(tester, const ProfileView(), desdeCache);
      _verificarTextosVisibles(tester);
      expect(find.text(MensajesCuenta.datosGuardados), findsOneWidget);

      // Perfil sin datos locales: mensaje de RF-08 con acción de reintento.
      final sinCache = _FakeAccountRepository()
        ..perfil = Left(
          NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado),
        );
      await montarConBloc(tester, const ProfileView(), sinCache);
      _verificarTextosVisibles(tester);
      expect(find.text(MensajesCuenta.sinPerfilCacheado), findsOneWidget);

      // Actualización de perfil con errores de cliente simultáneos.
      final formulario = _FakeAccountRepository();
      await montarConBloc(tester, const UpdateProfileView(), formulario);
      _verificarTextosVisibles(tester);
      await tester.enterText(
        find.byKey(const Key('update_profile_email')),
        'mal@correo',
      );
      await tester.enterText(
        find.byKey(const Key('update_profile_password')),
        'corta',
      );
      await tester.enterText(
        find.byKey(const Key('update_profile_confirmation')),
        'corta',
      );
      await tester.tap(find.byKey(const Key('update_profile_save')));
      await tester.pumpAndSettle();
      _verificarTextosVisibles(tester);
      expect(find.text(MensajesCuenta.correoInvalido), findsOneWidget);
      expect(find.text(MensajesCuenta.passwordCorta), findsOneWidget);

      // Actualización válida: confirmación del catálogo y regreso al menú.
      await montarFormularioActualizacion(tester, _FakeAccountRepository());
      _verificarTextosVisibles(tester);
      await tester.enterText(
        find.byKey(const Key('update_profile_password')),
        '12345678',
      );
      await tester.enterText(
        find.byKey(const Key('update_profile_confirmation')),
        '12345678',
      );
      await tester.tap(find.byKey(const Key('update_profile_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      _verificarTextosVisibles(tester);
      expect(find.text(MensajesCuenta.datosActualizados), findsOneWidget);
      await tester.pumpAndSettle();

      // Baja de cuenta y diálogo destructivo.
      await montarConBloc(
        tester,
        const DeleteAccountView(),
        _FakeAccountRepository(),
      );
      _verificarTextosVisibles(tester);
      expect(find.text(MensajesCuenta.avisoIrreversible), findsOneWidget);
      expect(find.text(MensajesCuenta.datosEnRiesgo), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete_account_open')));
      await tester.pumpAndSettle();
      _verificarTextosVisibles(tester);
      expect(
        find.text(MensajesCuenta.indicacionPasswordActual),
        findsOneWidget,
      );
      expect(find.text(MensajesCuenta.passwordActual), findsOneWidget);

      // Login con la cuenta eliminada: confirmación del catálogo (RF-18).
      await montarLoginConCuentaEliminada(tester);
      _verificarTextosVisibles(tester);
      expect(find.text(MensajesCuenta.cuentaEliminada), findsOneWidget);
    },
  );

  test('cada mensaje de error nombra el campo y la acción', () {
    final mensajes = <({String texto, String? campo, String accion})>[
      (
        texto: MensajesCuenta.correoObligatorio,
        campo: 'correo',
        accion: 'obligatorio',
      ),
      (
        texto: MensajesCuenta.correoInvalido,
        campo: 'correo',
        accion: 'introduce',
      ),
      (
        texto: MensajesCuenta.passwordNuevaObligatoria,
        campo: 'contraseña',
        accion: 'escribe',
      ),
      (
        texto: MensajesCuenta.confirmacionObligatoria,
        campo: 'contraseña',
        accion: 'confirma',
      ),
      (
        texto: MensajesCuenta.passwordsNoCoinciden,
        campo: 'contraseña',
        accion: 'no coinciden',
      ),
      (
        texto: MensajesCuenta.passwordCorta,
        campo: 'contraseña',
        accion: 'debe tener',
      ),
      (
        texto: MensajesCuenta.passwordLarga,
        campo: 'contraseña',
        accion: 'demasiado larga',
      ),
      (texto: MensajesCuenta.sinCambios, campo: 'correo', accion: 'escribe'),
      (
        texto: MensajesCuenta.porCodigo[CodigosCuenta.emailAlreadyRegistered]!,
        campo: 'correo',
        accion: 'ya está registrado',
      ),
      (
        texto: MensajesCuenta.passwordIncorrecta,
        campo: 'contraseña',
        accion: 'no es correcta',
      ),
      (
        texto: MensajesCuenta.passwordRegistroObligatoria,
        campo: 'contraseña',
        accion: 'obligatoria',
      ),
      (
        texto: MensajesCuenta.credencialesInvalidas,
        campo: 'correo',
        accion: 'incorrectos',
      ),
      (texto: MensajesCuenta.sesionInvalida, campo: null, accion: 'vuelve'),
      (texto: MensajesCuenta.errorServidor, campo: null, accion: 'inténtalo'),
      (texto: MensajesCuenta.sinConexion, campo: null, accion: 'se requiere'),
      (
        texto: MensajesCuenta.sinPerfilCacheado,
        campo: null,
        accion: 'conéctate',
      ),
      (
        texto: MensajesCuenta.limpiezaLocalFallida,
        campo: null,
        accion: 'se cerró',
      ),
    ];

    for (final mensaje in mensajes) {
      _verificarMensaje(
        mensaje.texto,
        campo: mensaje.campo,
        accion: mensaje.accion,
      );
    }
  });

  test(
    'los validadores devuelven los errores del catálogo junto a su campo',
    () {
      final escenarios =
          <
            ({
              String nombre,
              String correo,
              String password,
              String confirmacion,
              CampoPerfil campo,
              String esperado,
              String accion,
            })
          >[
            (
              nombre: 'correo vacío',
              correo: '',
              password: '',
              confirmacion: '',
              campo: CampoPerfil.correo,
              esperado: MensajesCuenta.correoObligatorio,
              accion: 'obligatorio',
            ),
            (
              nombre: 'correo inválido',
              correo: 'mal@correo',
              password: '',
              confirmacion: '',
              campo: CampoPerfil.correo,
              esperado: MensajesCuenta.correoInvalido,
              accion: 'introduce',
            ),
            (
              nombre: 'envío sin cambios',
              correo: 'USER@X.COM ',
              password: '',
              confirmacion: '',
              campo: CampoPerfil.formulario,
              esperado: MensajesCuenta.sinCambios,
              accion: 'escribe',
            ),
            (
              nombre: 'falta la confirmación',
              correo: 'user@x.com',
              password: '12345678',
              confirmacion: '',
              campo: CampoPerfil.confirmacion,
              esperado: MensajesCuenta.confirmacionObligatoria,
              accion: 'confirma',
            ),
            (
              nombre: 'falta la contraseña nueva',
              correo: 'user@x.com',
              password: '',
              confirmacion: '12345678',
              campo: CampoPerfil.passwordNueva,
              esperado: MensajesCuenta.passwordNuevaObligatoria,
              accion: 'escribe',
            ),
            (
              nombre: 'contraseñas distintas',
              correo: 'user@x.com',
              password: '12345678',
              confirmacion: '87654321',
              campo: CampoPerfil.confirmacion,
              esperado: MensajesCuenta.passwordsNoCoinciden,
              accion: 'no coinciden',
            ),
            (
              nombre: 'contraseña corta',
              correo: 'user@x.com',
              password: '1234567',
              confirmacion: '1234567',
              campo: CampoPerfil.passwordNueva,
              esperado: MensajesCuenta.passwordCorta,
              accion: 'debe tener',
            ),
            (
              nombre: 'contraseña demasiado larga',
              correo: 'user@x.com',
              password: List.filled(73, 'a').join(),
              confirmacion: List.filled(73, 'a').join(),
              campo: CampoPerfil.passwordNueva,
              esperado: MensajesCuenta.passwordLarga,
              accion: 'demasiado larga',
            ),
          ];

      for (final escenario in escenarios) {
        final errores = validarFormularioPerfil(
          correoActual: 'user@x.com',
          correo: escenario.correo,
          passwordNueva: escenario.password,
          confirmacion: escenario.confirmacion,
        );
        expect(
          errores[escenario.campo],
          escenario.esperado,
          reason: 'Escenario «${escenario.nombre}»',
        );
        _verificarMensaje(
          escenario.esperado,
          campo: escenario.campo == CampoPerfil.correo
              ? 'correo'
              : 'contraseña',
          accion: escenario.accion,
        );
      }
    },
  );

  test(
    'todos los mensajes del catálogo de la API son españoles y no vacíos',
    () {
      for (final entrada in MensajesCuenta.porCodigo.entries) {
        _verificarTextoVisible(entrada.value);
      }
    },
  );
}
