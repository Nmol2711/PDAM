import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:dartz/dartz.dart';

class RegisterTokenUc {
  final AuthTokenRepositories repository;

  const RegisterTokenUc({required this.repository});

  Future<Either<Failures, AuthToken>> call(
    String token, {
    String typeToken = 'bearer',
  }) async {
    return await repository.cacheToken(token, typeToken: typeToken);
  }
}
