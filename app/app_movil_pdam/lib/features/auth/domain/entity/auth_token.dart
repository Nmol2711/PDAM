class AuthToken {
  final String token;
  final String typeToken;

  AuthToken({required this.token, this.typeToken = 'Bearer'});
}
