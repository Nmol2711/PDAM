import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/network/auth_interceptor.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:dio/dio.dart';

class DioClient {
  final Dio _dio;

  // _internal hace un constructor privado, lo que significa que nadie puede crear otra instancias desde fuera
  DioClient._internal({required StorageService storageService}) : _dio = Dio() {
    _configureOptions();
    _configureInterceptor(storageService);
  }

  // Instancia unica
  static DioClient? _instance;

  // 4. FACTORY CONSTRUCTOR: El punto de entrada público.
  // Si la instancia no existe, la crea; si ya existe, devuelve la que ya estaba en memoria.
  factory DioClient(StorageService storageService) {
    _instance ??= DioClient._internal(storageService: storageService);
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

  void _configureInterceptor(StorageService storageService) {
    _dio.interceptors.addAll([
      AuthInterceptor(storageService: storageService),

      // Logger para ver el comportamiento de la consola
      LogInterceptor(
        requestHeader: true, // Para verificar que el Authorization va en camino
        requestBody: true,
        responseBody: true,
      ),
    ]);
  }
}
