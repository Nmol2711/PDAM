import 'package:isar/isar.dart';
import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';

class DispensersLocalDatasource {
  Future<List<LocalDispenser>> getLocalDispensers() async {
    final isar = await IsarService.init();
    return await isar.localDispensers.where().findAll();
  }

  Future<void> saveLocalDispenser(LocalDispenser dispenser) async {
    final isar = await IsarService.init();
    await isar.writeTxn(() async {
      await isar.localDispensers.put(dispenser);
    });
  }
}
