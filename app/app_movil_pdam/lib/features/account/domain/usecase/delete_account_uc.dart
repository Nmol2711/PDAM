import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/account/domain/repository/account_repository.dart';
import 'package:dartz/dartz.dart';

/// Elimina la cuenta en el servidor con la contraseña actual (RF-17, RF-18).
class DeleteAccountUc {
  final AccountRepository repository;

  const DeleteAccountUc({required this.repository});

  Future<Either<Failures, bool>> call(String password) {
    return repository.deleteAccount(password);
  }
}
