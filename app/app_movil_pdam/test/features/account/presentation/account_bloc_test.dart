import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
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
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

const UserProfile _perfil = UserProfile(email: 'user@x.com', isActive: true);

class _FakeAccountRepository implements AccountRepository {
  Either<Failures, ProfileSnapshot>? perfil;
  Either<Failures, AccountUpdateResult>? actualizacion;
  Either<Failures, bool>? baja;

  AccountUpdate? ultimaActualizacion;
  String? ultimaPasswordBaja;
  int llamadasPerfil = 0;
  int llamadasActualizacion = 0;
  int llamadasBaja = 0;

  /// Si está presente, la consulta del perfil espera a completarse: permite
  /// observar el estado intermedio sin el perfil anterior.
  Completer<void>? blocker;

  /// Si está presente, la actualización espera a completarse: permite cerrar
  /// la sesión mientras la petición está en curso.
  Completer<void>? blockerActualizacion;

  @override
  Future<Either<Failures, ProfileSnapshot>> getProfile() async {
    llamadasPerfil++;
    final espera = blocker;
    if (espera != null) {
      await espera.future;
      blocker = null;
    }
    return perfil ??
        Left(NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado));
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
  Future<Either<Failures, bool>> deleteAccount(String password) async {
    llamadasBaja++;
    ultimaPasswordBaja = password;
    return baja ?? const Right(true);
  }

  @override
  Future<Either<Failures, UserProfile?>> cachedProfile() async =>
      const Right(null);
}

class _FakeAuthTokenRepositories implements AuthTokenRepositories {
  final List<String> orden;
  bool fallarAlGuardar = false;
  bool fallarAlBorrar = false;
  String? tokenGuardado;
  String? tipoGuardado;
  int guardados = 0;
  int borrados = 0;

  _FakeAuthTokenRepositories(this.orden);

  @override
  Future<Either<Failures, AuthToken>> cacheToken(
    String token, {
    String typeToken = 'Bearer',
  }) async {
    if (fallarAlGuardar) {
      // Fallo técnico real de almacenamiento: el BLoC no debe mostrarlo tal cual.
      return Left(ServerFailures('write failed: secure storage unavailable'));
    }
    guardados++;
    tokenGuardado = token;
    tipoGuardado = typeToken;
    return Right(AuthToken(token: token, typeToken: typeToken));
  }

  @override
  Future<Either<Failures, void>> deleteToken() async {
    if (fallarAlBorrar) {
      return Left(ServerFailures(MensajesCuenta.errorServidor));
    }
    borrados++;
    orden.add('token');
    return const Right(null);
  }

  @override
  Future<Either<Failures, AuthToken>> getToken() async =>
      Left(ServerFailures('sin token'));
}

class _FakeAccountLocalCleaner implements AccountLocalCleaner {
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

void main() {
  late _FakeAccountRepository repo;
  late List<String> orden;
  late _FakeAuthTokenRepositories tokenRepo;
  late _FakeAccountLocalCleaner cleaner;
  late SessionEvents eventos;
  late StreamController<AuthState> authStates;
  late AccountBloc bloc;
  late List<SessionEvent> avisos;

  setUp(() {
    repo = _FakeAccountRepository();
    orden = <String>[];
    tokenRepo = _FakeAuthTokenRepositories(orden);
    cleaner = _FakeAccountLocalCleaner();
    eventos = SessionEvents();
    avisos = [];
    eventos.stream.listen(avisos.add);
    authStates = StreamController<AuthState>.broadcast();

    bloc = AccountBloc(
      getProfileUc: GetProfileUc(repository: repo),
      updateProfileUc: UpdateProfileUc(repository: repo),
      deleteAccountUc: DeleteAccountUc(repository: repo),
      registerTokenUc: RegisterTokenUc(repository: tokenRepo),
      accountLocalCleaner: cleaner,
      sessionEvents: eventos,
      authStates: authStates.stream,
    );
  });

  tearDown(() async {
    await bloc.close();
    await authStates.close();
    await eventos.dispose();
  });

  Future<AccountState> enviar(AccountEvent evento) {
    final estadoFinal = bloc.stream.firstWhere(
      (estado) => !estado.isSubmitting && !estado.isLoadingProfile,
    );
    bloc.add(evento);
    return estadoFinal;
  }

  group('carga del perfil (RF-06, RF-07, RF-08)', () {
    test('con servidor muestra el perfil real y no marca caché', () async {
      repo.perfil = const Right(ProfileSnapshot(profile: _perfil));

      final estado = await enviar(const ProfileRequested());

      expect(estado.profile, _perfil);
      expect(estado.isOffline, isFalse);
      expect(estado.message, isNull);
      expect(estado.fieldErrors, isEmpty);
    });

    test(
      'sin conexión muestra el perfil cacheado y avisa de la caché',
      () async {
        repo.perfil = const Right(
          ProfileSnapshot(
            profile: UserProfile(email: 'guardado@x.com', isActive: false),
            desdeCache: true,
          ),
        );

        final estado = await enviar(const ProfileRequested());

        expect(estado.profile?.email, 'guardado@x.com');
        expect(estado.profile?.isActive, isFalse);
        expect(estado.isOffline, isTrue);
        expect(estado.message, isNull);
      },
    );

    test('sin conexión y sin caché muestra el mensaje de RF-08 sin inventar '
        'perfil', () async {
      repo.perfil = Left(
        NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado),
      );

      final estado = await enviar(const ProfileRequested());

      expect(estado.profile, isNull);
      expect(estado.isOffline, isTrue);
      expect(estado.message?.text, MensajesCuenta.sinPerfilCacheado);
    });

    test(
      'sin perfil cargado se validan primero los campos y no se envía',
      () async {
        repo.perfil = Left(
          NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado),
        );
        await enviar(const ProfileRequested());

        final estado = await enviar(const ProfileUpdateSubmitted(correo: ''));

        expect(
          estado.fieldErrors[CampoPerfil.correo],
          MensajesCuenta.correoObligatorio,
        );
        // El aviso de perfil ausente se conserva para explicar la falta de datos.
        expect(estado.message?.text, MensajesCuenta.sinPerfilCacheado);
        expect(repo.llamadasActualizacion, 0);
      },
    );

    test('el reintento vuelve a consultar el perfil', () async {
      repo.perfil = Left(
        NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado),
      );
      await enviar(const ProfileRequested());

      repo.perfil = const Right(ProfileSnapshot(profile: _perfil));
      final estado = await enviar(const ProfileRetryRequested());

      expect(repo.llamadasPerfil, 2);
      expect(estado.profile, _perfil);
      expect(estado.message, isNull);
    });

    test('una sesión inválida se avisa con el texto del catálogo', () async {
      repo.perfil = Left(UnauthorizedFailure(MensajesCuenta.sesionInvalida));

      final estado = await enviar(const ProfileRequested());

      expect(estado.profile, isNull);
      expect(estado.message?.text, MensajesCuenta.sesionInvalida);
      expect(estado.message?.tipo, AccountMessageType.sesionInvalida);
    });

    test(
      'al empezar una carga no conserva el perfil de la cuenta anterior',
      () async {
        repo.perfil = const Right(
          ProfileSnapshot(
            profile: UserProfile(email: 'anterior@x.com', isActive: true),
          ),
        );
        await enviar(const ProfileRequested());

        repo.perfil = const Right(
          ProfileSnapshot(
            profile: UserProfile(email: 'nueva@x.com', isActive: true),
          ),
        );
        repo.blocker = Completer<void>();
        bloc.add(const ProfileRequested());

        final cargando = await bloc.stream.firstWhere(
          (estado) => estado.isLoadingProfile,
        );
        expect(cargando.profile, isNull);
        expect(cargando.message, isNull);
        expect(cargando.isSubmitting, isFalse);

        repo.blocker!.complete();
        final estado = await bloc.stream.firstWhere(
          (estado) => !estado.isLoadingProfile,
        );
        expect(estado.profile?.email, 'nueva@x.com');
      },
    );

    test('al cerrar sesión se limpia el perfil de la cuenta', () async {
      repo.perfil = const Right(ProfileSnapshot(profile: _perfil));
      await enviar(const ProfileRequested());
      repo.actualizacion = const Right(
        AccountUpdateResult(profile: _perfil, tokenNuevo: 'token-nuevo'),
      );
      final actualizado = await enviar(
        const ProfileUpdateSubmitted(
          correo: 'user@x.com',
          passwordNueva: '12345678',
          confirmacion: '12345678',
        ),
      );
      expect(actualizado.message?.text, MensajesCuenta.datosActualizados);

      authStates.add(AuthUnauthenticated());

      final estado = await bloc.stream.firstWhere(
        (estado) => estado.profile == null,
      );
      expect(estado.profile, isNull);
      expect(estado.message, isNull);
      expect(estado.isSubmitting, isFalse);
    });

    test('una sesión expirada limpia el perfil aunque la consulta siga en '
        'curso', () async {
      repo.perfil = const Right(ProfileSnapshot(profile: _perfil));
      await enviar(const ProfileRequested());

      repo.perfil = const Right(
        ProfileSnapshot(
          profile: UserProfile(email: 'otra@x.com', isActive: true),
        ),
      );
      repo.blocker = Completer<void>();
      bloc.add(const ProfileRequested());
      await bloc.stream.firstWhere((estado) => estado.isLoadingProfile);

      authStates.add(
        const AuthSessionExpired(message: MensajesCuenta.sesionInvalida),
      );
      await bloc.stream.firstWhere((estado) => estado.profile == null);

      // La respuesta tardía no debe volver a pintar el perfil tras expirar.
      repo.blocker!.complete();
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.profile, isNull);
    });

    test('una sesión expirada durante la actualización no guarda el token ni '
        'emite el perfil de la cuenta anterior', () async {
      repo.perfil = const Right(ProfileSnapshot(profile: _perfil));
      await enviar(const ProfileRequested());

      repo.actualizacion = const Right(
        AccountUpdateResult(
          profile: UserProfile(email: 'nuevo@x.com', isActive: true),
          tokenNuevo: 'token-nuevo',
        ),
      );
      repo.blockerActualizacion = Completer<void>();
      bloc.add(const ProfileUpdateSubmitted(correo: 'nuevo@x.com'));
      await bloc.stream.firstWhere((estado) => estado.isSubmitting);

      authStates.add(
        const AuthSessionExpired(message: MensajesCuenta.sesionInvalida),
      );
      await bloc.stream.firstWhere((estado) => estado.profile == null);

      // La respuesta tardía ya no pertenece a ninguna sesión activa (RF-05).
      repo.blockerActualizacion!.complete();
      await Future<void>.delayed(Duration.zero);

      expect(tokenRepo.guardados, 0);
      expect(bloc.state.profile, isNull);
      expect(bloc.state.message, isNull);
    });

    test('un cierre de sesión durante la actualización tampoco persiste el '
        'token ni el perfil', () async {
      repo.perfil = const Right(ProfileSnapshot(profile: _perfil));
      await enviar(const ProfileRequested());

      repo.actualizacion = const Right(
        AccountUpdateResult(
          profile: UserProfile(email: 'nuevo@x.com', isActive: true),
          tokenNuevo: 'token-nuevo',
        ),
      );
      repo.blockerActualizacion = Completer<void>();
      bloc.add(const ProfileUpdateSubmitted(correo: 'nuevo@x.com'));
      await bloc.stream.firstWhere((estado) => estado.isSubmitting);

      authStates.add(AuthUnauthenticated());
      await bloc.stream.firstWhere((estado) => estado.profile == null);

      repo.blockerActualizacion!.complete();
      await Future<void>.delayed(Duration.zero);

      expect(tokenRepo.guardados, 0);
      expect(bloc.state.profile, isNull);
    });
  });

  group('actualización del perfil (RF-10, RF-11, RF-13)', () {
    Future<AccountState> conPerfil(AccountEvent evento) async {
      repo.perfil = const Right(ProfileSnapshot(profile: _perfil));
      await enviar(const ProfileRequested());
      return enviar(evento);
    }

    test('los errores de cliente se muestran todos y no se envía la '
        'petición', () async {
      final estado = await conPerfil(
        const ProfileUpdateSubmitted(
          correo: 'mal@correo',
          passwordNueva: 'corta',
          confirmacion: 'otra',
        ),
      );

      expect(estado.fieldErrors, isNotEmpty);
      expect(
        estado.fieldErrors[CampoPerfil.correo],
        MensajesCuenta.correoInvalido,
      );
      expect(repo.llamadasActualizacion, 0);
      expect(estado.message, isNull);
    });

    test('el envío sin cambios se avisa junto al formulario', () async {
      final estado = await conPerfil(
        const ProfileUpdateSubmitted(correo: ' USER@X.COM '),
      );

      expect(
        estado.fieldErrors[CampoPerfil.formulario],
        MensajesCuenta.sinCambios,
      );
      expect(repo.llamadasActualizacion, 0);
    });

    test('un cambio de correo guarda el token nuevo y confirma', () async {
      repo.actualizacion = const Right(
        AccountUpdateResult(
          profile: UserProfile(email: 'nuevo@x.com', isActive: true),
          tokenNuevo: 'token-nuevo',
        ),
      );

      final estado = await conPerfil(
        const ProfileUpdateSubmitted(correo: '  Nuevo@X.com '),
      );

      expect(repo.ultimaActualizacion?.correo, 'nuevo@x.com');
      expect(repo.ultimaActualizacion?.passwordNueva, isNull);
      expect(tokenRepo.tokenGuardado, 'token-nuevo');
      expect(tokenRepo.guardados, 1);
      expect(estado.profile?.email, 'nuevo@x.com');
      expect(estado.message?.text, MensajesCuenta.datosActualizados);
      expect(estado.message?.tipo, AccountMessageType.confirmacion);
    });

    test('un cambio solo de contraseña no genera token nuevo', () async {
      repo.actualizacion = const Right(AccountUpdateResult(profile: _perfil));

      final estado = await conPerfil(
        const ProfileUpdateSubmitted(
          correo: 'user@x.com',
          passwordNueva: 'unaClaveLarga',
          confirmacion: 'unaClaveLarga',
        ),
      );

      expect(repo.ultimaActualizacion?.correo, isNull);
      expect(repo.ultimaActualizacion?.passwordNueva, 'unaClaveLarga');
      expect(tokenRepo.guardados, 0);
      expect(estado.message?.text, MensajesCuenta.datosActualizados);
    });

    test('si no se puede guardar el token, se avisa y no se pierde el '
        'perfil actualizado', () async {
      tokenRepo.fallarAlGuardar = true;
      repo.actualizacion = const Right(
        AccountUpdateResult(
          profile: UserProfile(email: 'nuevo@x.com', isActive: true),
          tokenNuevo: 'token-nuevo',
        ),
      );

      final estado = await conPerfil(
        const ProfileUpdateSubmitted(correo: 'nuevo@x.com'),
      );

      expect(estado.profile?.email, 'nuevo@x.com');
      expect(estado.message?.text, MensajesCuenta.errorServidor);
      expect(estado.message?.tipo, AccountMessageType.error);
    });

    test(
      'un correo ya registrado se muestra junto al campo de correo',
      () async {
        repo.actualizacion = Left(
          AccountFailure(
            CodigosCuenta.emailAlreadyRegistered,
            'El correo electrónico ya está registrado.',
          ),
        );

        final estado = await conPerfil(
          const ProfileUpdateSubmitted(correo: 'ocupado@x.com'),
        );

        expect(
          estado.fieldErrors[CampoPerfil.correo],
          'El correo electrónico ya está registrado.',
        );
        expect(estado.message, isNull);
      },
    );

    test(
      'una contraseña débil se muestra junto al campo de contraseña',
      () async {
        repo.actualizacion = Left(
          AccountFailure(
            CodigosCuenta.weakPassword,
            MensajesCuenta.passwordCorta,
          ),
        );

        final estado = await conPerfil(
          const ProfileUpdateSubmitted(
            correo: 'user@x.com',
            passwordNueva: 'corta12',
            confirmacion: 'corta12',
          ),
        );

        expect(
          estado.fieldErrors[CampoPerfil.passwordNueva],
          MensajesCuenta.passwordCorta,
        );
      },
    );

    test('sin conexión no aplica nada y avisa', () async {
      repo.actualizacion = Left(
        ConnectivityRequiredFailures(MensajesCuenta.sinConexion),
      );

      final estado = await conPerfil(
        const ProfileUpdateSubmitted(correo: 'nuevo@x.com'),
      );

      expect(estado.profile, _perfil);
      expect(estado.message?.text, MensajesCuenta.sinConexion);
      expect(estado.message?.tipo, AccountMessageType.aviso);
      expect(tokenRepo.guardados, 0);
    });

    test('un error del servidor se avisa con el texto del catálogo', () async {
      repo.actualizacion = Left(
        AccountFailure(CodigosCuenta.conflict, MensajesCuenta.errorServidor),
      );

      final estado = await conPerfil(
        const ProfileUpdateSubmitted(correo: 'nuevo@x.com'),
      );

      expect(estado.message?.text, MensajesCuenta.errorServidor);
      expect(estado.message?.tipo, AccountMessageType.error);
    });
  });

  group('eliminación de la cuenta (RF-17, RF-18, RF-20, RF-21, RNF-10)', () {
    test('una contraseña incorrecta se muestra junto al campo y no limpia '
        'nada', () async {
      repo.baja = Left(
        AccountFailure(
          CodigosCuenta.invalidPassword,
          MensajesCuenta.passwordIncorrecta,
        ),
      );

      final estado = await enviar(
        const AccountDeletionRequested(password: 'incorrecta'),
      );

      expect(repo.ultimaPasswordBaja, 'incorrecta');
      expect(
        estado.fieldErrors[CampoPerfil.passwordActual],
        MensajesCuenta.passwordIncorrecta,
      );
      expect(estado.message, isNull);
      expect(cleaner.llamadas, 0);
      expect(cleaner.marcaPendiente, isFalse);
      expect(avisos, isEmpty);
    });

    test('sin conexión no elimina nada ni inicia la limpieza', () async {
      repo.baja = Left(
        ConnectivityRequiredFailures(MensajesCuenta.sinConexion),
      );

      final estado = await enviar(
        const AccountDeletionRequested(password: 'claveActual'),
      );

      expect(estado.message?.text, MensajesCuenta.sinConexion);
      expect(estado.message?.tipo, AccountMessageType.aviso);
      expect(cleaner.llamadas, 0);
      expect(avisos, isEmpty);
    });

    test(
      'un fallo del servidor conserva la cuenta y permite reintentar',
      () async {
        repo.baja = Left(
          AccountFailure(
            CodigosCuenta.serverError,
            MensajesCuenta.errorServidor,
          ),
        );

        final estado = await enviar(
          const AccountDeletionRequested(password: 'claveActual'),
        );

        expect(estado.message?.text, MensajesCuenta.errorServidor);
        expect(estado.message?.tipo, AccountMessageType.error);
        expect(cleaner.llamadas, 0);
        expect(avisos, isEmpty);
      },
    );

    test('el éxito delega la limpieza completa y cierra la sesión con el '
        'mensaje definitivo', () async {
      final estado = await enviar(
        const AccountDeletionRequested(password: 'claveActual'),
      );

      expect(cleaner.llamadas, 1);
      // Sin perfil cargado en el BLoC, el limpiador obtiene la clave del perfil
      // cacheado por su cuenta.
      expect(cleaner.correo, isNull);
      expect(cleaner.marcaPendiente, isFalse);
      expect(estado.profile, isNull);
      expect(estado.isLoadingProfile, isFalse);
      expect(estado.message?.text, MensajesCuenta.cuentaEliminada);
      expect(estado.message?.tipo, AccountMessageType.cuentaEliminada);
      expect(avisos.single.type, SessionEventType.cuentaEliminada);
      expect(avisos.single.message, MensajesCuenta.cuentaEliminada);
    });

    test('la baja apaga isLoadingProfile de una precarga en curso', () async {
      repo.perfil = const Right(ProfileSnapshot(profile: _perfil));
      repo.blocker = Completer<void>();
      addTearDown(() {
        final espera = repo.blocker;
        if (espera != null && !espera.isCompleted) espera.complete();
      });

      bloc.add(const ProfileRequested());
      await bloc.stream.firstWhere((estado) => estado.isLoadingProfile);

      repo.baja = const Right(true);
      bloc.add(const AccountDeletionRequested(password: 'claveActual'));

      final durante = await bloc.stream.firstWhere(
        (estado) => estado.isSubmitting,
      );
      expect(durante.isLoadingProfile, isFalse);

      repo.blocker!.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('si la limpieza falla, la marca sobrevive y la sesión se cierra con '
        'el aviso de RNF-10', () async {
      cleaner.resultado = const AccountCleanupResult.fallo(
        pasoFallido: AccountCleanupStep.token,
        pasosCompletados: <AccountCleanupStep>[AccountCleanupStep.marca],
      );

      final estado = await enviar(
        const AccountDeletionRequested(password: 'claveActual'),
      );

      expect(cleaner.llamadas, 1);
      expect(cleaner.marcaPendiente, isTrue);
      expect(estado.message?.text, MensajesCuenta.limpiezaLocalFallida);
      expect(estado.message?.tipo, AccountMessageType.limpiezaFallida);
      expect(avisos.single.type, SessionEventType.cuentaEliminada);
      expect(avisos.single.message, MensajesCuenta.limpiezaLocalFallida);
    });

    test('si la marca no se puede escribir, se avisa del fallo de limpieza y '
        'la sesión se cierra', () async {
      cleaner.resultado = const AccountCleanupResult.fallo(
        pasoFallido: AccountCleanupStep.marca,
        pasosCompletados: <AccountCleanupStep>[],
      );

      final estado = await enviar(
        const AccountDeletionRequested(password: 'claveActual'),
      );

      expect(estado.message?.text, MensajesCuenta.limpiezaLocalFallida);
      expect(avisos.single.message, MensajesCuenta.limpiezaLocalFallida);
    });
  });

  group('cierre del BLoC y aviso de la baja', () {
    test(
      'close cancela la suscripción a AuthBloc y no emite después',
      () async {
        final local = AccountBloc(
          getProfileUc: GetProfileUc(repository: repo),
          updateProfileUc: UpdateProfileUc(repository: repo),
          deleteAccountUc: DeleteAccountUc(repository: repo),
          registerTokenUc: RegisterTokenUc(repository: tokenRepo),
          accountLocalCleaner: cleaner,
          sessionEvents: eventos,
          authStates: authStates.stream,
        );

        await local.close();
        expect(local.isClosed, isTrue);

        // Si la suscripción siguiera viva, esto intentaría emitir sobre un BLoC
        // cerrado y lanzaría StateError.
        authStates.add(AuthUnauthenticated());
        await Future<void>.delayed(Duration.zero);
        expect(local.isClosed, isTrue);
      },
    );

    test(
      'AuthAccountDeleted transporta el mensaje definitivo hasta el login',
      () async {
        final eventosReales = SessionEvents();
        addTearDown(eventosReales.dispose);
        final authBloc = AuthBloc(
          registerUc: RegisterUc(repository: _FakeUserRepository()),
          loginUc: LoginUc(repository: _FakeUserRepository()),
          currentUserUc: CurrentUserUc(repository: _FakeUserRepository()),
          pendingDeletionStore: _FakePendingDeletionStore(),
          sessionEvents: eventosReales,
          accountLocalCleaner: cleaner,
          hayConexion: () async => true,
        );
        addTearDown(authBloc.close);
        authBloc.add(AuthCheckStatusRequested());
        await authBloc.stream.firstWhere(
          (estado) => estado is AuthAuthenticated,
        );

        final accountBloc = AccountBloc(
          getProfileUc: GetProfileUc(repository: repo),
          updateProfileUc: UpdateProfileUc(repository: repo),
          deleteAccountUc: DeleteAccountUc(repository: repo),
          registerTokenUc: RegisterTokenUc(repository: tokenRepo),
          accountLocalCleaner: cleaner,
          sessionEvents: eventosReales,
          authStates: authBloc.stream,
        );
        addTearDown(accountBloc.close);

        accountBloc.add(
          const AccountDeletionRequested(password: 'claveActual'),
        );

        final estado = await authBloc.stream.firstWhere(
          (estado) => estado is AuthAccountDeleted,
        );
        expect(
          (estado as AuthAccountDeleted).message,
          MensajesCuenta.cuentaEliminada,
        );
        // El AccountBloc se limpia al recibir el cierre de sesión, pero el
        // mensaje final sigue disponible en AuthAccountDeleted para el login.
        await accountBloc.stream.firstWhere((estado) => estado.message == null);
        expect(accountBloc.state.message, isNull);
      },
    );
  });

  group('consumo del mensaje', () {
    test('descarta el mensaje y el token nuevo del estado', () async {
      repo.perfil = const Right(ProfileSnapshot(profile: _perfil));
      await enviar(const ProfileRequested());
      repo.actualizacion = const Right(
        AccountUpdateResult(
          profile: UserProfile(email: 'nuevo@x.com', isActive: true),
          tokenNuevo: 'token-nuevo',
        ),
      );
      await enviar(const ProfileUpdateSubmitted(correo: 'nuevo@x.com'));

      final estado = await enviar(const AccountMessageConsumed());

      expect(estado.message, isNull);
      expect(estado.profile?.email, 'nuevo@x.com');
    });
  });
}
