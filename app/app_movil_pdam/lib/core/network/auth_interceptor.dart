import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/constant/token_constant.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class AuthInterceptor extends Interceptor {
  /// Código del contrato que describe un token rechazado.
  static const String _codigoUnauthorized = 'unauthorized';

  final StorageService _storageService;
  final SessionEvents _sessionEvents;

  AuthInterceptor({
    required StorageService storageService,
    required SessionEvents sessionEvents,
  }) : _storageService = storageService,
       _sessionEvents = sessionEvents;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Si es una ruta pública de autenticación, no adjuntamos el token. Las
    // rutas públicas se marcan además con `requiresToken: false`.
    if (options.extra['requiresToken'] == false ||
        options.path.contains('/auth/login') ||
        options.path.contains('/auth/register')) {
      return super.onRequest(options, handler);
    }

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
    if (err.response?.statusCode == 401 && _esSesionInvalida(err)) {
      // El interceptor solo avisa: la limpieza de la sesión (token, tipo,
      // credenciales y perfil cacheado) la ejecuta `AuthBloc` antes de emitir
      // el estado de sesión expirada (RF-19).
      _sessionEvents.notify(const SessionEvent.sesionExpirada());
    }
    super.onError(err, handler);
  }

  /// Decide si un 401 significa que la sesión dejó de ser válida (RF-05, RF-19).
  ///
  /// Solo se aplica a peticiones autenticadas. Las rutas públicas marcan su
  /// petición con `extra['requiresToken'] = false`, así que un login fallido
  /// (401 `invalid_credentials`) no borra el token ni avisa de sesión expirada.
  /// Un `detail.code` de negocio distinto de `unauthorized` tampoco describe un
  /// token rechazado y se descarta.
  ///
  /// La baja de la cuenta queda exenta (RF-05: «cualquier petición autenticada
  /// distinta de la baja de RF-18»): es idempotente y su 401 no debe
  /// confundirse con una sesión inválida. El error del catálogo llega al BLoC,
  /// que lo muestra, y la sesión se mantiene intacta.
  bool _esSesionInvalida(DioException err) {
    if (err.requestOptions.extra['requiresToken'] == false) {
      return false;
    }

    if (_esBajaDeCuenta(err.requestOptions)) {
      return false;
    }

    final codigo = _codigoDeError(err.response);
    if (codigo != null && codigo != _codigoUnauthorized) {
      return false;
    }

    return true;
  }

  /// Identifica `DELETE /users/me`, la baja de la cuenta (RF-18).
  ///
  /// Se compara contra [ApiConstants.currentUsers] para no duplicar la ruta ni
  /// depender de una lista ad hoc. Se usa la ruta del `Uri` porque Dio recibe
  /// la URL completa y puede añadir parámetros de consulta.
  bool _esBajaDeCuenta(RequestOptions options) {
    if (options.method.toUpperCase() != 'DELETE') return false;

    final rutaBaja = Uri.tryParse(ApiConstants.currentUsers)?.path;
    final rutaSolicitada = Uri.tryParse(options.path)?.path;
    return rutaBaja != null && rutaBaja == rutaSolicitada;
  }

  /// Código de negocio del contrato `detail={code,message}`, si lo hay.
  String? _codigoDeError(Response<dynamic>? respuesta) {
    final data = respuesta?.data;
    if (data is! Map) return null;
    final detalle = data['detail'];
    if (detalle is! Map) return null;
    final codigo = detalle['code'];
    return codigo?.toString();
  }
}
