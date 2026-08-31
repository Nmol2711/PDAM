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
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, User>> login(String email, String password) async {
    try {
      final token = await _authRemoteDatasource.login(email, password);
      await _authLocalDatasource.cacheToken(token.token, token.typeToken);
      return await currentUser();
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
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
        return Left(UserFailures("Las contrseñas deben ser iguale"));
      }

      final result = await _authRemoteDatasource.register(email, password);

      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }
}
