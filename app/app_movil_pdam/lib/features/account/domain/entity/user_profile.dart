import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:equatable/equatable.dart';

/// Perfil de la cuenta tal como lo devuelve el servidor (RF-06, RF-07).
///
/// Solo contiene datos reales: el correo normalizado y el indicador de cuenta
/// activa. No hay nombre visible, foto ni contraseña, porque la cuenta no los
/// tiene y la spec prohíbe inventarlos.
class UserProfile extends Equatable {
  final String email;
  final bool isActive;

  const UserProfile({required this.email, required this.isActive});

  /// Etiqueta visible del estado: «Activa» o «Inactiva» (RF-06).
  String get estado => etiquetaEstado(isActive);

  /// Inicial del avatar a partir del correo normalizado (RF-06).
  String get inicial => inicialDeCorreo(email);

  UserProfile copyWith({String? email, bool? isActive}) {
    return UserProfile(
      email: email ?? this.email,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  List<Object?> get props => [email, isActive];
}

/// Resultado de consultar el perfil.
///
/// [desdeCache] es verdadero cuando el servidor no respondió y se muestran los
/// datos guardados en el dispositivo: la vista lo usa para mostrar el aviso de
/// RF-07 sin presentar la caché como una respuesta del servidor.
class ProfileSnapshot extends Equatable {
  final UserProfile profile;
  final bool desdeCache;

  const ProfileSnapshot({required this.profile, this.desdeCache = false});

  @override
  List<Object?> get props => [profile, desdeCache];
}
