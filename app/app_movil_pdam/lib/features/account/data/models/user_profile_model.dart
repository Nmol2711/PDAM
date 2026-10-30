import 'package:app_movil_pdam/features/account/domain/entity/user_profile.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';

/// Modelo del perfil de la cuenta según el contrato de `/users/me` (RF-06).
///
/// El correo se normaliza al leerlo: el servidor ya lo devuelve normalizado y
/// la aplicación no debe mostrar variantes con mayúsculas o espacios.
class UserProfileModel extends UserProfile {
  const UserProfileModel({required super.email, required super.isActive});

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    final estado = json['is_active'];
    if (estado is! bool) {
      // Sin `is_active` válido no se inventa «Inactiva» (RF-06, RF-07): es una
      // respuesta inválida del servidor y el datasource la traduce a fallo.
      throw const FormatException('Respuesta del perfil sin is_active válido');
    }
    final correo = json['email'];
    if (correo is! String || correo.trim().isEmpty) {
      // Un correo ausente, vacío o no textual no es un dato mostrable: nunca
      // se convierte en una cadena vacía presentada como correo real (RF-07).
      throw const FormatException('Respuesta del perfil sin email válido');
    }
    return UserProfileModel(
      email: normalizarCorreo(correo),
      isActive: estado,
    );
  }

  /// Copia de una entidad de dominio.
  factory UserProfileModel.fromEntity(UserProfile profile) {
    return UserProfileModel(
      email: normalizarCorreo(profile.email),
      isActive: profile.isActive,
    );
  }

  Map<String, dynamic> toJson() => {'email': email, 'is_active': isActive};

  /// Entidad de dominio sin datos adicionales, con el correo normalizado.
  UserProfile toEntity() =>
      UserProfile(email: normalizarCorreo(email), isActive: isActive);
}

/// Respuesta de `PATCH /users/me` (RF-10, RF-14).
///
/// `access_token` y `token_type` llegan nulos cuando el correo no cambió; en
/// ese caso el token vigente se conserva y [tokenNuevo] es nulo.
class AccountUpdateResponseModel {
  final UserProfileModel profile;
  final String? accessToken;
  final String? tokenType;

  const AccountUpdateResponseModel({
    required this.profile,
    this.accessToken,
    this.tokenType,
  });

  factory AccountUpdateResponseModel.fromJson(Map<String, dynamic> json) {
    return AccountUpdateResponseModel(
      profile: UserProfileModel.fromJson(json),
      accessToken: json['access_token'] as String?,
      tokenType: json['token_type'] as String?,
    );
  }
}
