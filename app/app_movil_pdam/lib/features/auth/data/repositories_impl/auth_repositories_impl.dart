import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:dartz/dartz.dart';

class AuthRepositoriesImpl implements AuthTokenRepositories {
  final AuthLocalDatasource _authLocalDatasource;

  AuthRepositoriesImpl({required AuthLocalDatasource authLocalDatasource})
    : _authLocalDatasource = authLocalDatasource;

  @override
  Future<Either<Failures, AuthToken>> cacheToken(
    String token, {
    String typeToken = 'Bearer',
  }) async {
    try {
      final result = await _authLocalDatasource.cacheToken(token, typeToken);
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, void>> deleteToken() async {
    try {
      await _authLocalDatasource.deleteToken();
      return Right(null);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }

  @override
  Future<Either<Failures, AuthToken>> getToken() async {
    try {
      final result = await _authLocalDatasource.getToken();
      return Right(result);
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      return Left(ServerFailures(errorMessage));
    }
  }
}
