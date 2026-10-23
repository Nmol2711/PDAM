/// Dispositivo encontrado durante el escaneo BLE de aprovisionamiento.
class ScannedDevice {
  final String name;
  final String remoteId;
  final int rssi;

  const ScannedDevice({
    required this.name,
    required this.remoteId,
    required this.rssi,
  });
}
