import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';

class DeleteTokenUseCase {
  final AuthRepository repository;

  DeleteTokenUseCase(this.repository);
  Future<void> execute() async {
    await repository.deleteToken();
  }
}
