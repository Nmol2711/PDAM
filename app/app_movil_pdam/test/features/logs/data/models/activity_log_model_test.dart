import 'package:app_movil_pdam/features/logs/data/models/activity_log_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del modelo del historial con el contrato nuevo (RF-27, RF-28,
/// RF-29, RF-32, RF-41).
void main() {
  Map<String, dynamic> itemCompleto() => {
    'id': 91,
    'created_at': '2026-10-01T17:00:00Z',
    'event_type': 'feeding_dispensed',
    'event_label': 'Comida dispensada',
    'outcome': 'success',
    'outcome_label': 'Éxito',
    'cause': 'objetivo_alcanzado',
    'cause_label': 'Objetivo alcanzado',
    'description': 'Comida dispensada',
    'pet_id': 3,
    'pet_name': 'Milo',
    'dispenser_mac_masked': '**:AB:1F',
    'order_id': 12,
    'requested_grams': 50.0,
    'measured_grams': 50.4,
    'discounted_grams': 50.4,
    'resulting_stock': 1149.6,
    'retry_count': 0,
    'context': {'faltante': 0.0, 'solicitados_reporte': 50.0},
  };

  group('ActivityLogModel.fromJson', () {
    test('lee los 19 campos del contrato', () {
      final log = ActivityLogModel.fromJson(itemCompleto());

      expect(log.id, 91);
      expect(log.createdAt, DateTime.utc(2026, 10, 1, 17));
      expect(log.createdAt.isUtc, isTrue);
      expect(log.eventType, 'feeding_dispensed');
      expect(log.eventLabel, 'Comida dispensada');
      expect(log.outcome, 'success');
      expect(log.outcomeLabel, 'Éxito');
      expect(log.cause, 'objetivo_alcanzado');
      expect(log.causeLabel, 'Objetivo alcanzado');
      expect(log.description, 'Comida dispensada');
      expect(log.petId, 3);
      expect(log.petName, 'Milo');
      expect(log.dispenserMacMasked, '**:AB:1F');
      expect(log.orderId, 12);
      expect(log.requestedGrams, 50.0);
      expect(log.measuredGrams, 50.4);
      expect(log.discountedGrams, 50.4);
      expect(log.resultingStock, 1149.6);
      expect(log.retryCount, 0);
      expect(log.context['faltante'], 0.0);
    });

    test('acepta created_at con fracciones de segundo opcionales', () {
      final conFraccion = ActivityLogModel.fromJson({
        ...itemCompleto(),
        'created_at': '2026-10-01T17:00:00.123456Z',
      });
      final sinFraccion = ActivityLogModel.fromJson({
        ...itemCompleto(),
        'created_at': '2026-10-01T17:00:00Z',
      });

      expect(conFraccion.createdAt.millisecond, 123);
      expect(conFraccion.createdAt.isUtc, isTrue);
      expect(sinFraccion.createdAt, DateTime.utc(2026, 10, 1, 17));
    });

    test('un registro histórico llega sin clasificar y sin etiquetas', () {
      final log = ActivityLogModel.fromJson({
        'id': 5,
        'created_at': '2026-01-01T00:00:00Z',
        'event_type': null,
        'event_label': 'Sin clasificar',
        'outcome': null,
        'outcome_label': null,
        'cause': null,
        'cause_label': null,
        'description': 'Registro histórico',
        'pet_id': null,
        'pet_name': null,
        'dispenser_mac_masked': null,
        'order_id': null,
        'requested_grams': null,
        'measured_grams': null,
        'discounted_grams': null,
        'resulting_stock': null,
        'retry_count': null,
        'context': {},
      });

      expect(log.eventType, isNull);
      expect(log.etiquetaEvento, 'Sin clasificar');
      expect(log.outcomeLabel, isNull);
      expect(log.causeLabel, isNull);
      expect(log.context, isEmpty);
    });

    test('un evento sin etiqueta se muestra como «Sin clasificar»', () {
      final log = ActivityLogModel.fromJson({
        ...itemCompleto(),
        'event_label': null,
      });

      expect(log.etiquetaEvento, 'Sin clasificar');
    });

    test('tolera el contexto ausente', () {
      final json = itemCompleto()..remove('context');
      final log = ActivityLogModel.fromJson(json);

      expect(log.context, isEmpty);
    });
  });

  group('ActivityLogModel.toJson', () {
    test('conserva el contrato para volver a serializar', () {
      final log = ActivityLogModel.fromJson(itemCompleto());
      final json = log.toJson();

      expect(json['id'], 91);
      expect(json['created_at'], '2026-10-01T17:00:00.000Z');
      expect(json['event_type'], 'feeding_dispensed');
      expect(json['outcome'], 'success');
      expect(json['pet_name'], 'Milo');
      expect(json['dispenser_mac_masked'], '**:AB:1F');
      expect(json['context'], isA<Map<String, dynamic>>());
    });

    test('ida y vuelta conserva los valores', () {
      final original = ActivityLogModel.fromJson(itemCompleto());
      final copia = ActivityLogModel.fromJson(original.toJson());

      expect(copia, original);
    });
  });

  group('LogPage', () {
    test('lee el sobre con items, total, page y page_size', () {
      final page = LogPageModel.fromJson({
        'items': [itemCompleto()],
        'total': 1,
        'page': 1,
        'page_size': 50,
      });

      expect(page.items.length, 1);
      expect(page.total, 1);
      expect(page.page, 1);
      expect(page.pageSize, 50);
      expect(page.totalPages, 1);
    });

    test('calcula el total de páginas del sobre', () {
      final page = LogPageModel.fromJson({
        'items': const [],
        'total': 120,
        'page': 2,
        'page_size': 50,
      });

      expect(page.totalPages, 3);
    });

    test('una página vacía conserva su total', () {
      final page = LogPageModel.fromJson({
        'items': const [],
        'total': 0,
        'page': 1,
        'page_size': 50,
      });

      expect(page.items, isEmpty);
      expect(page.total, 0);
    });
  });

  group('LogCatalog', () {
    test('lee tipos y resultados con código y etiqueta', () {
      final catalog = LogCatalogModel.fromJson({
        'event_types': [
          {'code': 'pet_created', 'label': 'Mascota creada'},
          {'code': 'feeding_dispensed', 'label': 'Comida dispensada'},
        ],
        'outcomes': [
          {'code': 'success', 'label': 'Éxito'},
          {'code': 'failure', 'label': 'Fallo'},
        ],
      });

      expect(catalog.eventTypes.length, 2);
      expect(catalog.eventTypes.first.code, 'pet_created');
      expect(catalog.eventTypes.first.label, 'Mascota creada');
      expect(catalog.outcomes.length, 2);
      expect(
        catalog.labelForEventType('feeding_dispensed'),
        'Comida dispensada',
      );
      expect(catalog.labelForOutcome('failure'), 'Fallo');
      expect(catalog.labelForEventType('desconocido'), isNull);
    });
  });
}
