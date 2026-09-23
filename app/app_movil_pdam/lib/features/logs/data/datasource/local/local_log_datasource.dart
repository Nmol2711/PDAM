import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_log.dart';
import 'package:app_movil_pdam/features/logs/domain/entity/activity_log.dart';
import 'package:isar/isar.dart';

abstract class LocalLogDatasource {
  Future<List<ActivityLogEntity>> getLocalLogs({int? petId, String? date});
  Future<void> cacheLogs(List<ActivityLogEntity> logs);
}

class LocalLogDatasourceImpl implements LocalLogDatasource {
  @override
  Future<List<ActivityLogEntity>> getLocalLogs({int? petId, String? date}) async {
    final isar = await IsarService.init();
    var query = isar.localLogs.where();
    
    List<LocalLog> localLogs = await query.findAll();

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
    final isar = await IsarService.init();
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
}
