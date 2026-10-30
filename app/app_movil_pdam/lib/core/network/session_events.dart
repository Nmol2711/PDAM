import 'dart:async';

/// Tipo de aviso de sesión que viaja desde la capa de red hasta el estado.
enum SessionEventType {
  /// El servidor rechazó el token con 401 en una petición distinta de la baja.
  sesionExpirada,

  /// La cuenta se eliminó en el servidor y la sesión local debe cerrarse.
  cuentaEliminada,
}

/// Aviso de sesión con su mensaje visible del catálogo (RF-05, RF-18, RNF-10).
///
/// El mensaje es opcional porque cada tipo tiene un texto por defecto en el
/// catálogo; la baja con limpieza local fallida envía el suyo propio.
class SessionEvent {
  final SessionEventType type;
  final String? message;

  const SessionEvent.sesionExpirada()
    : type = SessionEventType.sesionExpirada,
      message = null;

  const SessionEvent.cuentaEliminada({this.message})
    : type = SessionEventType.cuentaEliminada;

  @override
  String toString() => 'SessionEvent(${type.name})';
}

/// Canal único de avisos de sesión (RF-05).
///
/// El interceptor y el estado de la cuenta publican aquí y `AuthBloc` escucha:
/// así un solo punto cierra la sesión, sin repetir la comprobación en cada
/// repositorio (decisión 13 del plan). No transporta tokens ni credenciales.
class SessionEvents {
  final StreamController<SessionEvent> _controller =
      StreamController<SessionEvent>.broadcast();

  Stream<SessionEvent> get stream => _controller.stream;

  /// Publica un aviso. Se ignora si el canal ya está cerrado.
  void notify(SessionEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}
