import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/account/data/datasource/local/local_profile_datasource.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/remote/auth_remote_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/models/auth_token_model.dart';
import 'package:app_movil_pdam/features/auth/data/models/user_model.dart';
import 'package:app_movil_pdam/features/auth/data/repositories_impl/user_repositories_impl.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthLocalDatasource implements AuthLocalDatasource {
  final Map<String, String> storage = {};
  bool tokenCached = false;
  bool credentialsCached = false;

  @override
  Future<AuthTokenModel> cacheToken(String token, String typeToken) async {
    tokenCached = true;
    storage['token'] = token;
    return AuthTokenModel(token: token, typeToken: typeToken);
  }

  @override
  Future<void> deleteToken() async {
    storage.clear();
  }

  @override
  Future<AuthTokenModel> getToken() async {
    if (storage.containsKey('token')) {
      return AuthTokenModel(token: storage['token']!, typeToken: 'Bearer');
    }
    throw Exception('No token');
  }

  @override
  Future<void> cacheUserCredentials(String email, String password) async {
    credentialsCached = true;
    storage['email'] = email;
    storage['password'] = password;
  }

  @override
  Future<Map<String, String?>> getCachedCredentials() async {
    return {'email': storage['email'], 'password': storage['password']};
  }

  @override
  Future<void> clearCachedCredentials() async {
    storage.remove('email');
    storage.remove('password');
  }

  @override
  Future<void> updateCachedCredentials({String? email, String? password}) async {
    if (email != null) storage['email'] = email;
    if (password != null) storage['password'] = password;
  }
}

class _FakeAuthRemoteDatasource implements AuthRemoteDatasource {
  Object? errorCurrentUser;
  Object? errorLogin;
  Object? errorRegister;
  String emailActual = 'online@test.com';
  int llamadasCurrentUser = 0;

  @override
  Future<UserModel> currentUser() async {
    llamadasCurrentUser++;
    if (errorCurrentUser != null) throw errorCurrentUser!;
    return UserModel(id: 1, email: emailActual);
  }

  @override
  Future<AuthTokenModel> login(String email, String password) async {
    if (errorLogin != null) throw errorLogin!;
    return AuthTokenModel(token: 'fake-token', typeToken: 'Bearer');
  }

  @override
  Future<UserModel> register(String email, String password) async {
    if (errorRegister != null) throw errorRegister!;
    return UserModel(id: 1, email: email);
  }
}

class _FakeLocalProfileDatasource implements LocalProfileDatasource {
  UserProfile? perfil;
  Object? error;
  int getCalls = 0;

  @override
  Future<UserProfile?> getCachedProfile() async {
    getCalls++;
    if (error != null) throw error!;
    return perfil;
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    perfil = profile;
  }

  @override
  Future<void> deleteProfile(String correoNormalizado) async {
    if (perfil?.email == correoNormalizado) perfil = null;
  }
}

void main() {
  late UserRepositoriesImpl repository;
  late _FakeAuthLocalDatasource local;
  late _FakeAuthRemoteDatasource remote;
  late _FakeLocalProfileDatasource perfiles;

  setUp(() {
    local = _FakeAuthLocalDatasource();
    remote = _FakeAuthRemoteDatasource();
    perfiles = _FakeLocalProfileDatasource();
    repository = UserRepositoriesImpl(
      authLocalDatasource: local,
      authRemoteDatasource: remote,
      localProfileDatasource: perfiles,
    );
  });

  group('login', () {
    test('conectado guarda las credenciales y devuelve el correo del '
        'servidor', () async {
      final result = await repository.login('test@pdam.com', '12345678');

      expect(result.isRight(), isTrue);
      expect(local.credentialsCached, isTrue);
      result.fold(
        (l) => fail('No debería fallar'),
        (user) => expect(user.email, 'online@test.com'),
      );
    });

    test('sin conexión usa las credenciales cacheadas y devuelve el correo '
        'normalizado', () async {
      await local.cacheUserCredentials('offline@pdam.com', 'password123');
      remote.errorLogin = NetworkFailures(MensajesCuenta.sinConexion);

      final result = await repository.login('  Offline@PDAM.com ', 'password123');

      result.fold(
        (l) => fail('Debería usar el modo sin conexión: ${l.message}'),
        (user) => expect(user.email, 'offline@pdam.com'),
      );
    });

    test('sin conexión y con credenciales distintas rechaza con el texto del '
        'catálogo', () async {
      await local.cacheUserCredentials('offline@pdam.com', 'correctpass');
      remote.errorLogin = NetworkFailures(MensajesCuenta.sinConexion);

      final result = await repository.login('offline@pdam.com', 'wrongpass');

      result.fold((fallo) {
        expect(fallo, isA<AccountFailure>());
        expect(fallo.message, MensajesCuenta.credencialesInvalidas);
        expect(fallo.message, isNot(contains('Exception')));
      }, (_) => fail('No debería autenticar con credenciales distintas'));
    });

    test('un rechazo de credenciales no cae al modo sin conexión aunque las '
        'credenciales cacheadas coincidan', () async {
      await local.cacheUserCredentials('offline@pdam.com', 'correctpass');
      remote.errorLogin = AccountFailure(
        CodigosCuenta.invalidCredentials,
        MensajesCuenta.credencialesInvalidas,
      );

      final result = await repository.login('offline@pdam.com', 'correctpass');

      result.fold((fallo) {
        expect(fallo, isA<AccountFailure>());
        expect(
          (fallo as AccountFailure).code,
          CodigosCuenta.invalidCredentials,
        );
        expect(fallo.message, 'Correo o contraseña incorrectos');
      }, (_) => fail('No debería autenticar sin conexión tras un rechazo'));
    });

    test('un error no tipado responde el texto del catálogo y nunca el '
        'toString de la excepción', () async {
      remote.errorLogin = Exception('detalle interno de dio');

      final result = await repository.login('test@pdam.com', '12345678');

      result.fold((fallo) {
        expect(fallo, isA<ServerFailures>());
        expect(fallo.message, MensajesCuenta.errorServidor);
        expect(fallo.message, isNot(contains('detalle interno')));
        expect(fallo.message, isNot(contains('Exception')));
      }, (_) => fail('No debería autenticar con un error inesperado'));
    });
  });

  group('currentUser (RF-07, RF-08)', () {
    test('conectado devuelve el correo real del servidor normalizado', () async {
      remote.emailActual = '  Real@X.com ';

      final result = await repository.currentUser();

      result.fold(
        (l) => fail('No debería fallar: ${l.message}'),
        (user) => expect(user.email, 'real@x.com'),
      );
    });

    test('sin red devuelve el correo real cacheado, no un correo de relleno',
        () async {
      await local.cacheToken('token', 'Bearer');
      perfiles.perfil = const UserProfile(
        email: 'guardado@x.com',
        isActive: true,
      );
      remote.errorCurrentUser = NetworkFailures(MensajesCuenta.sinConexion);

      final result = await repository.currentUser();

      result.fold(
        (l) => fail('Debería usar el perfil cacheado: ${l.message}'),
        (user) {
          expect(user.email, 'guardado@x.com');
          expect(user.email, isNot('usuario@offline.com'));
        },
      );
    });

    test('sin red y sin perfil cacheado devuelve fallo y no inventa un '
        'usuario', () async {
      await local.cacheToken('token', 'Bearer');
      remote.errorCurrentUser = NetworkFailures(MensajesCuenta.sinConexion);

      final result = await repository.currentUser();

      result.fold((fallo) {
        expect(fallo, isA<NoCachedProfileFailure>());
        expect(fallo.message, MensajesCuenta.sinPerfilCacheado);
      }, (_) => fail('No debería devolver un usuario sin perfil cacheado'));
    });

    test('sin token no restaura la sesión aunque exista perfil cacheado',
        () async {
      perfiles.perfil = const UserProfile(
        email: 'guardado@x.com',
        isActive: true,
      );
      remote.errorCurrentUser = NetworkFailures(MensajesCuenta.sinConexion);

      final result = await repository.currentUser();

      expect(result.isLeft(), isTrue);
      expect(perfiles.getCalls, 0);
    });

    test('un 401 no devuelve el perfil cacheado como si la cuenta existiera',
        () async {
      await local.cacheToken('token', 'Bearer');
      perfiles.perfil = const UserProfile(
        email: 'guardado@x.com',
        isActive: true,
      );
      remote.errorCurrentUser = UnauthorizedFailure(
        MensajesCuenta.sesionInvalida,
      );

      final result = await repository.currentUser();

      result.fold(
        (fallo) => expect(fallo, isA<UnauthorizedFailure>()),
        (_) => fail('No debería devolver la caché ante un 401'),
      );
      expect(perfiles.getCalls, 0);
    });
  });

  group('register', () {
    test('un correo duplicado devuelve el texto del catálogo', () async {
      remote.errorRegister = AccountFailure(
        CodigosCuenta.emailAlreadyRegistered,
        'El correo electrónico ya está registrado.',
      );

      final result = await repository.register(
        'ocupado@x.com',
        '12345678',
        '12345678',
      );

      result.fold((fallo) {
        expect(fallo, isA<AccountFailure>());
        expect(
          fallo.message,
          'El correo electrónico ya está registrado.',
        );
      }, (_) => fail('No debería registrar un correo duplicado'));
    });

    test('un error no tipado responde el texto del catálogo', () async {
      remote.errorRegister = Exception('detalle interno de dio');

      final result = await repository.register(
        'nuevo@x.com',
        '12345678',
        '12345678',
      );

      result.fold((fallo) {
        expect(fallo, isA<ServerFailures>());
        expect(fallo.message, MensajesCuenta.errorServidor);
        expect(fallo.message, isNot(contains('detalle interno')));
      }, (_) => fail('No debería registrar con un error inesperado'));
    });
  });
}
