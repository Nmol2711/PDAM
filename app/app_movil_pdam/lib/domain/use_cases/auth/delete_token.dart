import 'package:app_movil_pdam/domain/repositories/auth_repository.dart';

class DeleteToken {
  final AuthRepository repository;

  DeleteToken(this.repository);
  Future<void> execute() async {
    await repository.deleteToken();
  }
}
