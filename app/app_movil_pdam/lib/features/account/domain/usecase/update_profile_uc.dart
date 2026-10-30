import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/repository/account_repository.dart';
import 'package:dartz/dartz.dart';

/// Aplica la actualización del perfil en el servidor (RF-10, RF-13).
class UpdateProfileUc {
  final AccountRepository repository;

  const UpdateProfileUc({required this.repository});

  Future<Either<Failures, AccountUpdateResult>> call(AccountUpdate update) {
    return repository.updateProfile(update);
  }
}
