import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';

class GetTokenUseCase {
  final AuthRepository repository;

  GetTokenUseCase(this.repository);

  Future<AuthToken?> execute() async {
    final result = await repository.getToken();
    return result;
  }
}
