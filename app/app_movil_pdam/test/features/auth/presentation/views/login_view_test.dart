import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
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

/// RF-05: al volver al login por una sesión terminada, el mensaje del catálogo
/// debe verse aunque la vista se monte después de la emisión del estado.
void main() {
  Future<AuthBloc> montarLogin(
    WidgetTester tester, {
    required SessionEvent evento,
  }) async {
    final eventos = SessionEvents();
    addTearDown(eventos.dispose);
    final bloc = AuthBloc(
      registerUc: RegisterUc(repository: _FakeUserRepository()),
      loginUc: LoginUc(repository: _FakeUserRepository()),
      currentUserUc: CurrentUserUc(repository: _FakeUserRepository()),
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
        child: MaterialApp(theme: AppTheme.lightTheme, home: const LoginView()),
      ),
    );
    await tester.pump();
    return bloc;
  }

  testWidgets('una sesión expirada muestra el texto del catálogo al volver al '
      'login', (tester) async {
    await montarLogin(tester, evento: const SessionEvent.sesionExpirada());

    expect(find.text(MensajesCuenta.sesionInvalida), findsOneWidget);
    expect(find.byKey(const Key('login_session_message')), findsOneWidget);
  });

  testWidgets('una cuenta eliminada muestra su mensaje y deja el login listo '
      'para T9', (tester) async {
    await montarLogin(tester, evento: const SessionEvent.cuentaEliminada());

    expect(find.text(MensajesCuenta.cuentaEliminada), findsOneWidget);
  });
}
