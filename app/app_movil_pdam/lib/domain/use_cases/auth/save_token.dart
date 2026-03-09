import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';

class SaveToken {
  final AuthRepository repository;

  SaveToken(this.repository);

  Future<void> execute(AuthToken token) async {
    await repository.saveToken(token);
  }
}
