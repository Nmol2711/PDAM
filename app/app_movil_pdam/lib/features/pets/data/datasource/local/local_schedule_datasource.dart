import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_schedule.dart';
import 'package:app_movil_pdam/features/pets/domain/entity/schedule.dart';
import 'package:isar/isar.dart';

abstract class LocalScheduleDatasource {
  Future<List<Schedule>> getLocalSchedules({int? petId});
  Future<void> cacheSchedules(List<Schedule> schedules);
  Future<void> saveLocalSchedule(Schedule schedule, {bool isSynced = true});
  Future<void> deleteLocalSchedule(int scheduleId);
}

class LocalScheduleDatasourceImpl implements LocalScheduleDatasource {
  final String? testDirectory;

  LocalScheduleDatasourceImpl({this.testDirectory});

  Future<Isar> _getIsar() async {
    return await IsarService.init(directory: testDirectory);
  }

  @override
  Future<List<Schedule>> getLocalSchedules({int? petId}) async {
    final isar = await _getIsar();
    List<LocalSchedule> localSchedules = await isar.localSchedules.where().findAll();

    if (petId != null) {
      localSchedules = localSchedules.where((ls) => ls.petRemoteId == petId).toList();
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
    final isar = await _getIsar();
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
    final isar = await _getIsar();
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

  @override
  Future<void> deleteLocalSchedule(int scheduleId) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = await isar.localSchedules.filter().remoteIdEqualTo(scheduleId).findFirst();
      if (existing != null) {
        await isar.localSchedules.delete(existing.id);
      } else {
        await isar.localSchedules.delete(scheduleId);
      }
    });
  }
}
