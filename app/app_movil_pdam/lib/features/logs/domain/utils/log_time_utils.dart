/// Utilidades de fecha del historial (RF-30, RF-33, RNF-4).
///
/// La app resuelve por su cuenta el desplazamiento de cada límite, incluido el
/// cambio de horario, y el servidor solo compara los instantes en UTC.
library;

/// Par de límites de un rango de fechas.
class RangoInstantes {
  /// Límite inferior con desplazamiento explícito.
  final String desde;

  /// Límite superior con desplazamiento explícito.
  final String hasta;

  /// Instante UTC equivalente al límite inferior.
  final DateTime desdeUtc;

  /// Instante UTC equivalente al límite superior.
  final DateTime hastaUtc;

  const RangoInstantes({
    required this.desde,
    required this.hasta,
    required this.desdeUtc,
    required this.hastaUtc,
  });
}

/// Formatea una hora de pared con su desplazamiento explícito.
///
/// Ejemplos: `2026-10-01T00:00:00-05:00`, `2026-03-29T23:59:59.999+02:00` y
/// `2026-10-01T12:00:00Z` cuando el desplazamiento es cero.
String formatearInstanteConDesplazamiento(
  DateTime horaDePared, {
  Duration? offset,
}) {
  final desplazamiento = offset ?? _desplazamientoDe(horaDePared);
  _validarDesplazamiento(desplazamiento);

  final base =
      '${_anio(horaDePared.year)}-${_dos(horaDePared.month)}-'
      '${_dos(horaDePared.day)}T${_dos(horaDePared.hour)}:'
      '${_dos(horaDePared.minute)}:${_dos(horaDePared.second)}';
  final fraccion = horaDePared.millisecond == 0 && horaDePared.microsecond == 0
      ? ''
      : '.${horaDePared.millisecond.toString().padLeft(3, '0')}';

  return '$base$fraccion${_formatearDesplazamiento(desplazamiento)}';
}

/// Traduce un rango de días del calendario local a dos instantes con
/// desplazamiento propio (RF-30).
///
/// Cada extremo usa el desplazamiento de su propio día, de modo que el día del
/// cambio de horario se envía con los dos desplazamientos que le corresponden.
RangoInstantes rangoDiaLocalAInstantes(
  DateTime inicio,
  DateTime fin, {
  Duration? offsetInicio,
  Duration? offsetFin,
}) {
  final desde = DateTime(inicio.year, inicio.month, inicio.day);
  final hasta = DateTime(fin.year, fin.month, fin.day, 23, 59, 59, 999);

  if (hasta.isBefore(desde)) {
    throw ArgumentError(
      'La fecha final no puede ser anterior a la fecha inicial',
    );
  }

  final desplazamientoInicio = offsetInicio ?? _desplazamientoDe(desde);
  final desplazamientoFin = offsetFin ?? _desplazamientoDe(hasta);
  _validarDesplazamiento(desplazamientoInicio);
  _validarDesplazamiento(desplazamientoFin);

  return RangoInstantes(
    desde: formatearInstanteConDesplazamiento(
      desde,
      offset: desplazamientoInicio,
    ),
    hasta: formatearInstanteConDesplazamiento(hasta, offset: desplazamientoFin),
    desdeUtc: instanteUtcDeHoraDePared(desde, offset: desplazamientoInicio),
    hastaUtc: instanteUtcDeHoraDePared(hasta, offset: desplazamientoFin),
  );
}

/// Convierte una hora de pared y su desplazamiento al instante UTC.
DateTime instanteUtcDeHoraDePared(DateTime horaDePared, {Duration? offset}) {
  final desplazamiento = offset ?? _desplazamientoDe(horaDePared);
  _validarDesplazamiento(desplazamiento);
  return DateTime.utc(
    horaDePared.year,
    horaDePared.month,
    horaDePared.day,
    horaDePared.hour,
    horaDePared.minute,
    horaDePared.second,
    horaDePared.millisecond,
    horaDePared.microsecond,
  ).subtract(desplazamiento);
}

/// Formatea un instante del servidor con la hora local del dispositivo.
String formatearFechaHoraLocal(DateTime instante) {
  final local = instante.toLocal();
  return '${_dos(local.day)}/${_dos(local.month)}/${_anio(local.year)} '
      '${_dos(local.hour)}:${_dos(local.minute)}';
}

/// Formatea solo el día del calendario, para la etiqueta del filtro.
String formatearFechaCorta(DateTime fecha) {
  return '${_dos(fecha.day)}/${_dos(fecha.month)}/${_anio(fecha.year)}';
}

String _anio(int anio) => anio.toString().padLeft(4, '0');

String _dos(int valor) => valor.toString().padLeft(2, '0');

Duration _desplazamientoDe(DateTime fecha) =>
    fecha.isUtc ? Duration.zero : fecha.timeZoneOffset;

void _validarDesplazamiento(Duration offset) {
  if (offset.inSeconds % 60 != 0) {
    throw ArgumentError(
      'El desplazamiento debe expresarse en minutos completos',
    );
  }
  if (offset.inMinutes.abs() > 14 * 60) {
    throw ArgumentError('El desplazamiento debe estar entre -14:00 y +14:00');
  }
}

String _formatearDesplazamiento(Duration offset) {
  if (offset == Duration.zero) return 'Z';
  final signo = offset.isNegative ? '-' : '+';
  final minutosTotales = offset.inMinutes.abs();
  final horas = minutosTotales ~/ 60;
  final minutos = minutosTotales % 60;
  return '$signo${_dos(horas)}:${_dos(minutos)}';
}
