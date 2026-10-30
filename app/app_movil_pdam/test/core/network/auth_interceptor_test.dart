import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/constant/token_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/auth_interceptor.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Almacenamiento en memoria que registra las claves borradas.
class _FakeStorage implements StorageService {
  final Map<String, String> valores;
  final List<String> borradas = [];
  bool fallarAlBorrar = false;

  _FakeStorage({Map<String, String>? valores}) : valores = {...?valores};

  @override
  Future<Either<Failures, void>> deleteString(String key) async {
    if (fallarAlBorrar) {
      return Left(LocalStorageFailures('fallo de almacenamiento'));
    }
    valores.remove(key);
    borradas.add(key);
    return const Right(null);
  }

  @override
  Future<Either<Failures, String?>> getString(String key) async =>
      Right(valores[key]);

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async {
    valores[key] = value;
    return const Right(null);
  }
}

/// Handler de petición que no completa el futuro interno de Dio.
class _HandlerPeticion extends RequestInterceptorHandler {
  RequestOptions? siguiente;

  @override
  void next(RequestOptions options) {
    siguiente = options;
  }
}

/// Handler de error que no completa el futuro interno de Dio.
class _HandlerError extends ErrorInterceptorHandler {
  DioException? siguiente;

  @override
  void next(DioException error) {
    siguiente = error;
  }
}

DioException _error401({
  String method = 'GET',
  String path = '/users/me',
  Map<String, dynamic>? data,
  Map<String, dynamic>? extra,
}) {
  final opciones = RequestOptions(
    path: path,
    method: method,
    extra: {...?extra},
  );
  return DioException(
    requestOptions: opciones,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: opciones,
      statusCode: 401,
      data: data,
    ),
  );
}

void main() {
  late _FakeStorage storage;
  late SessionEvents eventos;
  late AuthInterceptor interceptor;
  late List<SessionEvent> avisos;

  setUp(() {
    storage = _FakeStorage(
      valores: {
        TokenConstant.keyToken: 'token-secreto',
        TokenConstant.keyTypeToken: 'bearer',
      },
    );
    eventos = SessionEvents();
    avisos = [];
    eventos.stream.listen(avisos.add);
    interceptor = AuthInterceptor(
      storageService: storage,
      sessionEvents: eventos,
    );
  });

  tearDown(() async {
    await eventos.dispose();
  });

  group('onRequest (RNF-06)', () {
    test('adjunta el token y el tipo a una ruta protegida', () async {
      final handler = _HandlerPeticion();

      interceptor.onRequest(
        RequestOptions(path: '/users/me', method: 'GET'),
        handler,
      );
      await pumpEventQueue();

      expect(
        handler.siguiente?.headers['Authorization'],
        'bearer token-secreto',
      );
    });

    test('no adjunta el token a las rutas públicas de autenticación', () async {
      final handler = _HandlerPeticion();

      interceptor.onRequest(
        RequestOptions(path: '/auth/login', method: 'POST'),
        handler,
      );
      await pumpEventQueue();

      expect(handler.siguiente?.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('onError (RF-05, RF-19)', () {
    test('un 401 de una petición autenticada con code unauthorized emite el '
        'aviso de sesión y no borra nada: la limpieza la hace AuthBloc',
        () async {
      interceptor.onError(
        _error401(
          data: {
            'detail': {'code': 'unauthorized'},
          },
        ),
        _HandlerError(),
      );
      await pumpEventQueue();

      // RF-19: el interceptor solo avisa. `AuthBloc` borra token, tipo,
      // credenciales y perfil cacheado antes de emitir `AuthSessionExpired`.
      expect(storage.borradas, isEmpty);
      expect(storage.valores.containsKey(TokenConstant.keyToken), isTrue);
      expect(avisos, hasLength(1));
      expect(avisos.single.type, SessionEventType.sesionExpirada);
    });

    test('un 401 de una petición autenticada sin code también avisa de la '
        'sesión', () async {
      interceptor.onError(_error401(), _HandlerError());
      await pumpEventQueue();

      expect(storage.borradas, isEmpty);
      expect(avisos.single.type, SessionEventType.sesionExpirada);
    });

    test('un 401 del login público no borra el token ni emite el aviso de '
        'sesión', () async {
      interceptor.onError(
        _error401(
          method: 'POST',
          path: '/auth/login',
          extra: {'requiresToken': false},
          data: {
            'detail': {'code': 'invalid_credentials'},
          },
        ),
        _HandlerError(),
      );
      await pumpEventQueue();

      expect(storage.borradas, isEmpty);
      expect(storage.valores.containsKey(TokenConstant.keyToken), isTrue);
      expect(avisos, isEmpty);
    });

    test('un 401 de la baja de la cuenta no emite el aviso ni borra el token: '
        'la baja es idempotente y no es una sesión inválida', () async {
      interceptor.onError(
        _error401(
          method: 'DELETE',
          path: ApiConstants.currentUsers,
          data: {
            'detail': {'code': 'unauthorized'},
          },
        ),
        _HandlerError(),
      );
      await pumpEventQueue();

      expect(avisos, isEmpty);
      expect(storage.borradas, isEmpty);
      expect(storage.valores.containsKey(TokenConstant.keyToken), isTrue);
      expect(storage.valores.containsKey(TokenConstant.keyTypeToken), isTrue);
    });

    test('un 401 de otra ruta con DELETE sí avisa de la sesión', () async {
      interceptor.onError(
        _error401(
          method: 'DELETE',
          path: '/pets/7',
          data: {
            'detail': {'code': 'unauthorized'},
          },
        ),
        _HandlerError(),
      );
      await pumpEventQueue();

      expect(avisos.single.type, SessionEventType.sesionExpirada);
    });

    test('un error que no es 401 no toca el token ni emite avisos', () async {
      final opciones = RequestOptions(path: '/users/me', method: 'GET');
      final error = DioException(
        requestOptions: opciones,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: opciones, statusCode: 500),
      );

      interceptor.onError(error, _HandlerError());
      await pumpEventQueue();

      expect(storage.borradas, isEmpty);
      expect(avisos, isEmpty);
    });

    test('el aviso de sesión no depende del almacenamiento del interceptor',
        () async {
      storage.fallarAlBorrar = true;

      interceptor.onError(_error401(), _HandlerError());
      await pumpEventQueue();

      expect(avisos.single.type, SessionEventType.sesionExpirada);
      expect(storage.borradas, isEmpty);
    });
  });
}
