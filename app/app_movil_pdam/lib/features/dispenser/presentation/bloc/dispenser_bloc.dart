import 'dart:async';

import 'package:app_movil_pdam/core/error/failures.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_adapter_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_scan_event.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser_food_status.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/provisioning_stage.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/domain/repository/dispenser_repositories.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/activate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/associate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/dasactivate_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/delete_dispenser_uc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/use_case/get_dispenser_by_pet_uc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
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
  StreamSubscription<BleScanEvent>? _scanSubscription;
  StreamSubscription<BleAdapterStatus>? _adapterStatusSubscription;
  int _scanCycleId = 0;
  int? _activeScanCycleId;
  int _emptyScanWindows = 0;
  List<ScannedDevice> _lastScannedDevices = const <ScannedDevice>[];

  /// Fase interna del ciclo (RF-06, RF-08).
  ///
  /// La deduplicación y la idempotencia se apoyan en esta fase y no en el
  /// estado público: un handler concurrente puede llegar antes de que el
  /// estado se emita y no debe reabrir ni volver a detener un ciclo.
  _ScanPhase _scanPhase = _ScanPhase.idle;

  /// La pantalla de escaneo está abierta; sin ella no se muestran avisos del
  /// adaptador ni se reabre el ciclo (RF-11, RF-13).
  bool _scanScreenVisible = false;

  /// Liberación del ciclo pendiente; un inicio la espera (RF-09).
  Future<void>? _pendingStop;

  /// Indica si la apertura vigente la pidió la renovación automática (RF-06).
  bool _openingIsAutomatic = false;

  /// Último ciclo de vida recibido; antes del primero se asume primer plano
  /// para no bloquear la apertura inicial (RF-13).
  AppLifecycleState _lastLifecycle = AppLifecycleState.resumed;

  /// Último estado del adaptador recibido; `resumed` lo usa para reabrir el
  /// ciclo de un aviso si el Bluetooth ya está encendido (RF-12).
  BleAdapterStatus _lastAdapterStatus = BleAdapterStatus.unknown;

  /// Aprovisionamiento en curso: los eventos de escaneo no deben pisarlo
  /// (RF-22).
  bool _provisioningInProgress = false;

  /// Ventanas consecutivas sin resultados antes del estado final (RF-02, RF-03).
  static const int _maxEmptyScanWindows = 3;

  /// Cota de espera de la liberación del ciclo anterior (RF-09).
  static const Duration _pendingStopLimit = Duration(seconds: 5);

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

    on<LoadDispensersEvent>(_onLoadDispensersRequest);
    on<RefreshDispensersEvent>(_onRefreshDispensers);
    on<StartScanBleEvent>(_onStartScanRequest);
    on<StopScanBleEvent>(_onStopScanRequest);
    on<AppLifecycleChangedBleEvent>(_onAppLifecycleRequest);
    on<ConnectAndProvisionEvent>(_onConnectAndProvision);
    on<ResetWifiEvent>(_onResetWifi);
    on<RefillFoodEvent>(_onRefillFood);
    on<DiscountFoodEvent>(_onDiscountFood);
    on<_ScanCommandEvent>(
      _onScanCommand,
      transformer: _sequentialScanEvents(),
    );
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

  /// La carga de la lista pasa por la cola para respetar una detención
  /// encolada antes (RF-08, RF-24).
  void _onLoadDispensersRequest(
    LoadDispensersEvent event,
    Emitter<DispenserState> emit,
  ) {
    add(const _LoadDispensersCommand());
  }

  Future<void> _loadDispensers(Emitter<DispenserState> emit) async {
    if (!_puedeEmitirLista()) return;
    emit(DispenserListLoading());

    final List<Dispenser> dispensers;
    try {
      dispensers = await repository.getLocalDispensers();
    } catch (e) {
      if (isClosed || !_puedeEmitirLista()) return;
      emit(
        DispenserErrorState(
          message: 'Error al cargar los dispositivos: ${e.toString()}',
        ),
      );
      _markListRestored();
      return;
    }

    if (isClosed || !_puedeEmitirLista()) return;
    emit(DispenserListLoaded(dispensers: dispensers));
    _markListRestored();
  }

  /// Refresco silencioso (RF-4, RF-10): actualiza el stock desde el servidor y
  /// vuelve a emitir la lista sin pasar por [DispenserListLoading], solo si la
  /// precedencia lo permite (RF-24).
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

    if (isClosed || !_puedeEmitirLista()) return;
    emit(DispenserListLoaded(dispensers: dispensers));
    _markListRestored();
  }

  /// Tabla única de precedencia de la pantalla (RF-24):
  /// aprovisionamiento > aviso de adaptador/permisos > estados del ciclo >
  /// lista.
  ///
  /// Se apoya en la fase interna ([_ScanPhase]) y no en el estado público, para
  /// que un handler concurrente no pueda adelantarse a la emisión. La única
  /// cesión es el ciclo detenido, transitorio: la lista puede sustituirlo y,
  /// al hacerlo, el ciclo deja de estar vigente.
  bool _puedeEmitirLista() {
    if (_provisioningInProgress) return false;

    switch (_scanPhase) {
      case _ScanPhase.opening:
      case _ScanPhase.scanning:
      case _ScanPhase.retained:
      case _ScanPhase.betweenWindows:
      case _ScanPhase.finished:
      case _ScanPhase.notice:
        return false;
      case _ScanPhase.stopped:
        return true;
      case _ScanPhase.idle:
        return _isListState(state);
    }
  }

  /// Estados en los que una lista de dispensadores puede mostrarse sin pisar
  /// otra pantalla (detalle de mascota, QR, etc.).
  bool _isListState(DispenserState current) {
    return current is DispenserInitial ||
        current is DispenserListLoading ||
        current is DispenserListLoaded ||
        current is DispenserEmpty ||
        current is DispenserErrorState ||
        current is ProvisioningSuccessState ||
        current is ProvisioningFailureState;
  }

  /// Cierra la cesión del estado detenido en cuanto la lista se emite.
  void _markListRestored() {
    if (_scanPhase == _ScanPhase.stopped) _scanPhase = _ScanPhase.idle;
  }

  /// Transformer secuencial propio del módulo.
  ///
  /// Bloc 9 ejecuta los handlers en paralelo por defecto y no hay
  /// `bloc_concurrency` en el proyecto (RNF-07). `asyncExpand` espera a que el
  /// handler anterior termine antes de iniciar el siguiente, de modo que la
  /// cola de comandos del ciclo no se solapa (RF-06, RF-09, RF-23).
  EventTransformer<E> _sequentialScanEvents<E>() {
    return (events, mapper) => events.asyncExpand(mapper);
  }

  /// Convierte el evento público en el comando que abre el ciclo (RF-23).
  void _onStartScanRequest(
    StartScanBleEvent event,
    Emitter<DispenserState> emit,
  ) {
    // La pantalla está abierta: desde aquí se vigilan adaptador y avisos
    // (RF-11, RF-12). RF-14: nunca se enciende el adaptador.
    _scanScreenVisible = true;
    _listenToAdapterStatus();
    add(const _StartScanCommand());
  }

  /// Convierte el evento público en el comando que detiene el ciclo (RF-08).
  void _onStopScanRequest(
    StopScanBleEvent event,
    Emitter<DispenserState> emit,
  ) {
    _scanScreenVisible = false;
    _stopListeningToAdapterStatus();
    add(const _StopScanCommand());
  }

  /// Reenvía el ciclo de vida de la app al ciclo de escaneo (RF-13).
  void _onAppLifecycleRequest(
    AppLifecycleChangedBleEvent event,
    Emitter<DispenserState> emit,
  ) {
    add(_LifecycleCommand(event.lifecycle));
  }

  /// Vigila el adaptador solo mientras la pantalla de escaneo está abierta
  /// (RNF-06): al cerrarla no queda ninguna suscripción.
  void _listenToAdapterStatus() {
    if (_adapterStatusSubscription != null) return;
    _adapterStatusSubscription = repository.adapterStatus.listen(
      (status) {
        if (isClosed) return;
        add(_AdapterStatusCommand(status));
      },
    );
  }

  void _stopListeningToAdapterStatus() {
    final subscription = _adapterStatusSubscription;
    _adapterStatusSubscription = null;
    unawaited(subscription?.cancel());
  }

  Future<void> _onScanCommand(
    _ScanCommandEvent command,
    Emitter<DispenserState> emit,
  ) async {
    switch (command) {
      case _StartScanCommand():
        await _startScan(emit);
      case _StopScanCommand():
        _stopScan(emit);
      case _ScanDevicesCommand(:final cycleId, :final devices):
        _applyDevices(cycleId, devices, emit);
      case _ScanWindowClosedCommand(:final cycleId, :final hasDevices):
        _applyWindowClosed(cycleId, hasDevices, emit);
      case _ScanFailedCommand(:final cycleId, :final failure):
        _applyScanFailed(cycleId, failure, emit);
      case _RenewScanCommand():
        await _renewScan(emit);
      case _LoadDispensersCommand():
        await _loadDispensers(emit);
      case _LifecycleCommand(:final lifecycle):
        await _applyLifecycle(lifecycle, emit);
      case _AdapterStatusCommand(:final status):
        await _applyAdapterStatus(status, emit);
    }
  }

  /// Abre un ciclo con identidad propia. La apertura no cuenta como ventana:
  /// el contador solo avanza con un cierre sin dispositivos (RF-01, RF-03).
  Future<void> _openScanCycle(
    Emitter<DispenserState> emit, {
    required bool automatic,
  }) async {
    _openingIsAutomatic = automatic;
    _scanPhase = _ScanPhase.opening;
    emit(const BleScanOpeningState());
    _lastScannedDevices = const <ScannedDevice>[];

    // RF-09: un inicio no solapa el cierre pendiente del ciclo anterior; la
    // espera se acota para que una liberación atascada no bloquee la cola.
    final pendingStop = _pendingStop;
    if (pendingStop != null) {
      try {
        await pendingStop.timeout(_pendingStopLimit);
      } on TimeoutException {
        // El servicio sigue liberando en segundo plano; la identidad del ciclo
        // impide que un cierre tardío detenga el ciclo nuevo (RF-07).
      }
    }
    _cancelScanSubscription();

    final cycleId = ++_scanCycleId;
    _activeScanCycleId = cycleId;
    // La ventana (15 s por defecto) la resuelve el servicio; la presentación
    // no conoce duraciones ni importa data/services (Constitución art. 3).
    _scanSubscription = repository
        .scanBleDispensers(cycleId: cycleId)
        .listen(
          _onBleScanEvent,
          onError: (_) {
            if (!isClosed) add(const _ScanErrorEvent());
          },
        );
  }

  void _cancelScanSubscription() {
    final subscription = _scanSubscription;
    _scanSubscription = null;
    if (subscription == null) return;
    // La cancelación no se espera: el cierre del flujo del servicio no debe
    // retrasar el aviso ni el siguiente ciclo (RF-05, RF-08, RF-09). Los
    // eventos tardíos quedan descartados por el identificador del ciclo.
    unawaited(subscription.cancel());
  }

  void _onBleScanEvent(BleScanEvent event) {
    if (isClosed) return;
    switch (event) {
      case BleScanDevices(:final cycleId, :final devices):
        add(_ScanDevicesCommand(cycleId, devices));
      case BleScanWindowClosed(:final cycleId, :final hasDevices):
        add(_ScanWindowClosedCommand(cycleId, hasDevices));
      case BleScanFailed(:final cycleId, :final failure):
        add(_ScanFailedCommand(cycleId, failure));
    }
  }

  Future<void> _startScan(Emitter<DispenserState> emit) async {
    // RF-22: durante el aprovisionamiento no se abren ciclos.
    if (_provisioningInProgress) return;
    // RF-06: una ventana abierta absorbe el inicio repetido.
    if (_scanPhase == _ScanPhase.scanning) return;
    // RF-06: repetir una apertura pedida por el usuario también se descarta.
    if (_scanPhase == _ScanPhase.opening && !_openingIsAutomatic) return;

    // La búsqueda manual cancela la apertura automática y reinicia el contador
    // de ventanas (RF-03, RF-06).
    _emptyScanWindows = 0;
    await _openScanCycle(emit, automatic: false);
  }

  void _stopScan(Emitter<DispenserState> emit) {
    // RF-22/RF-24: el aprovisionamiento tiene precedencia; un stop no debe
    // pisar su estado.
    if (_provisioningInProgress) return;
    // RF-08: una sola detención, sin error ni liberación repetida.
    if (_scanPhase == _ScanPhase.stopped) return;

    // RF-24: el estado detenido no sustituye un aviso vigente. Al salir de la
    // pantalla el aviso deja de estar vigente y la lista encolada detrás del
    // stop puede restaurarse sin emitir el estado detenido.
    //
    // Tensión RF-08/RF-24 frente a 010 RF-05: se prioriza no pisar el aviso.
    // El stop de la página llega junto a la carga de la lista; la cesión
    // interna (fase stopped) permite restaurar la lista sin pasar por
    // "escaneo detenido".
    if (_scanPhase == _ScanPhase.notice) {
      _activeScanCycleId = null;
      _emptyScanWindows = 0;
      _openingIsAutomatic = false;
      _lastScannedDevices = const <ScannedDevice>[];
      _scanPhase = _ScanPhase.stopped;
      return;
    }

    final cycleId = _activeScanCycleId;
    _activeScanCycleId = null;
    _emptyScanWindows = 0;
    _openingIsAutomatic = false;
    _lastScannedDevices = const <ScannedDevice>[];
    _scanPhase = _ScanPhase.stopped;

    // El estado sin progreso sale en el acto (RF-05); la liberación del ciclo
    // queda pendiente y la espera el siguiente inicio (RF-09).
    if (cycleId != null) _scheduleRelease(cycleId);
    emit(const BleScanStoppedState());
  }

  /// Libera el ciclo sin bloquear la emisión del estado (RF-05, RF-09).
  void _scheduleRelease(int cycleId) {
    final release = _releaseScanCycle(cycleId);
    _pendingStop = release;
    unawaited(
      release.whenComplete(() {
        if (identical(_pendingStop, release)) _pendingStop = null;
      }),
    );
  }

  Future<void> _releaseScanCycle(int? cycleId) async {
    _cancelScanSubscription();
    if (cycleId == null) return;
    try {
      await repository.stopBleScan(cycleId: cycleId);
    } catch (_) {
      // La detención es idempotente; un fallo del adaptador no deja el ciclo
      // bloqueado para el siguiente inicio.
    }
  }

  void _applyDevices(
    int cycleId,
    List<ScannedDevice> devices,
    Emitter<DispenserState> emit,
  ) {
    // RF-22: los resultados del escaneo no pisan el aprovisionamiento.
    if (_provisioningInProgress) return;
    if (cycleId != _activeScanCycleId) return;
    _scanPhase = _ScanPhase.scanning;

    // RF-10: la lista interna conserva el último RSSI conocido aunque no se
    // emita un estado nuevo por tener los mismos identificadores y orden.
    final unchanged = _sameScanIdentity(_lastScannedDevices, devices);
    _lastScannedDevices = devices;
    if (devices.isNotEmpty) _emptyScanWindows = 0;
    if (unchanged && state is BleScanningState) return;

    emit(BleScanningState(scannedDevices: devices));
  }

  /// Igualdad por identificadores y orden, con independencia de la señal.
  bool _sameScanIdentity(List<ScannedDevice> current, List<ScannedDevice> next) {
    if (identical(current, next)) return true;
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (current[index].remoteId != next[index].remoteId) return false;
    }
    return true;
  }

  void _applyWindowClosed(
    int cycleId,
    bool hasDevices,
    Emitter<DispenserState> emit,
  ) {
    // RF-22: un cierre no renueva ni cambia el estado mientras se aprovisiona.
    if (_provisioningInProgress) return;
    if (cycleId != _activeScanCycleId) return;
    _activeScanCycleId = null;

    if (hasDevices) {
      // RF-04: se conservan los resultados, sin renovar ni dejar temporizadores.
      _scanPhase = _ScanPhase.retained;
      _emptyScanWindows = 0;
      emit(BleScanResultsState(scannedDevices: _lastScannedDevices));
      return;
    }

    _emptyScanWindows++;
    if (_emptyScanWindows >= _maxEmptyScanWindows) {
      // RF-02: tercera ventana consecutiva sin resultados.
      _scanPhase = _ScanPhase.finished;
      emit(const BleScanFinishedState());
      return;
    }

    // Entre ventanas: la renovación queda encolada y un inicio manual puede
    // adelantarse sin abrir dos ciclos (RF-06).
    _scanPhase = _ScanPhase.betweenWindows;
    add(const _RenewScanCommand());
  }

  Future<void> _renewScan(Emitter<DispenserState> emit) async {
    // RF-22: sin renovación mientras se aprovisiona.
    if (_provisioningInProgress) return;
    // Una detención o un aviso encolado ya cerró el ciclo (RF-08, RF-11).
    if (_scanPhase == _ScanPhase.stopped || _scanPhase == _ScanPhase.notice) {
      return;
    }
    // Una búsqueda manual pudo abrir un ciclo mientras la renovación esperaba.
    if (_activeScanCycleId != null) return;
    if (_emptyScanWindows >= _maxEmptyScanWindows) {
      _scanPhase = _ScanPhase.finished;
      emit(const BleScanFinishedState());
      return;
    }
    await _openScanCycle(emit, automatic: true);
  }

  void _applyScanFailed(
    int cycleId,
    BleScanFailure failure,
    Emitter<DispenserState> emit,
  ) {
    // RF-22: los errores de escaneo no pisan el aprovisionamiento.
    if (_provisioningInProgress) return;
    if (cycleId != _activeScanCycleId) return;

    // La causa tipada viaja al estado de aviso; el copy lo decide la vista
    // (RF-11, RF-17, RF-18, RF-25 y RNF-01).
    _showNotice(BleScanNoticeCause.fromScanFailure(failure), emit);
  }

  /// Aviso sin ciclo, sin progreso y sin lista previa (RF-11, RF-25).
  ///
  /// Cierra y libera el ciclo vigente sin esperar la liberación: el aviso sale
  /// en el acto y el siguiente inicio espera a que termine (RF-09, RNF-06).
  void _showNotice(BleScanNoticeCause cause, Emitter<DispenserState> emit) {
    final current = state;
    if (current is BleScanNoticeState &&
        !canReplaceScanNotice(current.cause, cause)) {
      // RF-24: el aviso de adaptador prevalece. Si quedó un ciclo activo detrás
      // del aviso (fallo de apertura tardío), se libera sin cambiar el estado.
      _discardActiveCycle();
      return;
    }

    _discardActiveCycle();
    _scanPhase = _ScanPhase.notice;
    emit(BleScanNoticeState(cause));
  }

  /// Cierra el ciclo vigente sin emitir estado (RF-06, RNF-06).
  void _discardActiveCycle() {
    final cycleId = _activeScanCycleId;
    _activeScanCycleId = null;
    _emptyScanWindows = 0;
    _openingIsAutomatic = false;
    _lastScannedDevices = const <ScannedDevice>[];
    if (cycleId != null) _scheduleRelease(cycleId);
  }

  /// Reacción al estado del adaptador (RF-11, RF-12, RF-25).
  ///
  /// `turningOn`/`turningOff` son transitorios y no producen ni retiran el
  /// aviso; `on` solo sustituye un aviso vigente por un ciclo nuevo. Nunca se
  /// pide ni se intenta encender el adaptador (RF-14).
  Future<void> _applyAdapterStatus(
    BleAdapterStatus status,
    Emitter<DispenserState> emit,
  ) async {
    _lastAdapterStatus = status;
    if (_provisioningInProgress) return;
    if (!_scanScreenVisible) return;

    switch (status) {
      case BleAdapterStatus.off:
        _showNotice(BleScanNoticeCause.adapterOff, emit);
      case BleAdapterStatus.unavailable:
        _showNotice(BleScanNoticeCause.adapterUnavailable, emit);
      case BleAdapterStatus.unauthorized:
        _showNotice(BleScanNoticeCause.adapterUnauthorized, emit);
      case BleAdapterStatus.on:
        // RF-12: reemplaza el aviso por un ciclo nuevo con lista vacía y
        // contador a cero, sin pulsar «Reintentar».
        if (_scanPhase != _ScanPhase.notice) return;
        // RF-13: no se abre una ventana en segundo plano; al volver a
        // `resumed` se reabre si el adaptador sigue encendido.
        if (_lastLifecycle != AppLifecycleState.resumed) return;
        _emptyScanWindows = 0;
        await _openScanCycle(emit, automatic: false);
      case BleAdapterStatus.turningOn:
      case BleAdapterStatus.turningOff:
      case BleAdapterStatus.unknown:
        return;
    }
  }

  /// Ciclo de vida de la app (RF-13).
  ///
  /// `paused`/`hidden`/`detached` cierran el ciclo; `inactive` es transitorio y
  /// no lo cierra; `resumed` reabre lo que cerró el segundo plano salvo que
  /// haya un aviso vigente.
  Future<void> _applyLifecycle(
    AppLifecycleState lifecycle,
    Emitter<DispenserState> emit,
  ) async {
    _lastLifecycle = lifecycle;
    // RF-22: el ciclo de vida no reabre ni cierra ciclos al aprovisionar.
    if (_provisioningInProgress) return;
    switch (lifecycle) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_scanPhase != _ScanPhase.opening &&
            _scanPhase != _ScanPhase.scanning &&
            _scanPhase != _ScanPhase.betweenWindows) {
          return;
        }
        _stopScan(emit);
      case AppLifecycleState.inactive:
        return;
      case AppLifecycleState.resumed:
        if (_scanPhase == _ScanPhase.stopped) {
          // RF-13: reabre lo que cerró el segundo plano.
          _emptyScanWindows = 0;
          await _openScanCycle(emit, automatic: false);
          return;
        }
        // RF-12: si el adaptador se encendió en segundo plano, al volver a
        // primer plano el aviso se sustituye por un ciclo con contador a cero.
        // RF-13/RF-17: los avisos de permisos o ubicación no abren ciclo al
        // reanudar; el diálogo del sistema se pide al escanear.
        final current = state;
        if (_scanPhase == _ScanPhase.notice &&
            current is BleScanNoticeState &&
            _lastAdapterStatus == BleAdapterStatus.on &&
            canReopenNoticeOnResume(current.cause)) {
          _emptyScanWindows = 0;
          await _openScanCycle(emit, automatic: false);
        }
    }
  }

  void _onScanError(
    _ScanErrorEvent event,
    Emitter<DispenserState> emit,
  ) {
    // RF-22: un error de escaneo no pisa el aprovisionamiento.
    if (_provisioningInProgress) return;
    // RNF-01: sin textos de excepción; el aviso tipado de escaneo es la salida.
    _showNotice(BleScanNoticeCause.scanFailed, emit);
  }

  /// Aprovisiona con estado terminal garantizado (RF-17, RF-19 a RF-21).
  ///
  /// El fallo viaja tipado ([ProvisioningFailureState]); la vista decide el
  /// copy y las acciones en T9 (RNF-01). El estado nunca se queda en progreso.
  Future<void> _onConnectAndProvision(
    ConnectAndProvisionEvent event,
    Emitter<DispenserState> emit,
  ) async {
    _provisioningInProgress = true;
    try {
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
      } on ProvisioningException catch (failure) {
        emit(ProvisioningFailureState(failure));
      } catch (_) {
        // Fallo no tipado (por ejemplo, al guardar en local): se cierra con
        // una causa del catálogo para no dejar la pantalla en progreso.
        emit(
          const ProvisioningFailureState(
            ProvisioningException(stage: ProvisioningStage.conexion),
          ),
        );
      }
    } finally {
      _provisioningInProgress = false;
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
      // RF-24: el resultado no pisa un estado de mayor precedencia; el stock
      // queda persistido y se ve al volver a la lista.
      if (isClosed || !_puedeEmitirLista()) return;
      emit(
        DispenserListLoaded(
          dispensers: dispensers,
          refillSuccess: true,
        ),
      );
      _markListRestored();
    } on RefillLimitException {
      final dispensers = await repository.getLocalDispensers();
      if (isClosed || !_puedeEmitirLista()) return;
      emit(
        DispenserListLoaded(
          dispensers: dispensers,
          refillLimitExceeded: true,
        ),
      );
      _markListRestored();
    } catch (_) {
      // El reabastecimiento solo muestra límite o éxito (RF-13). Cualquier
      // fallo inesperado se resuelve en silencio y se reintenta al refrescar.
      final dispensers = await repository.getLocalDispensers();
      if (isClosed || !_puedeEmitirLista()) return;
      emit(DispenserListLoaded(dispensers: dispensers));
      _markListRestored();
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
    _adapterStatusSubscription?.cancel();
    return super.close();
  }
}

/// Fases internas del ciclo de escaneo (RF-06, RF-08, RF-13).
///
/// Se usan para descartar inicios repetidos e idempotencia de la detención sin
/// depender del estado público, que puede no haberse emitido todavía cuando
/// llega un handler concurrente.
enum _ScanPhase {
  idle,
  opening,
  scanning,
  retained,
  betweenWindows,
  finished,
  stopped,
  notice,
}

/// Fallo para el caso en que la operación responde sin resultado, que solo
/// debería ocurrir ante una inconsistencia interna del caso de uso. Viaja sin
/// mensaje porque el copy del aviso lo decide la presentación
/// (`dispenser_notice_mapper`) y el BLoC no contiene textos (RNF-01).
DispenserFailure _falloOperacionNoCompletada() =>
    DispenserFailure(ServerFailures(''));
