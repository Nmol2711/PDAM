import 'dart:io';

import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/features/logs/data/datasource/local/local_log_datasource.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

ActivityLog _log({
  int id = 1,
  DateTime? createdAt,
  int? petId = 1,
  String? petName = 'Milo',
  String? eventType = 'pet_created',
  String? eventLabel = 'Mascota creada',
  String? outcome = 'success',
  String? outcomeLabel = 'Éxito',
  String? cause = 'objetivo_alcanzado',
  String? causeLabel = 'Objetivo alcanzado',
  String description = 'Mascota creada',
  double? requestedGrams,
  double? measuredGrams,
  double? discountedGrams,
  Map<String, dynamic> context = const <String, dynamic>{},
}) {
  return ActivityLog(
    id: id,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 1, 12),
    eventType: eventType,
    eventLabel: eventLabel,
    outcome: outcome,
    outcomeLabel: outcomeLabel,
    cause: cause,
    causeLabel: causeLabel,
    description: description,
    petId: petId,
    petName: petName,
    dispenserMacMasked: '**:AB:1F',
    orderId: 12,
    requestedGrams: requestedGrams,
    measuredGrams: measuredGrams,
    discountedGrams: discountedGrams,
    resultingStock: 1000,
    retryCount: 0,
    context: context,
  );
}

void main() {
  late Directory tempDir;
  late LocalLogDatasource datasource;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(download: true);
      final warmupDir = await Directory.systemTemp.createTemp('isar_warmup_');
      await IsarService.init(directory: warmupDir.path);
      await warmupDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_log_test_');
    datasource = LocalLogDatasourceImpl(testDirectory: tempDir.path);
  });

  tearDown(() async {
    try {
      final isar = await IsarService.init(directory: tempDir.path);
      await isar.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('caché del historial (RF-34, RF-35)', () {
    test('sin registros devuelve una página vacía', () async {
      final page = await datasource.getLocalLogs(
        filters: LogFilters.empty,
        page: 1,
      );

      expect(page.items, isEmpty);
      expect(page.total, 0);
      expect(page.page, 1);
      expect(page.totalPages, 1);
    });

    test('cacheLogs guarda los campos tipados y las etiquetas', () async {
      await datasource.cacheLogs([
        _log(
          id: 91,
          eventType: 'feeding_dispensed',
          eventLabel: 'Comida dispensada',
          description: 'Comida dispensada',
          requestedGrams: 50,
          measuredGrams: 50.4,
          discountedGrams: 50.4,
          context: const {'faltante': 0.0},
        ),
      ]);

      final page = await datasource.getLocalLogs(
        filters: LogFilters.empty,
        page: 1,
      );
      final log = page.items.single;

      expect(log.id, 91);
      expect(log.eventType, 'feeding_dispensed');
      expect(log.eventLabel, 'Comida dispensada');
      expect(log.outcomeLabel, 'Éxito');
      expect(log.causeLabel, 'Objetivo alcanzado');
      expect(log.petName, 'Milo');
      expect(log.dispenserMacMasked, '**:AB:1F');
      expect(log.requestedGrams, 50);
      expect(log.measuredGrams, 50.4);
      expect(log.discountedGrams, 50.4);
      expect(log.context['faltante'], 0.0);
      expect(log.createdAt, DateTime.utc(2026, 10, 1, 12));
    });

    test('hace upsert por remoteId sin duplicar (RF-35)', () async {
      await datasource.cacheLogs([_log(id: 7, description: 'Primera versión')]);
      await datasource.cacheLogs([_log(id: 7, description: 'Segunda versión')]);

      final page = await datasource.getLocalLogs(
        filters: LogFilters.empty,
        page: 1,
      );

      expect(page.total, 1);
      expect(page.items.single.description, 'Segunda versión');
    });

    test('cacheLogs no borra los registros ya cacheados', () async {
      await datasource.cacheLogs([_log(id: 1)]);
      await datasource.cacheLogs([_log(id: 2)]);

      final page = await datasource.getLocalLogs(
        filters: LogFilters.empty,
        page: 1,
      );

      expect(page.total, 2);
    });

    test('elimina un registro por su identificador remoto', () async {
      await datasource.cacheLogs([_log(id: 1), _log(id: 2)]);

      await datasource.deleteLocalLog(1);

      final page = await datasource.getLocalLogs(
        filters: LogFilters.empty,
        page: 1,
      );
      expect(page.total, 1);
      expect(page.items.single.id, 2);
    });

    test('saveLocalLog guarda un registro suelto', () async {
      await datasource.saveLocalLog(_log(id: 5));

      final page = await datasource.getLocalLogs(
        filters: LogFilters.empty,
        page: 1,
      );

      expect(page.items.single.id, 5);
    });
  });

  group(
    'consulta local con los mismos filtros y paginación (RF-27 a RF-32)',
    () {
      test('ordena del más reciente al más antiguo', () async {
        await datasource.cacheLogs([
          _log(id: 1, createdAt: DateTime.utc(2026, 10, 1, 8)),
          _log(id: 2, createdAt: DateTime.utc(2026, 10, 2, 8)),
          _log(id: 3, createdAt: DateTime.utc(2026, 10, 3, 8)),
        ]);

        final page = await datasource.getLocalLogs(
          filters: LogFilters.empty,
          page: 1,
        );

        expect(page.items.map((l) => l.id), [3, 2, 1]);
      });

      test('desempata por identificador descendente', () async {
        final mismoInstante = DateTime.utc(2026, 10, 1, 12);
        await datasource.cacheLogs([
          _log(id: 1, createdAt: mismoInstante),
          _log(id: 2, createdAt: mismoInstante),
        ]);

        final page = await datasource.getLocalLogs(
          filters: LogFilters.empty,
          page: 1,
        );

        expect(page.items.map((l) => l.id), [2, 1]);
      });

      test('pagina y calcula el total sobre la caché', () async {
        await datasource.cacheLogs([
          for (var i = 1; i <= 5; i++)
            _log(id: i, createdAt: DateTime.utc(2026, 10, i, 8)),
        ]);

        final primera = await datasource.getLocalLogs(
          filters: LogFilters.empty,
          page: 1,
          pageSize: 2,
        );
        final segunda = await datasource.getLocalLogs(
          filters: LogFilters.empty,
          page: 2,
          pageSize: 2,
        );
        final tercera = await datasource.getLocalLogs(
          filters: LogFilters.empty,
          page: 3,
          pageSize: 2,
        );

        expect(primera.items.map((l) => l.id), [5, 4]);
        expect(segunda.items.map((l) => l.id), [3, 2]);
        expect(tercera.items.map((l) => l.id), [1]);
        expect(tercera.total, 5);
        expect(tercera.totalPages, 3);
      });

      test('filtra por mascota', () async {
        await datasource.cacheLogs([
          _log(id: 1, petId: 1),
          _log(id: 2, petId: 2),
        ]);

        final page = await datasource.getLocalLogs(
          filters: const LogFilters(petId: 2),
          page: 1,
        );

        expect(page.total, 1);
        expect(page.items.single.id, 2);
      });

      test('filtra por tipo y excluye los históricos sin clasificar', () async {
        await datasource.cacheLogs([
          _log(id: 1, eventType: 'pet_created', eventLabel: 'Mascota creada'),
          _log(
            id: 2,
            eventType: null,
            eventLabel: 'Sin clasificar',
            outcome: null,
            outcomeLabel: null,
            cause: null,
            causeLabel: null,
          ),
        ]);

        final page = await datasource.getLocalLogs(
          filters: const LogFilters(eventType: 'pet_created'),
          page: 1,
        );

        expect(page.total, 1);
        expect(page.items.single.id, 1);
      });

      test(
        'filtra por resultado y excluye los históricos sin clasificar',
        () async {
          await datasource.cacheLogs([
            _log(id: 1, outcome: 'failure', outcomeLabel: 'Fallo'),
            _log(
              id: 2,
              eventType: null,
              eventLabel: 'Sin clasificar',
              outcome: null,
              outcomeLabel: null,
              cause: null,
              causeLabel: null,
            ),
          ]);

          final page = await datasource.getLocalLogs(
            filters: const LogFilters(outcome: 'failure'),
            page: 1,
          );

          expect(page.total, 1);
          expect(page.items.single.id, 1);
        },
      );

      test('aplica el rango de fechas con ambos extremos inclusivos', () async {
        final filters = LogFilters(
          fromDate: DateTime(2026, 10, 1),
          toDate: DateTime(2026, 10, 1),
        );

        await datasource.cacheLogs([
          _log(
            id: 1,
            createdAt: filters.fromUtc!.subtract(
              const Duration(milliseconds: 1),
            ),
          ),
          _log(id: 2, createdAt: filters.fromUtc!),
          _log(id: 3, createdAt: filters.toUtc!),
          _log(
            id: 4,
            createdAt: filters.toUtc!.add(const Duration(milliseconds: 1)),
          ),
        ]);

        final page = await datasource.getLocalLogs(filters: filters, page: 1);

        expect(page.total, 2);
        expect(page.items.map((l) => l.id), containsAll([2, 3]));
      });

      test('combina los cuatro filtros en conjunción', () async {
        final filters = LogFilters(
          petId: 1,
          eventType: 'feeding_dispensed',
          outcome: 'success',
          fromDate: DateTime(2026, 10, 1),
          toDate: DateTime(2026, 10, 1),
        );
        await datasource.cacheLogs([
          _log(
            id: 1,
            petId: 1,
            eventType: 'feeding_dispensed',
            createdAt: DateTime.utc(2026, 10, 1, 12),
          ),
          _log(
            id: 2,
            petId: 2,
            eventType: 'feeding_dispensed',
            createdAt: DateTime.utc(2026, 10, 1, 12),
          ),
          _log(
            id: 3,
            petId: 1,
            eventType: 'pet_created',
            createdAt: DateTime.utc(2026, 10, 1, 12),
          ),
        ]);

        final page = await datasource.getLocalLogs(filters: filters, page: 1);

        expect(page.total, 1);
        expect(page.items.single.id, 1);
      });
    },
  );

  group('catálogo local derivado de la caché', () {
    test('devuelve tipos y resultados distintos con sus etiquetas', () async {
      await datasource.cacheLogs([
        _log(id: 1, eventType: 'pet_created', eventLabel: 'Mascota creada'),
        _log(id: 2, eventType: 'pet_created', eventLabel: 'Mascota creada'),
        _log(
          id: 3,
          eventType: 'feeding_dispensed',
          eventLabel: 'Comida dispensada',
        ),
        _log(id: 4, outcome: 'failure', outcomeLabel: 'Fallo'),
        _log(
          id: 5,
          eventType: null,
          eventLabel: 'Sin clasificar',
          outcome: null,
          outcomeLabel: null,
        ),
      ]);

      final catalog = await datasource.getLocalCatalog();

      expect(
        catalog.eventTypes.map((e) => e.code),
        containsAll(['pet_created', 'feeding_dispensed']),
      );
      expect(catalog.eventTypes.length, 2);
      expect(catalog.labelForOutcome('failure'), 'Fallo');
      expect(catalog.labelForOutcome('success'), 'Éxito');
    });

    test('sin caché devuelve un catálogo vacío', () async {
      final catalog = await datasource.getLocalCatalog();

      expect(catalog.eventTypes, isEmpty);
      expect(catalog.outcomes, isEmpty);
    });
  });
}
