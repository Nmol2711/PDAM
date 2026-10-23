import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser_food_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/activate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/associate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/dasactivate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/delete_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/get_dispenser_by_pet_uc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'dispenser_event.dart';
part 'dispenser_state.dart';

/// BLoC único del módulo de dispensadores.
///
/// Agrupa los eventos del flujo QR/MAC (asociar, cargar por mascota, activar,
/// desactivar y eliminar) y los del flujo BLE/WiFi (listar, escanear,
/// aprovisionar, reiniciar WiFi, reabastecer y descontar alimento).
class DispenserBloc extends Bloc<DispenserEvent, DispenserState> {
  final DispenserRepositories repository;
  final AssociateDispenserUc associateUseCase;
  final GetDispenserByPetUc getDispenserByPetUseCase;
  final ActivateDispenserUc activateUseCase;
  final DesactivateDispenserUc deactivateUseCase;
  final DeleteDispenserUc deleteDispenserUseCase;

  Dispenser? _lastLoadedDispenser;
  StreamSubscription<List<ScannedDevice>>? _scanSubscription;

  DispenserBloc({
    required this.repository,
    required this.associateUseCase,
    required this.getDispenserByPetUseCase,
    required this.activateUseCase,
    required this.deactivateUseCase,
    required this.deleteDispenserUseCase,
  }) : super(DispenserInitial()) {
    on<AssociateDispenserEvent>(_onAssociate);
    on<LoadDispenserByPetEvent>(_onLoadDispenserByPet);
    on<DeactivateDispenserEvent>(_onDeactivate);
    on<ActivateDispenserEvent>(_onActivate);
    on<DeleteDispenserEvent>(_onDelete);
    on<QrCodeDetectedEvent>(_onQrDetected);

    on<LoadDispensersEvent>(_onLoadDispensers);
    on<RefreshDispensersEvent>(_onRefreshDispensers);
    on<StartScanBleEvent>(_onStartScanBle);
    on<StopScanBleEvent>(_onStopScanBle);
    on<ConnectAndProvisionEvent>(_onConnectAndProvision);
    on<ResetWifiEvent>(_onResetWifi);
    on<RefillFoodEvent>(_onRefillFood);
    on<DiscountFoodEvent>(_onDiscountFood);
    on<_ScanResultUpdatedEvent>(_onScanResultUpdated);
    on<_ScanErrorEvent>(_onScanError);
  }

  // --- Flujo QR / MAC ---

  Future<void> _onAssociate(
    AssociateDispenserEvent event,
    Emitter<DispenserState> emit,
  ) async {
    emit(DispenserLoading());
    final failureOrDispenser = await associateUseCase(
      event.macAddress,
      event.petId,
      event.secretKeyQr,
    );

    // El fallo viaja tipado hasta la presentación, que decide el copy
    // (RF-10 a RF-13). Aquí no hay textos (RNF-01).
    failureOrDispenser.fold(
      (failure) => emit(DispenserFailure(failure)),
      (dispenser) => emit(DispenserSuccess()),
    );
  }

  Future<void> _onLoadDispenserByPet(
    LoadDispenserByPetEvent event,
    Emitter<DispenserState> emit,
  ) async {
    emit(DispenserLoading());
    final failureOrDispenser = await getDispenserByPetUseCase(event.petId);

    failureOrDispenser.fold(
      (failure) {
        _lastLoadedDispenser = null;
        emit(DispenserEmpty());
      }, // Si da error 404 de que no existe, asumimos vacío
      (dispenser) {
        _lastLoadedDispenser = dispenser;
        emit(DispenserLoaded(dispenser));
      },
    );
  }

  Future<void> _onDeactivate(
    DeactivateDispenserEvent event,
    Emitter<DispenserState> emit,
  ) async {
    emit(DispenserLoading());
    final result = await deactivateUseCase(event.dispenserId, event.petId);

    if (result.isLeft()) {
      result.fold(
        (failure) => emit(
          DispenserFailure(failure, dispenser: _lastLoadedDispenser),
        ),
        (_) => null,
      );
      return;
    }

    final success = result.getOrElse(() => false);
    if (!success) {
      emit(
        DispenserFailure(
          _falloOperacionNoCompletada().failure,
          dispenser: _lastLoadedDispenser,
        ),
      );
      return;
    }

    await _refreshLoadedDispenser(event.petId, emit);
  }

  Future<void> _onActivate(
    ActivateDispenserEvent event,
    Emitter<DispenserState> emit,
  ) async {
    emit(DispenserLoading());
    final result = await activateUseCase(event.dispenserId, event.petId);

    if (result.isLeft()) {
      result.fold(
        (failure) => emit(
          DispenserFailure(failure, dispenser: _lastLoadedDispenser),
        ),
        (_) => null,
      );
      return;
    }

    final success = result.getOrElse(() => false);
    if (!success) {
      emit(
        DispenserFailure(
          _falloOperacionNoCompletada().failure,
          dispenser: _lastLoadedDispenser,
        ),
      );
      return;
    }

    await _refreshLoadedDispenser(event.petId, emit);
  }

  Future<void> _onDelete(
    DeleteDispenserEvent event,
    Emitter<DispenserState> emit,
  ) async {
    emit(DispenserLoading());
    final result = await deleteDispenserUseCase(event.petId);

    if (result.isLeft()) {
      result.fold(
        (failure) => emit(
          DispenserFailure(failure, dispenser: _lastLoadedDispenser),
        ),
        (_) => null,
      );
      return;
    }

    final success = result.getOrElse(() => false);
    if (!success) {
      emit(
        DispenserFailure(
          _falloOperacionNoCompletada().failure,
          dispenser: _lastLoadedDispenser,
        ),
      );
      return;
    }

    _lastLoadedDispenser = null;
    emit(DispenserEmpty());
  }

  void _onQrDetected(
    QrCodeDetectedEvent event,
    Emitter<DispenserState> emit,
  ) {
    emit(
      DispenserQrScanned(
        macAddress: event.macAddress,
        secretKeyQr: event.secretKeyQr,
      ),
    );
  }

  Future<void> _refreshLoadedDispenser(
    int petId,
    Emitter<DispenserState> emit,
  ) async {
    final refreshed = await getDispenserByPetUseCase(petId);
    refreshed.fold(
      (failure) => emit(
        DispenserFailure(failure, dispenser: _lastLoadedDispenser),
      ),
      (dispenser) {
        _lastLoadedDispenser = dispenser;
        emit(DispenserLoaded(dispenser));
      },
    );
  }

  // --- Flujo local / BLE / WiFi ---

  Future<void> _onLoadDispensers(
    LoadDispensersEvent event,
    Emitter<DispenserState> emit,
  ) async {
    emit(DispenserListLoading());
    try {
      final dispensers = await repository.getLocalDispensers();
      emit(DispenserListLoaded(dispensers: dispensers));
    } catch (e) {
      emit(
        DispenserErrorState(
          message: 'Error al cargar los dispositivos: ${e.toString()}',
        ),
      );
    }
  }

  /// Refresco silencioso (RF-4, RF-10): actualiza el stock desde el servidor y
  /// vuelve a emitir la lista sin pasar por [DispenserListLoading]. No pisa los
  /// estados de escaneo, aprovisionamiento ni el detalle de una mascota.
  Future<void> _onRefreshDispensers(
    RefreshDispensersEvent event,
    Emitter<DispenserState> emit,
  ) async {
    try {
      await repository.refreshDispensers();
    } catch (_) {
      // Silencioso: la lista local sigue siendo válida.
    }

    final List<Dispenser> dispensers;
    try {
      dispensers = await repository.getLocalDispensers();
    } catch (_) {
      return;
    }

    if (isClosed || !_canEmitListState()) return;
    emit(DispenserListLoaded(dispensers: dispensers));
  }

  bool _canEmitListState() {
    final current = state;
    return current is DispenserInitial ||
        current is DispenserListLoading ||
        current is DispenserListLoaded ||
        current is DispenserEmpty ||
        current is DispenserErrorState;
  }

  Future<void> _onStartScanBle(
    StartScanBleEvent event,
    Emitter<DispenserState> emit,
  ) async {
    emit(const BleScanningState(scannedDevices: []));
    // 1. Cancela y limpia la suscripción anterior por completo.
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    // 2. Detiene el escaneo de hardware y espera el cooldown del adaptador.
    await repository.stopBleScan();
    await Future.delayed(const Duration(milliseconds: 1000));
    // 3. Crea una nueva suscripción para reiniciar el escaneo.
    _scanSubscription = repository.scanBleDispensers().listen(
      (devices) {
        if (!isClosed) add(_ScanResultUpdatedEvent(devices));
      },
      onError: (error) {
        if (!isClosed) add(_ScanErrorEvent(error.toString()));
      },
    );
  }

  Future<void> _onStopScanBle(
    StopScanBleEvent event,
    Emitter<DispenserState> emit,
  ) async {
    await repository.stopBleScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  void _onScanResultUpdated(
    _ScanResultUpdatedEvent event,
    Emitter<DispenserState> emit,
  ) {
    emit(BleScanningState(scannedDevices: event.devices));
  }

  void _onScanError(
    _ScanErrorEvent event,
    Emitter<DispenserState> emit,
  ) {
    emit(DispenserErrorState(message: event.error));
  }

  Future<void> _onConnectAndProvision(
    ConnectAndProvisionEvent event,
    Emitter<DispenserState> emit,
  ) async {
    emit(ProvisioningInProgressState());
    try {
      await repository.connectAndProvisionBle(
        deviceId: event.deviceId,
        ssid: event.ssid,
        password: event.password,
      );
      final shortId = event.deviceId.length > 5
          ? event.deviceId.substring(event.deviceId.length - 5)
          : event.deviceId;
      await repository.saveLocalDispenser(
        Dispenser(
          id: int.tryParse(event.deviceId) ?? 0,
          macAddress: event.deviceId,
          isActive: true,
          name: 'Dispensador $shortId',
          wifiSsid: event.ssid,
          currentFoodGrams: 5000.0,
        ),
      );
      emit(ProvisioningSuccessState());
      add(LoadDispensersEvent());
    } catch (e) {
      emit(DispenserErrorState(message: 'Error al aprovisionar: ${e.toString()}'));
    }
  }

  Future<void> _onResetWifi(
    ResetWifiEvent event,
    Emitter<DispenserState> emit,
  ) async {
    try {
      await repository.resetWifiRemote(event.dispenserId);
      add(LoadDispensersEvent());
    } catch (e) {
      emit(DispenserErrorState(message: 'Error al resetear WiFi: ${e.toString()}'));
    }
  }

  Future<void> _onRefillFood(
    RefillFoodEvent event,
    Emitter<DispenserState> emit,
  ) async {
    try {
      final grams = convertAndValidateRefill(event.amount, event.unit);
      await repository.refillFood(event.dispenserId, grams);
      final dispensers = await repository.getLocalDispensers();
      if (isClosed) return;
      emit(
        DispenserListLoaded(
          dispensers: dispensers,
          refillSuccess: true,
        ),
      );
    } on RefillLimitException {
      final dispensers = await repository.getLocalDispensers();
      if (isClosed) return;
      emit(
        DispenserListLoaded(
          dispensers: dispensers,
          refillLimitExceeded: true,
        ),
      );
    } catch (_) {
      // El reabastecimiento solo muestra límite o éxito (RF-13). Cualquier
      // fallo inesperado se resuelve en silencio y se reintenta al refrescar.
      final dispensers = await repository.getLocalDispensers();
      if (isClosed) return;
      emit(DispenserListLoaded(dispensers: dispensers));
      add(RefreshDispensersEvent());
    }
  }

  Future<void> _onDiscountFood(
    DiscountFoodEvent event,
    Emitter<DispenserState> emit,
  ) async {
    try {
      await repository.discountFood(event.dispenserId, event.dispensedGrams);
      add(LoadDispensersEvent());
    } catch (e) {
      emit(
        DispenserErrorState(
          message: e.toString().replaceAll('Exception: ', ''),
        ),
      );
      add(LoadDispensersEvent());
    }
  }

  @override
  Future<void> close() {
    _scanSubscription?.cancel();
    return super.close();
  }
}

/// Fallo para el caso en que la operación responde sin resultado, que solo
/// debería ocurrir ante una inconsistencia interna del caso de uso. Viaja sin
/// mensaje porque el copy del aviso lo decide la presentación
/// (`dispenser_notice_mapper`) y el BLoC no contiene textos (RNF-01).
DispenserFailure _falloOperacionNoCompletada() =>
    DispenserFailure(ServerFailures(''));
