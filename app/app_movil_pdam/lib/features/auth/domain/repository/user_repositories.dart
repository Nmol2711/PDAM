import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:dartz/dartz.dart';

abstract class UserRepositories {
  Future<Either<Failures, User>> register(
    String email,
    String password,
    String confirmPassword,
  );

  Future<Either<Failures, User>> login(String email, String password);

  Future<Either<Failures, User>> currentUser();
}
