import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/dispenser_bloc.dart';

class RegisterDispenserView extends StatefulWidget {
  final int petId;

  const RegisterDispenserView({super.key, required this.petId});

  @override
  State<RegisterDispenserView> createState() => _RegisterDispenserViewState();
}

class _RegisterDispenserViewState extends State<RegisterDispenserView> {
  final TextEditingController _macController = TextEditingController();
  String _currentSecretKey = '';

  @override
  void dispose() {
    _macController.dispose(); // Súper importante para evitar fugas de memoria
    super.dispose();
  }

  void _scanQrCode() async {
    if (!mounted) return;

    // Dejamos que GoRouter abra la pantalla directamente.
    // El paquete MobileScanner se encargará de disparar el diálogo nativo automáticamente.
    final Map<String, String?>? result = await context
        .pushNamed<Map<String, String?>>('qr_scanner');

    if (result != null && mounted) {
      final mac = result['mac_address'] ?? '';
      final key = result['secret_key_qr'] ?? '';

      context.read<DispenserBloc>().add(
        QrCodeDetectedEvent(macAddress: mac, secretKeyQr: key),
      );
    }
  }

  void _vincularDispositivo() {
    if (_macController.text.isEmpty || _currentSecretKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, escanea el código QR primero.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    context.read<DispenserBloc>().add(
      AssociateDispenserEvent(
        macAddress: _macController.text,
        petId: widget.petId,
        secretKeyQr: _currentSecretKey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular Dispensador')),
      body: MultiBlocListener(
        listeners: [
          BlocListener<DispenserBloc, DispenserState>(
            listener: (context, state) {
              if (state is DispenserSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Dispensador asociado correctamente'),
                    backgroundColor: Colors.green,
                  ),
                );
                context.pop();
              } else if (state is DispenserFailure) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
          BlocListener<DispenserBloc, DispenserState>(
            listenWhen: (previous, current) => current is DispenserQrScanned,
            listener: (context, state) {
              if (state is DispenserQrScanned) {
                _macController.text = state.macAddress;
                _currentSecretKey = state.secretKeyQr;
              }
            },
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Asocia un dispositivo PDAM escaneando su código QR.',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _macController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Dirección MAC del Dispositivo',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.blue),
                    onPressed: _scanQrCode,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              BlocBuilder<DispenserBloc, DispenserState>(
                builder: (context, state) {
                  final isLoading = state is DispenserLoading;

                  return ElevatedButton(
                    onPressed: isLoading ? null : _vincularDispositivo,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Vincular Dispositivo',
                            style: TextStyle(fontSize: 16),
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
