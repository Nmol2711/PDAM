import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/core/network/session_events.dart';
import 'package:app_movil_pdam/core/services/account_local_cleaner.dart';
import 'package:app_movil_pdam/features/account/domain/entity/account_update.dart';
import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/delete_account_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/get_profile_uc.dart';
import 'package:app_movil_pdam/features/account/domain/usecase/update_profile_uc.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/domain/usecase/auth_token_uc/register_token_uc.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'account_event.dart';
part 'account_state.dart';

/// Estado de la cuenta: carga, actualización y baja (RF-06 a RF-21).
///
/// Toda la lógica vive aquí y en el dominio; la vista solo emite eventos y
/// dibuja el estado (principio 3). La baja escribe la marca de RNF-10 antes de
/// limpiar y la mantiene mientras la limpieza local no sea completa.
class AccountBloc extends Bloc<AccountEvent, AccountState> {
  final GetProfileUc _getProfileUc;
  final UpdateProfileUc _updateProfileUc;
  final DeleteAccountUc _deleteAccountUc;
  final RegisterTokenUc _registerTokenUc;
  final AccountLocalCleaner _accountLocalCleaner;
  final SessionEvents _sessionEvents;

  /// Estados de sesión que confirman el cierre de la cuenta (RF-05, RF-18).
  ///
  /// El BLoC los escucha para no conservar el perfil ni el token de una cuenta
  /// anterior cuando se cierra sesión, expira la sesión o se elimina la cuenta.
  final Stream<AuthState>? _authStates;
  StreamSubscription<AuthState>? _authSubscription;

  /// Falso desde que la sesión termina: una respuesta tardía del perfil no debe
  /// volver a pintar datos de una cuenta ya cerrada.
  bool _sesionValida = true;

  AccountBloc({
    required GetProfileUc getProfileUc,
    required UpdateProfileUc updateProfileUc,
    required DeleteAccountUc deleteAccountUc,
    required RegisterTokenUc registerTokenUc,
    required AccountLocalCleaner accountLocalCleaner,
    required SessionEvents sessionEvents,
    Stream<AuthState>? authStates,
  }) : _getProfileUc = getProfileUc,
       _updateProfileUc = updateProfileUc,
       _deleteAccountUc = deleteAccountUc,
       _registerTokenUc = registerTokenUc,
       _accountLocalCleaner = accountLocalCleaner,
       _sessionEvents = sessionEvents,
       _authStates = authStates,
       super(const AccountState()) {
    on<ProfileRequested>(_onProfileRequested);
    on<ProfileRetryRequested>(_onProfileRetryRequested);
    on<ProfileUpdateSubmitted>(_onProfileUpdateSubmitted);
    on<AccountDeletionRequested>(_onAccountDeletionRequested);
    on<AccountMessageConsumed>(_onAccountMessageConsumed);
    on<AccountSessionCleared>(_onAccountSessionCleared);

    _authSubscription = _authStates?.listen(_onAuthStateChanged);
  }

  /// Cierra el perfil en cuanto la sesión deja de ser válida (RF-05, RF-18).
  void _onAuthStateChanged(AuthState state) {
    if (state is AuthAuthenticated) {
      _sesionValida = true;
      return;
    }
    if (state is AuthUnauthenticated ||
        state is AuthSessionExpired ||
        state is AuthAccountDeleted) {
      _sesionValida = false;
      add(const AccountSessionCleared());
    }
  }

  void _onAccountSessionCleared(
    AccountSessionCleared event,
    Emitter<AccountState> emit,
  ) {
    emit(const AccountState());
  }

  Future<void> _onProfileRequested(
    ProfileRequested event,
    Emitter<AccountState> emit,
  ) {
    return _cargarPerfil(emit);
  }

  Future<void> _onProfileRetryRequested(
    ProfileRetryRequested event,
    Emitter<AccountState> emit,
  ) {
    return _cargarPerfil(emit);
  }

  Future<void> _cargarPerfil(Emitter<AccountState> emit) async {
    emit(
      state.copyWith(
        clearProfile: true,
        isSubmitting: false,
        isLoadingProfile: true,
        fieldErrors: const {},
        clearMessage: true,
      ),
    );

    final resultado = await _getProfileUc();

    // Si la sesión terminó mientras se consultaba, la respuesta ya no
    // pertenece a una cuenta activa y no debe mostrarse (RF-05).
    if (!_sesionValida) return;

    resultado.fold(
      (fallo) => emit(_estadoDeFalloPerfil(fallo)),
      (snapshot) => emit(
        state.copyWith(
          profile: snapshot.profile,
          isOffline: snapshot.desdeCache,
          isSubmitting: false,
          isLoadingProfile: false,
          fieldErrors: const {},
          clearMessage: true,
        ),
      ),
    );
  }

  AccountState _estadoDeFalloPerfil(Failures fallo) {
    if (fallo is UnauthorizedFailure) {
      return state.copyWith(
        clearProfile: true,
        isOffline: false,
        isSubmitting: false,
        isLoadingProfile: false,
        fieldErrors: const {},
        message: AccountMessage(
          fallo.message,
          AccountMessageType.sesionInvalida,
        ),
      );
    }

    if (fallo is NoCachedProfileFailure ||
        fallo is ConnectivityRequiredFailures ||
        fallo is NetworkFailures) {
      return state.copyWith(
        clearProfile: true,
        isOffline: true,
        isSubmitting: false,
        isLoadingProfile: false,
        fieldErrors: const {},
        message: AccountMessage(fallo.message, AccountMessageType.aviso),
      );
    }

    return state.copyWith(
      clearProfile: true,
      isOffline: false,
      isSubmitting: false,
      isLoadingProfile: false,
      fieldErrors: const {},
      message: AccountMessage(fallo.message, AccountMessageType.error),
    );
  }

  Future<void> _onProfileUpdateSubmitted(
    ProfileUpdateSubmitted event,
    Emitter<AccountState> emit,
  ) async {
    final perfil = state.profile;

    // Las validaciones de cliente van primero también cuando no hay perfil
    // cargado: el error de su campo no se sustituye por el aviso de perfil
    // ausente (RF-11).
    final errores = validarFormularioPerfil(
      correoActual: perfil?.email ?? '',
      correo: event.correo,
      passwordNueva: event.passwordNueva,
      confirmacion: event.confirmacion,
    );

    if (errores.isNotEmpty) {
      emit(
        state.copyWith(
          isSubmitting: false,
          fieldErrors: errores,
          // Sin perfil se conserva el aviso que explica por qué el correo no
          // venía precargado.
          clearMessage: perfil != null,
        ),
      );
      return;
    }

    if (perfil == null) {
      emit(
        state.copyWith(
          isSubmitting: false,
          fieldErrors: const {},
          message: const AccountMessage(
            MensajesCuenta.sinPerfilCacheado,
            AccountMessageType.aviso,
          ),
        ),
      );
      return;
    }

    final correoNuevo = normalizarCorreo(event.correo);
    final update = AccountUpdate(
      correo: correoNuevo == normalizarCorreo(perfil.email)
          ? null
          : correoNuevo,
      passwordNueva: event.passwordNueva.isEmpty ? null : event.passwordNueva,
    );

    emit(
      state.copyWith(
        isSubmitting: true,
        fieldErrors: const {},
        clearMessage: true,
      ),
    );

    final resultado = await _updateProfileUc(update);

    // Una respuesta tardía no puede aplicarse a una sesión ya cerrada por un
    // 401, un cierre de sesión o una baja (RF-05): ni perfil ni token.
    if (!_sesionValida) return;

    await resultado.fold(
      (fallo) async => emit(_estadoDeFalloActualizacion(fallo)),
      (actualizacion) async {
        final tokenNuevo = actualizacion.tokenNuevo;
        if (tokenNuevo != null) {
          // El cierre de sesión pudo ocurrir mientras se esperaba la
          // respuesta: no se persiste un token de la cuenta anterior.
          if (!_sesionValida) return;
          final guardado = await _registerTokenUc(tokenNuevo);
          if (!_sesionValida) return;
          final falloGuardado = guardado.fold<Failures?>(
            (fallo) => fallo,
            (_) => null,
          );
          if (falloGuardado != null) {
            // El perfil actualizado se conserva, pero el token no se expone
            // si no quedó guardado de forma segura (RNF-06). El fallo puede
            // traer un texto técnico del almacenamiento: nunca se muestra tal
            // cual, siempre el mensaje del catálogo (RNF-01).
            emit(
              state.copyWith(
                profile: actualizacion.profile,
                isOffline: false,
                isSubmitting: false,
                fieldErrors: const {},
                message: const AccountMessage(
                  MensajesCuenta.errorServidor,
                  AccountMessageType.error,
                ),
              ),
            );
            return;
          }
        }

        if (!_sesionValida) return;

        emit(
          state.copyWith(
            profile: actualizacion.profile,
            isOffline: false,
            isSubmitting: false,
            fieldErrors: const {},
            message: const AccountMessage(
              MensajesCuenta.datosActualizados,
              AccountMessageType.confirmacion,
            ),
          ),
        );
      },
    );
  }

  AccountState _estadoDeFalloActualizacion(Failures fallo) {
    if (fallo is AccountFailure) {
      final campo = _campoDeCodigo(fallo.code);
      if (campo != null) {
        return state.copyWith(
          isSubmitting: false,
          fieldErrors: {campo: fallo.message},
          clearMessage: true,
        );
      }

      if (fallo.code == CodigosCuenta.unauthorized) {
        return state.copyWith(
          isSubmitting: false,
          fieldErrors: const {},
          message: AccountMessage(
            fallo.message,
            AccountMessageType.sesionInvalida,
          ),
        );
      }

      return state.copyWith(
        isSubmitting: false,
        fieldErrors: const {},
        message: AccountMessage(fallo.message, AccountMessageType.error),
      );
    }

    if (fallo is UnauthorizedFailure) {
      return state.copyWith(
        isSubmitting: false,
        fieldErrors: const {},
        message: AccountMessage(
          fallo.message,
          AccountMessageType.sesionInvalida,
        ),
      );
    }

    if (fallo is ConnectivityRequiredFailures || fallo is NetworkFailures) {
      return state.copyWith(
        isSubmitting: false,
        fieldErrors: const {},
        message: AccountMessage(fallo.message, AccountMessageType.aviso),
      );
    }

    return state.copyWith(
      isSubmitting: false,
      fieldErrors: const {},
      message: AccountMessage(fallo.message, AccountMessageType.error),
    );
  }

  /// Campo del formulario al que pertenece un rechazo de negocio (RF-11).
  CampoPerfil? _campoDeCodigo(String codigo) {
    switch (codigo) {
      case CodigosCuenta.invalidEmail:
      case CodigosCuenta.emailAlreadyRegistered:
        return CampoPerfil.correo;
      case CodigosCuenta.weakPassword:
      case CodigosCuenta.passwordTooLong:
        return CampoPerfil.passwordNueva;
      case CodigosCuenta.emptyUpdate:
        return CampoPerfil.formulario;
      default:
        return null;
    }
  }

  Future<void> _onAccountDeletionRequested(
    AccountDeletionRequested event,
    Emitter<AccountState> emit,
  ) async {
    emit(
      state.copyWith(
        isSubmitting: true,
        isLoadingProfile: false,
        fieldErrors: const {},
        clearMessage: true,
      ),
    );

    final resultado = await _deleteAccountUc(event.password);
    final fallo = resultado.fold<Failures?>((fallo) => fallo, (_) => null);

    if (fallo != null) {
      emit(_estadoDeFalloBaja(fallo));
      return;
    }

    await _limpiarTrasBaja(emit);
  }

  AccountState _estadoDeFalloBaja(Failures fallo) {
    if (fallo is AccountFailure &&
        fallo.code == CodigosCuenta.invalidPassword) {
      // RF-17: el rechazo va junto al campo y el diálogo sigue abierto para
      // reintentar sin cerrar la cuenta ni la sesión.
      return state.copyWith(
        isSubmitting: false,
        isLoadingProfile: false,
        fieldErrors: const {
          CampoPerfil.passwordActual: MensajesCuenta.passwordIncorrecta,
        },
        clearMessage: true,
      );
    }

    if (fallo is UnauthorizedFailure ||
        (fallo is AccountFailure && fallo.code == CodigosCuenta.unauthorized)) {
      return state.copyWith(
        isSubmitting: false,
        isLoadingProfile: false,
        message: AccountMessage(
          fallo.message,
          AccountMessageType.sesionInvalida,
        ),
      );
    }

    if (fallo is ConnectivityRequiredFailures || fallo is NetworkFailures) {
      return state.copyWith(
        isSubmitting: false,
        isLoadingProfile: false,
        message: AccountMessage(fallo.message, AccountMessageType.aviso),
      );
    }

    return state.copyWith(
      isSubmitting: false,
      isLoadingProfile: false,
      message: AccountMessage(fallo.message, AccountMessageType.error),
    );
  }

  /// Limpieza local de la baja con marca persistente (RF-18, RNF-10).
  ///
  /// La marca la escribe y la borra `AccountLocalCleaner` alrededor de toda la
  /// limpieza: token, tipo, credenciales cifradas, perfil cacheado y
  /// colecciones Isar. La vista no limpia nada (principio 3). Si cualquier paso
  /// falla, la marca sobrevive y la sesión se cierra para proteger la
  /// información de una cuenta que ya no existe.
  Future<void> _limpiarTrasBaja(Emitter<AccountState> emit) async {
    final AccountCleanupResult resultado;
    try {
      resultado = await _accountLocalCleaner.limpiarTrasBaja(
        correo: state.profile?.email,
      );
    } catch (_) {
      _cerrarSesionPorBajaFallida(emit);
      return;
    }

    if (!resultado.exitoso) {
      _cerrarSesionPorBajaFallida(emit);
      return;
    }

    // El aviso se publica antes del estado final para que el cierre de sesión
    // del AuthBloc quede encolado en el mismo turno (RF-18).
    _sessionEvents.notify(
      const SessionEvent.cuentaEliminada(
        message: MensajesCuenta.cuentaEliminada,
      ),
    );

    emit(
      state.copyWith(
        clearProfile: true,
        isOffline: false,
        isSubmitting: false,
        isLoadingProfile: false,
        fieldErrors: const {},
        message: const AccountMessage(
          MensajesCuenta.cuentaEliminada,
          AccountMessageType.cuentaEliminada,
        ),
      ),
    );
  }

  void _cerrarSesionPorBajaFallida(Emitter<AccountState> emit) {
    _sessionEvents.notify(
      const SessionEvent.cuentaEliminada(
        message: MensajesCuenta.limpiezaLocalFallida,
      ),
    );

    emit(
      state.copyWith(
        clearProfile: true,
        isOffline: false,
        isSubmitting: false,
        isLoadingProfile: false,
        fieldErrors: const {},
        message: const AccountMessage(
          MensajesCuenta.limpiezaLocalFallida,
          AccountMessageType.limpiezaFallida,
        ),
      ),
    );
  }

  void _onAccountMessageConsumed(
    AccountMessageConsumed event,
    Emitter<AccountState> emit,
  ) {
    emit(
      state.copyWith(
        clearMessage: true,
        fieldErrors: const {},
      ),
    );
  }

  @override
  Future<void> close() async {
    await _authSubscription?.cancel();
    return super.close();
  }
}
