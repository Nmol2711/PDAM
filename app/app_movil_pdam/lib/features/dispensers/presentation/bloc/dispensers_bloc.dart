import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_entity.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/scanned_device.dart';
import 'package:app_movil_pdam/features/dispensers/domain/repositories/dispensers_repository.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_event.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_state.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/dispenser_food_status.dart';

class DispensersBloc extends Bloc<DispensersEvent, DispensersState> {
  final DispensersRepository repository;
  StreamSubscription? _scanSubscription;

  DispensersBloc({required this.repository}) : super(DispensersInitial()) {
    on<LoadDispensersEvent>(_onLoadDispensers);
    on<StartScanBleEvent>(_onStartScanBle);
    on<StopScanBleEvent>(_onStopScanBle);
    on<ConnectAndProvisionEvent>(_onConnectAndProvision);
    on<ResetWifiEvent>(_onResetWifi);
    on<RefillFoodEvent>(_onRefillFood);
    on<DiscountFoodEvent>(_onDiscountFood);
    on<_ScanResultUpdatedEvent>(_onScanResultUpdated);
    on<_ScanErrorEvent>(_onScanError);
  }

  Future<void> _onLoadDispensers(
    LoadDispensersEvent event,
    Emitter<DispensersState> emit,
  ) async {
    emit(DispensersLoading());
    try {
      final dispensers = await repository.getLocalDispensers();
      emit(DispensersLoaded(dispensers: dispensers));
    } catch (e) {
      emit(DispensersErrorState(message: 'Error al cargar los dispositivos: ${e.toString()}'));
    }
  }

  Future<void> _onStartScanBle(
    StartScanBleEvent event,
    Emitter<DispensersState> emit,
  ) async {
    emit(const BleScanningState(scannedDevices: []));
    // 1. Cancel and clean the previous subscription completely
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    // 2. Stop the hardware scan and wait for adapter cooldown
    await repository.stopBleScan();
    await Future.delayed(const Duration(milliseconds: 500));
    // 3. Create new subscription to restart scanning
    _scanSubscription = repository.scanBleDispensers().listen(
      (devices) {
        add(_ScanResultUpdatedEvent(devices));
      },
      onError: (error) {
        add(_ScanErrorEvent(error.toString()));
      },
    );
  }

  Future<void> _onStopScanBle(
    StopScanBleEvent event,
    Emitter<DispensersState> emit,
  ) async {
    await repository.stopBleScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  void _onScanResultUpdated(
    _ScanResultUpdatedEvent event,
    Emitter<DispensersState> emit,
  ) {
    emit(BleScanningState(scannedDevices: event.devices));
  }

  void _onScanError(
    _ScanErrorEvent event,
    Emitter<DispensersState> emit,
  ) {
    emit(DispensersErrorState(message: event.error));
  }

  Future<void> _onConnectAndProvision(
    ConnectAndProvisionEvent event,
    Emitter<DispensersState> emit,
  ) async {
    emit(ProvisioningInProgressState());
    try {
      await repository.connectAndProvisionBle(
        deviceId: event.deviceId,
        ssid: event.ssid,
        password: event.password,
      );
      await repository.saveLocalDispenser(
        DispenserEntity(
          id: event.deviceId,
          macAddress: event.deviceId,
          name: 'Dispensador ${event.deviceId.substring(event.deviceId.length > 5 ? event.deviceId.length - 5 : 0)}',
          isConnected: true,
          wifiSsid: event.ssid,
          currentFoodGrams: 5000.0,
        ),
      );
      emit(ProvisioningSuccessState());
      add(LoadDispensersEvent());
    } catch (e) {
      emit(DispensersErrorState(message: 'Error al aprovisionar: ${e.toString()}'));
    }
  }

  Future<void> _onResetWifi(
    ResetWifiEvent event,
    Emitter<DispensersState> emit,
  ) async {
    try {
      await repository.resetWifiRemote(event.dispenserId);
      add(LoadDispensersEvent());
    } catch (e) {
      emit(DispensersErrorState(message: 'Error al resetear WiFi: ${e.toString()}'));
    }
  }

  Future<void> _onRefillFood(
    RefillFoodEvent event,
    Emitter<DispensersState> emit,
  ) async {
    try {
      final grams = convertAndValidateRefill(event.amount, event.unit);
      await repository.refillFood(event.dispenserId, grams);
      add(LoadDispensersEvent());
    } catch (e) {
      emit(DispensersErrorState(message: e.toString().replaceAll('Exception: ', '')));
      add(LoadDispensersEvent());
    }
  }

  Future<void> _onDiscountFood(
    DiscountFoodEvent event,
    Emitter<DispensersState> emit,
  ) async {
    try {
      await repository.discountFood(event.dispenserId, event.dispensedGrams);
      add(LoadDispensersEvent());
    } catch (e) {
      emit(DispensersErrorState(message: e.toString().replaceAll('Exception: ', '')));
      add(LoadDispensersEvent());
    }
  }

  @override
  Future<void> close() {
    _scanSubscription?.cancel();
    return super.close();
  }
}

class _ScanResultUpdatedEvent extends DispensersEvent {
  final List<ScannedDevice> devices;
  const _ScanResultUpdatedEvent(this.devices);

  @override
  List<Object?> get props => [devices];
}

class _ScanErrorEvent extends DispensersEvent {
  final String error;
  const _ScanErrorEvent(this.error);

  @override
  List<Object?> get props => [error];
}
