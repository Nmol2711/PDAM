import 'package:app_movil_pdam/core/constant/api_constant.dart';
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/api_client.dart';
import 'package:app_movil_pdam/data/models/auth_model.dart';
import 'package:app_movil_pdam/data/models/user_model.dart';
import 'package:app_movil_pdam/domain/entities/auth_token.dart';
import 'package:dio/dio.dart';

abstract class AuthRemoteDataSource {
  Future<AuthToken> login(String username, String password);
  Future<UserModel> signUp(String username, String password);
  Future<UserModel> getCurrentUser(AuthToken token);
}

class AuthRemoteDataSourceImpl extends AuthRemoteDataSource {
  @override
  Future<AuthToken> login(String username, String password) async {
    final dioResult = getDioClient(null);
    return await dioResult.fold(
      (failure) => throw ServerFailures(failure.message),
      (dio) async {
        try {
          final response = await dio.post(
            ApiConstants.login,
            data: FormData.fromMap({
              'username': username,
              'password': password,
            }),
          );
          return AuthModel.fromJson(response.data);
        } on DioException catch (e) {
          throw ServerFailures(
            e.response?.data['detail'] ?? "Error con el servidor",
          );
        }
      },
    );
  }

  @override
  Future<UserModel> signUp(String username, String password) async {
    final dioResult = getDioClient(null);

    return await dioResult.fold(
      (failure) => throw ServerFailures(failure.message),
      (dio) async {
        try {
          final response = await dio.post(
            ApiConstants.users,
            data: {'username': username, 'password': password},
          );
          return UserModel.fromJson(response.data);
        } on DioException catch (e) {
          throw ServerFailures(
            e.response?.data['detail'] ?? "Error con el servidor",
          );
        }
      },
    );
  }

  @override
  Future<UserModel> getCurrentUser(AuthToken token) async {
    final dioResult = getDioClient(token);

    return await dioResult.fold(
      (failure) => throw ServerFailures(failure.message),
      (dio) async {
        try {
          final response = await dio.get("${ApiConstants.users}me");
          return UserModel.fromJson(response.data);
        } on DioException catch (e) {
          throw ServerFailures(
            e.response?.data['detail'] ?? "Error con el servidor",
          );
        }
      },
    );
  }
}
