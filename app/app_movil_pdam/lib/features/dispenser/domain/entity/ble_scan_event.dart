import 'package:equatable/equatable.dart';

import 'scanned_device.dart';

/// Causa tipada de un ciclo de escaneo que no pudo abrirse o mantenerse.
///
/// Permite que la interfaz elija el aviso sin leer textos de excepciones
/// (RF-11, RF-17, RF-18, RF-25 y RNF-01).
enum BleScanFailure {
  adapterOff,
  adapterUnavailable,
  adapterUnauthorized,
  permissionDenied,
  permissionPermanentlyDenied,
  locationDisabled,
  startFailed,
}

/// Eventos que el servicio BLE emite durante un ciclo de escaneo.
///
/// Los eventos de ventana llevan el `cycleId` del ciclo que los originó para
/// que un cierre tardío no afecte a un ciclo posterior (RF-07).
sealed class BleScanEvent extends Equatable {
  const BleScanEvent();
}

/// Lista recibida mientras la ventana del ciclo está abierta (RF-01, RF-04).
final class BleScanDevices extends BleScanEvent {
  final int cycleId;
  final List<ScannedDevice> devices;

  const BleScanDevices({required this.cycleId, required this.devices});

  @override
  List<Object?> get props => [cycleId, devices];
}

/// Cierre de la ventana del ciclo, con o sin dispositivos (RF-02, RF-03).
final class BleScanWindowClosed extends BleScanEvent {
  final int cycleId;
  final bool hasDevices;

  const BleScanWindowClosed({required this.cycleId, required this.hasDevices});

  @override
  List<Object?> get props => [cycleId, hasDevices];
}

/// El ciclo no pudo abrirse o el adaptador falló durante la apertura.
///
/// Lleva el `cycleId` del ciclo que falló para que un fallo tardío de un ciclo
/// cancelado no pise el aviso ni el estado de un ciclo nuevo (RF-07, RF-24).
final class BleScanFailed extends BleScanEvent {
  final int cycleId;
  final BleScanFailure failure;

  const BleScanFailed({required this.cycleId, required this.failure});

  @override
  List<Object?> get props => [cycleId, failure];
}
