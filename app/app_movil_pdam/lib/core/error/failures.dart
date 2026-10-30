abstract class Failures {
  final String message;
  Failures(this.message);
}

class MapFailure {
  static String mapFailureToMessage(Failures failure) {
    return failure.message;
  }
}

class UserFailures extends Failures {
  UserFailures(super.message);
}

class ServerFailures extends Failures {
  ServerFailures(super.message);
}

class ConfigurationFailure extends Failures {
  ConfigurationFailure(super.message);
}

class NetworkFailures extends Failures {
  NetworkFailures(super.message);
}

class LocalStorageFailures extends Failures {
  LocalStorageFailures(super.message);
}

// Fallos tipados del módulo de dispensadores (RF-03, RF-04, RF-06, RF-13). La
// capa de datos los crea a partir del `code` del `detail` del servidor y la
// presentación decide el copy, de modo que ningún texto de estas clases llega
// tal cual a la interfaz (RF-16).

/// La dirección ya está registrada en el sistema (409 `mac_already_registered`).
class MacAlreadyRegisteredFailures extends Failures {
  MacAlreadyRegisteredFailures(super.message);
}

/// La dirección indicada ya la usa otro dispensador (409 `mac_in_use`).
class MacInUseFailures extends Failures {
  MacInUseFailures(super.message);
}

/// La dirección no tiene un formato válido (400 `mac_invalid_format`).
class InvalidMacFormatFailures extends Failures {
  InvalidMacFormatFailures(super.message);
}

/// La operación requiere conexión y no la hay (RF-13, DO-3).
class ConnectivityRequiredFailures extends Failures {
  ConnectivityRequiredFailures(super.message);
}

/// Fallo de validación del motor nutricional WSAVA (RF-1, RF-2). La capa de
/// dominio lo crea con el mensaje descriptivo en español correspondiente.
class NutritionValidationFailures extends Failures {
  NutritionValidationFailures(super.message);
}

// Fallos tipados de la cuenta (spec 015). La capa de datos los crea a partir
// del `code` del `detail` del servidor y la presentación decide el copy; ningún
// texto crudo de Dio llega a la interfaz (RF-05, RF-07, RF-21).

/// Rechazo de negocio de la cuenta con su código estable del catálogo.
///
/// Cubre `invalid_email`, `weak_password`, `password_too_long`,
/// `empty_update`, `email_already_registered`, `invalid_password`,
/// `unauthorized`, `conflict` y `server_error`. [message] es el texto visible
/// del catálogo, nunca el `toString()` de una excepción.
class AccountFailure extends Failures implements Exception {
  final String code;

  AccountFailure(this.code, super.message);

  @override
  String toString() => 'AccountFailure($code): $message';
}

/// El servidor rechazó el token (401 `unauthorized`): la sesión ya no vale y
/// el estado de la cuenta debe cerrarla (RF-05, RF-19).
class UnauthorizedFailure extends Failures {
  UnauthorizedFailure(super.message);
}

/// No hay perfil cacheado del que mostrar datos sin conexión (RF-08).
class NoCachedProfileFailure extends Failures {
  NoCachedProfileFailure(super.message);
}
