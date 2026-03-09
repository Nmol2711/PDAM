import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';
import 'package:dartz/dartz.dart';

class LoginUseCase {
  final AuthRepository repository;

  LoginUseCase(this.repository);

  Future<Either<Failures, AuthToken>> execute(
    String email,
    String password,
  ) async {
    final result = await repository.login(email, password);
    return result;
  }
}
