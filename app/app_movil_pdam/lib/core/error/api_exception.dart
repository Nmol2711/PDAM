/// Error de la API con el contrato de `detail` de DO-5/AC-4.
///
/// El cliente clasifica por [code], nunca por el texto de [message]: es lo que
/// permite distinguir un conflicto de MAC (409) de un formato inválido (400) sin
/// depender del copy del servidor (RF-06, RF-16).
class ApiException implements Exception {
  /// Código estable del rechazo (`mac_already_registered`, `mac_in_use`,
  /// `mac_invalid_format`, ...). Cuando el servidor aún no devuelve un objeto
  /// `detail` (403, 404, 422 de esquema, rutas no migradas) se usa
  /// [serverErrorCode].
  final String code;

  /// Copy en español que devuelve el servidor. Se conserva para diagnóstico y
  /// para los flujos que aún lo muestran; no se usa para clasificar.
  final String message;

  /// Código HTTP de la respuesta, o `null` si el fallo no tuvo respuesta
  /// (error de red o tiempo de espera agotado).
  final int? status;

  const ApiException({required this.code, required this.message, this.status});

  /// Código usado cuando el `detail` del servidor todavía es texto plano.
  static const String serverErrorCode = 'server_error';

  @override
  String toString() => 'ApiException($code, $status): $message';
}