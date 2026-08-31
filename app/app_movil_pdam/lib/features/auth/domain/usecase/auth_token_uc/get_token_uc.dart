import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:dartz/dartz.dart';

class GetTokenUc {
  final AuthTokenRepositories repository;

  const GetTokenUc({required this.repository});

  Future<Either<Failures, AuthToken>> call() async {
    return await repository.getToken();
  }
}
