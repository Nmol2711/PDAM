import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/user_entity.dart';
import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';
import 'package:dartz/dartz.dart';

class SingUpUseCase {
  final AuthRepository repository;

  SingUpUseCase(this.repository);

  Future<Either<Failures, UserEntity>> execute(
    String email,
    String password,
  ) async {
    return await repository.signUp(email, password);
  }
}
