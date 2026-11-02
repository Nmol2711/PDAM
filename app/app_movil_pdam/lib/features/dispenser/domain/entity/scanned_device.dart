import 'package:equatable/equatable.dart';

/// Dispositivo encontrado durante el escaneo BLE de aprovisionamiento.
///
/// La igualdad usa solo [remoteId]: el nombre y el RSSI se refrescan en cada
/// anuncio y no deben forzar una emisión de estado nueva (RF-10).
class ScannedDevice extends Equatable {
  final String name;
  final String remoteId;
  final int rssi;

  const ScannedDevice({
    required this.name,
    required this.remoteId,
    required this.rssi,
  });

  @override
  List<Object?> get props => [remoteId];
}
