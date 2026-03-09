abstract class Failures {
  final String message;
  Failures(this.message);
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
