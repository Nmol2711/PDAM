import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/remote/auth_remote_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/models/auth_token_model.dart';
import 'package:app_movil_pdam/features/auth/data/models/user_model.dart';
import 'package:app_movil_pdam/features/auth/data/repositories_impl/user_repositories_impl.dart';

class MockAuthLocalDatasource implements AuthLocalDatasource {
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
}

class MockAuthRemoteDatasource implements AuthRemoteDatasource {
  bool shouldThrow = false;

  @override
  Future<UserModel> currentUser() async {
    if (shouldThrow) throw Exception('Server offline');
    return UserModel(id: 1, email: 'online@test.com');
  }

  @override
  Future<AuthTokenModel> login(String email, String password) async {
    if (shouldThrow) throw Exception('Server offline or timeout');
    return AuthTokenModel(token: 'fake-token', typeToken: 'Bearer');
  }

  @override
  Future<UserModel> register(String email, String password) async {
    return UserModel(id: 1, email: email);
  }
}

void main() {
  late UserRepositoriesImpl repository;
  late MockAuthLocalDatasource mockLocal;
  late MockAuthRemoteDatasource mockRemote;

  setUp(() {
    mockLocal = MockAuthLocalDatasource();
    mockRemote = MockAuthRemoteDatasource();
    repository = UserRepositoriesImpl(
      authLocalDatasource: mockLocal,
      authRemoteDatasource: mockRemote,
    );
  });

  test('debe realizar login online con éxito y cachear credenciales', () async {
    // Act
    final result = await repository.login('test@pdam.com', '123456');

    // Assert
    expect(result.isRight(), true);
    expect(mockLocal.credentialsCached, true);
    result.fold(
      (l) => fail('No debería fallar'),
      (user) => expect(user.email, 'online@test.com'),
    );
  });

  test('debe autenticar localmente con credenciales cacheadas cuando el servidor falla o hay timeout (RF-02)', () async {
    // Arrange: Primero cacheamos credenciales válidas
    await mockLocal.cacheUserCredentials('offline@pdam.com', 'password123');
    mockRemote.shouldThrow = true; // Simulamos caída del servidor / timeout de 10s

    // Act
    final result = await repository.login('offline@pdam.com', 'password123');

    // Assert
    expect(result.isRight(), true);
    result.fold(
      (l) => fail('Debería usar fallback offline'),
      (user) => expect(user.email, 'offline@pdam.com'),
    );
  });

  test('debe fallar el login offline si las credenciales cacheadas no coinciden', () async {
    // Arrange
    await mockLocal.cacheUserCredentials('offline@pdam.com', 'correctpass');
    mockRemote.shouldThrow = true;

    // Act
    final result = await repository.login('offline@pdam.com', 'wrongpass');

    // Assert
    expect(result.isLeft(), true);
  });
}
