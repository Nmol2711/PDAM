import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/account/data/datasource/local/local_profile_datasource.dart';
import 'package:app_movil_pdam/features/account/data/datasource/remote/account_remote_datasource.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/repository/account_repository.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/data/datasources/local/auth_local_datasource.dart';
import 'package:dartz/dartz.dart';

/// Repositorio único de la cuenta (RF-06, RF-07, RF-10, RF-13, RF-20).
///
/// El servidor es la fuente de verdad: la consulta guarda su respuesta en la
/// caché y solo cae a ella cuando no hubo respuesta (red o tiempo de espera).
/// Un 401 `unauthorized` nunca devuelve la caché. Las mutaciones exigen
/// conexión, no escriben nada sin ella y no se encolan.
class AccountRepositoryImpl implements AccountRepository {
  final AccountRemoteDatasource _remoteDatasource;
  final LocalProfileDatasource _localProfileDatasource;
  final AuthLocalDatasource _authLocalDatasource;

  const AccountRepositoryImpl({
    required AccountRemoteDatasource remoteDatasource,
    required LocalProfileDatasource localProfileDatasource,
    required AuthLocalDatasource authLocalDatasource,
  }) : _remoteDatasource = remoteDatasource,
       _localProfileDatasource = localProfileDatasource,
       _authLocalDatasource = authLocalDatasource;

  @override
  Future<Either<Failures, ProfileSnapshot>> getProfile() async {
    try {
      final model = await _remoteDatasource.getProfile();
      final perfil = model.toEntity();
      await _guardarEnCache(perfil);
      return Right(ProfileSnapshot(profile: perfil));
    } on AccountFailure catch (fallo) {
      return Left(_falloDeCuenta(fallo));
    } on NetworkFailures {
      return _perfilDesdeCache();
    } catch (_) {
      // Nunca se filtra el texto técnico de una excepción a la interfaz.
      return Left(ServerFailures(MensajesCuenta.errorServidor));
    }
  }

  @override
  Future<Either<Failures, AccountUpdateResult>> updateProfile(
    AccountUpdate update,
  ) async {
    try {
      final respuesta = await _remoteDatasource.updateProfile(
        AccountUpdate(
          correo: update.correo == null
              ? null
              : normalizarCorreo(update.correo!),
          passwordNueva: update.passwordNueva,
        ),
      );
      final perfil = respuesta.profile.toEntity();
      await _guardarEnCache(perfil);
      // RF-14: el acceso sin conexión de este dispositivo pasa a usar el
      // correo y la contraseña nuevos; la parte que no cambió se conserva.
      await _actualizarCredencialesLocales(
        correo: perfil.email,
        passwordNueva: update.passwordNueva,
      );
      return Right(
        AccountUpdateResult(profile: perfil, tokenNuevo: respuesta.accessToken),
      );
    } on AccountFailure catch (fallo) {
      return Left(_falloDeCuenta(fallo));
    } on NetworkFailures {
      return Left(ConnectivityRequiredFailures(MensajesCuenta.sinConexion));
    } catch (_) {
      // Nunca se filtra el texto técnico de una excepción a la interfaz.
      return Left(ServerFailures(MensajesCuenta.errorServidor));
    }
  }

  @override
  Future<Either<Failures, bool>> deleteAccount(String password) async {
    try {
      final eliminada = await _remoteDatasource.deleteAccount(password);
      return Right(eliminada);
    } on AccountFailure catch (fallo) {
      return Left(_falloDeCuenta(fallo));
    } on NetworkFailures {
      return Left(ConnectivityRequiredFailures(MensajesCuenta.sinConexion));
    } catch (_) {
      // Nunca se filtra el texto técnico de una excepción a la interfaz.
      return Left(ServerFailures(MensajesCuenta.errorServidor));
    }
  }

  @override
  Future<Either<Failures, UserProfile?>> cachedProfile() async {
    try {
      final perfil = await _localProfileDatasource.getCachedProfile();
      return Right(perfil);
    } catch (_) {
      return Left(NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado));
    }
  }

  /// Guarda el perfil recibido del servidor. Un fallo de escritura no impide
  /// mostrar el dato real que acaba de llegar.
  Future<void> _guardarEnCache(UserProfile perfil) async {
    try {
      await _localProfileDatasource.saveProfile(perfil);
    } catch (_) {
      // La caché es un respaldo: si falla, la respuesta del servidor sigue
      // siendo válida.
    }
  }

  /// Actualiza las credenciales cifradas del acceso sin conexión (RF-14).
  ///
  /// La contraseña solo se escribe en el almacenamiento cifrado y nunca se
  /// registra ni se devuelve. Un fallo de escritura no invalida la
  /// actualización que el servidor ya aplicó.
  Future<void> _actualizarCredencialesLocales({
    required String correo,
    required String? passwordNueva,
  }) async {
    try {
      await _authLocalDatasource.updateCachedCredentials(
        email: correo,
        password: passwordNueva,
      );
    } catch (_) {
      // La sesión sigue válida: las credenciales locales se reintentarán en
      // el siguiente inicio de sesión con conexión.
    }
  }

  /// Perfil cacheado como respaldo de una consulta sin respuesta.
  Future<Either<Failures, ProfileSnapshot>> _perfilDesdeCache() async {
    try {
      final perfil = await _localProfileDatasource.getCachedProfile();
      if (perfil == null) {
        return Left(NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado));
      }
      return Right(ProfileSnapshot(profile: perfil, desdeCache: true));
    } catch (_) {
      return Left(NoCachedProfileFailure(MensajesCuenta.sinPerfilCacheado));
    }
  }

  /// Un 401 se propaga como sesión inválida para que el estado cierre sesión.
  Failures _falloDeCuenta(AccountFailure fallo) {
    if (fallo.code == CodigosCuenta.unauthorized) {
      return UnauthorizedFailure(fallo.message);
    }
    return fallo;
  }
}
