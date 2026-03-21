
import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/domain/use_cases/auth/login_use_case.dart';
import 'package:app_movil_pdam/domain/use_cases/auth/sing_up_use_case.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase loginUseCase;
  final SingUpUseCase singUpUseCase;

  AuthBloc({required this.loginUseCase, required this.singUpUseCase}) : super(const AuthInitial()) {
    
    // Evento para el Email
    on<EmailChanged>((event, emit) {
      final currentState = state;
      if (currentState is AuthInitial) {
        emit(AuthInitial(
          email: event.email, 
          password: currentState.password // Mantenemos la clave actual
        ));
      }
    });

    // Evento para la Contraseña (¡Indispensable!)
    on<PasswordChanged>((event, emit) {
      final currentState = state;
      if (currentState is AuthInitial) {
        emit(AuthInitial(
          email: currentState.email, // Mantenemos el email actual
          password: event.password   // Actualizamos la clave
        ));
      }
    });
    
    // El evento de Login final
   on<LoginSubmitted>((event, emit) async {
      // 1. Obtenemos los datos guardados en el estado actual
      final currentState = state;
      
      if (currentState is AuthInitial) {
        final email = currentState.email;
        final password = currentState.password;

        // Validaciones básicas antes de "llamar" a FastAPI
        if (email.isEmpty || password.isEmpty) {
          emit(const AuthFailure("Por favor, llena todos los campos"));
          return;
        }

        emit(AuthLoading());

        // Simulación de red
        final result = await loginUseCase.execute(
          email,
          password,
        );

        result.fold(
          // Caso IZQUIERDO (Error)
          (failure) {
            emit(AuthFailure( MapFailure.mapFailureToMessage(failure)));
          },
          // Caso DERECHO (Éxito)
          (token) {
            // Aquí podrías emitir éxito o avisar al SessionBloc que guarde el token
            emit(AuthSuccess());
          }
        );
      }
    });
  }
}