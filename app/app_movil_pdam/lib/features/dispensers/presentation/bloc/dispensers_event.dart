import 'package:equatable/equatable.dart';

abstract class DispensersEvent extends Equatable {
  const DispensersEvent();

  @override
  List<Object?> get props => [];
}

class LoadDispensersEvent extends DispensersEvent {}

class StartScanBleEvent extends DispensersEvent {}

class StopScanBleEvent extends DispensersEvent {}

class ConnectAndProvisionEvent extends DispensersEvent {
  final String deviceId;
  final String ssid;
  final String password;

  const ConnectAndProvisionEvent({
    required this.deviceId,
    required this.ssid,
    required this.password,
  });

  @override
  List<Object?> get props => [deviceId, ssid, password];
}

class ResetWifiEvent extends DispensersEvent {
  final String dispenserId;

  const ResetWifiEvent({required this.dispenserId});

  @override
  List<Object?> get props => [dispenserId];
}
