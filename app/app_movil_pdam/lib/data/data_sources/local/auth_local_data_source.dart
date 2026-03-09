import 'dart:convert';

import 'package:app_movil_pdam/data/models/auth_model.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class AuthLocalDataSource {
  Future<void> saveToken(AuthToken token);
  Future<AuthToken?> getToken();
  Future<void> deleteToken();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final FlutterSecureStorage storage;
  static const String _tokenKey = "AUTH_TOKEN";

  AuthLocalDataSourceImpl({required this.storage});

  @override
  Future<void> saveToken(AuthToken token) async {
    // Convertimos el modelo a un String JSON para guardarlo

    final String tokenJson = json.encode(AuthModel.fromEntity(token).toJson());
    await storage.write(key: _tokenKey, value: tokenJson);
  }

  @override
  Future<AuthToken?> getToken() async {
    final String? tokenJson = await storage.read(key: _tokenKey);

    if (tokenJson != null) {
      // Si existe, lo convertimos de String JSON a nuestro objeto AuthModel
      return AuthModel.fromJson(json.decode(tokenJson));
    }
    return null;
  }

  @override
  Future<void> deleteToken() async {
    await storage.delete(key: _tokenKey);
  }
}
