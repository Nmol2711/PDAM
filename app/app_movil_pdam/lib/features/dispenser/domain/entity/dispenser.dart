class Dispenser {
  final int id;
  final String macAddress;
  final bool pendingDispensing;
  final bool isActive;
  final int petId;

  const Dispenser({
    required this.id,
    required this.macAddress,
    required this.pendingDispensing,
    required this.isActive,
    required this.petId,
  });
}
