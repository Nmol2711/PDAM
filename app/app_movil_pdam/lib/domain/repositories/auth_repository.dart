import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/entities/user_entity.dart';
import 'package:dartz/dartz.dart';

abstract class AuthRepository {
  Future<Either<Failures, AuthToken>> login(
    String email,
    String password,
  ); // funcion para loguearse en la app

  Future<Either<Failures, UserEntity>> signUp(String email, String password);

  Future<Either<Failures, UserEntity>> getCurrentUser(
    AuthToken token,
  ); // funcion para obtener el usuario

  //persitencia de token
  Future<void> saveToken(AuthToken token);
  Future<AuthToken?> getToken();
  Future<void> deleteToken();
}
