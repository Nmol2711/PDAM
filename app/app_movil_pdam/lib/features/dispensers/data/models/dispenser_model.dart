import 'package:app_movil_pdam/core/offline/models/local_dispenser.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_entity.dart';

class DispenserModel extends DispenserEntity {
  const DispenserModel({
    required super.id,
    required super.macAddress,
    required super.name,
    super.isConnected,
    super.wifiSsid,
  });

  factory DispenserModel.fromLocal(LocalDispenser local) {
    return DispenserModel(
      id: local.remoteId?.toString() ?? local.id.toString(),
      macAddress: local.macAddress,
      name: 'Dispensador ${local.macAddress}',
      isConnected: local.isActive,
      wifiSsid: null,
    );
  }

  LocalDispenser toLocal() {
    final local = LocalDispenser()
      ..remoteId = int.tryParse(id)
      ..macAddress = macAddress
      ..isActive = isConnected
      ..pendingDispensing = false
      ..updatedAt = DateTime.now()
      ..isSynced = true;
    return local;
  }

  factory DispenserModel.fromEntity(DispenserEntity entity) {
    return DispenserModel(
      id: entity.id,
      macAddress: entity.macAddress,
      name: entity.name,
      isConnected: entity.isConnected,
      wifiSsid: entity.wifiSsid,
    );
  }
}
