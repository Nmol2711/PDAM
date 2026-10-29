import 'dart:convert';

import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/log_filters.dart';
import 'package:isar/isar.dart';

/// Consulta, filtrado y paginación del historial en la caché local (RF-34).
abstract class LocalLogDatasource {
  Future<LogPage> getLocalLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  });

  /// Guarda o actualiza los registros por su `remoteId`, sin duplicar (RF-35).
  Future<void> cacheLogs(List<ActivityLog> logs);

  Future<void> saveLocalLog(ActivityLog log, {bool isSynced = true});

  Future<void> deleteLocalLog(int logId);

  /// Tipos y resultados conocidos por la caché, para poblar los filtros sin
  /// conexión.
  Future<LogCatalog> getLocalCatalog();
}

class LocalLogDatasourceImpl implements LocalLogDatasource {
  final String? testDirectory;

  LocalLogDatasourceImpl({this.testDirectory});

  Future<Isar> _getIsar() async {
    return await IsarService.init(directory: testDirectory);
  }

  @override
  Future<LogPage> getLocalLogs({
    required LogFilters filters,
    required int page,
    int pageSize = 50,
  }) async {
    final isar = await _getIsar();
    final consulta = _aplicarFiltros(isar, filters);
    final pagina = page < 1 ? 1 : page;
    final tamano = pageSize < 1 ? 50 : pageSize;

    final total = await consulta.count();
    final filas = await consulta
        .sortByTimestampDesc()
        .thenByRemoteIdDesc()
        .offset((pagina - 1) * tamano)
        .limit(tamano)
        .findAll();

    return LogPage(
      items: filas.map(_aEntidad).toList(growable: false),
      total: total,
      page: pagina,
      pageSize: tamano,
    );
  }

  QueryBuilder<LocalLog, LocalLog, QAfterFilterCondition> _aplicarFiltros(
    Isar isar,
    LogFilters filters,
  ) {
    var consulta = isar.localLogs.filter().idGreaterThan(0);
    if (filters.petId != null) {
      consulta = consulta.petRemoteIdEqualTo(filters.petId!);
    }
    final tipo = filters.eventType;
    if (tipo != null && tipo.isNotEmpty) {
      consulta = consulta.eventTypeEqualTo(tipo);
    }
    final resultado = filters.outcome;
    if (resultado != null && resultado.isNotEmpty) {
      consulta = consulta.outcomeEqualTo(resultado);
    }
    final desde = filters.fromUtc;
    if (desde != null) {
      consulta = consulta.timestampGreaterThan(desde, include: true);
    }
    final hasta = filters.toUtc;
    if (hasta != null) {
      consulta = consulta.timestampLessThan(hasta, include: true);
    }
    return consulta;
  }

  @override
  Future<void> cacheLogs(List<ActivityLog> logs) async {
    if (logs.isEmpty) return;
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      for (final log in logs) {
        await _guardar(isar, log, isSynced: true);
      }
    });
  }

  @override
  Future<void> saveLocalLog(ActivityLog log, {bool isSynced = true}) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      await _guardar(isar, log, isSynced: isSynced);
    });
  }

  Future<void> _guardar(
    Isar isar,
    ActivityLog log, {
    required bool isSynced,
  }) async {
    // Upsert por `remoteId`: conserva la última versión descargada y no
    // duplica registros ya almacenados (RF-35).
    final existente = log.id > 0
        ? await isar.localLogs.filter().remoteIdEqualTo(log.id).findFirst()
        : null;
    final local = existente ?? LocalLog();

    local.remoteId = log.id > 0 ? log.id : null;
    local.userId = 'default_user';
    local.petRemoteId = log.petId;
    local.timestamp = log.createdAt.toUtc();
    local.eventType = log.eventType;
    local.eventLabel = log.eventLabel;
    local.outcome = log.outcome;
    local.outcomeLabel = log.outcomeLabel;
    local.cause = log.cause;
    local.causeLabel = log.causeLabel;
    local.description = log.description;
    local.petName = log.petName;
    local.dispenserMacMasked = log.dispenserMacMasked;
    local.orderId = log.orderId;
    local.requestedGrams = log.requestedGrams;
    local.measuredGrams = log.measuredGrams;
    local.discountedGrams = log.discountedGrams;
    local.resultingStock = log.resultingStock;
    local.retryCount = log.retryCount;
    local.contextJson = log.context.isEmpty ? null : jsonEncode(log.context);
    local.isSynced = isSynced;

    await isar.localLogs.put(local);
  }

  @override
  Future<void> deleteLocalLog(int logId) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existente = await isar.localLogs
          .filter()
          .remoteIdEqualTo(logId)
          .findFirst();
      if (existente != null) {
        await isar.localLogs.delete(existente.id);
      } else {
        await isar.localLogs.delete(logId);
      }
    });
  }

  @override
  Future<LogCatalog> getLocalCatalog() async {
    final isar = await _getIsar();
    final filas = await isar.localLogs.where().findAll();

    final tipos = <String, String>{};
    final resultados = <String, String>{};
    for (final fila in filas) {
      final tipo = fila.eventType;
      if (tipo != null && tipo.isNotEmpty) {
        tipos.putIfAbsent(tipo, () => fila.eventLabel ?? tipo);
      }
      final resultado = fila.outcome;
      if (resultado != null && resultado.isNotEmpty) {
        resultados.putIfAbsent(resultado, () => fila.outcomeLabel ?? resultado);
      }
    }

    return LogCatalog(
      eventTypes: _entradasOrdenadas(tipos),
      outcomes: _entradasOrdenadas(resultados),
    );
  }

  List<LogCatalogEntry> _entradasOrdenadas(Map<String, String> valores) {
    final codigos = valores.keys.toList()..sort();
    return codigos
        .map((codigo) => LogCatalogEntry(code: codigo, label: valores[codigo]!))
        .toList(growable: false);
  }

  ActivityLog _aEntidad(LocalLog local) {
    return ActivityLog(
      id: local.remoteId ?? local.id,
      createdAt: local.timestamp.toUtc(),
      eventType: local.eventType,
      eventLabel: local.eventLabel,
      outcome: local.outcome,
      outcomeLabel: local.outcomeLabel,
      cause: local.cause,
      causeLabel: local.causeLabel,
      description: local.description,
      petId: local.petRemoteId,
      petName: local.petName,
      dispenserMacMasked: local.dispenserMacMasked,
      orderId: local.orderId,
      requestedGrams: local.requestedGrams,
      measuredGrams: local.measuredGrams,
      discountedGrams: local.discountedGrams,
      resultingStock: local.resultingStock,
      retryCount: local.retryCount,
      context: _decodificarContexto(local.contextJson),
    );
  }

  Map<String, dynamic> _decodificarContexto(String? contexto) {
    if (contexto == null || contexto.isEmpty) return const <String, dynamic>{};
    try {
      final decodificado = jsonDecode(contexto);
      if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
    } catch (_) {
      // Un contexto ilegible no debe invalidar el registro completo.
    }
    return const <String, dynamic>{};
  }
}
