import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/data/data_sources/local/auth_local_data_source.dart';
import 'package:app_movil_pdam/data/data_sources/remote/auth_remote_data_source.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/entities/user_entity.dart';
import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';
import 'package:dartz/dartz.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource authRemoteDataSource;
  final AuthLocalDataSource authLocalDataSource;

  AuthRepositoryImpl({
    required this.authLocalDataSource,
    required this.authRemoteDataSource,
  });

  @override
  Future<Either<Failures, AuthToken>> login(
    String email,
    String password,
  ) async {
    try {
      final resp = await authRemoteDataSource.login(email, password);
      await authLocalDataSource.saveToken(
        resp,
      ); //guardar el token automaticamente
      return Right(resp);
    } on ServerFailures catch (e) {
      return Left(e);
    }
  }

  @override
  Future<Either<Failures, UserEntity>> getCurrentUser(AuthToken token) async {
    try {
      final resp = await authRemoteDataSource.getCurrentUser(token);
      return Right(resp);
    } on ServerFailures catch (e) {
      return Left(e);
    }
  }

  @override
  Future<Either<Failures, UserEntity>> signUp(
    String email,
    String password,
  ) async {
    try {
      final resp = await authRemoteDataSource.signUp(email, password);
      return Right(resp);
    } on ServerFailures catch (e) {
      return Left(e);
    }
  }

  @override
  Future<AuthToken?> getToken() async {
    try {
      final resp = await authLocalDataSource.getToken();
      return resp;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> saveToken(AuthToken token) async {
    final resp = await authLocalDataSource.saveToken(token);
    return resp;
  }

  @override
  Future<void> deleteToken() async {
    return await authLocalDataSource.deleteToken();
  }
}
