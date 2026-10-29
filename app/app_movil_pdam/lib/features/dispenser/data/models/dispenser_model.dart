import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';

/// Modelo de datos único del dispensador.
///
/// Traduce entre el contrato HTTP, el registro local de Isar y la entidad de
/// dominio, tanto para el flujo QR/MAC como para el aprovisionamiento BLE/WiFi.
class DispenserModel extends Dispenser {
  const DispenserModel({
    required super.id,
    required super.macAddress,
    super.pendingDispensing,
    required super.isActive,
    super.petId,
    super.name,
    super.wifiSsid,
    super.currentFoodGrams,
    super.isOfflineCached,
    super.pendingRefillGrams,
    super.pendingRefillId,
  });

  factory DispenserModel.fromJson(Map<String, dynamic> json) {
    return DispenserModel(
      id: json['id'] as int? ?? 0,
      macAddress: json['mac_address'] as String? ?? '',
      pendingDispensing: json['pending_dispensing'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? false,
      petId: json['pet_id'] as int?,
      name: json['name'] as String? ?? '',
      currentFoodGrams:
          (json['current_food_grams'] as num?)?.toDouble() ?? 5000.0,
      pendingRefillGrams: 0.0,
    );
  }

  factory DispenserModel.fromLocal(LocalDispenser local) {
    final mac = local.macAddress.toUpperCase();
    return DispenserModel(
      id: local.remoteId ?? local.id,
      macAddress: mac,
      pendingDispensing: local.pendingDispensing,
      isActive: local.isActive,
      petId: local.petRemoteId,
      name: 'Dispensador $mac',
      currentFoodGrams: local.currentFoodGrams,
      isOfflineCached: local.isOfflineCached,
      pendingRefillGrams: local.pendingRefillGrams,
      pendingRefillId: local.pendingRefillId,
    );
  }

  LocalDispenser toLocal() {
    final local = LocalDispenser()
      ..remoteId = id > 0 ? id : null
      ..petRemoteId = petId
      ..macAddress = macAddress
      ..isActive = isActive
      ..pendingDispensing = pendingDispensing
      ..currentFoodGrams = currentFoodGrams
      ..isOfflineCached = isOfflineCached
      ..pendingRefillGrams = pendingRefillGrams
      ..pendingRefillId = pendingRefillId
      ..updatedAt = DateTime.now()
      ..isSynced = true;
    return local;
  }
}
