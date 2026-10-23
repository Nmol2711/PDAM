import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';

class BleScanPage extends StatefulWidget {
  const BleScanPage({super.key});

  @override
  State<BleScanPage> createState() => _BleScanPageState();
}

class _BleScanPageState extends State<BleScanPage> {
  late DispenserBloc _dispensersBloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dispensersBloc = context.read<DispenserBloc>();
  }

  @override
  void initState() {
    super.initState();
    // Use stored reference or context safely in initState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _dispensersBloc.add(StartScanBleEvent());
      }
    });
  }

  @override
  void dispose() {
    _dispensersBloc.add(StopScanBleEvent());
    // Al volver de la pantalla de escaneo el BLoC seguía en BleScanningState y
    // la lista caía en el botón "Cargar Dispensadores" (RF-9). Se restaura la
    // lista para que el usuario vea sus dispositivos al regresar.
    _dispensersBloc.add(LoadDispensersEvent());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar Dispensador (BLE)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<DispenserBloc>().add(StartScanBleEvent());
            },
          ),
        ],
      ),
      body: BlocBuilder<DispenserBloc, DispenserState>(
        builder: (context, state) {
          if (state is BleScanningState) {
            final devices = state.scannedDevices;
            return Column(
              children: [
                Expanded(
                  child: devices.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 24),
                                Text(
                                  'Buscando dispensadores cercanos (PDAM-Config-*)...',
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Asegúrate de que el dispositivo esté encendido y en modo de configuración.',
                                  style: TextStyle(color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: devices.length,
                          itemBuilder: (context, index) {
                            final device = devices[index];
                            return ListTile(
                              leading: const Icon(Icons.bluetooth),
                              title: Text(device.name),
                              subtitle: Text('ID / MAC: ${device.remoteId} (RSSI: ${device.rssi})'),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  context.read<DispenserBloc>().add(StopScanBleEvent());
                                  context.go('/dispensers/provision', extra: device);
                                },
                                child: const Text('Conectar'),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        context.read<DispenserBloc>().add(StopScanBleEvent());
                        context.pop();
                      },
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancelar Escaneo'),
                    ),
                  ),
                ),
              ],
            );
          }
          if (state is DispenserErrorState) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${state.message}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.read<DispenserBloc>().add(StartScanBleEvent());
                    },
                    child: const Text('Reintentar Escaneo'),
                  ),
                ],
              ),
            );
          }
          return Center(
            child: ElevatedButton(
              onPressed: () {
                context.read<DispenserBloc>().add(StartScanBleEvent());
              },
              child: const Text('Iniciar Escaneo BLE'),
            ),
          );
        },
      ),
    );
  }
}
