import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/auth_token_repositories.dart';
import 'package:dartz/dartz.dart';

class DeleteTokenUc {
  final AuthTokenRepositories repository;

  const DeleteTokenUc({required this.repository});

  Future<Either<Failures, void>> call() async {
    return await repository.deleteToken();
  }
}
