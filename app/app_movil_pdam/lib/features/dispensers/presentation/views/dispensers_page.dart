import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_bloc.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_event.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_state.dart';

class DispensersPage extends StatelessWidget {
  const DispensersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispensadores'),
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
      body: BlocConsumer<DispensersBloc, DispensersState>(
        listener: (context, state) {
          if (state is DispensersErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          if (state is DispensersLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DispensersLoaded) {
            if (state.dispensers.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.router_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'No hay dispensadores registrados',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('Pulsa el botón de búsqueda para configurar uno por Bluetooth.'),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        context.go('/dispensers/scan');
                      },
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Buscar Dispensador'),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: state.dispensers.length,
              itemBuilder: (context, index) {
                final dispenser = state.dispensers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.router,
                      color: dispenser.isConnected ? Colors.green : Colors.grey,
                    ),
                    title: Text(dispenser.name),
                    subtitle: Text('MAC: ${dispenser.macAddress}\nWiFi: ${dispenser.wifiSsid ?? "No configurado"}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Reconfigurar WiFi',
                      onPressed: () {
                        context.go('/dispensers/scan');
                      },
                    ),
                  ),
                );
              },
            );
          }
          return Center(
            child: ElevatedButton(
              onPressed: () {
                context.read<DispensersBloc>().add(LoadDispensersEvent());
              },
              child: const Text('Cargar Dispensadores'),
            ),
          );
        },
      ),
    );
  }
}
