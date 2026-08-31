part of 'dispenser_bloc.dart';

abstract class DispenserEvent {}

class AssociateDispenserEvent extends DispenserEvent {
  final String macAddress;
  final int petId;
  final String secretKeyQr;
  AssociateDispenserEvent({
    required this.macAddress,
    required this.petId,
    required this.secretKeyQr,
  });
}

class LoadDispenserByPetEvent extends DispenserEvent {
  final int petId;
  LoadDispenserByPetEvent(this.petId);
}

class DeactivateDispenserEvent extends DispenserEvent {
  final int dispenserId;
  final int petId;

  DeactivateDispenserEvent({required this.dispenserId, required this.petId});
}

class ActivateDispenserEvent extends DispenserEvent {
  final int dispenserId;
  final int petId;

  ActivateDispenserEvent({required this.dispenserId, required this.petId});
}

class DeleteDispenserEvent extends DispenserEvent {
  final int petId;

  DeleteDispenserEvent({required this.petId});
}

class QrCodeDetectedEvent extends DispenserEvent {
  final String macAddress;
  final String secretKeyQr;

  QrCodeDetectedEvent({required this.macAddress, required this.secretKeyQr});
}
