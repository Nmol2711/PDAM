import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/network/auth_interceptor.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class DioClient {
  final Dio _dio;

  // _internal hace un constructor privado, lo que significa que nadie puede crear otra instancias desde fuera
  DioClient._internal({
    required StorageService storageService,
    required SessionEvents sessionEvents,
  }) : _dio = Dio() {
    _configureOptions();
    _configureInterceptor(storageService, sessionEvents);
  }

  // Instancia unica
  static DioClient? _instance;

  // 4. FACTORY CONSTRUCTOR: El punto de entrada público.
  // Si la instancia no existe, la crea; si ya existe, devuelve la que ya estaba en memoria.
  // [sessionEvents] es obligatorio y debe ser la misma instancia que escucha
  // `AuthBloc`: un 401 avisa por ese canal para que la sesión se limpie y se
  // cierre (RF-05, RF-19). Sin él, el interceptor avisaría a un canal que nadie
  // escucha y el token rechazado no cerraría la sesión.
  factory DioClient(
    StorageService storageService, {
    required SessionEvents sessionEvents,
  }) {
    _instance ??= DioClient._internal(
      storageService: storageService,
      sessionEvents: sessionEvents,
    );
    return _instance!;
  }

  Dio get dio => _dio;

  // Configuraciones de la opciones de red
  void _configureOptions() {
    _dio.options = BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(
        seconds: 5,
      ), // Tiempo de espera para conectar
      receiveTimeout: const Duration(
        seconds: 5,
      ), // Tiempo de espera para recibir
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
  }

  void _configureInterceptor(
    StorageService storageService,
    SessionEvents sessionEvents,
  ) {
    _dio.interceptors.addAll([
      AuthInterceptor(
        storageService: storageService,
        sessionEvents: sessionEvents,
      ),

      // Registro de peticiones sin datos sensibles (RNF-06).
      const _LogSinDatosSensibles(),
    ]);
  }
}

/// Deja rastro de cada petición sin volcar nada confidencial.
///
/// La cuenta envía `password` y `new_password` en el cuerpo y el token en la
/// cabecera `Authorization`, así que ni los cuerpos ni las cabeceras pueden
/// imprimirse: solo método, ruta y estado, que es lo necesario para
/// diagnosticar sin exponer contraseñas ni sesiones (RNF-06, principio 5).
class _LogSinDatosSensibles extends Interceptor {
  const _LogSinDatosSensibles();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[HTTP] ${options.method} ${options.uri.path}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final peticion = response.requestOptions;
    debugPrint(
      '[HTTP] ${response.statusCode} ${peticion.method} ${peticion.uri.path}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final peticion = err.requestOptions;
    final estado = err.response?.statusCode ?? err.type.name;
    debugPrint('[HTTP] error $estado ${peticion.method} ${peticion.uri.path}');
    handler.next(err);
  }
}
