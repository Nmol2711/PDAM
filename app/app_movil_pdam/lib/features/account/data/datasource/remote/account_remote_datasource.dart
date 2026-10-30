import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/account/data/models/user_profile_model.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:dio/dio.dart';

/// Acceso remoto a la cuenta (RF-06, RF-10, RF-18).
///
/// Traduce el contrato de `/users/me`: `detail={code,message}` se convierte en
/// [AccountFailure] y un fallo de red o de tiempo de espera en
/// [NetworkFailures], de modo que el repositorio decide con esa distinción si
/// puede usar la caché. Nunca propaga el texto crudo de Dio.
abstract class AccountRemoteDatasource {
  Future<UserProfileModel> getProfile();

  Future<AccountUpdateResponseModel> updateProfile(AccountUpdate update);

  Future<bool> deleteAccount(String password);
}

class AccountRemoteDatasourceImpl implements AccountRemoteDatasource {
  final DioClient _dioClient;

  const AccountRemoteDatasourceImpl({required DioClient dioClient})
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
  Future<UserProfileModel> getProfile() {
    return _ejecutar(() async {
      final response = await _dioClient.dio.get(ApiConstants.currentUsers);
      return UserProfileModel.fromJson(response.data as Map<String, dynamic>);
    });
  }

  @override
  Future<AccountUpdateResponseModel> updateProfile(AccountUpdate update) {
    return _ejecutar(() async {
      // La confirmación de la contraseña no viaja al servidor (RF-11); los
      // campos sin cambio se omiten para no enviar nulos innecesarios.
      final cuerpo = <String, dynamic>{};
      final correo = update.correo;
      if (correo != null && correo.isNotEmpty) {
        cuerpo['email'] = normalizarCorreo(correo);
      }
      final password = update.passwordNueva;
      if (password != null && password.isNotEmpty) {
        cuerpo['new_password'] = password;
      }

      final response = await _dioClient.dio.patch(
        ApiConstants.currentUsers,
        data: cuerpo,
      );
      return AccountUpdateResponseModel.fromJson(
        response.data as Map<String, dynamic>,
      );
    });
  }

  @override
  Future<bool> deleteAccount(String password) {
    return _ejecutar(() async {
      final response = await _dioClient.dio.delete(
        ApiConstants.currentUsers,
        data: {'password': password},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['deleted'] is bool) {
        return data['deleted'] as bool;
      }
      // La baja es idempotente: un 200 sin cuerpo también es éxito (RF-18).
      return true;
    });
  }

  /// Ejecuta la petición y traduce cualquier fallo al fallo tipado.
  ///
  /// Un cuerpo que no cumple el contrato es una respuesta inválida del
  /// servidor, no un dato que se pueda completar con valores inventados.
  Future<T> _ejecutar<T>(Future<T> Function() peticion) async {
    try {
      return await peticion();
    } on DioException catch (e) {
      throw _traducir(e);
    } on FormatException {
      throw AccountFailure(
        CodigosCuenta.serverError,
        MensajesCuenta.errorServidor,
      );
    }
  }

  /// Distingue red/tiempo de espera de un rechazo de negocio.
  Failures _traducir(DioException e) {
    final respuesta = e.response;
    if (respuesta == null || _tiposDeRed.contains(e.type)) {
      return NetworkFailures(MensajesCuenta.sinConexion);
    }

    final detalle = _detalleDe(respuesta);
    final codigo = detalle?['code']?.toString();
    if (codigo != null && codigo.isNotEmpty) {
      return AccountFailure(codigo, _mensajeDe(detalle, codigo));
    }

    if (respuesta.statusCode == 401) {
      return AccountFailure(
        CodigosCuenta.unauthorized,
        MensajesCuenta.sesionInvalida,
      );
    }

    return AccountFailure(
      CodigosCuenta.serverError,
      MensajesCuenta.errorServidor,
    );
  }

  Map<String, dynamic>? _detalleDe(Response<dynamic> respuesta) {
    final data = respuesta.data;
    if (data is! Map) return null;
    final detalle = data['detail'];
    if (detalle is! Map) return null;
    return detalle.map((clave, valor) => MapEntry(clave.toString(), valor));
  }

  /// El mensaje visible sale siempre del catálogo local por código (RNF-01).
  ///
  /// El `message` del cuerpo solo se usa como respaldo cuando el código es
  /// desconocido para esta versión de la aplicación; nunca se prefiere un
  /// texto libre del servidor sobre el del catálogo.
  String _mensajeDe(Map<String, dynamic>? detalle, String codigo) {
    final delCatalogo = MensajesCuenta.porCodigo[codigo];
    if (delCatalogo != null) return delCatalogo;
    final mensaje = detalle?['message']?.toString();
    if (mensaje != null && mensaje.isNotEmpty) return mensaje;
    return MensajesCuenta.errorServidor;
  }
}
