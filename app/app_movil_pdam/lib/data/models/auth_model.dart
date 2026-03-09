import 'package:app_movil_pdam/domain/entities/auth_token.dart';

class AuthModel extends AuthToken {
  AuthModel({required super.accessToken, required super.tokenType});
  factory AuthModel.fromJson(Map<String, dynamic> json) {
    return AuthModel(
      accessToken: json['access_token'],
      tokenType: json['token_type'],
    );
  }

  factory AuthModel.fromEntity(AuthToken entity) {
    return AuthModel(
      accessToken: entity.accessToken,
      tokenType: entity.tokenType,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['access_token'] = accessToken;
    data['token_type'] = tokenType;
    return data;
  }
}
