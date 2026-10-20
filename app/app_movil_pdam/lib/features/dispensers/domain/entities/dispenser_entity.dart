class DispenserEntity {
  final String id;
  final String macAddress;
  final String name;
  final bool isConnected;
  final String? wifiSsid;
  final double currentFoodGrams;
  final bool isOfflineCached;

  const DispenserEntity({
    required this.id,
    required this.macAddress,
    required this.name,
    this.isConnected = false,
    this.wifiSsid,
    this.currentFoodGrams = 5000.0,
    this.isOfflineCached = false,
  });

  DispenserEntity copyWith({
    String? id,
    String? macAddress,
    String? name,
    bool? isConnected,
    String? wifiSsid,
    double? currentFoodGrams,
    bool? isOfflineCached,
  }) {
    return DispenserEntity(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      name: name ?? this.name,
      isConnected: isConnected ?? this.isConnected,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      currentFoodGrams: currentFoodGrams ?? this.currentFoodGrams,
      isOfflineCached: isOfflineCached ?? this.isOfflineCached,
    );
  }
}
