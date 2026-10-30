import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_movil_pdam/core/presentation/utils/settings_entry_visibility.dart';
import 'package:app_movil_pdam/core/presentation/widgets/settings_entry_button.dart';
import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser_food_status.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/device_card_widget.dart';

class DispensersPage extends StatefulWidget {
  /// Intervalo del sondeo automático. `null` lo desactiva (pruebas de widget);
  /// la aplicación usa el valor por defecto de 5 segundos (RNF-1).
  final Duration? refreshInterval;

  const DispensersPage({
    super.key,
    this.refreshInterval = const Duration(seconds: 5),
  });

  @override
  State<DispensersPage> createState() => _DispensersPageState();
}

class _DispensersPageState extends State<DispensersPage>
    with WidgetsBindingObserver {
  static const Duration _minimumRefreshGap = Duration(seconds: 4);

  Timer? _refreshTimer;
  bool _isForeground = true;
  DateTime? _lastRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final interval = widget.refreshInterval;
    if (interval != null) {
      _refreshTimer = Timer.periodic(interval, (_) => _refreshIfVisible());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      _refreshIfVisible();
    }
  }

  /// Refresca solo si la pantalla está montada, en primer plano y es la ruta
  /// actual (un diálogo o el escaneo BLE la dejan en segundo plano visual).
  void _refreshIfVisible() {
    if (!mounted || !_isForeground) return;
    // En un StatefulShellRoute.indexedStack la pestaña oculta sigue montada;
    // TickerMode.enabled refleja si su rama está activa.
    if (!TickerMode.of(context)) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _minimumRefreshGap) {
      return;
    }
    _lastRefreshAt = now;
    context.read<DispenserBloc>().add(RefreshDispensersEvent());
  }

  Future<void> _onPullToRefresh() async {
    context.read<DispenserBloc>().add(RefreshDispensersEvent());
    // El BLoC no reemite un estado idéntico, así que se espera un instante
    // para que el indicador muestre la consulta sin bloquear la interfaz.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  void _handleState(DispenserState state) {
    if (state is DispenserErrorState) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.message)),
      );
    } else if (state is DispenserListLoaded && state.refillLimitExceeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RefillLimitException.message)),
      );
    } else if (state is DispenserListLoaded && state.refillSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reabastecimiento con éxito')),
      );
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final minHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - 48).clamp(0.0, double.infinity).toDouble()
            : 0.0;
        return RefreshIndicator(
          onRefresh: _onPullToRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 48.0 : 24.0,
              vertical: 24.0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.router_rounded,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No hay dispositivos vinculados',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aún no se ha vinculado ningún dispositivo dispensador. Configura tu hardware mediante Bluetooth para comenzar a alimentar a tus mascotas automáticamente.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () {
                      context.go('/dispensers/scan');
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.bluetooth_searching_rounded),
                    label: const Text(
                      'Buscar y Configurar Dispositivo',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDispenserList(DispenserListLoaded state) {
    return RefreshIndicator(
      onRefresh: _onPullToRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.dispensers.length,
        itemBuilder: (context, index) {
          final dispenser = state.dispensers[index];
          return DeviceCardWidget(
            dispenser: dispenser,
            onResetWifi: () {
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Eliminar credenciales WiFi'),
                  content: Text(
                    '¿Deseas eliminar las credenciales WiFi del dispositivo "${dispenser.name}"?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        context.read<DispenserBloc>().add(
                              ResetWifiEvent(dispenserId: dispenser.deviceId),
                            );
                      },
                      child: const Text('Eliminar'),
                    ),
                  ],
                ),
              );
            },
            onTap: () {
              context.go('/dispensers/scan');
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos'),
        actions: [
          const SettingsEntryButton(
            ubicacion: UbicacionEntrada.cabeceraPantalla,
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_searching),
            tooltip: 'Buscar dispensadores BLE',
            onPressed: () {
              context.go('/dispensers/scan');
            },
          ),
        ],
      ),
      body: BlocConsumer<DispenserBloc, DispenserState>(
        listener: (context, state) => _handleState(state),
        builder: (context, state) {
          if (state is DispenserListLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DispenserListLoaded) {
            if (state.dispensers.isEmpty) {
              return _buildEmptyState(context);
            }
            return _buildDispenserList(state);
          }
          return Center(
            child: ElevatedButton(
              onPressed: () {
                context.read<DispenserBloc>().add(LoadDispensersEvent());
              },
              child: const Text('Cargar Dispensadores'),
            ),
          );
        },
      ),
    );
  }
}
