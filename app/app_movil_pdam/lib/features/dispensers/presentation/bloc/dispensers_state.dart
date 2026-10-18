import 'package:equatable/equatable.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_entity.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/scanned_device.dart';

abstract class DispensersState extends Equatable {
  const DispensersState();

  @override
  List<Object?> get props => [];
}

class DispensersInitial extends DispensersState {}

class DispensersLoading extends DispensersState {}

class DispensersLoaded extends DispensersState {
  final List<DispenserEntity> dispensers;

  const DispensersLoaded({required this.dispensers});

  @override
  List<Object?> get props => [dispensers];
}

class BleScanningState extends DispensersState {
  final List<ScannedDevice> scannedDevices;

  const BleScanningState({required this.scannedDevices});

  @override
  List<Object?> get props => [scannedDevices];
}

class ProvisioningInProgressState extends DispensersState {}

class ProvisioningSuccessState extends DispensersState {}

class DispensersErrorState extends DispensersState {
  final String message;

  const DispensersErrorState({required this.message});

  @override
  List<Object?> get props => [message];
}
