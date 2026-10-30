import 'package:isar/isar.dart';

part 'local_profile.g.dart';

/// Perfil de la cuenta guardado en el dispositivo (RF-07, RF-08, RF-10).
///
/// Solo almacena datos recibidos del servidor: correo normalizado y estado de
/// la cuenta. La clave de la cuenta es el correo normalizado, de modo que la
/// misma cuenta no duplica filas y un correo nuevo actualiza el perfil
/// vigente. No guarda contraseñas, tokens ni datos de relleno.
@collection
class LocalProfile {
  Id id = Isar.autoIncrement;

  /// Correo normalizado de la cuenta; identifica el perfil.
  @Index(unique: true, replace: true)
  late String accountKey;

  /// Correo normalizado mostrado al usuario.
  late String email;

  /// Indicador de cuenta activa del servidor.
  late bool isActive;

  /// Momento en que se recibió el perfil del servidor.
  late DateTime updatedAt;
}
