import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';
import 'package:dartz/dartz.dart';

abstract class AuthTokenRepositories {
  Future<Either<Failures, AuthToken>> cacheToken(
    String token, {
    String typeToken = 'Bearer',
  });

  Future<Either<Failures, AuthToken>> getToken();

  Future<Either<Failures, void>> deleteToken();
}
