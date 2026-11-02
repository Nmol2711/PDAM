/// Estado del adaptador Bluetooth observado por el ciclo de escaneo.
///
/// Es un catálogo cerrado e independiente del plugin BLE: la frontera del
/// adaptador traduce el estado de la plataforma con [fromPlatformName].
enum BleAdapterStatus {
  unknown,
  unavailable,
  unauthorized,
  turningOn,
  on,
  turningOff,
  off;

  /// Solo `on` habilita el escaneo; el resto cierra el ciclo o deja el aviso
  /// correspondiente (RF-11, RF-12, RF-25).
  bool get isUsable => this == BleAdapterStatus.on;

  /// Traduce el nombre del estado informado por la plataforma BLE.
  ///
  /// Un nombre no reconocido se trata como [unknown] para no inventar estados.
  static BleAdapterStatus fromPlatformName(String name) {
    switch (name) {
      case 'unknown':
        return BleAdapterStatus.unknown;
      case 'unavailable':
        return BleAdapterStatus.unavailable;
      case 'unauthorized':
        return BleAdapterStatus.unauthorized;
      case 'turningOn':
        return BleAdapterStatus.turningOn;
      case 'on':
        return BleAdapterStatus.on;
      case 'turningOff':
        return BleAdapterStatus.turningOff;
      case 'off':
        return BleAdapterStatus.off;
      default:
        return BleAdapterStatus.unknown;
    }
  }
}
