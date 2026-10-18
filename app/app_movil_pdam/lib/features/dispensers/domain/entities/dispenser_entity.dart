class DispenserEntity {
  final String id;
  final String macAddress;
  final String name;
  final bool isConnected;
  final String? wifiSsid;

  const DispenserEntity({
    required this.id,
    required this.macAddress,
    required this.name,
    this.isConnected = false,
    this.wifiSsid,
  });

  DispenserEntity copyWith({
    String? id,
    String? macAddress,
    String? name,
    bool? isConnected,
    String? wifiSsid,
  }) {
    return DispenserEntity(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      name: name ?? this.name,
      isConnected: isConnected ?? this.isConnected,
      wifiSsid: wifiSsid ?? this.wifiSsid,
    );
  }
}
