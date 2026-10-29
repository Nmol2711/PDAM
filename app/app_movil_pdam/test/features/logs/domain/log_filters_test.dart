import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:app_movil_pdam/features/logs/domain/utils/log_time_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas de los filtros de historial (RF-27 a RF-31, RF-33).
void main() {
  group('hasActiveFilters', () {
    test('sin filtros está vacío', () {
      expect(LogFilters.empty.hasActiveFilters, isFalse);
      expect(LogFilters.empty.hasDateRange, isFalse);
    });

    test('cualquiera de los cuatro filtros lo activa', () {
      expect(const LogFilters(petId: 3).hasActiveFilters, isTrue);
      expect(
        const LogFilters(eventType: 'pet_created').hasActiveFilters,
        isTrue,
      );
      expect(const LogFilters(outcome: 'failure').hasActiveFilters, isTrue);
      expect(
        LogFilters(fromDate: DateTime(2026, 10, 1)).hasActiveFilters,
        isTrue,
      );
      expect(
        LogFilters(toDate: DateTime(2026, 10, 1)).hasActiveFilters,
        isTrue,
      );
    });
  });

  group('copyWith', () {
    test('conserva los filtros que no se indican', () {
      final original = LogFilters(
        petId: 1,
        eventType: 'pet_created',
        outcome: 'success',
        fromDate: DateTime(2026, 10, 1),
        toDate: DateTime(2026, 10, 2),
      );

      final copia = original.copyWith(petId: 2);

      expect(copia.petId, 2);
      expect(copia.eventType, 'pet_created');
      expect(copia.outcome, 'success');
      expect(copia.fromDate, DateTime(2026, 10, 1));
      expect(copia.toDate, DateTime(2026, 10, 2));
    });

    test('permite limpiar un filtro concreto', () {
      const original = LogFilters(
        petId: 1,
        eventType: 'pet_created',
        outcome: 'success',
      );

      final copia = original.copyWith(clearPetId: true, clearOutcome: true);

      expect(copia.petId, isNull);
      expect(copia.eventType, 'pet_created');
      expect(copia.outcome, isNull);
    });

    test('permite limpiar el rango de fechas completo', () {
      final original = LogFilters(
        fromDate: DateTime(2026, 10, 1),
        toDate: DateTime(2026, 10, 2),
      );

      final copia = original.copyWith(clearDateRange: true);

      expect(copia.fromDate, isNull);
      expect(copia.toDate, isNull);
      expect(copia.hasDateRange, isFalse);
    });
  });

  group('traducción a instantes', () {
    test('un rango de un día usa el desplazamiento de la fecha', () {
      final dia = DateTime(2026, 10, 1);
      final filtros = LogFilters(fromDate: dia, toDate: dia);

      expect(
        filtros.fromIso,
        formatearInstanteConDesplazamiento(
          DateTime(2026, 10, 1),
          offset: dia.timeZoneOffset,
        ),
      );
      expect(
        filtros.toIso,
        formatearInstanteConDesplazamiento(
          DateTime(2026, 10, 1, 23, 59, 59, 999),
          offset: dia.timeZoneOffset,
        ),
      );
      expect(
        filtros.fromUtc,
        DateTime.utc(2026, 10, 1).subtract(dia.timeZoneOffset),
      );
    });

    test('sin fecha inicial no hay límite inferior', () {
      final filtros = LogFilters(toDate: DateTime(2026, 10, 1));

      expect(filtros.fromIso, isNull);
      expect(filtros.fromUtc, isNull);
      expect(filtros.toIso, isNotNull);
    });

    test('sin fecha final no hay límite superior', () {
      final filtros = LogFilters(fromDate: DateTime(2026, 10, 1));

      expect(filtros.toIso, isNull);
      expect(filtros.toUtc, isNull);
      expect(filtros.fromIso, isNotNull);
    });

    test('sin rango no hay instantes', () {
      expect(LogFilters.empty.fromIso, isNull);
      expect(LogFilters.empty.toIso, isNull);
    });

    test('un rango de varios días abarca desde el inicio hasta el fin', () {
      final filtros = LogFilters(
        fromDate: DateTime(2026, 10, 1),
        toDate: DateTime(2026, 10, 3),
      );

      expect(
        DateTime.parse(
          filtros.fromIso!,
        ).isBefore(DateTime.parse(filtros.toIso!)),
        isTrue,
      );
      expect(filtros.toUtc!.isAfter(filtros.fromUtc!), isTrue);
    });

    test('la igualdad compara todos los campos', () {
      expect(
        const LogFilters(petId: 1, outcome: 'success'),
        const LogFilters(petId: 1, outcome: 'success'),
      );
      expect(const LogFilters(petId: 1), isNot(const LogFilters(petId: 2)));
    });
  });

  /// Madrid adelanta la hora el 29/03/2026 (+01:00 → +02:00) y la atrasa el
  /// 25/10/2026 (+02:00 → +01:00). El extremo final del día se construye a las
  /// 23:59:59.999, así que debe usar el desplazamiento de ese instante y no el
  /// de medianoche (RF-30). Los desplazamientos se inyectan de forma explícita
  /// para que la prueba sea determinista en cualquier zona horaria del equipo.
  group('cambio de horario (RF-30)', () {
    test(
      'el 29/03/2026 el fin del día usa +02:00 y no el +01:00 de medianoche',
      () {
        final dia = DateTime(2026, 3, 29);
        final rango = rangoDiaLocalAInstantes(
          dia,
          dia,
          offsetInicio: const Duration(hours: 1),
          offsetFin: const Duration(hours: 2),
        );

        expect(rango.desde, '2026-03-29T00:00:00+01:00');
        expect(rango.hasta, '2026-03-29T23:59:59.999+02:00');
        expect(rango.desdeUtc, DateTime.utc(2026, 3, 28, 23));
        expect(rango.hastaUtc, DateTime.utc(2026, 3, 29, 21, 59, 59, 999));
      },
    );

    test(
      'el 25/10/2026 el fin del día usa +01:00 y no el +02:00 de medianoche',
      () {
        final dia = DateTime(2026, 10, 25);
        final rango = rangoDiaLocalAInstantes(
          dia,
          dia,
          offsetInicio: const Duration(hours: 2),
          offsetFin: const Duration(hours: 1),
        );

        expect(rango.desde, '2026-10-25T00:00:00+02:00');
        expect(rango.hasta, '2026-10-25T23:59:59.999+01:00');
        expect(rango.desdeUtc, DateTime.utc(2026, 10, 24, 22));
        expect(rango.hastaUtc, DateTime.utc(2026, 10, 25, 22, 59, 59, 999));
      },
    );

    test(
      'un rango de varios días con cambio de horario usa un desplazamiento por extremo',
      () {
        final rango = rangoDiaLocalAInstantes(
          DateTime(2026, 10, 24),
          DateTime(2026, 10, 25),
          offsetInicio: const Duration(hours: 2),
          offsetFin: const Duration(hours: 1),
        );

        expect(rango.desde, '2026-10-24T00:00:00+02:00');
        expect(rango.hasta, '2026-10-25T23:59:59.999+01:00');
        // Dos días de calendario cuyo último día dura 25 horas por la
        // repetición de la 02:00 del 25/10.
        expect(
          rango.hastaUtc.difference(rango.desdeUtc),
          const Duration(
            hours: 48,
            minutes: 59,
            seconds: 59,
            milliseconds: 999,
          ),
        );
      },
    );

    test('los filtros aplican el desplazamiento de cada extremo del día local',
        () {
      // Sin inyectar la zona: los filtros resuelven el desplazamiento de su
      // propio instante, de modo que la prueba vale en cualquier zona.
      final dia = DateTime(2026, 10, 25);
      final filtros = LogFilters(fromDate: dia, toDate: dia);
      final esperado = rangoDiaLocalAInstantes(dia, dia);

      expect(filtros.fromIso, esperado.desde);
      expect(filtros.toIso, esperado.hasta);
      expect(filtros.fromUtc, esperado.desdeUtc);
      expect(filtros.toUtc, esperado.hastaUtc);
      // El texto que viaja al servidor y el instante con el que se filtra la
      // caché representan el mismo momento.
      expect(DateTime.parse(filtros.fromIso!), esperado.desdeUtc);
      expect(DateTime.parse(filtros.toIso!), esperado.hastaUtc);
    });
  });
}
