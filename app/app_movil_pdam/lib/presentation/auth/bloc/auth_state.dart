part of 'auth_bloc.dart';

sealed class AuthState extends Equatable {
  const AuthState();
  
  @override
  List<Object?> get props => [];
}

final class AuthInitial extends AuthState {
  final String email;
  final String password;
  const AuthInitial({this.email = '', this.password = ''});

  @override
  List<Object?> get props => [email, password];
}

final class AuthLoading extends AuthState {}

final class AuthSuccess extends AuthState {}

final class AuthFailure extends AuthState {
  final String message;
  const AuthFailure(this.message,);

  @override
  List<Object?> get props => [message]; // Si el mensaje cambia, el estado cambia
}