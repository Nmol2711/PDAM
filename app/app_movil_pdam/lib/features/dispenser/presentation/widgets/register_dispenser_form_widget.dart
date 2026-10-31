import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
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
    final esquema = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Asocia un dispositivo PDAM escaneando su código QR.',
          style: TextStyle(fontSize: 15, color: esquema.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        TextFormField(
          controller: macController,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Dirección MAC del Dispositivo',
            suffixIcon: IconButton(
              icon: Icon(Icons.qr_code_scanner, color: esquema.primary),
              onPressed: onScanQr,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        BlocBuilder<DispenserBloc, DispenserState>(
          buildWhen: (previous, current) =>
              (previous is DispenserLoading) != (current is DispenserLoading),
          builder: (context, state) {
            final isLoading = state is DispenserLoading;

            return FilledButton(
              onPressed: isLoading ? null : onSubmit,
              child: isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: esquema.onSurfaceVariant,
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
