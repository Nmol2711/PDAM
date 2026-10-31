import 'package:app_movil_pdam/core/presentation/widgets/password_visibility_field.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/account/domain/utils/account_validators.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onRegisterPressed() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
        AuthRegisterRequested(
          email: normalizarCorreo(_emailController.text),
          password: _passwordController.text.trim(),
          confirmPassword: _confirmPasswordController.text.trim(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    final semantica = AppSemanticColors.of(context);
    final ancho = MediaQuery.sizeOf(context).width;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: esquema.error,
              content: Text(
                state.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: esquema.onError,
                ),
              ),
            ),
          );
        }

        if (state is AuthRegister) {
          context.replace('/login');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: semantica.success,
              content: Text(
                'Cuenta creada correctamente. Inicia sesión.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: semantica.onSuccess,
                ),
              ),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Crear Cuenta')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.pageFor(ancho),
                vertical: AppSpacing.page,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Únete a PDAM',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Crea una cuenta para automatizar la alimentación de tus '
                      'mascotas',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: esquema.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),

                    // --- CORREO ---
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        final correo = normalizarCorreo(value ?? '');
                        if (correo.isEmpty) {
                          return MensajesCuenta.correoObligatorio;
                        }
                        if (!esCorreoValido(correo)) {
                          return MensajesCuenta.correoInvalido;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.fieldGap),

                    // --- CONTRASEÑA ---
                    PasswordVisibilityField(
                      controller: _passwordController,
                      label: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      validator: validarPasswordRegistro,
                    ),
                    const SizedBox(height: AppSpacing.fieldGap),

                    // --- CONFIRMAR CONTRASEÑA ---
                    PasswordVisibilityField(
                      controller: _confirmPasswordController,
                      label: 'Confirmar Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirma tu contraseña';
                        }
                        if (value != _passwordController.text) {
                          return MensajesCuenta.passwordsNoCoinciden;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),

                    // --- BOTÓN DE REGISTRO ---
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthLoading;
                        return FilledButton(
                          onPressed: isLoading ? null : _onRegisterPressed,
                          child: isLoading
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: esquema.onPrimary,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Registrarse',
                                  style: TextStyle(fontSize: 16),
                                ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.fieldGap),

                    // --- VOLVER A LOGIN ---
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('¿Ya tienes cuenta? Inicia sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
