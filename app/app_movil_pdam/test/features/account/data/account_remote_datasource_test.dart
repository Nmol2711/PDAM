import 'dart:convert';
import 'dart:typed_data';

import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:app_movil_pdam/features/account/data/datasource/remote/account_remote_datasource.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
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

/// Adaptador HTTP falso: captura la petición y permite forzar un fallo de red.
class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<({int status, Object body})> respuestas = [];

  /// Si es true, la siguiente petición falla como error de red.
  bool fallarProxima = false;

  /// Tipo de fallo de red que se lanza cuando [fallarProxima] está activo.
  DioExceptionType tipoDeFallo = DioExceptionType.connectionError;

  Map<String, dynamic> get cuerpo => _cuerpo(requests.last);

  Map<String, dynamic> _cuerpo(RequestOptions peticion) {
    final data = peticion.data;
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return Map<String, dynamic>.from(data as Map);
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (fallarProxima) {
      fallarProxima = false;
      throw DioException(
        requestOptions: options,
        type: tipoDeFallo,
        message: 'sin red',
      );
    }
    final respuesta = respuestas.isEmpty
        ? (status: 200, body: const <String, dynamic>{})
        : respuestas.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(respuesta.body),
      respuesta.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Map<String, dynamic> _perfilJson({
  String email = 'user@x.com',
  bool isActive = true,
}) => {'id': 7, 'email': email, 'is_active': isActive};

Map<String, dynamic> _errorJson(String code, String message) => {
  'detail': {'code': code, 'message': message},
};

void main() {
  late _FakeAdapter adapter;
  late DioClient client;
  late AccountRemoteDatasource datasource;

  setUp(() {
    adapter = _FakeAdapter();
    client = DioClient(_FakeStorageService(), sessionEvents: SessionEvents());
    client.dio.interceptors.clear();
    client.dio.httpClientAdapter = adapter;
    datasource = AccountRemoteDatasourceImpl(dioClient: client);
  });

  group('getProfile (RF-06, RF-07)', () {
    test('hace GET /users/me y devuelve el perfil normalizado', () async {
      adapter.respuestas.add((
        status: 200,
        body: _perfilJson(email: '  User@X.com '),
      ));

      final perfil = await datasource.getProfile();

      final peticion = adapter.requests.single;
      expect(peticion.method, 'GET');
      expect(peticion.uri.path, '/users/me');
      expect(perfil.email, 'user@x.com');
      expect(perfil.isActive, isTrue);
    });

    test(
      'un 401 unauthorized se traduce al fallo de cuenta del catálogo',
      () async {
        adapter.respuestas.add((
          status: 401,
          body: _errorJson(
            'unauthorized',
            'La sesión no es válida. Vuelve a iniciar sesión.',
          ),
        ));

        await expectLater(
          datasource.getProfile(),
          throwsA(
            isA<AccountFailure>()
                .having((fallo) => fallo.code, 'code', 'unauthorized')
                .having(
                  (fallo) => fallo.message,
                  'message',
                  'La sesión no es válida. Vuelve a iniciar sesión.',
                ),
          ),
        );
      },
    );

    test('un 500 server_error conserva el mensaje del catálogo', () async {
      adapter.respuestas.add((
        status: 500,
        body: _errorJson(
          'server_error',
          'No se pudo completar la operación. Inténtalo de nuevo.',
        ),
      ));

      await expectLater(
        datasource.getProfile(),
        throwsA(
          isA<AccountFailure>()
              .having((fallo) => fallo.code, 'code', 'server_error')
              .having(
                (fallo) => fallo.message,
                'message',
                'No se pudo completar la operación. Inténtalo de nuevo.',
              ),
        ),
      );
    });

    test('un 401 sin detalle también se clasifica como unauthorized', () async {
      adapter.respuestas.add((status: 401, body: const <String, dynamic>{}));

      await expectLater(
        datasource.getProfile(),
        throwsA(
          isA<AccountFailure>().having(
            (fallo) => fallo.code,
            'code',
            'unauthorized',
          ),
        ),
      );
    });

    test('un fallo de conexión se distingue del rechazo de negocio', () async {
      adapter.fallarProxima = true;

      await expectLater(
        datasource.getProfile(),
        throwsA(isA<NetworkFailures>()),
      );
    });

    test('un timeout también es fallo de red y no de negocio', () async {
      adapter
        ..fallarProxima = true
        ..tipoDeFallo = DioExceptionType.receiveTimeout;

      await expectLater(
        datasource.getProfile(),
        throwsA(isA<NetworkFailures>()),
      );
    });

    test(
      'un is_active ausente es respuesta inválida y no un estado falso',
      () async {
        adapter.respuestas.add((
          status: 200,
          body: const <String, dynamic>{'id': 7, 'email': 'user@x.com'},
        ));

        await expectLater(
          datasource.getProfile(),
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
      },
    );

    test('un is_active de tipo incorrecto es respuesta inválida', () async {
      adapter.respuestas.add((
        status: 200,
        body: const <String, dynamic>{
          'id': 7,
          'email': 'user@x.com',
          'is_active': 'si',
        },
      ));

      await expectLater(
        datasource.getProfile(),
        throwsA(isA<AccountFailure>()),
      );
    });

    test('un email ausente es respuesta inválida y no un correo vacío',
        () async {
      adapter.respuestas.add((
        status: 200,
        body: const <String, dynamic>{'id': 7, 'is_active': true},
      ));

      await expectLater(
        datasource.getProfile(),
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

    test('un email vacío o en blanco es respuesta inválida', () async {
      for (final email in ['', '   ']) {
        adapter.respuestas.add((
          status: 200,
          body: _perfilJson(email: email),
        ));

        await expectLater(
          datasource.getProfile(),
          throwsA(isA<AccountFailure>()),
          reason: 'email "$email"',
        );
      }
    });

    test('un email no textual es respuesta inválida', () async {
      adapter.respuestas.add((
        status: 200,
        body: const <String, dynamic>{
          'id': 7,
          'email': 123,
          'is_active': true,
        },
      ));

      await expectLater(
        datasource.getProfile(),
        throwsA(
          isA<AccountFailure>().having(
            (fallo) => fallo.code,
            'code',
            'server_error',
          ),
        ),
      );
    });
  });

  group('updateProfile (RF-10, RF-11, RF-13)', () {
    test('hace PATCH /users/me y no envía la confirmación', () async {
      adapter.respuestas.add((
        status: 200,
        body: {
          ..._perfilJson(email: 'nuevo@x.com'),
          'access_token': 'token-nuevo',
          'token_type': 'bearer',
        },
      ));

      final respuesta = await datasource.updateProfile(
        const AccountUpdate(
          correo: 'nuevo@x.com',
          passwordNueva: 'unaClaveLarga',
        ),
      );

      final peticion = adapter.requests.single;
      expect(peticion.method, 'PATCH');
      expect(peticion.uri.path, '/users/me');
      expect(adapter.cuerpo, {
        'email': 'nuevo@x.com',
        'new_password': 'unaClaveLarga',
      });
      expect(adapter.cuerpo.keys, isNot(contains('confirmacion')));
      expect(adapter.cuerpo.keys, isNot(contains('confirm_password')));
      expect(respuesta.profile.email, 'nuevo@x.com');
      expect(respuesta.accessToken, 'token-nuevo');
      expect(respuesta.tokenType, 'bearer');
    });

    test('omite el correo cuando solo cambia la contraseña', () async {
      adapter.respuestas.add((
        status: 200,
        body: {..._perfilJson(), 'access_token': null, 'token_type': null},
      ));

      await datasource.updateProfile(
        const AccountUpdate(passwordNueva: 'unaClaveLarga'),
      );

      expect(adapter.cuerpo, {'new_password': 'unaClaveLarga'});
    });

    test('omite la contraseña cuando solo cambia el correo', () async {
      adapter.respuestas.add((
        status: 200,
        body: {
          ..._perfilJson(email: 'nuevo@x.com'),
          'access_token': 'token-nuevo',
          'token_type': 'bearer',
        },
      ));

      await datasource.updateProfile(
        const AccountUpdate(correo: 'nuevo@x.com'),
      );

      expect(adapter.cuerpo, {'email': 'nuevo@x.com'});
    });

    test('acepta access_token y token_type nulos', () async {
      adapter.respuestas.add((
        status: 200,
        body: {..._perfilJson(), 'access_token': null, 'token_type': null},
      ));

      final respuesta = await datasource.updateProfile(
        const AccountUpdate(passwordNueva: 'unaClaveLarga'),
      );

      expect(respuesta.accessToken, isNull);
      expect(respuesta.tokenType, isNull);
    });

    test('acepta una respuesta sin las claves del token', () async {
      adapter.respuestas.add((status: 200, body: _perfilJson()));

      final respuesta = await datasource.updateProfile(
        const AccountUpdate(passwordNueva: 'unaClaveLarga'),
      );

      expect(respuesta.accessToken, isNull);
      expect(respuesta.tokenType, isNull);
    });

    test('un 400 email_already_registered conserva código y mensaje', () async {
      adapter.respuestas.add((
        status: 400,
        body: _errorJson(
          'email_already_registered',
          'El correo electrónico ya está registrado.',
        ),
      ));

      await expectLater(
        datasource.updateProfile(const AccountUpdate(correo: 'ocupado@x.com')),
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

    test('un 400 weak_password se traduce al catálogo', () async {
      adapter.respuestas.add((
        status: 400,
        body: _errorJson(
          'weak_password',
          'La contraseña debe tener al menos 8 caracteres.',
        ),
      ));

      await expectLater(
        datasource.updateProfile(const AccountUpdate(passwordNueva: 'corta12')),
        throwsA(
          isA<AccountFailure>()
              .having((fallo) => fallo.code, 'code', 'weak_password')
              .having(
                (fallo) => fallo.message,
                'message',
                'La contraseña debe tener al menos 8 caracteres.',
              ),
        ),
      );
    });

    test('un 500 conflict usa el mensaje de reintento', () async {
      adapter.respuestas.add((
        status: 500,
        body: _errorJson(
          'conflict',
          'No se pudo completar la operación. Inténtalo de nuevo.',
        ),
      ));

      await expectLater(
        datasource.updateProfile(const AccountUpdate(correo: 'nuevo@x.com')),
        throwsA(
          isA<AccountFailure>()
              .having((fallo) => fallo.code, 'code', 'conflict')
              .having(
                (fallo) => fallo.message,
                'message',
                'No se pudo completar la operación. Inténtalo de nuevo.',
              ),
        ),
      );
    });

    test(
      'un 500 sin detalle cae en server_error con el texto del catálogo',
      () async {
        adapter.respuestas.add((status: 500, body: const <String, dynamic>{}));

        await expectLater(
          datasource.updateProfile(const AccountUpdate(correo: 'nuevo@x.com')),
          throwsA(
            isA<AccountFailure>()
                .having((fallo) => fallo.code, 'code', 'server_error')
                .having(
                  (fallo) => fallo.message,
                  'message',
                  'No se pudo completar la operación. Inténtalo de nuevo.',
                ),
          ),
        );
      },
    );

    test(
      'con código conocido manda el texto del catálogo, no el del cuerpo',
      () async {
        adapter.respuestas.add((
          status: 400,
          body: _errorJson(
            'invalid_email',
            'Texto libre que envía el servidor',
          ),
        ));

        await expectLater(
          datasource.updateProfile(const AccountUpdate(correo: 'mal@correo')),
          throwsA(
            isA<AccountFailure>()
                .having((fallo) => fallo.code, 'code', 'invalid_email')
                .having(
                  (fallo) => fallo.message,
                  'message',
                  MensajesCuenta.correoInvalido,
                ),
          ),
        );
      },
    );

    test(
      'con código desconocido usa el mensaje del cuerpo y conserva el código',
      () async {
        adapter.respuestas.add((
          status: 409,
          body: _errorJson('codigo_nuevo', 'Aviso del servidor.'),
        ));

        await expectLater(
          datasource.updateProfile(const AccountUpdate(correo: 'nuevo@x.com')),
          throwsA(
            isA<AccountFailure>()
                .having((fallo) => fallo.code, 'code', 'codigo_nuevo')
                .having(
                  (fallo) => fallo.message,
                  'message',
                  'Aviso del servidor.',
                ),
          ),
        );
      },
    );

    test(
      'con código desconocido y sin mensaje cae en el texto genérico',
      () async {
        adapter.respuestas.add((
          status: 409,
          body: _errorJson('codigo_nuevo', ''),
        ));

        await expectLater(
          datasource.updateProfile(const AccountUpdate(correo: 'nuevo@x.com')),
          throwsA(
            isA<AccountFailure>()
                .having((fallo) => fallo.code, 'code', 'codigo_nuevo')
                .having(
                  (fallo) => fallo.message,
                  'message',
                  MensajesCuenta.errorServidor,
                ),
          ),
        );
      },
    );

    test('sin red se distingue del rechazo de negocio', () async {
      adapter.fallarProxima = true;

      await expectLater(
        datasource.updateProfile(const AccountUpdate(correo: 'nuevo@x.com')),
        throwsA(isA<NetworkFailures>()),
      );
    });
  });

  group('deleteAccount (RF-17, RF-18, RF-20)', () {
    test('hace DELETE /users/me con la contraseña en el cuerpo', () async {
      adapter.respuestas.add((status: 200, body: {'deleted': true}));

      final eliminada = await datasource.deleteAccount('claveActual');

      final peticion = adapter.requests.single;
      expect(peticion.method, 'DELETE');
      expect(peticion.uri.path, '/users/me');
      expect(adapter.cuerpo, {'password': 'claveActual'});
      expect(eliminada, isTrue);
    });

    test('un 400 invalid_password conserva el mensaje del catálogo', () async {
      adapter.respuestas.add((
        status: 400,
        body: _errorJson('invalid_password', 'La contraseña no es correcta.'),
      ));

      await expectLater(
        datasource.deleteAccount('incorrecta'),
        throwsA(
          isA<AccountFailure>()
              .having((fallo) => fallo.code, 'code', 'invalid_password')
              .having(
                (fallo) => fallo.message,
                'message',
                'La contraseña no es correcta.',
              ),
        ),
      );
    });

    test('un 401 unauthorized se clasifica como sesión inválida', () async {
      adapter.respuestas.add((
        status: 401,
        body: _errorJson(
          'unauthorized',
          'La sesión no es válida. Vuelve a iniciar sesión.',
        ),
      ));

      await expectLater(
        datasource.deleteAccount('claveActual'),
        throwsA(
          isA<AccountFailure>()
              .having((fallo) => fallo.code, 'code', 'unauthorized')
              .having(
                (fallo) => fallo.message,
                'message',
                'La sesión no es válida. Vuelve a iniciar sesión.',
              ),
        ),
      );
    });

    test('sin red se distingue del rechazo de negocio', () async {
      adapter.fallarProxima = true;

      await expectLater(
        datasource.deleteAccount('claveActual'),
        throwsA(isA<NetworkFailures>()),
      );
    });
  });
}
