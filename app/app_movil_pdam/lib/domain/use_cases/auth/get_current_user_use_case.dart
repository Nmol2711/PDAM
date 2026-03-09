import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/entities/user_entity.dart';
import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';
import 'package:dartz/dartz.dart';

class GetCurrentUserUseCase {
  final AuthRepository repository;
  GetCurrentUserUseCase(this.repository);

  Future<Either<Failures, UserEntity>> execute(AuthToken token) async {
    final result = await repository.getCurrentUser(token);
    return result;
  }
}
