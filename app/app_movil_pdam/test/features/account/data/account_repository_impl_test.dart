import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/account/data/datasource/local/local_profile_datasource.dart';
import 'package:app_movil_pdam/features/account/data/datasource/remote/account_remote_datasource.dart';
import 'package:app_movil_pdam/features/account/data/models/user_profile_model.dart';
import 'package:app_movil_pdam/features/account/data/repository_impl/account_repository_impl.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/models/auth_token_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRemote implements AccountRemoteDatasource {
  Object? error;
  UserProfileModel? profile;
  AccountUpdateResponseModel? updateResponse;
  AccountUpdate? lastUpdate;
  String? lastPassword;
  int getCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;

  @override
  Future<UserProfileModel> getProfile() async {
    getCalls++;
    if (error != null) throw error!;
    return profile ??
        const UserProfileModel(email: 'user@x.com', isActive: true);
  }

  @override
  Future<AccountUpdateResponseModel> updateProfile(AccountUpdate update) async {
    updateCalls++;
    lastUpdate = update;
    if (error != null) throw error!;
    return updateResponse ??
        AccountUpdateResponseModel(
          profile:
              profile ??
              const UserProfileModel(email: 'user@x.com', isActive: true),
        );
  }

  @override
  Future<bool> deleteAccount(String password) async {
    deleteCalls++;
    lastPassword = password;
    if (error != null) throw error!;
    return true;
  }
}

class _FakeLocal implements LocalProfileDatasource {
  UserProfile? cached;
  Object? error;
  int getCalls = 0;
  int saveCalls = 0;
  int deleteCalls = 0;
  UserProfile? saved;

  @override
  Future<UserProfile?> getCachedProfile() async {
    getCalls++;
    if (error != null) throw error!;
    return cached;
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    saveCalls++;
    if (error != null) throw error!;
    saved = profile;
    cached = profile;
  }

  @override
  Future<void> deleteProfile(String correoNormalizado) async {
    deleteCalls++;
    if (cached?.email == correoNormalizado) cached = null;
  }
}

class _FakeAuthLocal implements AuthLocalDatasource {
  String? email;
  String? password;
  int actualizaciones = 0;
  Object? error;

  @override
  Future<AuthTokenModel> cacheToken(String token, String typeToken) async =>
      AuthTokenModel(token: token, typeToken: typeToken);

  @override
  Future<AuthTokenModel> getToken() async =>
      AuthTokenModel(token: 'token', typeToken: 'bearer');

  @override
  Future<void> deleteToken() async {}

  @override
  Future<void> cacheUserCredentials(String email, String password) async {
    this.email = email;
    this.password = password;
  }

  @override
  Future<Map<String, String?>> getCachedCredentials() async => {
    'email': email,
    'password': password,
  };

  @override
  Future<void> clearCachedCredentials() async {
    email = null;
    password = null;
  }

  @override
  Future<void> updateCachedCredentials({String? email, String? password}) async {
    actualizaciones++;
    if (error != null) throw error!;
    if (email != null) this.email = email;
    if (password != null) this.password = password;
  }
}

void main() {
  late _FakeRemote remote;
  late _FakeLocal local;
  late _FakeAuthLocal authLocal;
  late AccountRepositoryImpl repository;

  setUp(() {
    remote = _FakeRemote();
    local = _FakeLocal();
    authLocal = _FakeAuthLocal();
    repository = AccountRepositoryImpl(
      remoteDatasource: remote,
      localProfileDatasource: local,
      authLocalDatasource: authLocal,
    );
  });

  group('getProfile (RF-06, RF-07, RF-08)', () {
    test(
      'con red devuelve el perfil del servidor y lo guarda en caché',
      () async {
        remote.profile = const UserProfileModel(
          email: '  User@X.com ',
          isActive: true,
        );

        final resultado = await repository.getProfile();

        resultado.fold((fallo) => fail('No debería fallar: ${fallo.message}'), (
          snapshot,
        ) {
          expect(snapshot.desdeCache, isFalse);
          expect(snapshot.profile.email, 'user@x.com');
          expect(snapshot.profile.isActive, isTrue);
        });
        expect(local.saveCalls, 1);
        expect(local.saved?.email, 'user@x.com');
      },
    );

    test('la caché solo guarda respuestas del servidor', () async {
      local.cached = const UserProfile(email: 'viejo@x.com', isActive: true);
      remote.error = NetworkFailures(
        'Se requiere conexión con el servidor para completar esta operación.',
      );

      await repository.getProfile();

      expect(local.saveCalls, 0);
      expect(local.saved, isNull);
    });

    test('sin red devuelve el perfil cacheado marcado como caché', () async {
      remote.error = NetworkFailures(
        'Se requiere conexión con el servidor para completar esta operación.',
      );
      local.cached = const UserProfile(email: 'user@x.com', isActive: false);

      final resultado = await repository.getProfile();

      resultado.fold((fallo) => fail('No debería fallar: ${fallo.message}'), (
        snapshot,
      ) {
        expect(snapshot.desdeCache, isTrue);
        expect(snapshot.profile.email, 'user@x.com');
        expect(snapshot.profile.isActive, isFalse);
      });
    });

    test('sin red y sin caché devuelve NoCachedProfileFailure', () async {
      remote.error = NetworkFailures('sin conexión');

      final resultado = await repository.getProfile();

      resultado.fold((fallo) {
        expect(fallo, isA<NoCachedProfileFailure>());
        expect(
          fallo.message,
          'No hay datos de tu cuenta guardados en este dispositivo. '
          'Conéctate para consultarlos.',
        );
      }, (_) => fail('No debería devolver datos sin perfil cacheado'));
    });

    test('un 401 unauthorized no devuelve la caché', () async {
      remote.error = AccountFailure(
        'unauthorized',
        'La sesión no es válida. Vuelve a iniciar sesión.',
      );
      local.cached = const UserProfile(email: 'user@x.com', isActive: true);

      final resultado = await repository.getProfile();

      resultado.fold((fallo) {
        expect(fallo, isA<UnauthorizedFailure>());
        expect(
          fallo.message,
          'La sesión no es válida. Vuelve a iniciar sesión.',
        );
      }, (_) => fail('No debería devolver la caché ante un 401'));
      expect(local.getCalls, 0);
    });

    test('un rechazo de negocio distinto del 401 no cae a la caché', () async {
      remote.error = AccountFailure(
        'server_error',
        'No se pudo completar la operación. Inténtalo de nuevo.',
      );
      local.cached = const UserProfile(email: 'user@x.com', isActive: true);

      final resultado = await repository.getProfile();

      resultado.fold(
        (fallo) => expect(fallo, isA<AccountFailure>()),
        (_) => fail('No debería devolver la caché ante un 500'),
      );
      expect(local.getCalls, 0);
    });

    test('si la caché no se puede escribir se sigue mostrando el perfil del '
        'servidor', () async {
      local.error = Exception('isar no disponible');

      final resultado = await repository.getProfile();

      resultado.fold(
        (fallo) => fail('No debería fallar: ${fallo.message}'),
        (snapshot) => expect(snapshot.desdeCache, isFalse),
      );
    });

    test('un error inesperado se traduce al texto del catálogo, sin filtrar '
        'el detalle técnico', () async {
      remote.error = Exception('detalle interno de dio');
      local.cached = const UserProfile(email: 'user@x.com', isActive: true);

      final resultado = await repository.getProfile();

      resultado.fold((fallo) {
        expect(fallo, isA<ServerFailures>());
        expect(fallo.message, MensajesCuenta.errorServidor);
        expect(fallo.message, isNot(contains('detalle interno')));
        expect(fallo.message, isNot(contains('Exception')));
      }, (_) => fail('No debería devolver datos ante un error inesperado'));
      expect(local.getCalls, 0);
    });
  });

  group('cachedProfile (RF-07, RF-09)', () {
    test('devuelve el perfil guardado', () async {
      local.cached = const UserProfile(email: 'user@x.com', isActive: true);

      final resultado = await repository.cachedProfile();

      resultado.fold(
        (fallo) => fail('No debería fallar: ${fallo.message}'),
        (perfil) => expect(perfil?.email, 'user@x.com'),
      );
    });

    test('sin perfil guardado devuelve null y no inventa un correo', () async {
      final resultado = await repository.cachedProfile();

      resultado.fold(
        (fallo) => fail('No debería fallar: ${fallo.message}'),
        (perfil) => expect(perfil, isNull),
      );
    });
  });

  group('updateProfile (RF-10, RF-11, RF-13)', () {
    test('sin conexión no escribe nada, no encola y avisa', () async {
      remote.error = NetworkFailures('sin conexión');

      final resultado = await repository.updateProfile(
        const AccountUpdate(correo: 'nuevo@x.com'),
      );

      resultado.fold(
        (fallo) => expect(fallo, isA<ConnectivityRequiredFailures>()),
        (_) => fail('No debería aplicar el cambio sin conexión'),
      );
      expect(local.saveCalls, 0);
      expect(local.deleteCalls, 0);
      expect(local.saved, isNull);
    });

    test('normaliza el correo antes de enviarlo', () async {
      remote.updateResponse = AccountUpdateResponseModel(
        profile: const UserProfileModel(email: 'nuevo@x.com', isActive: true),
      );

      await repository.updateProfile(
        const AccountUpdate(correo: '  Nuevo@X.com '),
      );

      expect(remote.lastUpdate?.correo, 'nuevo@x.com');
    });

    test('con éxito devuelve el token nuevo y actualiza la caché', () async {
      remote.updateResponse = AccountUpdateResponseModel(
        profile: const UserProfileModel(email: 'nuevo@x.com', isActive: true),
        accessToken: 'token-nuevo',
        tokenType: 'bearer',
      );

      final resultado = await repository.updateProfile(
        const AccountUpdate(correo: 'nuevo@x.com'),
      );

      resultado.fold((fallo) => fail('No debería fallar: ${fallo.message}'), (
        actualizacion,
      ) {
        expect(actualizacion.profile.email, 'nuevo@x.com');
        expect(actualizacion.tokenNuevo, 'token-nuevo');
      });
      expect(local.saved?.email, 'nuevo@x.com');
    });

    test('RF-14: al cambiar el correo actualiza las credenciales cifradas y '
        'conserva la contraseña guardada', () async {
      authLocal.email = 'user@x.com';
      authLocal.password = 'claveVigente';
      remote.updateResponse = AccountUpdateResponseModel(
        profile: const UserProfileModel(email: 'nuevo@x.com', isActive: true),
        accessToken: 'token-nuevo',
      );

      await repository.updateProfile(const AccountUpdate(correo: 'nuevo@x.com'));

      expect(authLocal.actualizaciones, 1);
      expect(authLocal.email, 'nuevo@x.com');
      expect(authLocal.password, 'claveVigente');
    });

    test('RF-14: al cambiar solo la contraseña conserva el correo cifrado', () async {
      authLocal.email = 'user@x.com';
      authLocal.password = 'claveVigente';
      remote.updateResponse = AccountUpdateResponseModel(
        profile: const UserProfileModel(email: 'user@x.com', isActive: true),
      );

      await repository.updateProfile(
        const AccountUpdate(passwordNueva: 'claveNueva'),
      );

      expect(authLocal.actualizaciones, 1);
      expect(authLocal.email, 'user@x.com');
      expect(authLocal.password, 'claveNueva');
    });

    test('un rechazo del servidor no toca las credenciales cifradas', () async {
      remote.error = AccountFailure(
        'email_already_registered',
        'El correo electrónico ya está registrado.',
      );

      await repository.updateProfile(const AccountUpdate(correo: 'ocupado@x.com'));

      expect(authLocal.actualizaciones, 0);
    });

    test('si el correo no cambia, el token nuevo es nulo', () async {
      remote.updateResponse = AccountUpdateResponseModel(
        profile: const UserProfileModel(email: 'user@x.com', isActive: true),
      );

      final resultado = await repository.updateProfile(
        const AccountUpdate(passwordNueva: 'unaClaveLarga'),
      );

      resultado.fold(
        (fallo) => fail('No debería fallar: ${fallo.message}'),
        (actualizacion) => expect(actualizacion.tokenNuevo, isNull),
      );
    });

    test('un correo ya registrado no aplica ni escribe nada', () async {
      remote.error = AccountFailure(
        'email_already_registered',
        'El correo electrónico ya está registrado.',
      );

      final resultado = await repository.updateProfile(
        const AccountUpdate(correo: 'ocupado@x.com'),
      );

      resultado.fold((fallo) {
        expect(fallo, isA<AccountFailure>());
        expect((fallo as AccountFailure).code, 'email_already_registered');
      }, (_) => fail('No debería aplicar el cambio'));
      expect(local.saveCalls, 0);
    });

    test('un 401 se propaga como sesión inválida', () async {
      remote.error = AccountFailure(
        'unauthorized',
        'La sesión no es válida. Vuelve a iniciar sesión.',
      );

      final resultado = await repository.updateProfile(
        const AccountUpdate(correo: 'nuevo@x.com'),
      );

      resultado.fold(
        (fallo) => expect(fallo, isA<UnauthorizedFailure>()),
        (_) => fail('No debería aplicar el cambio'),
      );
      expect(local.saveCalls, 0);
    });

    test(
      'un 500 conflict se devuelve como fallo de cuenta reintentable',
      () async {
        remote.error = AccountFailure(
          'conflict',
          'No se pudo completar la operación. Inténtalo de nuevo.',
        );

        final resultado = await repository.updateProfile(
          const AccountUpdate(correo: 'nuevo@x.com'),
        );

        resultado.fold(
          (fallo) => expect((fallo as AccountFailure).code, 'conflict'),
          (_) => fail('No debería aplicar el cambio'),
        );
        expect(local.saveCalls, 0);
      },
    );

    test('un error inesperado responde el texto del catálogo sin escribir '
        'nada', () async {
      remote.error = Exception('detalle interno de dio');

      final resultado = await repository.updateProfile(
        const AccountUpdate(correo: 'nuevo@x.com'),
      );

      resultado.fold((fallo) {
        expect(fallo, isA<ServerFailures>());
        expect(fallo.message, MensajesCuenta.errorServidor);
        expect(fallo.message, isNot(contains('detalle interno')));
      }, (_) => fail('No debería aplicar el cambio'));
      expect(local.saveCalls, 0);
    });
  });

  group('deleteAccount (RF-17, RF-18, RF-20)', () {
    test('sin conexión no elimina nada, no encola y avisa', () async {
      remote.error = NetworkFailures('sin conexión');

      final resultado = await repository.deleteAccount('claveActual');

      resultado.fold(
        (fallo) => expect(fallo, isA<ConnectivityRequiredFailures>()),
        (_) => fail('No debería eliminar sin conexión'),
      );
      expect(local.deleteCalls, 0);
    });

    test(
      'con éxito devuelve verdadero y no borra datos locales todavía',
      () async {
        final resultado = await repository.deleteAccount('claveActual');

        resultado.fold(
          (fallo) => fail('No debería fallar: ${fallo.message}'),
          (eliminada) => expect(eliminada, isTrue),
        );
        expect(remote.lastPassword, 'claveActual');
        expect(local.deleteCalls, 0);
      },
    );

    test('una contraseña incorrecta se devuelve sin cambios', () async {
      remote.error = AccountFailure(
        'invalid_password',
        'La contraseña no es correcta.',
      );

      final resultado = await repository.deleteAccount('incorrecta');

      resultado.fold((fallo) {
        expect((fallo as AccountFailure).code, 'invalid_password');
        expect(fallo.message, 'La contraseña no es correcta.');
      }, (_) => fail('No debería eliminar con contraseña incorrecta'));
      expect(local.deleteCalls, 0);
    });

    test('un 401 se propaga como sesión inválida', () async {
      remote.error = AccountFailure(
        'unauthorized',
        'La sesión no es válida. Vuelve a iniciar sesión.',
      );

      final resultado = await repository.deleteAccount('claveActual');

      resultado.fold(
        (fallo) => expect(fallo, isA<UnauthorizedFailure>()),
        (_) => fail('No debería eliminar'),
      );
    });
    test('un error inesperado responde el texto del catálogo sin eliminar '
        'nada', () async {
      remote.error = Exception('detalle interno de dio');

      final resultado = await repository.deleteAccount('claveActual');

      resultado.fold((fallo) {
        expect(fallo, isA<ServerFailures>());
        expect(fallo.message, MensajesCuenta.errorServidor);
        expect(fallo.message, isNot(contains('detalle interno')));
      }, (_) => fail('No debería eliminar la cuenta'));
      expect(local.deleteCalls, 0);
    });
  });
}
