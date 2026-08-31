import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:dartz/dartz.dart';

class RegisterUc {
  final UserRepositories repository;

  const RegisterUc({required this.repository});

  Future<Either<Failures, User>> call(
    String email,
    String password,
    String confirmPassword,
  ) async {
    return await repository.register(email, password, confirmPassword);
  }
}
