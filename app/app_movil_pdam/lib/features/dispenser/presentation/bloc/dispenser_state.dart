part of 'dispenser_bloc.dart';

/// Estados del módulo unificado de dispensadores.
abstract class DispenserState extends Equatable {
  const DispenserState();

  @override
  List<Object?> get props => [];
}

class DispenserInitial extends DispenserState {}

/// Carga de un dispensador individual (detalle de mascota).
class DispenserLoading extends DispenserState {}

/// Carga de la lista de dispensadores (pantalla de dispositivos).
class DispenserListLoading extends DispenserState {}

class DispenserSuccess extends DispenserState {}

class DispenserLoaded extends DispenserState {
  final Dispenser dispenser;

  const DispenserLoaded(this.dispenser);

  @override
  List<Object?> get props => [dispenser];
}

class DispenserListLoaded extends DispenserState {
  final List<Dispenser> dispensers;

  /// Marca un reabastecimiento exitoso para que la vista muestre el aviso una
  /// sola vez. Los refrescos silenciosos la dejan en `false`.
  final bool refillSuccess;

  /// Marca un rechazo por capacidad para mostrar el único aviso de límite una
  /// sola vez (RF-8, RF-13).
  final bool refillLimitExceeded;

  const DispenserListLoaded({
    required this.dispensers,
    this.refillSuccess = false,
    this.refillLimitExceeded = false,
  });

  @override
  List<Object?> get props => [dispensers, refillSuccess, refillLimitExceeded];
}

class DispenserToggled extends DispenserState {
  final Dispenser dispenser;

  const DispenserToggled(this.dispenser);

  @override
  List<Object?> get props => [dispenser];
}

class DispenserQrScanned extends DispenserState {
  final String macAddress;
  final String secretKeyQr;

  const DispenserQrScanned({
    required this.macAddress,
    required this.secretKeyQr,
  });

  @override
  List<Object?> get props => [macAddress, secretKeyQr];
}

/// La mascota no tiene dispositivo asociado aún.
class DispenserEmpty extends DispenserState {}

/// Fallo tipado del módulo: transporta el `Failures` sin exponer su mensaje a
/// la interfaz. El copy lo decide `dispenser_notice_mapper` (RF-10 a RF-13) y
/// el BLoC no contiene textos (RNF-01).
class DispenserFailure extends DispenserState {
  final Failures failure;
  final Dispenser? dispenser;

  const DispenserFailure(this.failure, {this.dispenser});

  @override
  List<Object?> get props => [failure, dispenser];
}

// --- Estados del flujo BLE / WiFi ---

class BleScanningState extends DispenserState {
  final List<ScannedDevice> scannedDevices;

  const BleScanningState({required this.scannedDevices});

  @override
  List<Object?> get props => [scannedDevices];
}

class ProvisioningInProgressState extends DispenserState {}

class ProvisioningSuccessState extends DispenserState {}

class DispenserErrorState extends DispenserState {
  final String message;

  const DispenserErrorState({required this.message});

  @override
  List<Object?> get props => [message];
}
