import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/presentation/widgets/password_visibility_field.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/auth/presentation/views/register_view.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

class _FakeUserRepositories implements UserRepositories {
  int llamadasRegistro = 0;
  String? ultimaPassword;
  bool fallarRegistro = false;

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
  ) async {
    llamadasRegistro++;
    ultimaPassword = password;
    if (fallarRegistro) {
      return Left(ServerFailures('fallo de registro simulado'));
    }
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

void main() {
  late _FakeUserRepositories usuarios;
  AuthBloc? authBloc;
  late SessionEvents eventos;

  setUp(() {
    usuarios = _FakeUserRepositories();
    eventos = SessionEvents();
  });

  tearDown(() async {
    await authBloc?.close();
    await eventos.dispose();
  });

  Future<void> montar(
    WidgetTester tester, {
    double textScaler = 1.0,
    Size? tamano,
  }) async {
    if (tamano != null) {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    // El BLoC se crea dentro del cuerpo del test: así sus microtareas corren
    // en la zona de FakeAsync de testWidgets y los eventos se procesan.
    final bloc = AuthBloc(
      registerUc: RegisterUc(repository: usuarios),
      loginUc: LoginUc(repository: usuarios),
      currentUserUc: CurrentUserUc(repository: usuarios),
      pendingDeletionStore: _FakePendingDeletionStore(),
      sessionEvents: eventos,
      accountLocalCleaner: _FakeCleaner(),
      hayConexion: () async => true,
    );
    authBloc = bloc;

    final router = GoRouter(
      initialLocation: '/register',
      routes: <RouteBase>[
        GoRoute(
          path: '/register',
          builder: (context, state) => BlocProvider<AuthBloc>.value(
            value: bloc,
            child: const RegisterView(),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Inicio de sesión'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaler)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ColorScheme esquemaDe(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(RegisterView))).colorScheme;

  Material materialDelBoton(WidgetTester tester) {
    final boton = find.widgetWithText(FilledButton, 'Registrarse');
    return tester
        .widgetList<Material>(
          find.descendant(of: boton, matching: find.byType(Material)),
        )
        .firstWhere((material) => material.color == esquemaDe(tester).primary);
  }

  OutlineInputBorder bordeDelCampo(WidgetTester tester, int indice) {
    final decorador = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byType(TextFormField).at(indice),
        matching: find.byType(InputDecorator),
      ),
    );
    return decorador.decoration.border! as OutlineInputBorder;
  }

  Future<void> enviar(WidgetTester tester) async {
    await tester.tap(find.text('Registrarse'));
    await tester.pump();
  }

  Future<void> llenar(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'user@x.com');
    await tester.enterText(find.byType(TextFormField).at(1), '12345678');
    await tester.enterText(find.byType(TextFormField).at(2), '12345678');
    await tester.pump();
  }

  testWidgets('una contraseña de 7 caracteres se rechaza con el texto del '
      'catálogo', (tester) async {
    await montar(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'user@x.com');
    await tester.enterText(find.byType(TextFormField).at(1), '1234567');
    await tester.enterText(find.byType(TextFormField).at(2), '1234567');

    await enviar(tester);

    expect(
      find.text('La contraseña debe tener al menos 8 caracteres.'),
      findsOneWidget,
    );
    expect(
      find.text('La contraseña debe tener al menos 4 caracteres'),
      findsNothing,
    );
    expect(usuarios.llamadasRegistro, 0);
  });

  testWidgets('una contraseña de más de 72 bytes UTF-8 se rechaza', (
    tester,
  ) async {
    final larga = List.filled(73, 'a').join();
    await montar(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'user@x.com');
    await tester.enterText(find.byType(TextFormField).at(1), larga);
    await tester.enterText(find.byType(TextFormField).at(2), larga);

    await enviar(tester);

    expect(find.text('La contraseña es demasiado larga.'), findsOneWidget);
    expect(usuarios.llamadasRegistro, 0);
  });

  testWidgets('el registro recorta los espacios exteriores de la contraseña '
      'igual que el login', (tester) async {
    usuarios.fallarRegistro = true;
    await montar(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'user@x.com');
    await tester.enterText(find.byType(TextFormField).at(1), ' 12345678 ');
    await tester.enterText(find.byType(TextFormField).at(2), ' 12345678 ');

    await tester.tap(find.text('Registrarse'));
    await tester.pumpAndSettle();

    expect(usuarios.llamadasRegistro, 1);
    expect(usuarios.ultimaPassword, '12345678');
  });

  testWidgets('RF-10: las dos contraseñas usan el widget compartido con ojo', (
    tester,
  ) async {
    await montar(tester);

    expect(find.byType(PasswordVisibilityField), findsNWidgets(2));

    await tester.enterText(find.byType(TextFormField).at(1), '12345678');
    await tester.enterText(find.byType(TextFormField).at(2), '12345678');
    await tester.pump();

    expect(find.byTooltip('Mostrar contraseña'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Mostrar contraseña').first);
    await tester.pump();
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
  });

  testWidgets('RF-08: el botón y los campos heredan el radio 8 del tema', (
    tester,
  ) async {
    await montar(tester);
    final esquema = esquemaDe(tester);

    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Registrarse'),
    );
    expect(boton.style, isNull, reason: 'el botón no debe llevar estilo local');
    final material = materialDelBoton(tester);
    expect(material.color, esquema.primary);
    expect(
      material.shape,
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    for (final indice in <int>[0, 1, 2]) {
      expect(
        bordeDelCampo(tester, indice).borderRadius,
        BorderRadius.circular(8),
      );
    }
  });

  testWidgets('RF-04: el error de registro usa el rol error con su '
      'contenido', (tester) async {
    usuarios.fallarRegistro = true;
    await montar(tester);
    await llenar(tester);

    await tester.tap(find.text('Registrarse'));
    await tester.pumpAndSettle();

    final esquema = esquemaDe(tester);
    final aviso = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(aviso.backgroundColor, esquema.error);
    final texto = tester.widget<Text>(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('fallo de registro simulado'),
      ),
    );
    expect(texto.style?.color, esquema.onError);
  });

  testWidgets('RF-04: la cuenta creada usa el éxito y su contenido', (
    tester,
  ) async {
    await montar(tester);
    await llenar(tester);

    await tester.tap(find.text('Registrarse'));
    await tester.pumpAndSettle();

    final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;
    final aviso = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(aviso.backgroundColor, semantica.success);
    final texto = tester.widget<Text>(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Cuenta creada correctamente. Inicia sesión.'),
      ),
    );
    expect(texto.style?.color, semantica.onSuccess);
    expect(find.text('Inicio de sesión'), findsOneWidget);
  });

  testWidgets('RF-04 y RF-14: el texto secundario usa onSurfaceVariant', (
    tester,
  ) async {
    await montar(tester);

    final texto = tester.widget<Text>(
      find.text(
        'Crea una cuenta para automatizar la alimentación de tus mascotas',
      ),
    );
    expect(texto.style?.color, esquemaDe(tester).onSurfaceVariant);
  });

  testWidgets('RNF-02: a 320 puntos con texto al 130 % no desborda', (
    tester,
  ) async {
    await montar(tester, textScaler: 1.3, tamano: const Size(320, 640));

    expect(tester.takeException(), isNull);
    expect(find.text('Registrarse'), findsOneWidget);
  });
}
