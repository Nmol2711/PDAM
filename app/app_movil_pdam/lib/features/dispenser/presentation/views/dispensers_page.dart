import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/device_card_widget.dart';

class DispensersPage extends StatelessWidget {
  const DispensersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos'),
        actions: [
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
        listener: (context, state) {
          if (state is DispenserErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          if (state is DispenserListLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DispenserListLoaded) {
            if (state.dispensers.isEmpty) {
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 600;
                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 48.0 : 24.0,
                        vertical: 24.0,
                      ),
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
                  );
                },
              );
            }
            return ListView.builder(
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
            );
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
