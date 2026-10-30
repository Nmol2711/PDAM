import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';

class MockStorageService implements StorageService {
  final Map<String, String> storage = {};

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    storage.remove(key);
    return const Right(null);
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async {
    return Right(storage[key]);
  }

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    storage[key] = value;
    return const Right(null);
  }
}

void main() {
  late AuthLocalDatasourceImpl dataSource;
  late MockStorageService mockStorageService;

  setUp(() {
    mockStorageService = MockStorageService();
    dataSource = AuthLocalDatasourceImpl(storageService: mockStorageService);
  });

  test('debe guardar y recuperar credenciales cacheadas de forma segura', () async {
    // Arrange
    const email = 'test@pdam.com';
    const password = 'securepassword123';

    // Act
    await dataSource.cacheUserCredentials(email, password);
    final credentials = await dataSource.getCachedCredentials();

    // Assert
    expect(credentials['email'], email);
    expect(credentials['password'], password);
  });

  test('actualiza el correo conservando la contraseña cifrada', () async {
    // RF-14: al cambiar solo el correo, la contraseña del dispositivo se
    // conserva para el acceso sin conexión.
    await dataSource.cacheUserCredentials('viejo@pdam.com', 'claveSegura123');

    await dataSource.updateCachedCredentials(email: 'nuevo@pdam.com');
    final credentials = await dataSource.getCachedCredentials();

    expect(credentials['email'], 'nuevo@pdam.com');
    expect(credentials['password'], 'claveSegura123');
  });

  test('actualiza la contraseña conservando el correo cifrado', () async {
    // RF-14: al cambiar solo la contraseña, el correo se conserva.
    await dataSource.cacheUserCredentials('cuenta@pdam.com', 'claveVieja123');

    await dataSource.updateCachedCredentials(password: 'claveNueva123');
    final credentials = await dataSource.getCachedCredentials();

    expect(credentials['email'], 'cuenta@pdam.com');
    expect(credentials['password'], 'claveNueva123');
  });

  test('actualiza correo y contraseña en la misma operación', () async {
    await dataSource.cacheUserCredentials('viejo@pdam.com', 'claveVieja123');

    await dataSource.updateCachedCredentials(
      email: 'nuevo@pdam.com',
      password: 'claveNueva123',
    );
    final credentials = await dataSource.getCachedCredentials();

    expect(credentials['email'], 'nuevo@pdam.com');
    expect(credentials['password'], 'claveNueva123');
  });

  test('sin credenciales previas no escribe datos a medias', () async {
    await dataSource.updateCachedCredentials(email: 'nuevo@pdam.com');
    final credentials = await dataSource.getCachedCredentials();

    expect(credentials['email'], null);
    expect(credentials['password'], null);
  });

  test('debe limpiar credenciales cacheadas correctamente', () async {
    // Arrange
    await dataSource.cacheUserCredentials('test@pdam.com', '123456');

    // Act
    await dataSource.clearCachedCredentials();
    final credentials = await dataSource.getCachedCredentials();

    // Assert
    expect(credentials['email'], null);
    expect(credentials['password'], null);
  });
}
