import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:equatable/equatable.dart';

/// Datos que el usuario envía para actualizar su perfil (RF-09, RF-11).
///
/// Solo viajan al servidor el correo nuevo y la contraseña nueva: la
/// confirmación se valida en el cliente y nunca se envía (RF-11). Un campo nulo
/// o vacío significa que no se cambia.
class AccountUpdate extends Equatable {
  final String? correo;
  final String? passwordNueva;

  const AccountUpdate({this.correo, this.passwordNueva});

  /// Indica si no hay ningún cambio que enviar.
  bool get sinCambios =>
      (correo == null || correo!.isEmpty) &&
      (passwordNueva == null || passwordNueva!.isEmpty);

  @override
  List<Object?> get props => [correo, passwordNueva];
}

/// Resultado de una actualización aplicada por el servidor (RF-10, RF-14).
///
/// [tokenNuevo] solo llega cuando el correo cambió: el servidor emite un token
/// para esa sesión y la aplicación debe guardarlo. Si el correo no cambió, es
/// nulo y el token vigente se conserva.
class AccountUpdateResult extends Equatable {
  final UserProfile profile;
  final String? tokenNuevo;

  const AccountUpdateResult({required this.profile, this.tokenNuevo});

  @override
  List<Object?> get props => [profile, tokenNuevo];
}
