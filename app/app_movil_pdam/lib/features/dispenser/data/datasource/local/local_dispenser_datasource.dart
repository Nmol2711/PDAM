import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:isar/isar.dart';

abstract class LocalDispenserDatasource {
  Future<Dispenser?> getLocalDispenserByPet(int petId);
  Future<void> cacheDispenser(Dispenser dispenser);
  Future<void> saveLocalDispenser(Dispenser dispenser, {bool isSynced = true, String? secretKeyQr});
  Future<void> deleteLocalDispenser(int petId);
}

class LocalDispenserDatasourceImpl implements LocalDispenserDatasource {
  final String? testDirectory;

  LocalDispenserDatasourceImpl({this.testDirectory});

  Future<Isar> _getIsar() async {
    return await IsarService.init(directory: testDirectory);
  }

  @override
  Future<Dispenser?> getLocalDispenserByPet(int petId) async {
    final isar = await _getIsar();
    final local = await isar.localDispensers.filter().petRemoteIdEqualTo(petId).findFirst();
    if (local == null) return null;
    return Dispenser(
      id: local.remoteId ?? local.id,
      macAddress: local.macAddress,
      pendingDispensing: local.pendingDispensing,
      isActive: local.isActive,
      petId: local.petRemoteId ?? petId,
    );
  }

  @override
  Future<void> cacheDispenser(Dispenser dispenser) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = await isar.localDispensers.filter().remoteIdEqualTo(dispenser.id).findFirst();
      final local = existing ?? LocalDispenser();
      local.remoteId = dispenser.id;
      local.petRemoteId = dispenser.petId;
      local.macAddress = dispenser.macAddress;
      local.secretKeyQr = existing?.secretKeyQr ?? '';
      local.isActive = dispenser.isActive;
      local.pendingDispensing = dispenser.pendingDispensing;
      local.updatedAt = DateTime.now();
      local.isSynced = true;
      await isar.localDispensers.put(local);
    });
  }

  @override
  Future<void> saveLocalDispenser(Dispenser dispenser, {bool isSynced = true, String? secretKeyQr}) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = await isar.localDispensers.filter().petRemoteIdEqualTo(dispenser.petId).findFirst();
      final local = existing ?? LocalDispenser();
      local.remoteId = dispenser.id > 0 ? dispenser.id : null;
      local.petRemoteId = dispenser.petId;
      local.macAddress = dispenser.macAddress;
      local.secretKeyQr = secretKeyQr ?? (existing?.secretKeyQr ?? '');
      local.isActive = dispenser.isActive;
      local.pendingDispensing = dispenser.pendingDispensing;
      local.updatedAt = DateTime.now();
      local.isSynced = isSynced;
      await isar.localDispensers.put(local);
    });
  }

  @override
  Future<void> deleteLocalDispenser(int petId) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = await isar.localDispensers.filter().petRemoteIdEqualTo(petId).findFirst();
      if (existing != null) {
        await isar.localDispensers.delete(existing.id);
      }
    });
  }
}
