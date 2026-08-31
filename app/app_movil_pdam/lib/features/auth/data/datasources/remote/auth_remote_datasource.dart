import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/network/dio_client.dart';
import 'package:app_movil_pdam/features/auth/data/models/auth_token_model.dart';
import 'package:app_movil_pdam/features/auth/data/models/user_model.dart';
import 'package:dio/dio.dart';

abstract class AuthRemoteDatasource {
  Future<UserModel> register(String email, String password);

  Future<AuthTokenModel> login(String email, String password);

  Future<UserModel> currentUser();
}

class AuthRemoteDatasourceImpl implements AuthRemoteDatasource {
  final DioClient _dioClient;

  AuthRemoteDatasourceImpl({required DioClient dioClient})
    : _dioClient = dioClient;

  @override
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
          // ◄ Forzamos a que el content-type sea estrictamente urlencoded
          contentType: 'application/x-www-form-urlencoded',
          extra: {'requiresToken': false},
        ),
      );

      return AuthTokenModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Error de autenticación');
    }
  }

  @override
  Future<UserModel> register(String email, String password) async {
    try {
      final response = await _dioClient.dio.post(
        ApiConstants.users,
        data: {
          // OAuth2PasswordRequestForm busca obligatoriamente la llave "username"
          'email': email,
          'password': password,
        },
      );

      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(
        e.message ?? 'Error con el servidor al registar el usuario',
      );
    }
  }

  @override
  Future<UserModel> currentUser() async {
    try {
      final response = await _dioClient.dio.get(ApiConstants.currentUsers);

      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(
        e.message ?? 'Error con el servidor al obtener el usuario actual',
      );
    }
  }
}
