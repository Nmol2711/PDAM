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
