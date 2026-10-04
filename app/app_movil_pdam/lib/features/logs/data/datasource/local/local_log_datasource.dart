import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:isar/isar.dart';

abstract class LocalLogDatasource {
  Future<List<ActivityLogEntity>> getLocalLogs({int? petId, String? date});
  Future<void> cacheLogs(List<ActivityLogEntity> logs);
  Future<void> saveLocalLog(ActivityLogEntity log, {bool isSynced = true});
  Future<void> deleteLocalLog(int logId);
}

class LocalLogDatasourceImpl implements LocalLogDatasource {
  final String? testDirectory;

  LocalLogDatasourceImpl({this.testDirectory});

  Future<Isar> _getIsar() async {
    return await IsarService.init(directory: testDirectory);
  }

  @override
  Future<List<ActivityLogEntity>> getLocalLogs({int? petId, String? date}) async {
    final isar = await _getIsar();
    List<LocalLog> localLogs = await isar.localLogs.where().findAll();

    if (petId != null) {
      localLogs = localLogs.where((l) => l.petRemoteId == petId).toList();
    }

    if (date != null && date.isNotEmpty) {
      localLogs = localLogs.where((l) => l.timestamp.toIso8601String().startsWith(date)).toList();
    }

    return localLogs
        .map((ll) => ActivityLogEntity(
              id: ll.remoteId ?? ll.id,
              event: ll.event,
              timestamp: ll.timestamp,
              petId: ll.petRemoteId,
            ))
        .toList();
  }

  @override
  Future<void> cacheLogs(List<ActivityLogEntity> logs) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      for (final log in logs) {
        final existing = await isar.localLogs.filter().remoteIdEqualTo(log.id).findFirst();
        final local = existing ?? LocalLog();
        local.remoteId = log.id;
        local.userId = 'default_user';
        local.petRemoteId = log.petId;
        local.event = log.event;
        local.timestamp = log.timestamp;
        local.isSynced = true;
        await isar.localLogs.put(local);
      }
    });
  }

  @override
  Future<void> saveLocalLog(ActivityLogEntity log, {bool isSynced = true}) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = log.id > 0 
          ? await isar.localLogs.filter().remoteIdEqualTo(log.id).findFirst()
          : null;
      final local = existing ?? LocalLog();
      local.remoteId = log.id > 0 ? log.id : null;
      local.userId = 'default_user';
      local.petRemoteId = log.petId;
      local.event = log.event;
      local.timestamp = log.timestamp;
      local.isSynced = isSynced;
      await isar.localLogs.put(local);
    });
  }

  @override
  Future<void> deleteLocalLog(int logId) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = await isar.localLogs.filter().remoteIdEqualTo(logId).findFirst();
      if (existing != null) {
        await isar.localLogs.delete(existing.id);
      } else {
        await isar.localLogs.delete(logId);
      }
    });
  }
}
