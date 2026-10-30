part of 'account_bloc.dart';

/// Tipo del mensaje visible del estado de la cuenta.
enum AccountMessageType {
  /// Confirmación de una operación correcta (RF-10, RF-18).
  confirmacion,

  /// Aviso no bloqueante, como la falta de conexión (RF-07, RF-13).
  aviso,

  /// Error reintentable de la operación (RF-21).
  error,

  /// La sesión ya no es válida y debe volver a iniciarse (RF-05, RF-19).
  sesionInvalida,

  /// La cuenta se eliminó correctamente (RF-18).
  cuentaEliminada,

  /// La cuenta se eliminó pero la limpieza local no terminó (RNF-10).
  limpiezaFallida,
}

/// Mensaje visible del estado, siempre con texto del catálogo (RNF-01).
class AccountMessage {
  final String text;
  final AccountMessageType tipo;

  const AccountMessage(this.text, this.tipo);

  @override
  String toString() => 'AccountMessage(${tipo.name})';
}

/// Estado de la cuenta (RF-06, RF-07, RF-10, RF-14, RF-21, RNF-10).
class AccountState {
  final UserProfile? profile;

  /// Verdadero cuando el perfil mostrado viene de la caché local (RF-07).
  final bool isOffline;

  /// Verdadero mientras hay una operación en curso.
  final bool isSubmitting;

  /// Verdadero mientras solo se está cargando el perfil (precarga).
  ///
  /// Se separa de [isSubmitting] para que la precarga no se confunda con un
  /// envío: el botón «Guardar» no gira mientras se consultan los datos.
  final bool isLoadingProfile;

  /// Errores de cliente o del servidor asociados a un campo (RF-11).
  final Map<CampoPerfil, String> fieldErrors;

  /// Mensaje pendiente de mostrar una sola vez.
  final AccountMessage? message;

  const AccountState({
    this.profile,
    this.isOffline = false,
    this.isSubmitting = false,
    this.isLoadingProfile = false,
    this.fieldErrors = const {},
    this.message,
  });

  AccountState copyWith({
    UserProfile? profile,
    bool clearProfile = false,
    bool? isOffline,
    bool? isSubmitting,
    bool? isLoadingProfile,
    Map<CampoPerfil, String>? fieldErrors,
    AccountMessage? message,
    bool clearMessage = false,
  }) {
    return AccountState(
      profile: clearProfile ? null : (profile ?? this.profile),
      isOffline: isOffline ?? this.isOffline,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isLoadingProfile: isLoadingProfile ?? this.isLoadingProfile,
      fieldErrors: fieldErrors ?? this.fieldErrors,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}
