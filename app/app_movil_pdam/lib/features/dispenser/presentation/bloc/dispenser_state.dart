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

/// Fallo tipado del módulo: transporta el `Failures` sin exponer su mensaje a
/// la interfaz. El copy lo decide `dispenser_notice_mapper` (RF-10 a RF-13) y
/// el BLoC no contiene textos (RNF-01).
class DispenserFailure extends DispenserState {
  final Failures failure;
  final Dispenser? dispenser;
  DispenserFailure(this.failure, {this.dispenser});
}
