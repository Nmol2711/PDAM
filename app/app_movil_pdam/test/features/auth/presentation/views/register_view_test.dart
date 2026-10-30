import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
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

  Future<void> montar(WidgetTester tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: const RegisterView(),
        ),
      ),
    );
  }

  Future<void> enviar(WidgetTester tester) async {
    await tester.tap(find.text('Registrarse'));
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
}
