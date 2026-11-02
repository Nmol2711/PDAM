/// Utilidades puras del panel (RF-10, RNF-2).
///
/// La vista solo deriva estas dos cifras a partir de campos del contrato; no
/// usa el reloj del dispositivo ni contiene reglas de negocio.
library;

/// Porcentaje entero de cumplimiento de lo programado.
///
/// Devuelve `null` cuando no hay ración programada (programado menor o igual
/// que 0), porque no existe una meta contra la cual comparar. En otro caso
/// redondea al entero más cercano y acota el resultado entre 0 y 100.
int? porcentajeCumplimiento(double dispensado, double programado) {
  if (programado <= 0) return null;

  final porcentaje = (dispensado / programado * 100).round();
  return porcentaje.clamp(0, 100).toInt();
}

/// Gramos sin decimales para mostrar en las métricas.
String formatearGramos(double gramos) => gramos.round().toString();
