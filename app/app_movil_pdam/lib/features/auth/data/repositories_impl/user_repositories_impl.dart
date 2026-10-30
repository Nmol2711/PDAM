import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/features/account/data/datasource/local/local_profile_datasource.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/remote/auth_remote_datasource.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/repository/user_repositories.dart';
import 'package:dartz/dartz.dart';

/// Repositorio de identidad con respaldo local (RF-02, RF-05, RF-07, RF-08).
///
/// El servidor es la fuente de verdad. El modo sin conexión solo se activa
/// ante un fallo de red real: un rechazo de credenciales del servidor nunca
/// cae al respaldo local (RF-19). Cuando no hay red, el correo mostrado es el
/// perfil real guardado en el dispositivo; no existe un correo de relleno.
class UserRepositoriesImpl implements UserRepositories {
  final AuthLocalDatasource _authLocalDatasource;
  final AuthRemoteDatasource _authRemoteDatasource;
  final LocalProfileDatasource _localProfileDatasource;

  UserRepositoriesImpl({
    required AuthLocalDatasource authLocalDatasource,
    required AuthRemoteDatasource authRemoteDatasource,
    required LocalProfileDatasource localProfileDatasource,
  }) : _authLocalDatasource = authLocalDatasource,
       _authRemoteDatasource = authRemoteDatasource,
       _localProfileDatasource = localProfileDatasource;

  @override
  Future<Either<Failures, User>> currentUser() async {
    try {
      final remoto = await _authRemoteDatasource.currentUser();
      return Right(User(id: remoto.id, email: normalizarCorreo(remoto.email)));
    } on UnauthorizedFailure catch (fallo) {
      // Un 401 significa que la sesión ya no vale: no se devuelve la caché
      // como si la cuenta siguiera existiendo (RF-07, RF-19).
      return Left(fallo);
    } on NetworkFailures catch (fallo) {
      return _usuarioDesdeCache(fallo.message);
    } on AccountFailure catch (fallo) {
      return Left(fallo);
    } catch (_) {
      // Nunca se filtra el detalle técnico de una excepción a la interfaz.
      return Left(ServerFailures(MensajesCuenta.errorServidor));
    }
  }

  @override
  Future<Either<Failures, User>> login(String email, String password) async {
    final correo = normalizarCorreo(email);

    try {
      await _limpiarSiCambiaDeUsuario(correo);

      // 1. Intento online con tiempo de espera estricto (RF-02).
      final token = await _authRemoteDatasource
          .login(correo, password)
          .timeout(const Duration(seconds: 10));
      await _authLocalDatasource.cacheToken(token.token, token.typeToken);

      // 2. Credenciales cifradas para el modo sin conexión posterior.
      await _authLocalDatasource.cacheUserCredentials(correo, password);
      return await currentUser();
    } on NetworkFailures catch (fallo) {
      return _loginSinConexion(correo, password, fallo.message);
    } on TimeoutException {
      return _loginSinConexion(correo, password, MensajesCuenta.sinConexion);
    } on AccountFailure catch (fallo) {
      // Rechazo de negocio del servidor: no se usa el respaldo local (RF-19).
      return Left(fallo);
    } on UnauthorizedFailure catch (fallo) {
      return Left(fallo);
    } catch (_) {
      return Left(ServerFailures(MensajesCuenta.errorServidor));
    }
  }

  @override
  Future<Either<Failures, User>> register(
    String email,
    String password,
    String confirmPassword,
  ) async {
    if (password != confirmPassword) {
      return Left(UserFailures(MensajesCuenta.passwordsNoCoinciden));
    }

    try {
      final remoto = await _authRemoteDatasource.register(
        normalizarCorreo(email),
        password,
      );
      return Right(User(id: remoto.id, email: normalizarCorreo(remoto.email)));
    } on AccountFailure catch (fallo) {
      return Left(fallo);
    } on NetworkFailures {
      return Left(ConnectivityRequiredFailures(MensajesCuenta.sinConexion));
    } catch (_) {
      return Left(ServerFailures(MensajesCuenta.errorServidor));
    }
  }

  /// Limpia los datos locales si el correo ingresado pertenece a otra cuenta.
  ///
  /// Evita que el modo sin conexión mezcle datos de dos usuarios. Un fallo de
  /// lectura no bloquea el inicio de sesión: la limpieza es defensiva.
  Future<void> _limpiarSiCambiaDeUsuario(String correo) async {
    try {
      final cache = await _authLocalDatasource.getCachedCredentials();
      final correoAnterior = cache['email'];
      if (correoAnterior != null &&
          normalizarCorreo(correoAnterior) != correo) {
        await IsarService.clearAllData();
      }
    } catch (_) {
      // Sin credenciales previas no hay nada que limpiar.
    }
  }

  /// Autenticación local con las credenciales cifradas del dispositivo.
  ///
  /// Solo se acepta cuando el correo normalizado y la contraseña coinciden con
  /// los guardados. Cualquier otra combinación es un rechazo de credenciales.
  Future<Either<Failures, User>> _loginSinConexion(
    String correo,
    String password,
    String mensajeRed,
  ) async {
    try {
      final cache = await _authLocalDatasource.getCachedCredentials();
      final correoCache = cache['email'];
      final passwordCache = cache['password'];

      if (correoCache != null &&
          passwordCache != null &&
          normalizarCorreo(correoCache) == correo &&
          passwordCache == password) {
        return Right(User(id: 0, email: normalizarCorreo(correoCache)));
      }

      return Left(
        AccountFailure(
          CodigosCuenta.invalidCredentials,
          MensajesCuenta.credencialesInvalidas,
        ),
      );
    } catch (_) {
      return Left(NetworkFailures(mensajeRed));
    }
  }

  /// Usuario real a partir del perfil guardado cuando no hay red (RF-07, RF-08).
  ///
  /// Sin token no hay sesión que restaurar. Sin perfil cacheado se devuelve
  /// [NoCachedProfileFailure]: nunca se inventa un correo ni un estado.
  Future<Either<Failures, User>> _usuarioDesdeCache(String mensajeRed) async {
    try {
      await _authLocalDatasource.getToken();
    } catch (_) {
      return Left(NetworkFailures(mensajeRed));
    }

    try {
      final perfil = await _localProfileDatasource.getCachedProfile();
      if (perfil == null) {
        return Left(NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado));
      }
      return Right(User(id: 0, email: normalizarCorreo(perfil.email)));
    } catch (_) {
      return Left(NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado));
    }
  }
}
