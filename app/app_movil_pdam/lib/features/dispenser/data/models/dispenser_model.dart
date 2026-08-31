import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';

class DispenserModel extends Dispenser {
  DispenserModel({
    required super.id,
    required super.macAddress,
    required super.pendingDispensing,
    required super.isActive,
    required super.petId,
  });

  factory DispenserModel.fromJson(Map<String, dynamic> json) {
    return DispenserModel(
      id: json['id'],
      macAddress: json['mac_address'],
      pendingDispensing: json['pending_dispensing'],
      isActive: json['is_active'],
      petId: json['pet_id'],
    );
  }
}
