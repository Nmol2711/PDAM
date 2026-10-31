import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/presentation/widgets/password_visibility_field.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_theme.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/features/auth/presentation/views/login_view.dart';
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

class _FakeUserRepository implements UserRepositories {
  _FakeUserRepository({this.fallarLogin = false, this.loginPendiente});

  final bool fallarLogin;
  final Completer<Either<Failures, User>>? loginPendiente;
  int llamadasLogin = 0;

  @override
  Future<Either<Failures, User>> currentUser() async =>
      Left(ServerFailures('sin sesión'));

  @override
  Future<Either<Failures, User>> login(String email, String password) async {
    llamadasLogin++;
    final pendiente = loginPendiente;
    if (pendiente != null) {
      return pendiente.future;
    }
    if (fallarLogin) {
      return Left(ServerFailures('fallo de login simulado'));
    }
    return Right(User(id: 1, email: email));
  }

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

/// RF-05: al volver al login por una sesión terminada, el mensaje del catálogo
/// debe verse aunque la vista se monte después de la emisión del estado.
void main() {
  Future<AuthBloc> montarLogin(
    WidgetTester tester, {
    required SessionEvent evento,
    _FakeUserRepository? usuarios,
    double textScaler = 1.0,
    Size? tamano,
    ThemeData? tema,
  }) async {
    if (tamano != null) {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final repo = usuarios ?? _FakeUserRepository();
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final bloc = AuthBloc(
      registerUc: RegisterUc(repository: repo),
      loginUc: LoginUc(repository: repo),
      currentUserUc: CurrentUserUc(repository: repo),
      pendingDeletionStore: _FakePendingDeletionStore(),
      sessionEvents: eventos,
      accountLocalCleaner: _FakeCleaner(),
    );
    addTearDown(bloc.close);

    // El aviso llega antes de que la vista exista: el mensaje debe leerse del
    // estado actual y no depender del listener de la pantalla.
    eventos.notify(evento);
    await bloc.stream.firstWhere(
      (estado) => estado is AuthSessionExpired || estado is AuthAccountDeleted,
    );

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: bloc,
        child: MaterialApp(
          theme: tema ?? AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScaler)),
            child: child!,
          ),
          home: const LoginView(),
        ),
      ),
    );
    await tester.pump();
    return bloc;
  }

  ColorScheme esquemaDe(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(LoginView))).colorScheme;

  Material materialDelBoton(WidgetTester tester) {
    final boton = find.widgetWithText(FilledButton, 'Iniciar Sesión');
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

  testWidgets('una sesión expirada muestra el texto del catálogo al volver al '
      'login', (tester) async {
    await montarLogin(tester, evento: const SessionEvent.sesionExpirada());

    expect(find.text(MensajesCuenta.sesionInvalida), findsOneWidget);
    expect(find.byKey(const Key('login_session_message')), findsOneWidget);

    final esquema = AppTheme.lightTheme.colorScheme;
    final contenedor = tester.widget<Container>(
      find.byKey(const Key('login_session_message')),
    );
    final decoracion = contenedor.decoration! as BoxDecoration;
    expect(decoracion.color, esquema.errorContainer);
    final texto = tester.widget<Text>(find.text(MensajesCuenta.sesionInvalida));
    expect(texto.style?.color, esquema.onErrorContainer);
  });

  testWidgets('una cuenta eliminada muestra su mensaje y deja el login listo '
      'para T9', (tester) async {
    await montarLogin(tester, evento: const SessionEvent.cuentaEliminada());

    expect(find.text(MensajesCuenta.cuentaEliminada), findsOneWidget);

    final semantica = AppTheme.lightTheme.extension<AppSemanticColors>()!;
    final contenedor = tester.widget<Container>(
      find.byKey(const Key('login_session_message')),
    );
    final decoracion = contenedor.decoration! as BoxDecoration;
    expect(decoracion.color, semantica.success);
    final texto = tester.widget<Text>(
      find.text(MensajesCuenta.cuentaEliminada),
    );
    expect(texto.style?.color, semantica.onSuccess);
  });

  testWidgets(
    'RF-10: la contraseña usa el widget compartido y alterna el ojo',
    (tester) async {
      await montarLogin(tester, evento: const SessionEvent.sesionExpirada());

      expect(find.byType(PasswordVisibilityField), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), 'claveLarga');
      await tester.pump();
      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);

      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();

      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(PasswordVisibilityField),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isFalse,
      );
    },
  );

  testWidgets('RF-08: el botón y los campos heredan el radio 8 del tema', (
    tester,
  ) async {
    await montarLogin(tester, evento: const SessionEvent.sesionExpirada());
    final esquema = esquemaDe(tester);

    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Iniciar Sesión'),
    );
    expect(boton.style, isNull, reason: 'el botón no debe llevar estilo local');
    final material = materialDelBoton(tester);
    expect(material.color, esquema.primary);
    expect(
      material.shape,
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    for (final indice in <int>[0, 1]) {
      expect(
        bordeDelCampo(tester, indice).borderRadius,
        BorderRadius.circular(8),
      );
    }
  });

  testWidgets('RF-04: el error de autenticación usa el rol error con su '
      'contenido', (tester) async {
    final repo = _FakeUserRepository(fallarLogin: true);
    await montarLogin(
      tester,
      evento: const SessionEvent.sesionExpirada(),
      usuarios: repo,
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'user@x.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'claveLarga');
    await tester.pump();
    await tester.tap(find.text('Iniciar Sesión'));
    await tester.pumpAndSettle();

    final esquema = esquemaDe(tester);
    final aviso = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(aviso.backgroundColor, esquema.error);
    final texto = tester.widget<Text>(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('fallo de login simulado'),
      ),
    );
    expect(texto.style?.color, esquema.onError);
  });

  testWidgets('RF-04 y RF-14: el indicador de carga usa el contenido del '
      'principal', (tester) async {
    final pendiente = Completer<Either<Failures, User>>();
    final repo = _FakeUserRepository(loginPendiente: pendiente);
    await montarLogin(
      tester,
      evento: const SessionEvent.sesionExpirada(),
      usuarios: repo,
      tema: AppTheme.darkTheme,
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'user@x.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'claveLarga');
    await tester.pump();
    await tester.tap(find.text('Iniciar Sesión'));
    await tester.pump();

    final indicador = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(
      indicador.color,
      AppTheme.darkTheme.colorScheme.onPrimary,
      reason: 'en oscuro el blanco literal no coincide con onPrimary',
    );

    pendiente.complete(Right(User(id: 1, email: 'user@x.com')));
    await tester.pumpAndSettle();
  });

  testWidgets('RF-10: conserva los textos y validadores del formulario', (
    tester,
  ) async {
    final repo = _FakeUserRepository();
    await montarLogin(
      tester,
      evento: const SessionEvent.sesionExpirada(),
      usuarios: repo,
    );

    await tester.tap(find.text('Iniciar Sesión'));
    await tester.pump();

    expect(find.text('El correo es obligatorio'), findsOneWidget);
    expect(find.text('La contraseña es obligatoria'), findsOneWidget);
    expect(repo.llamadasLogin, 0);
    expect(find.text('¿No tienes una cuenta? Regístrate aquí'), findsOneWidget);
  });

  testWidgets('RF-04 y RF-14: el texto secundario usa onSurfaceVariant', (
    tester,
  ) async {
    await montarLogin(tester, evento: const SessionEvent.sesionExpirada());

    final texto = tester.widget<Text>(
      find.text('Gestión nutricional y dispensador inteligente'),
    );
    expect(texto.style?.color, esquemaDe(tester).onSurfaceVariant);
  });

  testWidgets('RNF-02: a 320 puntos con texto al 130 % no desborda', (
    tester,
  ) async {
    await montarLogin(
      tester,
      evento: const SessionEvent.sesionExpirada(),
      textScaler: 1.3,
      tamano: const Size(320, 640),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Iniciar Sesión'), findsOneWidget);
  });
}
