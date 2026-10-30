import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/data/models/auth_token_model.dart';
import 'package:app_movil_pdam/features/auth/data/models/user_model.dart';
import 'package:dio/dio.dart';

/// Acceso remoto de autenticación (RF-05, RF-12, RF-19).
///
/// Traduce el contrato `detail={code,message}` a fallos tipados: un rechazo de
/// negocio llega como [AccountFailure] con el texto del catálogo, un 401 de una
/// petición autenticada como [UnauthorizedFailure], un fallo de red como
/// [NetworkFailures] y cualquier otro como [ServerFailures]. Nunca propaga el
/// `toString()` de una excepción ni el texto crudo de Dio (RNF-01, RNF-06).
abstract class AuthRemoteDatasource {
  Future<UserModel> register(String email, String password);

  Future<AuthTokenModel> login(String email, String password);

  Future<UserModel> currentUser();
}

class AuthRemoteDatasourceImpl implements AuthRemoteDatasource {
  final DioClient _dioClient;

  AuthRemoteDatasourceImpl({required DioClient dioClient})
    : _dioClient = dioClient;

  /// Tipos de `DioException` que representan un fallo de red y no del servidor.
  static const Set<DioExceptionType> _tiposDeRed = {
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
    DioExceptionType.badCertificate,
  };

  @override
  Future<AuthTokenModel> login(String email, String password) async {
    try {
      // 1. Creamos el FormData
      final formData = FormData.fromMap({
        'username': email,
        'password': password,
      });

      final response = await _dioClient.dio.post(
        ApiConstants.login,
        data: formData,
        options: Options(
          // Forzamos a que el content-type sea estrictamente urlencoded
          contentType: 'application/x-www-form-urlencoded',
          extra: {'requiresToken': false},
        ),
      );

      return AuthTokenModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _traducir(e, esLogin: true);
    }
  }

  @override
  Future<UserModel> register(String email, String password) async {
    try {
      final response = await _dioClient.dio.post(
        ApiConstants.users,
        data: {'email': email, 'password': password},
        options: Options(extra: {'requiresToken': false}),
      );

      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _traducir(e);
    }
  }

  @override
  Future<UserModel> currentUser() async {
    try {
      final response = await _dioClient.dio.get(ApiConstants.currentUsers);

      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _traducir(e);
    }
  }

  /// Distingue red, sesión inválida y rechazo de negocio (RF-05, RF-19).
  Failures _traducir(DioException e, {bool esLogin = false}) {
    final respuesta = e.response;
    if (respuesta == null || _tiposDeRed.contains(e.type)) {
      return NetworkFailures(MensajesCuenta.sinConexion);
    }

    final detalle = _detalleDe(respuesta);
    final codigo = detalle?['code']?.toString();

    if (codigo == CodigosCuenta.invalidCredentials) {
      return AccountFailure(codigo!, MensajesCuenta.credencialesInvalidas);
    }

    // Un 401 sin detalle en el login es un rechazo de credenciales; en una
    // petición autenticada es una sesión inválida.
    if (codigo == CodigosCuenta.unauthorized ||
        (codigo == null && respuesta.statusCode == 401)) {
      if (esLogin) {
        return AccountFailure(
          CodigosCuenta.invalidCredentials,
          MensajesCuenta.credencialesInvalidas,
        );
      }
      return UnauthorizedFailure(MensajesCuenta.sesionInvalida);
    }

    if (codigo != null && codigo.isNotEmpty) {
      return AccountFailure(codigo, _mensajeDe(detalle, codigo));
    }

    return ServerFailures(MensajesCuenta.errorServidor);
  }

  Map<String, dynamic>? _detalleDe(Response<dynamic> respuesta) {
    final data = respuesta.data;
    if (data is! Map) return null;
    final detalle = data['detail'];
    if (detalle is! Map) return null;
    return detalle.map((clave, valor) => MapEntry(clave.toString(), valor));
  }

  /// El mensaje visible sale del catálogo local por código (RNF-01).
  String _mensajeDe(Map<String, dynamic>? detalle, String codigo) {
    final delCatalogo = MensajesCuenta.porCodigo[codigo];
    if (delCatalogo != null) return delCatalogo;
    final mensaje = detalle?['message']?.toString();
    if (mensaje != null && mensaje.isNotEmpty) return mensaje;
    return MensajesCuenta.errorServidor;
  }
}
