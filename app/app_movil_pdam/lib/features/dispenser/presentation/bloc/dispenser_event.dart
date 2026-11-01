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

/// Actualiza el stock consultando el servidor sin mostrar la pantalla de carga
/// (RF-4). Si falla, conserva la caché local (RF-10).
class RefreshDispensersEvent extends DispenserEvent {}

class StartScanBleEvent extends DispenserEvent {}

class StopScanBleEvent extends DispenserEvent {}

/// Ciclo de vida de la aplicación reenviado por la pantalla de escaneo
/// (RF-13). La página registra y retira su [WidgetsBindingObserver], de modo
/// que solo llega mientras la pantalla está montada.
class AppLifecycleChangedBleEvent extends DispenserEvent {
  final AppLifecycleState lifecycle;

  const AppLifecycleChangedBleEvent(this.lifecycle);
}

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

/// Comandos internos del ciclo de escaneo. Se procesan en una única cola
/// secuencial, de modo que apertura, renovación, resultados y detención no se
/// solapan (RF-06, RF-09, RF-23).
sealed class _ScanCommandEvent extends DispenserEvent {
  const _ScanCommandEvent();
}

class _StartScanCommand extends _ScanCommandEvent {
  const _StartScanCommand();
}

class _StopScanCommand extends _ScanCommandEvent {
  const _StopScanCommand();
}

class _ScanDevicesCommand extends _ScanCommandEvent {
  final int cycleId;
  final List<ScannedDevice> devices;

  const _ScanDevicesCommand(this.cycleId, this.devices);
}

/// Cierre de la ventana del ciclo (RF-01, RF-03).
class _ScanWindowClosedCommand extends _ScanCommandEvent {
  final int cycleId;
  final bool hasDevices;

  const _ScanWindowClosedCommand(this.cycleId, this.hasDevices);
}

/// Apertura fallida del ciclo, con la causa tipada (RF-11, RF-17, RF-18, RF-25).
class _ScanFailedCommand extends _ScanCommandEvent {
  final int cycleId;
  final BleScanFailure failure;

  const _ScanFailedCommand(this.cycleId, this.failure);
}

/// Renovación automática del ciclo tras cerrar una ventana sin resultados.
class _RenewScanCommand extends _ScanCommandEvent {
  const _RenewScanCommand();
}

/// Carga de la lista de dispensadores. Va por la cola de comandos para que un
/// stop encolado antes se resuelva primero (RF-08, RF-24).
class _LoadDispensersCommand extends _ScanCommandEvent {
  const _LoadDispensersCommand();
}

/// Transición del ciclo de vida de la aplicación (RF-13).
class _LifecycleCommand extends _ScanCommandEvent {
  final AppLifecycleState lifecycle;

  const _LifecycleCommand(this.lifecycle);
}

/// Cambio de estado del adaptador Bluetooth (RF-11, RF-12, RF-25).
class _AdapterStatusCommand extends _ScanCommandEvent {
  final BleAdapterStatus status;

  const _AdapterStatusCommand(this.status);
}

/// Error no tipado del flujo de escaneo; la presentación lo resuelve con el
/// aviso `scanFailed` y nunca con texto de excepción (RNF-01).
class _ScanErrorEvent extends DispenserEvent {
  const _ScanErrorEvent();
}
