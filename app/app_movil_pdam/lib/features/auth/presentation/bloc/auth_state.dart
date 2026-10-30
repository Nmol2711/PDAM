part of 'auth_bloc.dart';

sealed class AuthState {
  const AuthState();
}

final class AuthInitial extends AuthState {}

final class AuthLoading extends AuthState {}

final class AuthAuthenticated extends AuthState {
  final User user;
  const AuthAuthenticated({required this.user});
}

final class AuthRegister extends AuthState {}

final class AuthUnauthenticated extends AuthState {}

final class AuthError extends AuthState {
  final String message;
  const AuthError({required this.message});
}

/// La sesión dejó de ser válida por un 401 del servidor (RF-05, RF-19).
final class AuthSessionExpired extends AuthState {
  final String message;
  const AuthSessionExpired({required this.message});
}

/// La cuenta se eliminó y la sesión local debe cerrarse (RF-18, RNF-10).
final class AuthAccountDeleted extends AuthState {
  final String message;
  const AuthAccountDeleted({required this.message});
}
