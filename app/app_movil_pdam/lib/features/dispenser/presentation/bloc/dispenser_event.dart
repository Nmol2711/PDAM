part of 'dispenser_bloc.dart';

/// Eventos del módulo unificado de dispensadores.
abstract class DispenserEvent {
  const DispenserEvent();
}

// --- Flujo QR / MAC ---

class AssociateDispenserEvent extends DispenserEvent {
  final String macAddress;
  final int petId;
  final String secretKeyQr;

  AssociateDispenserEvent({
    required this.macAddress,
    required this.petId,
    required this.secretKeyQr,
  });
}

class LoadDispenserByPetEvent extends DispenserEvent {
  final int petId;

  LoadDispenserByPetEvent(this.petId);
}

class DeactivateDispenserEvent extends DispenserEvent {
  final int dispenserId;
  final int petId;

  DeactivateDispenserEvent({required this.dispenserId, required this.petId});
}

class ActivateDispenserEvent extends DispenserEvent {
  final int dispenserId;
  final int petId;

  ActivateDispenserEvent({required this.dispenserId, required this.petId});
}

class DeleteDispenserEvent extends DispenserEvent {
  final int petId;

  DeleteDispenserEvent({required this.petId});
}

class QrCodeDetectedEvent extends DispenserEvent {
  final String macAddress;
  final String secretKeyQr;

  QrCodeDetectedEvent({required this.macAddress, required this.secretKeyQr});
}

// --- Flujo local / BLE / WiFi ---

class LoadDispensersEvent extends DispenserEvent {}

class StartScanBleEvent extends DispenserEvent {}

class StopScanBleEvent extends DispenserEvent {}

class ConnectAndProvisionEvent extends DispenserEvent {
  final String deviceId;
  final String ssid;
  final String password;

  const ConnectAndProvisionEvent({
    required this.deviceId,
    required this.ssid,
    required this.password,
  });
}

class ResetWifiEvent extends DispenserEvent {
  final String dispenserId;

  const ResetWifiEvent({required this.dispenserId});
}

class RefillFoodEvent extends DispenserEvent {
  final String dispenserId;
  final double amount;
  final String unit;

  const RefillFoodEvent({
    required this.dispenserId,
    required this.amount,
    required this.unit,
  });
}

class DiscountFoodEvent extends DispenserEvent {
  final String dispenserId;
  final double dispensedGrams;

  const DiscountFoodEvent({
    required this.dispenserId,
    required this.dispensedGrams,
  });
}

class _ScanResultUpdatedEvent extends DispenserEvent {
  final List<ScannedDevice> devices;

  const _ScanResultUpdatedEvent(this.devices);
}

class _ScanErrorEvent extends DispenserEvent {
  final String error;

  const _ScanErrorEvent(this.error);
}
