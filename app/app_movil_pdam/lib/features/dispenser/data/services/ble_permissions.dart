import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../../domain/entity/ble_permission_result.dart';

/// Frontera de permisos BLE y ubicación del escaneo y del aprovisionamiento
/// (RF-17, RF-18). Los tests inyectan un doble para no depender del plugin.
abstract class BlePermissions {
  /// Pide los permisos necesarios y devuelve el resultado tipado.
  Future<BlePermissionResult> check();
}

/// Traduce los estados de plataforma a un [BlePermissionResult].
///
/// La ubicación solo participa cuando la versión de Android la exige; en el
/// resto se informa como activa para que no bloquee el escaneo (RF-18).
BlePermissionResult buildBlePermissionResult({
  required PermissionStatus bluetoothScan,
  required PermissionStatus bluetoothConnect,
  PermissionStatus? location,
  required bool locationRequired,
  required bool locationEnabled,
}) {
  final permissionsGranted =
      bluetoothScan.isGranted &&
      bluetoothConnect.isGranted &&
      (!locationRequired || (location?.isGranted ?? true));
  final permanentlyDenied =
      bluetoothScan.isPermanentlyDenied ||
      bluetoothConnect.isPermanentlyDenied ||
      (locationRequired && (location?.isPermanentlyDenied ?? false));

  final BlePermissionStatus status;
  if (permissionsGranted) {
    status = BlePermissionStatus.granted;
  } else if (permanentlyDenied) {
    status = BlePermissionStatus.permanentlyDenied;
  } else {
    status = BlePermissionStatus.denied;
  }

  return BlePermissionResult(
    status: status,
    locationRequired: locationRequired,
    locationEnabled: locationRequired ? locationEnabled : true,
  );
}

/// Primer nivel de API de Android que ya no exige ubicación para escanear BLE
/// (Android 12 / API 31).
const int firstAndroidApiLevelWithoutLocation = 31;

/// Nivel de API de Android inferido del texto de versión del sistema (RF-18).
///
/// Acepta los formatos que informa Dart (`Android 13 (API 33)`) y variantes sin
/// paréntesis (`Android 12`). Devuelve `null` si no se puede interpretar.
int? androidApiLevel(String operatingSystemVersion) {
  final api = RegExp(
    r'API\s*(?:level\s*)?(\d+)',
    caseSensitive: false,
  ).firstMatch(operatingSystemVersion);
  if (api != null) return int.tryParse(api.group(1)!);

  final release = RegExp(
    r'Android\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(operatingSystemVersion);
  final major = int.tryParse(release?.group(1) ?? '');
  return _apiLevelByRelease[major];
}

const Map<int, int> _apiLevelByRelease = {
  4: 19,
  5: 21,
  6: 23,
  7: 24,
  8: 26,
  9: 28,
  10: 29,
  11: 30,
  12: 31,
  13: 33,
  14: 34,
  15: 35,
  16: 36,
};

/// Decide si la versión de Android exige ubicación activa para escanear BLE.
///
/// Es pura e inyectable: la prueba fija plataforma y versión sin leer el SDK
/// real. Si el texto no se interpreta devuelve `false`: el requisito nunca se
/// añade por un parseo fallido, y el respaldo ante una exigencia real es el
/// fallo del plugin al escanear (RF-18).
class AndroidLocationRequirement {
  const AndroidLocationRequirement({
    bool Function()? isAndroid,
    String Function()? operatingSystemVersion,
  }) : _isAndroid = isAndroid,
       _operatingSystemVersion = operatingSystemVersion;

  final bool Function()? _isAndroid;
  final String Function()? _operatingSystemVersion;

  bool get isRequired {
    final isAndroid = _isAndroid?.call() ?? Platform.isAndroid;
    if (!isAndroid) return false;

    final version =
        _operatingSystemVersion?.call() ?? Platform.operatingSystemVersion;
    final apiLevel = androidApiLevel(version);
    if (apiLevel == null) return false;
    return apiLevel < firstAndroidApiLevelWithoutLocation;
  }
}

/// Implementación real sobre `permission_handler`.
class PermissionHandlerBlePermissions implements BlePermissions {
  const PermissionHandlerBlePermissions({
    AndroidLocationRequirement locationRequirement =
        const AndroidLocationRequirement(),
  }) : _locationRequirement = locationRequirement;

  final AndroidLocationRequirement _locationRequirement;

  @override
  Future<BlePermissionResult> check() async {
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final locationRequired = _locationRequirement.isRequired;
    final location = locationRequired
        ? await Permission.locationWhenInUse.request()
        : null;
    final locationEnabled = !locationRequired || await _isLocationEnabled();

    return buildBlePermissionResult(
      bluetoothScan:
          statuses[Permission.bluetoothScan] ?? PermissionStatus.denied,
      bluetoothConnect:
          statuses[Permission.bluetoothConnect] ?? PermissionStatus.denied,
      location: location,
      locationRequired: locationRequired,
      locationEnabled: locationEnabled,
    );
  }

  Future<bool> _isLocationEnabled() async {
    final serviceStatus = await Permission.locationWhenInUse.serviceStatus;
    return serviceStatus == ServiceStatus.enabled;
  }
}
