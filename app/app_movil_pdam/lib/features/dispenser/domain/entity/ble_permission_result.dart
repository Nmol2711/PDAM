import 'package:equatable/equatable.dart';

/// Resultado del permiso de escaneo y conexión BLE (RF-17).
enum BlePermissionStatus { granted, denied, permanentlyDenied }

/// Resultado tipado de los permisos BLE y del estado de la ubicación (RF-18).
///
/// [locationRequired] indica que la versión de Android exige la ubicación
/// activa para escanear; [locationEnabled] refleja si el servicio está
/// encendido. En versiones que no la exigen, [canStartScan] solo depende del
/// permiso.
class BlePermissionResult extends Equatable {
  final BlePermissionStatus status;
  final bool locationRequired;
  final bool locationEnabled;

  const BlePermissionResult({
    required this.status,
    this.locationRequired = false,
    this.locationEnabled = true,
  });

  const BlePermissionResult.granted({
    this.locationRequired = false,
    this.locationEnabled = true,
  }) : status = BlePermissionStatus.granted;

  const BlePermissionResult.denied({
    this.locationRequired = false,
    this.locationEnabled = true,
  }) : status = BlePermissionStatus.denied;

  const BlePermissionResult.permanentlyDenied({
    this.locationRequired = false,
    this.locationEnabled = true,
  }) : status = BlePermissionStatus.permanentlyDenied;

  bool get isGranted => status == BlePermissionStatus.granted;

  bool get isPermanentlyDenied =>
      status == BlePermissionStatus.permanentlyDenied;

  /// La denegación no es permanente: la interfaz puede ofrecer reintentar.
  bool get canRetry => status == BlePermissionStatus.denied;

  /// La elevación del permiso requiere abrir los ajustes de la aplicación.
  bool get requiresAppSettings => isPermanentlyDenied;

  /// La versión de Android exige ubicación y el servicio está desactivado.
  bool get requiresLocationSettings => locationRequired && !locationEnabled;

  /// Único criterio de arranque del ciclo de escaneo o aprovisionamiento.
  bool get canStartScan => isGranted && !requiresLocationSettings;

  @override
  List<Object?> get props => [status, locationRequired, locationEnabled];
}
