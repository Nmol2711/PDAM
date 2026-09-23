import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/dispenser_bloc.dart';

class RegisterDispenserFormWidget extends StatelessWidget {
  final TextEditingController macController;
  final VoidCallback onScanQr;
  final VoidCallback onSubmit;

  const RegisterDispenserFormWidget({
    super.key,
    required this.macController,
    required this.onScanQr,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Asocia un dispositivo PDAM escaneando su código QR.',
          style: TextStyle(fontSize: 15, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: macController,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Dirección MAC del Dispositivo',
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.blue),
              onPressed: onScanQr,
            ),
          ),
        ),
        const SizedBox(height: 32),
        BlocBuilder<DispenserBloc, DispenserState>(
          buildWhen: (previous, current) =>
              (previous is DispenserLoading) != (current is DispenserLoading),
          builder: (context, state) {
            final isLoading = state is DispenserLoading;

            return FilledButton(
              onPressed: isLoading ? null : onSubmit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Vincular Dispositivo',
                      style: TextStyle(fontSize: 16),
                    ),
            );
          },
        ),
      ],
    );
  }
}
