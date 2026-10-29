import 'dart:math';

/// Genera el identificador de operación del reabastecimiento (RF-11).
///
/// Se crea una sola vez por reabastecimiento y se conserva junto al pendiente
/// hasta recibir una respuesta definitiva del servidor. Usa [Random.secure] y
/// `dart:math`, sin dependencias nuevas (RNF-4).
String generarIdentificadorOperacion({Random? random}) {
  final generador = random ?? Random.secure();
  final valores = List<int>.generate(16, (_) => generador.nextInt(256));
  return valores.map((valor) => valor.toRadixString(16).padLeft(2, '0')).join();
}
