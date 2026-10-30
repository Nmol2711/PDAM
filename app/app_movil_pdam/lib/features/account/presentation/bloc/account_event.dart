part of 'account_bloc.dart';

sealed class AccountEvent {
  const AccountEvent();
}

/// Pide el perfil al entrar en la pantalla (RF-06, RF-07).
final class ProfileRequested extends AccountEvent {
  const ProfileRequested();
}

/// Repite la consulta del perfil tras un fallo sin conexión (RF-08).
final class ProfileRetryRequested extends AccountEvent {
  const ProfileRetryRequested();
}

/// Envía el formulario de actualización del perfil (RF-10, RF-11).
final class ProfileUpdateSubmitted extends AccountEvent {
  final String correo;
  final String passwordNueva;
  final String confirmacion;

  const ProfileUpdateSubmitted({
    required this.correo,
    this.passwordNueva = '',
    this.confirmacion = '',
  });
}

/// Solicita la baja de la cuenta con la contraseña actual (RF-17, RF-18).
final class AccountDeletionRequested extends AccountEvent {
  final String password;

  const AccountDeletionRequested({required this.password});
}

/// Descarta el mensaje y el token nuevo ya consumidos por la vista (RF-14).
final class AccountMessageConsumed extends AccountEvent {
  const AccountMessageConsumed();
}

/// La sesión terminó: el perfil y el token de la cuenta anterior no deben
/// sobrevivir al cierre, la expiración o la baja (RF-05, RF-18, RNF-10).
final class AccountSessionCleared extends AccountEvent {
  const AccountSessionCleared();
}
