import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/remote/auth_remote_datasource.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:dartz/dartz.dart';

class UserRepositoriesImpl implements UserRepositories {
  final AuthLocalDatasource _authLocalDatasource;
  final AuthRemoteDatasource _authRemoteDatasource;

  UserRepositoriesImpl({
    required AuthLocalDatasource authLocalDatasource,
    required AuthRemoteDatasource authRemoteDatasource,
  }) : _authLocalDatasource = authLocalDatasource,
       _authRemoteDatasource = authRemoteDatasource;

  @override
  Future<Either<Failures, User>> currentUser() async {
    try {
      final result = await _authRemoteDatasource.currentUser();
      return Right(result);
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Si el servidor está apagado/sin internet, pero hay token local, permitimos acceso offline
      try {
        await _authLocalDatasource.getToken();
        return Right(User(id: 1, email: 'usuario@offline.com'));
      } catch (_) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, User>> login(String email, String password) async {
    try {
      // 1. Intentar login online con timeout estricto de 10 segundos (RF-02)
      final token = await _authRemoteDatasource.login(email, password).timeout(
        const Duration(seconds: 10),
      );
      await _authLocalDatasource.cacheToken(token.token, token.typeToken);
      // 2. Guardar credenciales de forma cifrada para autenticación offline posterior
      await _authLocalDatasource.cacheUserCredentials(email, password);
      return await currentUser();
    } catch (e) {
      // 🔄 OFFLINE FALLBACK: Timeout o error de red -> autenticación local usando credenciales cacheadas (RF-02)
      try {
        final cached = await _authLocalDatasource.getCachedCredentials();
        final cachedEmail = cached['email'];
        final cachedPassword = cached['password'];

        if (cachedEmail != null &&
            cachedPassword != null &&
            cachedEmail == email &&
            cachedPassword == password) {
          return Right(User(id: 1, email: email));
        } else {
          return Left(
            ServerFailures(
              "Sin conexión a internet y las credenciales locales no coinciden",
            ),
          );
        }
      } catch (localError) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        return Left(ServerFailures(errorMessage));
      }
    }
  }

  @override
  Future<Either<Failures, User>> register(
    String email,
    String password,
    String confirmPassword,
  ) async {
    try {
      if (password != confirmPassword) {
        return Left(UserFailures("Las contrseñas deben ser iguales"));
      }

      final result = await _authRemoteDatasource.register(email, password);

      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }
}
