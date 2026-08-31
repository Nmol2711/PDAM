import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:dartz/dartz.dart';

class LoginUc {
  final UserRepositories repository;

  const LoginUc({required this.repository});
  /*
    El call permite llamar a la objecto como una funcion.
    En vez de LoginUc.login(emai, pass) se hace LoginUc(email, pass)
   */
  Future<Either<Failures, User>> call(String email, String password) async {
    return await repository.login(email, password);
  }
}
