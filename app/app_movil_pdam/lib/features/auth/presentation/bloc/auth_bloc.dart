import 'dart:async';

import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/core/services/pending_deletion_store.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/domain/entity/user.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/current_user_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/login_uc.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/user_uc/register_uc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Estado de la sesión (RF-02, RF-03, RF-05, RF-19, RNF-10).
///
/// Escucha el canal de avisos de red: un 401 distinto de la baja limpia la
/// sesión local y la cierra con [AuthSessionExpired]; una baja terminada la
/// cierra con [AuthAccountDeleted]. Además bloquea el acceso sin conexión
/// cuando existe la marca de baja pendiente, para no reabrir una cuenta ya
/// eliminada.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final RegisterUc _registerUc;
  final LoginUc _loginUc;
  final CurrentUserUc _currentUserUc;
  final PendingDeletionStore _pendingDeletionStore;
  final SessionEvents _sessionEvents;
  final AccountLocalCleaner _accountLocalCleaner;
  final Future<bool> Function() _hayConexion;

  late final StreamSubscription<SessionEvent> _sessionSubscription;

  AuthBloc({
    required RegisterUc registerUc,
    required LoginUc loginUc,
    required CurrentUserUc currentUserUc,
    required PendingDeletionStore pendingDeletionStore,
    required SessionEvents sessionEvents,
    required AccountLocalCleaner accountLocalCleaner,
    Future<bool> Function()? hayConexion,
  }) : _registerUc = registerUc,
       _loginUc = loginUc,
       _currentUserUc = currentUserUc,
       _pendingDeletionStore = pendingDeletionStore,
       _sessionEvents = sessionEvents,
       _accountLocalCleaner = accountLocalCleaner,
       _hayConexion = hayConexion ?? _conectividadPorDefecto,
       super(AuthInitial()) {
    on<AuthCheckStatusRequested>(_onCheckStatusRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutPressed>(_onLogoutPressed);
    on<AuthProfileUpdated>(_onProfileUpdated);
    on<_SessionEventReceived>(_onSessionEventReceived);

    _sessionSubscription = _sessionEvents.stream.listen(
      (event) => add(_SessionEventReceived(event)),
    );
  }

  /// Consulta de conectividad usada cuando el llamador no inyecta una propia.
  static Future<bool> _conectividadPorDefecto() async {
    final resultados = await Connectivity().checkConnectivity();
    return !resultados.contains(ConnectivityResult.none);
  }

  /// Traduce el aviso de red al estado que corresponde (RF-05, RF-18, RF-19).
  ///
  /// Antes de emitir [AuthSessionExpired] se limpia la sesión local: token,
  /// tipo, credenciales cifradas y perfil cacheado. Así un 401 impide volver a
  /// entrar sin conexión con las credenciales de una cuenta que ya no existe,
  /// mientras las mascotas, horarios e historial se conservan para
  /// resincronizarlos tras volver a iniciar sesión (RF-19).
  Future<void> _onSessionEventReceived(
    _SessionEventReceived event,
    Emitter<AuthState> emit,
  ) async {
    switch (event.event.type) {
      case SessionEventType.sesionExpirada:
        try {
          await _accountLocalCleaner.limpiarPorSesionExpirada();
        } catch (_) {
          // Un fallo de la limpieza no puede impedir el cierre de sesión.
        }
        emit(
          AuthSessionExpired(
            message: event.event.message ?? MensajesCuenta.sesionInvalida,
          ),
        );
      case SessionEventType.cuentaEliminada:
        emit(
          AuthAccountDeleted(
            message: event.event.message ?? MensajesCuenta.cuentaEliminada,
          ),
        );
    }
  }

  /// Refresca el correo de la identidad sin cerrar ni reabrir la sesión
  /// (RF-10). Sin sesión activa no hay nada que actualizar.
  void _onProfileUpdated(AuthProfileUpdated event, Emitter<AuthState> emit) {
    final actual = state;
    if (actual is AuthAuthenticated) {
      emit(AuthAuthenticated(user: User(id: actual.user.id, email: event.email)));
    }
  }

  Future<void> _onCheckStatusRequested(
    AuthCheckStatusRequested event,
    Emitter<AuthState> emit,
  ) async {
    // RNF-10: una baja pendiente impide restaurar la sesión tras un reinicio.
    if (await _hayBajaPendiente()) {
      emit(AuthUnauthenticated());
      return;
    }

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
    // Sin conexión y con baja pendiente no se aceptan las credenciales
    // guardadas de una cuenta ya eliminada (RNF-10).
    if (await _hayBajaPendiente() && !await _hayConexion()) {
      emit(const AuthError(message: MensajesCuenta.limpiezaLocalFallida));
      return;
    }

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
    // RF-03: el registro exige conexión activa con el servidor.
    if (!await _hayConexion()) {
      emit(
        const AuthError(
          message:
              'Se requiere conexión activa con el servidor para registrarse o '
              'actualizar credenciales',
        ),
      );
      return;
    }

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

    // NOTA (Offline-First): el cierre de sesión no borra el token ni Isar para
    // preservar la disponibilidad de los datos locales.
    emit(AuthUnauthenticated());
  }

  /// Lee la marca de baja pendiente sin romper el flujo si el almacenamiento
  /// no responde: solo un valor escrito de forma explícita bloquea el acceso.
  Future<bool> _hayBajaPendiente() async {
    try {
      return await _pendingDeletionStore.isPending();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> close() async {
    await _sessionSubscription.cancel();
    return super.close();
  }
}
