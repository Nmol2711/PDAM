import 'package:app_movil_pdam/features/logs/domain/utils/log_time_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas de las utilidades de fecha del historial (RF-30, RF-33, RNF-4).
///
/// La app resuelve por su cuenta el desplazamiento de cada límite, incluido el
/// cambio de horario, y envía instantes ISO 8601 con desplazamiento explícito.
void main() {
  group('formatearInstanteConDesplazamiento', () {
    test('formatea un día completo con desplazamiento negativo', () {
      final texto = formatearInstanteConDesplazamiento(
        DateTime(2026, 10, 1),
        offset: const Duration(hours: -5),
      );

      expect(texto, '2026-10-01T00:00:00-05:00');
    });

    test('formatea con desplazamiento positivo y fracciones de segundo', () {
      final texto = formatearInstanteConDesplazamiento(
        DateTime(2026, 3, 29, 23, 59, 59, 999),
        offset: const Duration(hours: 2),
      );

      expect(texto, '2026-03-29T23:59:59.999+02:00');
    });

    test('un desplazamiento cero se escribe como sufijo Z', () {
      final texto = formatearInstanteConDesplazamiento(
        DateTime(2026, 10, 1, 12),
        offset: Duration.zero,
      );

      expect(texto, '2026-10-01T12:00:00Z');
    });

    test('rechaza desplazamientos que no son minutos completos', () {
      expect(
        () => formatearInstanteConDesplazamiento(
          DateTime(2026, 10, 1),
          offset: const Duration(seconds: 30),
        ),
        throwsArgumentError,
      );
    });

    test('rechaza desplazamientos fuera del rango de la norma', () {
      expect(
        () => formatearInstanteConDesplazamiento(
          DateTime(2026, 10, 1),
          offset: const Duration(hours: 15),
        ),
        throwsArgumentError,
      );
    });
  });

  group('rangoDiaLocalAInstantes', () {
    test('traduce un día local a instantes con su desplazamiento', () {
      final rango = rangoDiaLocalAInstantes(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 1),
        offsetInicio: const Duration(hours: -5),
        offsetFin: const Duration(hours: -5),
      );

      expect(rango.desde, '2026-10-01T00:00:00-05:00');
      expect(rango.hasta, '2026-10-01T23:59:59.999-05:00');
      expect(rango.desdeUtc, DateTime.utc(2026, 10, 1, 5));
      expect(rango.hastaUtc, DateTime.utc(2026, 10, 2, 4, 59, 59, 999));
    });

    test(
      'cada límite usa su propio desplazamiento en el cambio de horario',
      () {
        // En el cambio de primavera europeo, el 29/03/2026 el día empieza en
        // +01:00 y termina en +02:00: el día dura 23 horas.
        final rango = rangoDiaLocalAInstantes(
          DateTime(2026, 3, 29),
          DateTime(2026, 3, 29),
          offsetInicio: const Duration(hours: 1),
          offsetFin: const Duration(hours: 2),
        );

        expect(rango.desde, '2026-03-29T00:00:00+01:00');
        expect(rango.hasta, '2026-03-29T23:59:59.999+02:00');
        expect(
          rango.hastaUtc.difference(rango.desdeUtc),
          const Duration(
            hours: 22,
            minutes: 59,
            seconds: 59,
            milliseconds: 999,
          ),
        );
      },
    );

    test('un rango de varios días conserva los extremos de cada día', () {
      final rango = rangoDiaLocalAInstantes(
        DateTime(2026, 3, 28, 18),
        DateTime(2026, 3, 30, 6),
        offsetInicio: const Duration(hours: 1),
        offsetFin: const Duration(hours: 2),
      );

      expect(rango.desde, '2026-03-28T00:00:00+01:00');
      expect(rango.hasta, '2026-03-30T23:59:59.999+02:00');
      expect(rango.hastaUtc.isAfter(rango.desdeUtc), isTrue);
    });

    test('rechaza un rango con la fecha final anterior a la inicial', () {
      expect(
        () => rangoDiaLocalAInstantes(
          DateTime(2026, 10, 2),
          DateTime(2026, 10, 1),
        ),
        throwsArgumentError,
      );
    });

    test('sin desplazamiento explícito usa el de la fecha recibida', () {
      final desde = DateTime(2026, 10, 1);
      final rango = rangoDiaLocalAInstantes(desde, desde);

      expect(
        rango.desdeUtc,
        DateTime.utc(2026, 10, 1).subtract(desde.timeZoneOffset),
      );
    });
  });

  group('formatearFechaHoraLocal', () {
    test('muestra fecha y hora con dos dígitos', () {
      expect(
        formatearFechaHoraLocal(DateTime(2026, 1, 5, 7, 4)),
        '05/01/2026 07:04',
      );
    });

    test('convierte un instante UTC a la hora local del dispositivo', () {
      final utc = DateTime.utc(2026, 10, 1, 17, 30);

      expect(
        formatearFechaHoraLocal(utc),
        formatearFechaHoraLocal(utc.toLocal()),
      );
    });
  });

  group('formatearFechaCorta', () {
    test('muestra solo el día del calendario', () {
      expect(formatearFechaCorta(DateTime(2026, 1, 5)), '05/01/2026');
    });
  });
}
