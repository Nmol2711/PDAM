import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:isar/isar.dart';

abstract class LocalScheduleDatasource {
  Future<List<Schedule>> getLocalSchedules({int? petId});
  Future<void> cacheSchedules(List<Schedule> schedules);
  Future<void> saveLocalSchedule(Schedule schedule, {bool isSynced = true});
}

class LocalScheduleDatasourceImpl implements LocalScheduleDatasource {
  @override
  Future<List<Schedule>> getLocalSchedules({int? petId}) async {
    final isar = await IsarService.init();
    var query = isar.localSchedules.where();
    List<LocalSchedule> localSchedules = await query.findAll();

    if (petId != null) {
      localSchedules = localSchedules.where((s) => s.petRemoteId == petId).toList();
    }

    return localSchedules
        .map((ls) => Schedule(
              id: ls.remoteId ?? ls.id,
              time: ls.time,
              amount: ls.amount,
              petId: ls.petRemoteId,
            ))
        .toList();
  }

  @override
  Future<void> cacheSchedules(List<Schedule> schedules) async {
    final isar = await IsarService.init();
    await isar.writeTxn(() async {
      for (final schedule in schedules) {
        final existing = await isar.localSchedules.filter().remoteIdEqualTo(schedule.id).findFirst();
        
        // Si hay un cambio local pendiente de sincronización (isSynced == false), respetamos el cambio local
        if (existing != null && !existing.isSynced) {
          continue;
        }

        final local = existing ?? LocalSchedule();
        local.remoteId = schedule.id;
        local.userId = 'default_user';
        local.petRemoteId = schedule.petId;
        local.time = schedule.time;
        local.amount = schedule.amount;
        local.updatedAt = DateTime.now();
        local.isSynced = true;
        await isar.localSchedules.put(local);
      }
    });
  }

  @override
  Future<void> saveLocalSchedule(Schedule schedule, {bool isSynced = true}) async {
    final isar = await IsarService.init();
    await isar.writeTxn(() async {
      final existing = schedule.id > 0 
          ? await isar.localSchedules.filter().remoteIdEqualTo(schedule.id).findFirst()
          : null;
      final local = existing ?? LocalSchedule();
      local.remoteId = schedule.id > 0 ? schedule.id : null;
      local.userId = 'default_user';
      local.petRemoteId = schedule.petId;
      local.time = schedule.time;
      local.amount = schedule.amount;
      local.updatedAt = DateTime.now();
      local.isSynced = isSynced;
      await isar.localSchedules.put(local);
    });
  }
}
