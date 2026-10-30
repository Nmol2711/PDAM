import 'dart:convert';
import 'dart:typed_data';

import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/remote/auth_remote_datasource.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorageService implements StorageService {
  @override
  Future<Either<Failures, void>> deleteString(String key) async =>
      const Right(null);

  @override
  Future<Either<Failures, String?>> getString(String key) async =>
      const Right(null);

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async =>
      const Right(null);
}

/// Adaptador HTTP falso: responde con el estado y el cuerpo indicados.
class _FakeAdapter implements HttpClientAdapter {
  int status = 200;
  Object body = const <String, dynamic>{};
  DioExceptionType? tipoDeFallo;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (tipoDeFallo != null) {
      throw DioException(
        requestOptions: options,
        type: tipoDeFallo!,
        message: 'sin red',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Map<String, dynamic> _error(String code, String message) => {
  'detail': {'code': code, 'message': message},
};

void main() {
  late _FakeAdapter adapter;
  late AuthRemoteDatasource datasource;

  setUp(() {
    adapter = _FakeAdapter();
    final client = DioClient(_FakeStorageService(), sessionEvents: SessionEvents());
    client.dio.interceptors.clear();
    client.dio.httpClientAdapter = adapter;
    datasource = AuthRemoteDatasourceImpl(dioClient: client);
  });

  group('login (RF-19, RNF-01)', () {
    test('invalid_credentials muestra el texto exacto del catálogo', () async {
      adapter
        ..status = 401
        ..body = _error('invalid_credentials', 'Texto libre del servidor');

      await expectLater(
        datasource.login('user@x.com', 'incorrecta'),
        throwsA(
          isA<AccountFailure>()
              .having((fallo) => fallo.code, 'code', 'invalid_credentials')
              .having(
                (fallo) => fallo.message,
                'message',
                'Correo o contraseña incorrectos',
              ),
        ),
      );
    });

    test('un 401 sin detalle también es invalid_credentials', () async {
      adapter
        ..status = 401
        ..body = const <String, dynamic>{};

      await expectLater(
        datasource.login('user@x.com', 'incorrecta'),
        throwsA(
          isA<AccountFailure>().having(
            (fallo) => fallo.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
    });

    test('un 500 server_error usa el mensaje del catálogo, no el del cuerpo',
        () async {
      adapter
        ..status = 500
        ..body = _error('server_error', 'Traza interna del servidor');

      await expectLater(
        datasource.login('user@x.com', 'clave'),
        throwsA(
          isA<AccountFailure>()
              .having((fallo) => fallo.code, 'code', 'server_error')
              .having(
                (fallo) => fallo.message,
                'message',
                MensajesCuenta.errorServidor,
              ),
        ),
      );
    });

    test('un 500 sin detalle se traduce a un fallo tipado del catálogo',
        () async {
      adapter
        ..status = 500
        ..body = const <String, dynamic>{};

      await expectLater(
        datasource.login('user@x.com', 'clave'),
        throwsA(
          isA<ServerFailures>().having(
            (fallo) => fallo.message,
            'message',
            MensajesCuenta.errorServidor,
          ),
        ),
      );
    });

    test('sin red se distingue del rechazo de negocio', () async {
      adapter.tipoDeFallo = DioExceptionType.connectionError;

      await expectLater(
        datasource.login('user@x.com', 'clave'),
        throwsA(isA<NetworkFailures>()),
      );
    });
  });

  group('currentUser (RF-05, RF-07)', () {
    test('un 401 unauthorized se traduce a UnauthorizedFailure', () async {
      adapter
        ..status = 401
        ..body = _error(
          'unauthorized',
          'La sesión no es válida. Vuelve a iniciar sesión.',
        );

      await expectLater(
        datasource.currentUser(),
        throwsA(
          isA<UnauthorizedFailure>().having(
            (fallo) => fallo.message,
            'message',
            MensajesCuenta.sesionInvalida,
          ),
        ),
      );
    });

    test('un 401 sin detalle también es sesión inválida', () async {
      adapter
        ..status = 401
        ..body = const <String, dynamic>{};

      await expectLater(
        datasource.currentUser(),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('sin red se distingue del rechazo de negocio', () async {
      adapter.tipoDeFallo = DioExceptionType.receiveTimeout;

      await expectLater(
        datasource.currentUser(),
        throwsA(isA<NetworkFailures>()),
      );
    });
  });

  group('register (RF-12, RNF-01)', () {
    test('un correo duplicado usa el mensaje del catálogo', () async {
      adapter
        ..status = 400
        ..body = _error(
          'email_already_registered',
          'Texto libre del servidor',
        );

      await expectLater(
        datasource.register('ocupado@x.com', '12345678'),
        throwsA(
          isA<AccountFailure>()
              .having((fallo) => fallo.code, 'code', 'email_already_registered')
              .having(
                (fallo) => fallo.message,
                'message',
                'El correo electrónico ya está registrado.',
              ),
        ),
      );
    });

    test('un error no tipado nunca expone el toString de la excepción',
        () async {
      adapter
        ..status = 500
        ..body = const <String, dynamic>{};

      await expectLater(
        datasource.register('nuevo@x.com', '12345678'),
        throwsA(
          isA<ServerFailures>().having(
            (fallo) => fallo.message,
            'message',
            MensajesCuenta.errorServidor,
          ),
        ),
      );
    });
  });
}
