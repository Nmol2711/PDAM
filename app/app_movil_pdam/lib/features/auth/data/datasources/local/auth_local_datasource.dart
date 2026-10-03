import 'package:app_movil_pdam/core/constant/token_constant.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/auth/data/models/auth_token_model.dart';

abstract class AuthLocalDatasource {
  Future<AuthTokenModel> cacheToken(String token, String typeToken);
  Future<AuthTokenModel> getToken();
  Future<void> deleteToken();
  Future<void> cacheUserCredentials(String email, String password);
  Future<Map<String, String?>> getCachedCredentials();
  Future<void> clearCachedCredentials();
}

class AuthLocalDatasourceImpl implements AuthLocalDatasource {
  final StorageService _storageService;

  AuthLocalDatasourceImpl({required StorageService storageService})
    : _storageService = storageService;

  @override
  Future<AuthTokenModel> cacheToken(String token, String typeToken) async {
    final resultToken = await _storageService.saveString(
      TokenConstant.keyToken,
      token,
    );

    resultToken.fold(
      (failure) =>
          throw Exception("Error al guardar el token ${failure.message}"),
      (_) => null,
    );
    final resultTypeToken = await _storageService.saveString(
      TokenConstant.keyTypeToken,
      typeToken,
    );
    resultTypeToken.fold(
      (failure) => throw Exception(
        "Error al guardar el tipo de token ${failure.message}",
      ),
      (_) => null,
    );

    return AuthTokenModel(token: token, typeToken: typeToken);
  }

  @override
  Future<void> deleteToken() async {
    final resultToken = await _storageService.deleteString(
      TokenConstant.keyToken,
    );

    resultToken.fold(
      (failure) =>
          throw Exception("Error al eliminar el token ${failure.message}"),
      (_) => null,
    );

    final resultTypeToken = await _storageService.deleteString(
      TokenConstant.keyTypeToken,
    );

    resultTypeToken.fold(
      (failure) => throw Exception(
        "Error al eliminar el tipo de token ${failure.message}",
      ),
      (_) => null,
    );
  }

  @override
  Future<AuthTokenModel> getToken() async {
    String? token;
    String? typeToken;

    final resultToken = await _storageService.getString(TokenConstant.keyToken);

    // Obtener el Token
    resultToken.fold(
      (failure) => throw Exception(
        "Error leyendo el token desde el interceptor ${failure.message}",
      ),
      (localToken) {
        if (localToken != null) {
          token = localToken;
        }
      },
    );

    final resultType = await _storageService.getString(
      TokenConstant.keyTypeToken,
    );

    // Obtener el tipo de token
    resultType.fold(
      (failure) => throw Exception(
        "Error leyendo el token desde el interceptor ${failure.message}",
      ),
      (localTypeToken) {
        if (localTypeToken != null) {
          typeToken = localTypeToken;
        }
      },
    );

    if (token == null || typeToken == null) {
      throw Exception('No se pudo obtener un token valido local');
    }

    return AuthTokenModel(token: token!, typeToken: typeToken!);
  }

  @override
  Future<void> cacheUserCredentials(String email, String password) async {
    final resultEmail = await _storageService.saveString(
      TokenConstant.keyCachedEmail,
      email,
    );
    resultEmail.fold(
      (failure) => throw Exception("Error al guardar email en caché: ${failure.message}"),
      (_) => null,
    );

    final resultPassword = await _storageService.saveString(
      TokenConstant.keyCachedPassword,
      password,
    );
    resultPassword.fold(
      (failure) => throw Exception("Error al guardar contraseña en caché: ${failure.message}"),
      (_) => null,
    );
  }

  @override
  Future<Map<String, String?>> getCachedCredentials() async {
    String? email;
    String? password;

    final resultEmail = await _storageService.getString(TokenConstant.keyCachedEmail);
    resultEmail.fold(
      (failure) => throw Exception("Error leyendo email de caché: ${failure.message}"),
      (val) => email = val,
    );

    final resultPassword = await _storageService.getString(TokenConstant.keyCachedPassword);
    resultPassword.fold(
      (failure) => throw Exception("Error leyendo contraseña de caché: ${failure.message}"),
      (val) => password = val,
    );

    return {'email': email, 'password': password};
  }

  @override
  Future<void> clearCachedCredentials() async {
    await _storageService.deleteString(TokenConstant.keyCachedEmail);
    await _storageService.deleteString(TokenConstant.keyCachedPassword);
  }
}
