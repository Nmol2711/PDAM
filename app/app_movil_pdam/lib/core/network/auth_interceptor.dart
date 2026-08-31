import 'package:app_movil_pdam/core/constant/token_constant.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class AuthInterceptor extends Interceptor {
  final StorageService _storageService;

  AuthInterceptor({required StorageService storageService})
    : _storageService = storageService;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    String? token;
    String? typeToken;

    final resultToken = await _storageService.getString(TokenConstant.keyToken);

    // Obtener el Token
    resultToken.fold(
      (failure) => debugPrint(
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
      (failure) => debugPrint(
        "Error leyendo el token desde el interceptor ${failure.message}",
      ),
      (localTypeToken) {
        if (localTypeToken != null) {
          typeToken = localTypeToken;
        }
      },
    );

    if (token != null && typeToken != null) {
      options.headers['Authorization'] = '$typeToken $token';
    }

    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      debugPrint('Sesión expirada: Error 401');

      await _storageService.deleteString(TokenConstant.keyToken);
      await _storageService.deleteString(TokenConstant.keyTypeToken);
    }
    super.onError(err, handler);
  }
}
