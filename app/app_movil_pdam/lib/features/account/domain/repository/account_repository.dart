import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:dartz/dartz.dart';

/// Contrato de datos de la cuenta (RF-06, RF-07, RF-10, RF-13, RF-20).
///
/// La consulta del perfil cae al perfil cacheado solo cuando el servidor no
/// responde; las mutaciones exigen conexión y no se encolan.
abstract class AccountRepository {
  /// Perfil del servidor o, si no hay conexión, el cacheado real.
  ///
  /// Un 401 `unauthorized` se devuelve como [UnauthorizedFailure] y nunca como
  /// perfil cacheado (RF-07, RF-19). Sin caché devuelve
  /// [NoCachedProfileFailure] (RF-08).
  Future<Either<Failures, ProfileSnapshot>> getProfile();

  /// Aplica la actualización en el servidor y refresca el perfil cacheado.
  ///
  /// Sin conexión no escribe nada y devuelve [ConnectivityRequiredFailures]
  /// (RF-13).
  Future<Either<Failures, AccountUpdateResult>> updateProfile(
    AccountUpdate update,
  );

  /// Elimina la cuenta en el servidor con la contraseña actual (RF-17, RF-18).
  ///
  /// Sin conexión no elimina nada y devuelve [ConnectivityRequiredFailures]
  /// (RF-20). La limpieza local no forma parte de esta operación.
  Future<Either<Failures, bool>> deleteAccount(String password);

  /// Último perfil real guardado en el dispositivo, o `null` si no hay.
  ///
  /// Es la única fuente admitida para precargar datos sin conexión; nunca
  /// devuelve un correo de relleno (RF-07, RF-09).
  Future<Either<Failures, UserProfile?>> cachedProfile();
}
