import 'dart:developer' as developer;

import 'package:app_movil_pdam/core/offline/isar_service.dart';
import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/data/models/dispenser_model.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:isar/isar.dart';

abstract class LocalDispenserDatasource {
  Future<Dispenser?> getLocalDispenserByPet(int petId);
  Future<List<Dispenser>> getLocalDispensers();
  Future<void> cacheDispenser(Dispenser dispenser);
  Future<void> saveLocalDispenser(
    Dispenser dispenser, {
    bool isSynced = true,
    String? secretKeyQr,
  });
  Future<void> deleteLocalDispenser(int petId);
}

/// Predicado puro de huérfano heredado (RF-18, RF-19): un registro creado por
/// el fallback offline retirado, que nunca llegó al servidor y por tanto no
/// tiene identificador remoto. Sin `remoteId` ni marca de pendiente, no se puede
/// confirmar con el servidor, así que se descarta en lugar de mostrarlo.
bool isLegacyLocalOrphan({required int? remoteId, required bool isSynced}) {
  return remoteId == null && !isSynced;
}

/// Fuente de datos local única para los dos flujos del dispensador.
///
/// Conserva la purga de huérfanos del flujo QR/MAC y el upsert por MAC o
/// `remoteId` que usaba el flujo BLE/WiFi.
class LocalDispenserDatasourceImpl implements LocalDispenserDatasource {
  final String? testDirectory;

  LocalDispenserDatasourceImpl({this.testDirectory});

  Future<Isar> _getIsar() async {
    return await IsarService.init(directory: testDirectory);
  }

  @override
  Future<Dispenser?> getLocalDispenserByPet(int petId) async {
    final isar = await _getIsar();
    // La purga va ANTES de la lectura: si fuera después, el huérfano de esta
    // mascota ya se habría devuelto una vez (RF-19).
    await _purgeLegacyLocalOrphans(isar);
    final local = await isar.localDispensers
        .filter()
        .petRemoteIdEqualTo(petId)
        .findFirst();
    if (local == null) return null;
    return DispenserModel.fromLocal(local).copyWith(
      petId: local.petRemoteId ?? petId,
    );
  }

  @override
  Future<List<Dispenser>> getLocalDispensers() async {
    final isar = await _getIsar();
    await _purgeLegacyLocalOrphans(isar);
    final rows = await isar.localDispensers.where().findAll();
    return rows.map(DispenserModel.fromLocal).toList(growable: false);
  }

  @override
  Future<void> cacheDispenser(Dispenser dispenser) async {
    await saveLocalDispenser(dispenser);
  }

  @override
  Future<void> saveLocalDispenser(
    Dispenser dispenser, {
    bool isSynced = true,
    String? secretKeyQr,
  }) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      // Upsert por MAC o por id remoto: evita duplicados cuando el mismo
      // dispositivo llega desde el servidor o desde el aprovisionamiento BLE.
      final existing = await isar.localDispensers
          .filter()
          .macAddressEqualTo(dispenser.macAddress)
          .or()
          .optional(
            dispenser.id > 0,
            (q) => q.remoteIdEqualTo(dispenser.id),
          )
          .findFirst();

      final local = existing ?? LocalDispenser();
      local.remoteId = dispenser.id > 0 ? dispenser.id : existing?.remoteId;
      local.petRemoteId = dispenser.petId ?? existing?.petRemoteId;
      local.macAddress = dispenser.macAddress;
      local.secretKeyQr =
          secretKeyQr ?? (existing?.secretKeyQr ?? '');
      local.isActive = dispenser.isActive;
      local.pendingDispensing = dispenser.pendingDispensing;
      local.currentFoodGrams = dispenser.currentFoodGrams;
      local.isOfflineCached = dispenser.isOfflineCached;
      local.updatedAt = DateTime.now();
      local.isSynced = isSynced;
      await isar.localDispensers.put(local);
    });
  }

  @override
  Future<void> deleteLocalDispenser(int petId) async {
    final isar = await _getIsar();
    await isar.writeTxn(() async {
      final existing = await isar.localDispensers
          .filter()
          .petRemoteIdEqualTo(petId)
          .findFirst();
      if (existing != null) {
        await isar.localDispensers.delete(existing.id);
      }
    });
  }

  /// Localiza los huérfanos heredados. Solo lectura, sin transacción de escritura.
  Future<List<LocalDispenser>> _findLegacyLocalOrphans(Isar isar) async {
    final candidates = await isar.localDispensers
        .filter()
        .remoteIdIsNull()
        .findAll();
    return candidates
        .where(
          (row) => isLegacyLocalOrphan(
            remoteId: row.remoteId,
            isSynced: row.isSynced,
          ),
        )
        .toList(growable: false);
  }

  /// Elimina los huérfanos heredados y deja rastro en el log local (RF-18).
  /// No toca la red ni ninguna otra colección: `localPets`, `localSchedules`,
  /// `localLogs` y el almacenamiento de sesión quedan intactos (RF-20).
  Future<void> _purgeLegacyLocalOrphans(Isar isar) async {
    final orphans = await _findLegacyLocalOrphans(isar);
    if (orphans.isEmpty) {
      // Caso normal: no se abre transacción de escritura.
      return;
    }

    await isar.writeTxn(() async {
      for (final orphan in orphans) {
        await isar.localDispensers.delete(orphan.id);
        developer.log(
          'dispensador huérfano eliminado - MAC:${orphan.macAddress}',
          name: 'pdam.dispenser',
        );
      }
    });
  }
}
