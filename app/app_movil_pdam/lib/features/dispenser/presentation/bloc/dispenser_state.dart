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

/// Fase de apertura de un ciclo de escaneo (RF-23): detención previa, cooldown y
/// comprobación de permisos, adaptador y ubicación. No muestra progreso ni
/// lista y no consume ventana ni renovación.
class BleScanOpeningState extends DispenserState {
  const BleScanOpeningState();
}

/// Ventana de escaneo abierta. Con la lista vacía la vista muestra progreso;
/// con dispositivos muestra la lista sin progreso (RF-01).
///
/// La lista solo se reemite cuando cambian los identificadores o su orden
/// (RF-10); el último RSSI recibido se conserva para [BleScanResultsState].
class BleScanningState extends DispenserState {
  final List<ScannedDevice> scannedDevices;

  const BleScanningState({required this.scannedDevices});

  @override
  List<Object?> get props => [scannedDevices];
}

/// Resultados conservados al cerrar una ventana con dispositivos (RF-04).
/// La lista se mantiene visible sin progreso ni texto de búsqueda y lleva el
/// último RSSI conocido del ciclo (RF-10).
class BleScanResultsState extends DispenserState {
  final List<ScannedDevice> scannedDevices;

  const BleScanResultsState({required this.scannedDevices});

  @override
  List<Object?> get props => [scannedDevices];
}

/// Estado final tras tres ventanas consecutivas sin resultados (RF-02, RF-03).
class BleScanFinishedState extends DispenserState {
  const BleScanFinishedState();
}

/// Escaneo detenido (RF-08). Es el punto de cesión transitorio hacia la lista
/// de dispensadores (RF-24, T8).
class BleScanStoppedState extends DispenserState {
  const BleScanStoppedState();
}

/// Causa tipada de un aviso de la pantalla de escaneo (RF-11, RF-17, RF-18,
/// RF-25).
///
/// El BLoC solo transporta la causa: el copy y las acciones los decide la vista
/// (T9, RNF-01). [fromScanFailure] no descarta ninguna causa del ciclo.
enum BleScanNoticeCause {
  adapterOff,
  adapterUnavailable,
  adapterUnauthorized,
  permissionDenied,
  permissionPermanentlyDenied,
  locationDisabled,
  scanFailed;

  /// Traduce el fallo tipado de la apertura a la causa del aviso.
  static BleScanNoticeCause fromScanFailure(BleScanFailure failure) {
    switch (failure) {
      case BleScanFailure.adapterOff:
        return BleScanNoticeCause.adapterOff;
      case BleScanFailure.adapterUnavailable:
        return BleScanNoticeCause.adapterUnavailable;
      case BleScanFailure.adapterUnauthorized:
        return BleScanNoticeCause.adapterUnauthorized;
      case BleScanFailure.permissionDenied:
        return BleScanNoticeCause.permissionDenied;
      case BleScanFailure.permissionPermanentlyDenied:
        return BleScanNoticeCause.permissionPermanentlyDenied;
      case BleScanFailure.locationDisabled:
        return BleScanNoticeCause.locationDisabled;
      case BleScanFailure.startFailed:
        return BleScanNoticeCause.scanFailed;
    }
  }
}

/// Precedencia entre avisos de la pantalla de escaneo (RF-24).
///
/// Un aviso de adaptador (`off`, `unavailable`, `unauthorized`) tiene más
/// precedencia que permisos, ubicación y fallo de escaneo: no se sustituye.
/// En cambio, un aviso de adaptador sí sustituye a los de menor precedencia, y
/// los avisos de permisos/ubicación pueden sustituirse entre sí.
bool canReplaceScanNotice(BleScanNoticeCause current, BleScanNoticeCause next) {
  if (!_isAdapterNotice(current)) return true;
  return _isAdapterNotice(next);
}

/// RF-13: al volver a primer plano solo se reabre el ciclo de un aviso de
/// adaptador o de un fallo de escaneo. Los avisos de permisos/ubicación se
/// mantienen sin abrir ciclo: el diálogo del sistema se pide al escanear
/// (RF-17), no al reanudar.
bool canReopenNoticeOnResume(BleScanNoticeCause cause) =>
    _isAdapterNotice(cause) || cause == BleScanNoticeCause.scanFailed;

bool _isAdapterNotice(BleScanNoticeCause cause) =>
    cause == BleScanNoticeCause.adapterOff ||
    cause == BleScanNoticeCause.adapterUnavailable ||
    cause == BleScanNoticeCause.adapterUnauthorized;

/// Aviso en la zona de la lista (RF-11, RF-25): adaptador apagado, no
/// disponible, sin autorización, permisos o ubicación.
///
/// No hay ciclo abierto, ni progreso, ni lista previa. Mientras está vigente,
/// `resumed` no reabre el ciclo (RF-13) y un `on` del adaptador lo sustituye
/// por uno nuevo (RF-12).
class BleScanNoticeState extends DispenserState {
  final BleScanNoticeCause cause;

  const BleScanNoticeState(this.cause);

  @override
  List<Object?> get props => [cause];
}

class ProvisioningInProgressState extends DispenserState {}

class ProvisioningSuccessState extends DispenserState {}

/// Fallo terminal del aprovisionamiento con su causa tipada (RF-17, RF-19 a
/// RF-21). La vista traduce la etapa y el permiso a copy y acciones (T9,
/// RNF-01); el botón de la página queda habilitado porque este estado no es
/// [ProvisioningInProgressState].
class ProvisioningFailureState extends DispenserState {
  final ProvisioningException failure;

  const ProvisioningFailureState(this.failure);

  @override
  List<Object?> get props => [failure];
}

class DispenserErrorState extends DispenserState {
  final String message;

  const DispenserErrorState({required this.message});

  @override
  List<Object?> get props => [message];
}
