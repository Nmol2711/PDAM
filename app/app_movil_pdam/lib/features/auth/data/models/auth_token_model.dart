import 'package:app_movil_pdam/features/auth/domain/entity/auth_token.dart';

class AuthTokenModel extends AuthToken {
  AuthTokenModel({required super.token, super.typeToken = 'bearer'});

  factory AuthTokenModel.fromJson(Map<String, dynamic> json) {
    return AuthTokenModel(
      token: json['access_token'],
      typeToken: json['token_type'],
    );
  }
}
