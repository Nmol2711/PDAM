import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';

class GetToken {
  final AuthRepository repository;

  GetToken(this.repository);

  Future<AuthToken?> execute() async {
    final result = await repository.getToken();
    return result;
  }
}
