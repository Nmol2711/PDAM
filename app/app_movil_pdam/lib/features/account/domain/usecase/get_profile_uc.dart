import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/repository/account_repository.dart';
import 'package:dartz/dartz.dart';

/// Consulta el perfil de la cuenta con caída al perfil cacheado (RF-06, RF-07).
class GetProfileUc {
  final AccountRepository repository;

  const GetProfileUc({required this.repository});

  Future<Either<Failures, ProfileSnapshot>> call() {
    return repository.getProfile();
  }
}
