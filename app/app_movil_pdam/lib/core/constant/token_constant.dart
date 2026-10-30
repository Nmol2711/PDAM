class TokenConstant {
  static const String keyToken = 'access_token';
  static const String keyTypeToken = 'token_type';
  static const String keyCachedEmail = 'cached_email';
  static const String keyCachedPassword = 'cached_password';

  /// Marca de baja pendiente (RNF-10). Se escribe antes de la limpieza local
  /// de la baja y solo se borra cuando esa limpieza termina; su presencia
  /// bloquea el acceso sin conexión con las credenciales de la cuenta.
  static const String keyPendingDeletion = 'pending_deletion';
}
