import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUserRepositories implements UserRepositories {
  Either<Failures, User>? respuestaUsuario;
  Either<Failures, User>? respuestaLogin;
  int llamadasCurrentUser = 0;
  int llamadasLogin = 0;

  @override
  Future<Either<Failures, User>> currentUser() async {
    llamadasCurrentUser++;
    return respuestaUsuario ?? Right(User(id: 1, email: 'current@test.com'));
  }

  @override
  Future<Either<Failures, User>> login(String email, String password) async {
    llamadasLogin++;
    return respuestaLogin ?? Right(User(id: 1, email: email));
  }

  @override
  Future<Either<Failures, User>> register(
    String email,
    String password,
    String confirmPassword,
  ) async {
    return Right(User(id: 1, email: email));
  }
}

/// Limpieza de sesión simulada para comprobar el orden del 401 (RF-19).
class _FakeCleanerSesion implements AccountLocalCleaner {
  bool limpiada = false;
  int llamadas = 0;

  @override
  Future<AccountCleanupResult> limpiarTrasBaja({String? correo}) async =>
      AccountCleanupResult.exito(pasosCompletados: AccountCleanupStep.values);

  @override
  Future<AccountCleanupResult?> limpiarSiPendiente() async => null;

  @override
  Future<void> limpiarPorSesionExpirada() async {
    llamadas++;
    limpiada = true;
  }
}

class _FakePendingDeletionStore implements PendingDeletionStore {
  bool pendiente = false;

  @override
  Future<void> markPending() async {
    pendiente = true;
  }

  @override
  Future<bool> isPending() async => pendiente;

  @override
  Future<void> clear() async {
    pendiente = false;
  }
}

void main() {
  late _FakeUserRepositories usuarios;
  late _FakePendingDeletionStore store;
  late _FakeCleanerSesion cleaner;
  late SessionEvents eventos;
  late AuthBloc authBloc;
  bool conectado = true;

  setUp(() {
    usuarios = _FakeUserRepositories();
    store = _FakePendingDeletionStore();
    cleaner = _FakeCleanerSesion();
    eventos = SessionEvents();
    conectado = true;

    authBloc = AuthBloc(
      registerUc: RegisterUc(repository: usuarios),
      loginUc: LoginUc(repository: usuarios),
      currentUserUc: CurrentUserUc(repository: usuarios),
      pendingDeletionStore: store,
      sessionEvents: eventos,
      accountLocalCleaner: cleaner,
      hayConexion: () async => conectado,
    );
  });

  tearDown(() async {
    await authBloc.close();
    await eventos.dispose();
  });

  test('el estado inicial es AuthInitial', () {
    expect(authBloc.state, isA<AuthInitial>());
  });

  test('el login correcto emite AuthLoading y AuthAuthenticated', () async {
    final expectativa = expectLater(
      authBloc.stream,
      emitsInOrder([isA<AuthLoading>(), isA<AuthAuthenticated>()]),
    );

    authBloc.add(
      const AuthLoginRequested(email: 'test@pdam.com', password: '12345678'),
    );

    await expectativa;
  });

  test('el login rechazado muestra el mensaje del catálogo', () async {
    usuarios.respuestaLogin = Left(
      AccountFailure(
        CodigosCuenta.invalidCredentials,
        MensajesCuenta.credencialesInvalidas,
      ),
    );

    final esperado = authBloc.stream.firstWhere(
      (estado) => estado is AuthError,
    );
    authBloc.add(
      const AuthLoginRequested(email: 'test@pdam.com', password: 'incorrecta'),
    );
    final estado = await esperado;

    expect((estado as AuthError).message, 'Correo o contraseña incorrectos');
    expect(estado.message, isNot(contains('Exception')));
  });

  test('sin conexión y con marca de baja pendiente el login se rechaza sin '
      'consultar las credenciales', () async {
    conectado = false;
    store.pendiente = true;

    final esperado = authBloc.stream.firstWhere(
      (estado) => estado is AuthError,
    );
    authBloc.add(
      const AuthLoginRequested(email: 'test@pdam.com', password: '12345678'),
    );
    final estado = await esperado;

    expect((estado as AuthError).message, MensajesCuenta.limpiezaLocalFallida);
    expect(usuarios.llamadasLogin, 0);
  });

  test('con conexión y con marca de baja pendiente el login llega al caso de '
      'uso y no se bloquea', () async {
    conectado = true;
    store.pendiente = true;

    final esperado = authBloc.stream.firstWhere(
      (estado) => estado is AuthAuthenticated,
    );
    authBloc.add(
      const AuthLoginRequested(email: 'test@pdam.com', password: '12345678'),
    );
    final estado = await esperado;

    expect((estado as AuthAuthenticated).user.email, 'test@pdam.com');
    expect(usuarios.llamadasLogin, 1);
  });

  test('sin conexión y sin marca de baja pendiente el login usa el modo '
      'sin conexión', () async {
    conectado = false;
    usuarios.respuestaLogin = Right(User(id: 0, email: 'cache@x.com'));

    final esperado = authBloc.stream.firstWhere(
      (estado) => estado is AuthAuthenticated,
    );
    authBloc.add(
      const AuthLoginRequested(email: 'cache@x.com', password: '12345678'),
    );
    final estado = await esperado;

    expect((estado as AuthAuthenticated).user.email, 'cache@x.com');
    expect(usuarios.llamadasLogin, 1);
  });

  test(
    'con marca de baja pendiente el arranque no restaura la sesión',
    () async {
      store.pendiente = true;

      final esperado = authBloc.stream.firstWhere(
        (estado) => estado is AuthUnauthenticated,
      );
      authBloc.add(AuthCheckStatusRequested());
      await esperado;

      expect(usuarios.llamadasCurrentUser, 0);
    },
  );

  test(
    'sin marca de baja pendiente el arranque restaura la sesión real',
    () async {
      final esperado = authBloc.stream.firstWhere(
        (estado) => estado is AuthAuthenticated,
      );
      authBloc.add(AuthCheckStatusRequested());
      final estado = await esperado;

      expect((estado as AuthAuthenticated).user.email, 'current@test.com');
      expect(usuarios.llamadasCurrentUser, 1);
    },
  );

  test('RF-10: el correo actualizado refresca la identidad sin cerrar la '
      'sesión ni volver a iniciar sesión', () async {
    usuarios.respuestaUsuario = Right(User(id: 7, email: 'viejo@test.com'));
    authBloc.add(AuthCheckStatusRequested());
    await authBloc.stream.firstWhere((estado) => estado is AuthAuthenticated);

    authBloc.add(const AuthProfileUpdated(email: 'nuevo@test.com'));
    final actualizado = await authBloc.stream.firstWhere(
      (estado) =>
          estado is AuthAuthenticated &&
          estado.user.email == 'nuevo@test.com',
    );

    expect((actualizado as AuthAuthenticated).user.id, 7);
    expect(usuarios.llamadasLogin, 0);
  });

  test('el aviso de sesión expirada del interceptor cierra la sesión con el '
      'mensaje del catálogo', () async {
    final esperado = authBloc.stream.firstWhere(
      (estado) => estado is AuthSessionExpired,
    );
    eventos.notify(const SessionEvent.sesionExpirada());
    final estado = await esperado;

    expect(
      (estado as AuthSessionExpired).message,
      MensajesCuenta.sesionInvalida,
    );
  });

  test('RF-19: el 401 limpia la sesión antes de emitir AuthSessionExpired',
      () async {
    var limpiadaAlEmitir = false;
    final escucha = authBloc.stream.listen((estado) {
      if (estado is AuthSessionExpired) {
        limpiadaAlEmitir = cleaner.limpiada;
      }
    });
    addTearDown(escucha.cancel);

    final esperado = authBloc.stream.firstWhere(
      (estado) => estado is AuthSessionExpired,
    );
    eventos.notify(const SessionEvent.sesionExpirada());
    await esperado;

    expect(cleaner.llamadas, 1);
    expect(limpiadaAlEmitir, isTrue);
  });

  test('el aviso de cuenta eliminada emite AuthAccountDeleted con el mensaje '
      'de la baja', () async {
    final esperado = authBloc.stream.firstWhere(
      (estado) => estado is AuthAccountDeleted,
    );
    eventos.notify(const SessionEvent.cuentaEliminada());
    final estado = await esperado;

    expect(
      (estado as AuthAccountDeleted).message,
      MensajesCuenta.cuentaEliminada,
    );
  });

  test(
    'el aviso de cuenta eliminada conserva el mensaje de fallo de limpieza',
    () async {
      final esperado = authBloc.stream.firstWhere(
        (estado) => estado is AuthAccountDeleted,
      );
      eventos.notify(
        const SessionEvent.cuentaEliminada(
          message: MensajesCuenta.limpiezaLocalFallida,
        ),
      );
      final estado = await esperado;

      expect(
        (estado as AuthAccountDeleted).message,
        MensajesCuenta.limpiezaLocalFallida,
      );
    },
  );
}
