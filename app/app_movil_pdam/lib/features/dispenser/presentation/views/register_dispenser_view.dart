import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/dispenser_bloc.dart';
import '../widgets/register_dispenser_form_widget.dart';

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
    _macController.dispose();
    super.dispose();
  }

  void _scanQrCode() async {
    if (!mounted) return;

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
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: RegisterDispenserFormWidget(
              macController: _macController,
              onScanQr: _scanQrCode,
              onSubmit: _vincularDispositivo,
            ),
          ),
        ),
      ),
    );
  }
}
