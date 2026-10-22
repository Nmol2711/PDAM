import 'package:isar/isar.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';

class DispensersLocalDatasource {
  final String? testDirectory;

  DispensersLocalDatasource({this.testDirectory});

  Future<Isar> _getIsar() async {
    return await IsarService.init(directory: testDirectory);
  }

  Future<List<LocalDispenser>> getLocalDispensers() async {
    final isar = await _getIsar();
    return await isar.localDispensers.where().findAll();
  }

  Future<void> saveLocalDispenser(LocalDispenser dispenser) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = await isar.localDispensers
          .filter()
          .macAddressEqualTo(dispenser.macAddress)
          .or()
          .optional(dispenser.remoteId != null, (q) => q.remoteIdEqualTo(dispenser.remoteId!))
          .findFirst();

      if (existing != null) {
        existing.remoteId = dispenser.remoteId ?? existing.remoteId;
        existing.petRemoteId = dispenser.petRemoteId ?? existing.petRemoteId;
        existing.macAddress = dispenser.macAddress;
        if (dispenser.secretKeyQr.isNotEmpty) {
          existing.secretKeyQr = dispenser.secretKeyQr;
        }
        existing.isActive = dispenser.isActive;
        existing.pendingDispensing = dispenser.pendingDispensing;
        existing.currentFoodGrams = dispenser.currentFoodGrams;
        existing.isOfflineCached = dispenser.isOfflineCached;
        existing.updatedAt = dispenser.updatedAt;
        existing.isSynced = dispenser.isSynced;
        await isar.localDispensers.put(existing);
      } else {
        await isar.localDispensers.put(dispenser);
      }
    });
  }
}
