import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/delete_token_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final RegisterUc _registerUc;
  final LoginUc _loginUc;
  final CurrentUserUc _currentUserUc;

  final DeleteTokenUc _deleteTokenUc;

  AuthBloc({
    required RegisterUc registerUc,
    required LoginUc loginUc,
    required CurrentUserUc currentUserUc,
    required DeleteTokenUc deleteTokenUc,
  }) : _registerUc = registerUc,
       _loginUc = loginUc,
       _currentUserUc = currentUserUc,
       _deleteTokenUc = deleteTokenUc,
       super(AuthInitial()) {
    on<AuthCheckStatusRequested>(_onCheckStatusRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutPressed>(_onLogoutPressed);
  }

  Future<void> _onCheckStatusRequested(
    AuthCheckStatusRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await _currentUserUc();

    result.fold(
      (failure) => emit(AuthUnauthenticated()),
      (user) => emit(AuthAuthenticated(user: user)),
    );
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await _loginUc(event.email, event.password);

    result.fold(
      (failure) => emit(AuthError(message: failure.message)),
      (user) => emit(AuthAuthenticated(user: user)),
    );
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await _registerUc(
      event.email,
      event.password,
      event.confirmPassword,
    );

    result.fold(
      (failure) => emit(AuthError(message: failure.message)),
      (user) => emit(AuthRegister()),
    );
  }

  Future<void> _onLogoutPressed(
    AuthLogoutPressed event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await _deleteTokenUc();

    result.fold(
      (failures) => emit(AuthError(message: failures.message)),
      (_) => emit(AuthUnauthenticated()),
    );
  }
}
