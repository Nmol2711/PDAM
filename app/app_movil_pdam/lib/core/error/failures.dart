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
