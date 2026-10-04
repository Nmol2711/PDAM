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
