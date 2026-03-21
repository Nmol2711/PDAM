import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';

class SaveTokenUseCase {
  final AuthRepository repository;

  SaveTokenUseCase(this.repository);

  Future<void> execute(AuthToken token) async {
    await repository.saveToken(token);
  }
}
