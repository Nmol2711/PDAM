import 'package:equatable/equatable.dart';

/// Entidad única del módulo de dispensadores.
///
/// Integra la información que necesita el flujo de asociación por QR/MAC
/// (`id`, `pendingDispensing`, `petId`) y la del aprovisionamiento BLE/WiFi
/// (`name`, `wifiSsid`, `currentFoodGrams`, `isOfflineCached`). De este modo
/// ambos flujos comparten un solo modelo de dominio y un solo repositorio.
class Dispenser extends Equatable {
  final int id;
  final String macAddress;
  final bool pendingDispensing;
  final bool isActive;
  final int? petId;
  final String name;
  final String? wifiSsid;
  final double currentFoodGrams;
  final bool isOfflineCached;

  /// Delta de alimento agregado sin conexión que aún debe enviarse al servidor.
  /// Es un dato local de sincronización; el servidor no lo devuelve.
  final double pendingRefillGrams;

  const Dispenser({
    required this.id,
    required this.macAddress,
    this.pendingDispensing = false,
    required this.isActive,
    this.petId,
    this.name = '',
    this.wifiSsid,
    this.currentFoodGrams = 5000.0,
    this.isOfflineCached = false,
    this.pendingRefillGrams = 0.0,
  });

  /// Alias de compatibilidad con las vistas del flujo BLE, que hablan de
  /// "conectado" en lugar de "activo".
  bool get isConnected => isActive;

  /// Identificador estable usado por las operaciones locales y de WiFi.
  /// Si el servidor aún no devolvió un id remoto se usa la MAC.
  String get deviceId => id > 0 ? id.toString() : macAddress;

  @override
  List<Object?> get props => [
    id,
    macAddress,
    pendingDispensing,
    isActive,
    petId,
    name,
    wifiSsid,
    currentFoodGrams,
    isOfflineCached,
    pendingRefillGrams,
  ];

  Dispenser copyWith({
    int? id,
    String? macAddress,
    bool? pendingDispensing,
    bool? isActive,
    int? petId,
    String? name,
    String? wifiSsid,
    double? currentFoodGrams,
    bool? isOfflineCached,
    double? pendingRefillGrams,
  }) {
    return Dispenser(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      pendingDispensing: pendingDispensing ?? this.pendingDispensing,
      isActive: isActive ?? this.isActive,
      petId: petId ?? this.petId,
      name: name ?? this.name,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      currentFoodGrams: currentFoodGrams ?? this.currentFoodGrams,
      isOfflineCached: isOfflineCached ?? this.isOfflineCached,
      pendingRefillGrams: pendingRefillGrams ?? this.pendingRefillGrams,
    );
  }
}
