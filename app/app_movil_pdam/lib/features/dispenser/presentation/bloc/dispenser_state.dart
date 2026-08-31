part of 'dispenser_bloc.dart';

abstract class DispenserState {}

class DispenserInitial extends DispenserState {}

class DispenserLoading extends DispenserState {}

class DispenserSuccess extends DispenserState {}

class DispenserLoaded extends DispenserState {
  final Dispenser dispenser;
  DispenserLoaded(this.dispenser);
}

class DispenserToggled extends DispenserState {
  final Dispenser dispenser;
  DispenserToggled(this.dispenser);
}

class DispenserQrScanned extends DispenserState {
  final String macAddress;
  final String secretKeyQr;

  DispenserQrScanned({required this.macAddress, required this.secretKeyQr});
}

class DispenserEmpty
    extends DispenserState {} // La mascota no tiene dispositivo asociado aún

class DispenserFailure extends DispenserState {
  final String message;
  DispenserFailure(this.message);
}
