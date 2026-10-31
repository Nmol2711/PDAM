import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/core/presentation/widgets/password_visibility_field.dart';
import 'package:app_movil_pdam/core/theme/app_semantic_colors.dart';
import 'package:app_movil_pdam/core/theme/app_shape.dart';
import 'package:app_movil_pdam/core/theme/app_spacing.dart';
import 'package:app_movil_pdam/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:go_router/go_router.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
        AuthLoginRequested(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // La vista se monta después de que el BLoC emita el estado, así que el
    // mensaje de sesión se lee del estado actual y no solo del listener
    // (RF-05: el aviso debe verse al volver al login).
    final authState = context.watch<AuthBloc>().state;
    final mensajeSesion = switch (authState) {
      AuthSessionExpired(:final message) => message,
      AuthAccountDeleted(:final message) => message,
      _ => null,
    };
    final esConfirmacionBaja = authState is AuthAccountDeleted;
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    final ancho = MediaQuery.sizeOf(context).width;

    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            final colores = Theme.of(context).colorScheme;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: colores.error,
                content: Text(
                  state.message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colores.onError),
                ),
              ),
            );
          }
        },
        child: SafeArea(
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
                    // --- LOGO / HEADER ---
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: esquema.primaryContainer.withValues(
                            alpha: 0.4,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/imgs/logo.png',
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),
                    Text(
                      "Bienvenido a PDAM",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      "Gestión nutricional y dispensador inteligente",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: esquema.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),

                    if (mensajeSesion != null) ...[
                      _MensajeSesion(
                        mensaje: mensajeSesion,
                        confirmacion: esConfirmacionBaja,
                      ),
                      const SizedBox(height: AppSpacing.fieldGap),
                    ],

                    // --- EMAIL ---
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'El correo es obligatorio';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.fieldGap),

                    // --- PASSWORD ---
                    PasswordVisibilityField(
                      controller: _passwordController,
                      label: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'La contraseña es obligatoria';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),

                    // --- BOTÓN DE INGRESO ---
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthLoading;
                        return FilledButton(
                          onPressed: isLoading ? null : _onLoginPressed,
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
                                  'Iniciar Sesión',
                                  style: TextStyle(fontSize: 16),
                                ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.fieldGap),

                    // --- ENLACE A REGISTRO ---
                    TextButton(
                      onPressed: () => context.push('/register'),
                      child: const Text(
                        '¿No tienes una cuenta? Regístrate aquí',
                      ),
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

/// Aviso no bloqueante de sesión terminada (RF-05, RF-18).
///
/// El texto llega del catálogo a través del estado del BLoC; la vista no lo
/// hardcodea y no expone credenciales ni tokens.
class _MensajeSesion extends StatelessWidget {
  final String mensaje;
  final bool confirmacion;

  const _MensajeSesion({required this.mensaje, this.confirmacion = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantica = AppSemanticColors.of(context);
    final fondo = confirmacion ? semantica.success : colors.errorContainer;
    final contenido = confirmacion
        ? semantica.onSuccess
        : colors.onErrorContainer;
    final icono = confirmacion
        ? Icons.check_circle_outline
        : Icons.error_outline;

    return Container(
      key: const Key('login_session_message'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(AppRadii.banner),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icono, color: contenido),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              mensaje,
              style: textTheme.bodyMedium?.copyWith(color: contenido),
            ),
          ),
        ],
      ),
    );
  }
}
