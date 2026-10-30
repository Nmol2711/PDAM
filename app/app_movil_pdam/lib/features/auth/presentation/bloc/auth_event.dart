part of 'auth_bloc.dart';

sealed class AuthEvent {
  const AuthEvent();
}

final class AuthCheckStatusRequested extends AuthEvent {}

final class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginRequested({required this.email, required this.password});
}

final class AuthRegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String confirmPassword;

  const AuthRegisterRequested({
    required this.email,
    required this.password,
    required this.confirmPassword,
  });
}

final class AuthLogoutPressed extends AuthEvent {}

/// La cuenta actualizó su correo: la sesión sigue activa, pero la identidad
/// mostrada (saludo del panel) debe reflejar el correo nuevo sin volver a
/// iniciar sesión (RF-10).
final class AuthProfileUpdated extends AuthEvent {
  final String email;

  const AuthProfileUpdated({required this.email});
}

/// Evento interno: aviso recibido del canal de red (RF-05, RF-18).
final class _SessionEventReceived extends AuthEvent {
  final SessionEvent event;

  const _SessionEventReceived(this.event);
}
