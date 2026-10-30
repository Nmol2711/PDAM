import 'dart:async';
import 'dart:convert';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/constant/token_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/core/services/storage_service.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Valores de prueba: si alguno aparece en la consola, el log filtra datos.
const String _passwordActual = 'clave-actual-123';
const String _passwordNueva = 'clave-nueva-456';
const String _token = 'token-secreto-789';

class _FakeStorageService implements StorageService {
  @override
  Future<Either<Failures, void>> deleteString(String key) async =>
      const Right(null);

  @override
  Future<Either<Failures, String?>> getString(String key) async {
    if (key == TokenConstant.keyToken) return const Right(_token);
    if (key == TokenConstant.keyTypeToken) return const Right('bearer');
    return const Right(null);
  }

  @override
  Future<Either<Failures, void>> saveString(String key, String value) async =>
      const Right(null);
}

/// Adaptador HTTP falso: responde 200 sin salir a la red.
class _AdapterFalso implements HttpClientAdapter {
  final List<RequestOptions> peticiones = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    peticiones.add(options);
    return ResponseBody.fromString(
      jsonEncode(const <String, dynamic>{
        'deleted': true,
        'email': 'user@x.com',
        'is_active': true,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  late _AdapterFalso adapter;
  late Dio dio;
  late List<String> salida;
  late DebugPrintCallback debugPrintOriginal;

  setUpAll(() {
    debugPrintOriginal = debugPrint;
  });

  setUp(() {
    adapter = _AdapterFalso();
    salida = <String>[];
    // Se captura todo lo que el cliente escribiría en la consola, tanto por
    // `debugPrint` como por `print` (que es lo que usa el logger de Dio).
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) salida.add(message);
    };
    final client = DioClient(_FakeStorageService(), sessionEvents: SessionEvents());
    client.dio.httpClientAdapter = adapter;
    dio = client.dio;
  });

  tearDown(() {
    debugPrint = debugPrintOriginal;
  });

  /// Ejecuta la petición dentro de una zona que intercepta `print`.
  Future<void> ejecutar(Future<void> Function() peticion) {
    return runZoned(
      peticion,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, linea) => salida.add(linea),
      ),
    );
  }

  String log() => salida.join('\n');

  group('registro de peticiones sin datos sensibles (RNF-06)', () {
    test(
      'el PATCH con contraseña nueva no vuelca el cuerpo en el log',
      () async {
        await ejecutar(
          () => dio.patch(
            '/users/me',
            data: {'email': 'nuevo@x.com', 'new_password': _passwordNueva},
          ),
        );

        expect(salida, isNotEmpty);
        expect(log(), isNot(contains(_passwordNueva)));
        expect(log(), isNot(contains('new_password')));
        expect(log(), isNot(contains('nuevo@x.com')));
      },
    );

    test('el DELETE con contraseña no vuelca el cuerpo en el log', () async {
      await ejecutar(
        () => dio.delete('/users/me', data: {'password': _passwordActual}),
      );

      expect(salida, isNotEmpty);
      expect(log(), isNot(contains(_passwordActual)));
      expect(log(), isNot(contains('password')));
    });

    test('el token de Authorization no aparece en el log', () async {
      await ejecutar(() => dio.get('/users/me'));

      expect(
        adapter.peticiones.single.headers['Authorization'],
        contains(_token),
      );
      expect(salida, isNotEmpty);
      expect(log(), isNot(contains(_token)));
      expect(log(), isNot(contains('Authorization')));
    });

    test('sí registra el método y la ruta para poder diagnosticar', () async {
      await ejecutar(
        () => dio.patch('/users/me', data: {'new_password': _passwordNueva}),
      );

      expect(log(), contains('PATCH'));
      expect(log(), contains('/users/me'));
    });
  });
}
