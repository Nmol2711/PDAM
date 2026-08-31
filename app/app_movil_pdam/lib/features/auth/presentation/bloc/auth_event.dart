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
