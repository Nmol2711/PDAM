import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:dartz/dartz.dart';

import 'package:dio/dio.dart';

Either<Failures, Dio> getDioClient(AuthToken? token) {
  try {
    // 1. Validación previa (Ejemplo: URL mal formada)
    if (ApiConstants.baseUrl.isEmpty) {
      return Left(ConfigurationFailure("La URL base no está configurada"));
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 3),
      ),
    );

    // 2. Agregar Interceptor para el Token
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (token != null && token.accessToken.isNotEmpty) {
            options.headers['Authorization'] =
                '${token.tokenType} ${token.accessToken}';
          }
          return handler.next(options);
        },
      ),
    );

    return Right(dio);
  } catch (e) {
    return Left(NetworkFailures("Error al inicializar el cliente: $e"));
  }
}
