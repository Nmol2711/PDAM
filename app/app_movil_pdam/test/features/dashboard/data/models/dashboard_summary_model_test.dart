import 'package:app_movil_pdam/features/dashboard/data/models/dashboard_summary_model.dart';
import 'package:app_movil_pdam/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del contrato del resumen con `today_index` y `calculated_at`
/// (RF-6, RF-12): parseo estricto y sin cifras por defecto distintas de 0.
void main() {
  Map<String, dynamic> respuestaCompleta() => {
        'total_pets': 3,
        'sterilized_pets': 2,
        'food_dispensed_today': 120.5,
        'food_target_today': 250.0,
        'pending_feedings': 4,
        'completed_feedings': 2,
        'weekly_dispensed': [50.0, 0.0, 70.5, 0.0, 0.0, 0.0, 0.0],
        'today_index': 2,
        'calculated_at': '2026-10-01T17:00:00Z',
      };

  group('DashboardSummaryModel.fromJson', () {
    test('lee los siete campos del contrato más today_index y calculated_at', () {
      final resumen = DashboardSummaryModel.fromJson(respuestaCompleta());

      expect(resumen.totalPets, 3);
      expect(resumen.sterilizedPets, 2);
      expect(resumen.foodDispensedToday, 120.5);
      expect(resumen.foodTargetToday, 250.0);
      expect(resumen.pendingFeedings, 4);
      expect(resumen.completedFeedings, 2);
      expect(resumen.weeklyDispensed, [50.0, 0.0, 70.5, 0.0, 0.0, 0.0, 0.0]);
      expect(resumen.todayIndex, 2);
      expect(resumen.calculatedAt, DateTime.utc(2026, 10, 1, 17));
      expect(resumen.calculatedAt!.isUtc, isTrue);
    });

    test('los numéricos ausentes valen 0 y la meta no se rellena con 300', () {
      final json = respuestaCompleta()
        ..remove('total_pets')
        ..remove('sterilized_pets')
        ..remove('food_dispensed_today')
        ..remove('food_target_today')
        ..remove('pending_feedings')
        ..remove('completed_feedings');

      final resumen = DashboardSummaryModel.fromJson(json);

      expect(resumen.totalPets, 0);
      expect(resumen.sterilizedPets, 0);
      expect(resumen.foodDispensedToday, 0.0);
      expect(resumen.foodTargetToday, 0.0);
      expect(resumen.pendingFeedings, 0);
      expect(resumen.completedFeedings, 0);
    });

    test('weekly_dispensed ausente devuelve siete ceros', () {
      final json = respuestaCompleta()..remove('weekly_dispensed');

      final resumen = DashboardSummaryModel.fromJson(json);

      expect(resumen.weeklyDispensed, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
    });

    test('weekly_dispensed con seis elementos lanza FormatException', () {
      final json = respuestaCompleta()
        ..['weekly_dispensed'] = [50.0, 0.0, 70.5, 0.0, 0.0, 0.0];

      expect(
        () => DashboardSummaryModel.fromJson(json),
        throwsFormatException,
      );
    });

    test('weekly_dispensed con ocho elementos lanza FormatException', () {
      final json = respuestaCompleta()
        ..['weekly_dispensed'] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];

      expect(
        () => DashboardSummaryModel.fromJson(json),
        throwsFormatException,
      );
    });

    test('weekly_dispensed que no es lista lanza FormatException', () {
      final json = respuestaCompleta()..['weekly_dispensed'] = 'sin serie';

      expect(
        () => DashboardSummaryModel.fromJson(json),
        throwsFormatException,
      );
    });

    test('un elemento no numérico de weekly_dispensed lanza FormatException', () {
      final json = respuestaCompleta()
        ..['weekly_dispensed'] = [50.0, 0.0, '70.5', 0.0, 0.0, 0.0, 0.0];

      expect(
        () => DashboardSummaryModel.fromJson(json),
        throwsFormatException,
      );
    });

    test('la ausencia de today_index lanza FormatException', () {
      final json = respuestaCompleta()..remove('today_index');

      expect(
        () => DashboardSummaryModel.fromJson(json),
        throwsFormatException,
      );
    });

    test('la ausencia de calculated_at lanza FormatException', () {
      final json = respuestaCompleta()..remove('calculated_at');

      expect(
        () => DashboardSummaryModel.fromJson(json),
        throwsFormatException,
      );
    });

    test('today_index fuera de rango en los extremos lanza FormatException', () {
      final negativo = respuestaCompleta()..['today_index'] = -1;
      final excedido = respuestaCompleta()..['today_index'] = 7;

      expect(
        () => DashboardSummaryModel.fromJson(negativo),
        throwsFormatException,
      );
      expect(
        () => DashboardSummaryModel.fromJson(excedido),
        throwsFormatException,
      );
    });

    test('today_index que no es entero lanza FormatException', () {
      final json = respuestaCompleta()..['today_index'] = '2';

      expect(
        () => DashboardSummaryModel.fromJson(json),
        throwsFormatException,
      );
    });

    test('calculated_at con sufijo Z se convierte a UTC', () {
      final resumen = DashboardSummaryModel.fromJson(respuestaCompleta());

      expect(resumen.calculatedAt, DateTime.utc(2026, 10, 1, 17));
    });

    test('calculated_at con microsegundos conserva el instante', () {
      final json = respuestaCompleta()
        ..['calculated_at'] = '2026-10-01T17:00:00.123456Z';

      final resumen = DashboardSummaryModel.fromJson(json);

      expect(resumen.calculatedAt, DateTime.utc(2026, 10, 1, 17, 0, 0, 123, 456));
      expect(resumen.calculatedAt!.isUtc, isTrue);
    });

    test('calculated_at con desplazamiento se normaliza a UTC', () {
      final json = respuestaCompleta()
        ..['calculated_at'] = '2026-10-01T12:00:00-05:00';

      final resumen = DashboardSummaryModel.fromJson(json);

      expect(resumen.calculatedAt, DateTime.utc(2026, 10, 1, 17));
      expect(resumen.calculatedAt!.isUtc, isTrue);
    });

    test('calculated_at con desplazamiento positivo se normaliza a UTC', () {
      final json = respuestaCompleta()
        ..['calculated_at'] = '2026-10-01T12:00:00+02:00';

      final resumen = DashboardSummaryModel.fromJson(json);

      expect(resumen.calculatedAt, DateTime.utc(2026, 10, 1, 10));
      expect(resumen.calculatedAt!.isUtc, isTrue);
    });

    test('calculated_at sin zona explícita lanza FormatException', () {
      final sinZona = respuestaCompleta()
        ..['calculated_at'] = '2026-10-01T17:00:00';
      final soloFecha = respuestaCompleta()..['calculated_at'] = '2026-10-01';

      // Sin anclaje, DateTime.tryParse usaría la zona del dispositivo.
      expect(
        () => DashboardSummaryModel.fromJson(sinZona),
        throwsFormatException,
      );
      expect(
        () => DashboardSummaryModel.fromJson(soloFecha),
        throwsFormatException,
      );
    });

    test('calculated_at inválido lanza FormatException', () {
      final json = respuestaCompleta()..['calculated_at'] = 'ayer';

      expect(
        () => DashboardSummaryModel.fromJson(json),
        throwsFormatException,
      );
    });
  });

  group('DashboardSummaryModel.toJson', () {
    test('incluye los campos nuevos con los nombres del contrato', () {
      final json = DashboardSummaryModel.fromJson(respuestaCompleta()).toJson();

      expect(json['today_index'], 2);
      expect(json['calculated_at'], '2026-10-01T17:00:00.000Z');
      expect(json['weekly_dispensed'], [50.0, 0.0, 70.5, 0.0, 0.0, 0.0, 0.0]);
    });

    test('ida y vuelta conserva los valores', () {
      final original = DashboardSummaryModel.fromJson(respuestaCompleta());
      final copia = DashboardSummaryModel.fromJson(original.toJson());

      expect(copia, original);
    });

    test('omite calculated_at en el resumen local sin instante del servidor', () {
      final local = DashboardSummaryModel(
        totalPets: 1,
        sterilizedPets: 0,
        foodDispensedToday: 0,
        foodTargetToday: 0,
        pendingFeedings: 0,
        completedFeedings: 0,
        weeklyDispensed: const [0, 0, 0, 0, 0, 0, 0],
        todayIndex: 0,
      );

      expect(local.toJson().containsKey('calculated_at'), isFalse);
      expect(
        () => DashboardSummaryModel.fromJson(local.toJson()),
        throwsFormatException,
      );
    });
  });

  group('DashboardSummary', () {
    test('isFromCache vale false por defecto', () {
      final resumen = DashboardSummary(
        totalPets: 0,
        sterilizedPets: 0,
        foodDispensedToday: 0,
        foodTargetToday: 0,
        pendingFeedings: 0,
        completedFeedings: 0,
        weeklyDispensed: const [0, 0, 0, 0, 0, 0, 0],
        todayIndex: 0,
      );

      expect(resumen.isFromCache, isFalse);
      expect(resumen.calculatedAt, isNull);
    });

    test('props distingue today_index, calculated_at e isFromCache', () {
      final base = DashboardSummary(
        totalPets: 1,
        sterilizedPets: 0,
        foodDispensedToday: 10,
        foodTargetToday: 20,
        pendingFeedings: 1,
        completedFeedings: 0,
        weeklyDispensed: const [10, 0, 0, 0, 0, 0, 0],
        todayIndex: 0,
        calculatedAt: DateTime.utc(2026, 10, 1, 17),
      );

      expect(base.copyWith(todayIndex: 3) == base, isFalse);
      expect(
        base.copyWith(calculatedAt: DateTime.utc(2026, 10, 1, 18)) == base,
        isFalse,
      );
      expect(base.copyWith(isFromCache: true) == base, isFalse);
      expect(base.copyWith() == base, isTrue);
    });
  });
}
