import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/ble_permission_result.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/provisioning_stage_messages.dart';

/// Pantalla de búsqueda de dispensadores (spec 018).
///
/// Cada estado del ciclo tiene su propia vista: apertura, ventana con o sin
/// dispositivos, resultados conservados, final, aviso y detenido. La vista no
/// guarda timers: todo el ciclo vive en el BLoC (RNF-06).
class BleScanPage extends StatefulWidget {
  const BleScanPage({super.key, this.openSettings});

  /// Abre los ajustes del sistema. Inyectable en pruebas (RF-14); por defecto
  /// usa los ajustes de la aplicación con una espera acotada a 3 s.
  final Future<void> Function()? openSettings;

  @override
  State<BleScanPage> createState() => _BleScanPageState();
}

class _BleScanPageState extends State<BleScanPage> with WidgetsBindingObserver {
  late DispenserBloc _dispensersBloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dispensersBloc = context.read<DispenserBloc>();
  }

  @override
  void initState() {
    super.initState();
    // RF-13: la pantalla reenvía el ciclo de vida al BLoC mientras está
    // montada; al salir se retira el observer.
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dispensersBloc.add(StartScanBleEvent());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _dispensersBloc.add(AppLifecycleChangedBleEvent(state));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dispensersBloc.add(StopScanBleEvent());
    // 010 RF-05: al volver de la pantalla de escaneo se restaura la lista. El
    // BLoC procesa el stop antes que esta carga (RF-08, RF-24).
    _dispensersBloc.add(LoadDispensersEvent());
    super.dispose();
  }

  void _cancel() {
    _dispensersBloc.add(StopScanBleEvent());
    if (context.canPop()) context.pop();
  }

  void _startSearch() {
    _dispensersBloc.add(StartScanBleEvent());
  }

  void _connect(ScannedDevice device) {
    _dispensersBloc.add(StopScanBleEvent());
    context.go('/dispensers/provision', extra: device);
  }

  /// RF-14: abre los ajustes sin bloquear el aviso; la espera se acota a 3 s.
  Future<void> _openSettings() async {
    final open = widget.openSettings ?? _openSystemSettings;
    try {
      await open().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Un fallo o un plazo vencido no bloquea el aviso ni la reanudación.
    }
  }

  Future<void> _openSystemSettings() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar Dispensador (BLE)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _startSearch,
          ),
        ],
      ),
      body: BlocBuilder<DispenserBloc, DispenserState>(
        builder: (context, state) => _body(state),
      ),
    );
  }

  Widget _body(DispenserState state) {
    if (state is BleScanNoticeState) {
      return _ScanNoticeView(
        cause: state.cause,
        onOpenSettings: _openSettings,
        onRetry: _startSearch,
        onCancel: _cancel,
      );
    }
    if (state is BleScanOpeningState) {
      return _ScanMessageView(
        message: 'Preparando la búsqueda de dispensadores...',
        onCancel: _cancel,
      );
    }
    if (state is BleScanningState) {
      if (state.scannedDevices.isEmpty) {
        return _ScanMessageView(
          message: 'Buscando dispensadores cercanos...',
          hint: 'Asegúrate de que el dispositivo esté encendido y en modo de '
              'configuración.',
          showProgress: true,
          onCancel: _cancel,
        );
      }
      // RF-06: con la ventana abierta no se ofrece reiniciar la búsqueda.
      return _ScanDeviceList(
        devices: state.scannedDevices,
        searchingMore: true,
        onConnect: _connect,
        onCancel: _cancel,
      );
    }
    if (state is BleScanResultsState) {
      return _ScanDeviceList(
        devices: state.scannedDevices,
        searchingMore: false,
        onConnect: _connect,
        onSearchAgain: _startSearch,
        onCancel: _cancel,
      );
    }
    if (state is BleScanFinishedState) {
      return _ScanMessageView(
        message: 'No se encontraron dispensadores en modo de configuración',
        hint: 'Comprueba que esté encendido y en modo de configuración.',
        onSearchAgain: _startSearch,
        onCancel: _cancel,
      );
    }
    if (state is DispenserErrorState) {
      // RNF-01: el fallo legado se muestra como el aviso tipado de escaneo,
      // nunca con el texto de la excepción.
      return _ScanNoticeView(
        cause: BleScanNoticeCause.scanFailed,
        onOpenSettings: _openSettings,
        onRetry: _startSearch,
        onCancel: _cancel,
      );
    }
    return _ScanMessageView(
      message: 'Busca dispensadores PDAM en modo de configuración.',
      searchAgainLabel: 'Iniciar Escaneo BLE',
      onSearchAgain: _startSearch,
      onCancel: _cancel,
    );
  }
}

/// Apertura, ventana sin dispositivos y estado final: copy y acciones sin
/// progreso salvo cuando la ventana está abierta y vacía (RF-01, RF-23).
class _ScanMessageView extends StatelessWidget {
  const _ScanMessageView({
    required this.message,
    this.hint,
    this.showProgress = false,
    this.searchAgainLabel = 'Volver a buscar',
    this.onSearchAgain,
    this.onCancel,
  });

  final String message;
  final String? hint;
  final bool showProgress;
  final String searchAgainLabel;
  final VoidCallback? onSearchAgain;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.xxl),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(color: esquema.onSurfaceVariant),
              ),
            ],
            if (onSearchAgain != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onSearchAgain,
                  child: Text(searchAgainLabel),
                ),
              ),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancelar Escaneo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lista de dispositivos del ciclo actual (RF-04).
class _ScanDeviceList extends StatelessWidget {
  const _ScanDeviceList({
    required this.devices,
    required this.searchingMore,
    required this.onConnect,
    required this.onCancel,
    this.onSearchAgain,
  });

  final List<ScannedDevice> devices;
  final bool searchingMore;
  final ValueChanged<ScannedDevice> onConnect;
  final VoidCallback? onSearchAgain;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (searchingMore)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 18),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('Buscando más dispensadores...')),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(device.name),
                subtitle: Text(
                  'ID / MAC: ${device.remoteId} (RSSI: ${device.rssi})',
                ),
                trailing: OutlinedButton(
                  onPressed: () => onConnect(device),
                  child: const Text('Conectar'),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              if (onSearchAgain != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onSearchAgain,
                    child: const Text('Volver a buscar'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancelar Escaneo'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aviso de adaptador, permisos o ubicación en la zona de la lista (RF-11,
/// RF-17, RF-25). No es un modal y no bloquea la navegación.
class _ScanNoticeView extends StatelessWidget {
  const _ScanNoticeView({
    required this.cause,
    required this.onOpenSettings,
    required this.onRetry,
    required this.onCancel,
  });

  final BleScanNoticeCause cause;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: esquema.error),
            const SizedBox(height: AppSpacing.lg),
            Text(
              noticeMessage(cause),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  unawaited(onOpenSettings());
                },
                child: Text(noticeSettingsLabel(cause)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Cancelar Escaneo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta de la acción de ajustes (RF-17, RF-18).
///
/// Sin una dependencia adicional no hay API directa a los ajustes de ubicación:
/// `permission_handler.openAppSettings` abre los ajustes de la aplicación, así
/// que la etiqueta de ubicación lo indica y se justifica esa aproximación.
String noticeSettingsLabel(BleScanNoticeCause cause) =>
    cause == BleScanNoticeCause.locationDisabled
    ? 'Abrir ajustes de ubicación'
    : 'Abrir ajustes';

/// Copy en español de cada aviso (RNF-04). Los permisos y la ubicación usan el
/// mismo catálogo que el aprovisionamiento para no duplicar textos.
///
/// `scanFailed` no está definido en la spec: se propone un mensaje accionable
/// que no expone la excepción (RNF-01).
String noticeMessage(BleScanNoticeCause cause) {
  switch (cause) {
    case BleScanNoticeCause.adapterOff:
      return 'El Bluetooth está desactivado';
    case BleScanNoticeCause.adapterUnavailable:
      return 'El Bluetooth no está disponible en este teléfono';
    case BleScanNoticeCause.adapterUnauthorized:
      return bluetoothAuthorizationSettingsMessage;
    case BleScanNoticeCause.permissionDenied:
      return provisioningPermissionMessage(const BlePermissionResult.denied());
    case BleScanNoticeCause.permissionPermanentlyDenied:
      return provisioningPermissionMessage(
        const BlePermissionResult.permanentlyDenied(),
      );
    case BleScanNoticeCause.locationDisabled:
      return provisioningPermissionMessage(
        const BlePermissionResult.granted(
          locationRequired: true,
          locationEnabled: false,
        ),
      );
    case BleScanNoticeCause.scanFailed:
      return 'No se pudo iniciar la búsqueda de dispensadores. '
          'Revisa el Bluetooth e inténtalo de nuevo.';
  }
}
