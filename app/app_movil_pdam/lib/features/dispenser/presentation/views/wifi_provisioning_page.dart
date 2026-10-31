import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_movil_pdam/core/presentation/widgets/password_visibility_field.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/bloc/dispenser_bloc.dart';

class WifiProvisioningPage extends StatefulWidget {
  final ScannedDevice device;

  const WifiProvisioningPage({super.key, required this.device});

  @override
  State<WifiProvisioningPage> createState() => _WifiProvisioningPageState();
}

class _WifiProvisioningPageState extends State<WifiProvisioningPage> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<DispenserBloc>().add(
        ConnectAndProvisionEvent(
          deviceId: widget.device.remoteId,
          ssid: _ssidController.text.trim(),
          password: _passwordController.text,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final semantica = AppSemanticColors.of(context);
    final ancho = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración WiFi')),
      body: BlocConsumer<DispenserBloc, DispenserState>(
        listener: (context, state) {
          if (state is ProvisioningSuccessState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: semantica.success,
                content: Text(
                  'Dispensador conectado y configurado exitosamente',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: semantica.onSuccess),
                ),
              ),
            );
            context.go('/dispensers');
          } else if (state is DispenserErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: esquema.error,
                content: Text(
                  state.message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: esquema.onError),
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state is ProvisioningInProgressState;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.pageFor(ancho),
              vertical: AppSpacing.page,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Prominent 2.4GHz Warning (RF-04)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: semantica.alert,
                      borderRadius: BorderRadius.circular(AppRadii.banner),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: semantica.onAlert,
                          size: 28,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'ATENCIÓN: El dispensador ESP32 SOLO es compatible con redes WiFi de 2.4GHz. No se admiten redes de 5GHz.',
                            style: TextStyle(
                              color: semantica.onAlert,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  Text(
                    'Dispositivo seleccionado:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.device.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  TextFormField(
                    controller: _ssidController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de red WiFi (SSID - 2.4GHz)',
                      prefixIcon: Icon(Icons.wifi),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor ingresa el nombre de la red WiFi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.fieldGap),
                  PasswordVisibilityField(
                    controller: _passwordController,
                    label: 'Contraseña WiFi',
                    prefixIcon: const Icon(Icons.lock),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor ingresa la contraseña';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  FilledButton(
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: esquema.onSurfaceVariant,
                            ),
                          )
                        : const Text(
                            'Enviar Credenciales y Conectar',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
