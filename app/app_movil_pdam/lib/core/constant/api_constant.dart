class ApiConstants {
  // Para emuladores de Android
  // static const String baseUrl = "http://10.0.2.2:8000";

  // Para acceder desde otro dispositivo en tu red local la ip publica de tu maquina
  static const String baseUrl = "http://192.168.1.58:8000";

  //static const String baseUrl = "http://10.22.168.8:8000";

  // Para Flutter Web
  // static const String baseUrl = "http://localhost:8000";

  static const String login = "$baseUrl/auth/login";
  static const String users = "$baseUrl/users/";
  static const String currentUsers = "$baseUrl/users/me";

  static const String pet = "$baseUrl/pets/";

  static const String schedules = "$baseUrl/schedules/";
  static const String logs = "$baseUrl/logs/";

  static const String dispenser = "$baseUrl/dispensers/";
}
