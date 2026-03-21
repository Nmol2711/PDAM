import 'package:app_movil_pdam/core/theme/app_typography.dart';
import 'package:app_movil_pdam/presentation/auth/bloc/auth_bloc.dart';
import 'package:app_movil_pdam/presentation/layout/view/main_screen.dart';
import 'package:app_movil_pdam/presentation/shared/widgets/custom_card_widget.dart';
import 'package:app_movil_pdam/presentation/shared/widgets/custom_outlined_button.dart';
import 'package:app_movil_pdam/presentation/shared/widgets/custom_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LoginScreenMobile extends StatelessWidget {
  const LoginScreenMobile({super.key});

  @override
  Widget build(BuildContext context) {
    final double fontSize = MediaQuery.of(context).size.width * 0.025;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: AppTypography.textTitle(context, 'Sign In', fontSize: fontSize),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          
          if (state is AuthFailure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
          }
          if (state is AuthSuccess) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const MainScreen()),
            );
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: _LoginHeader(fontSize: fontSize),
                        ),
                        Center(
                          child: _LoginForm(fontSize: fontSize),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  final double fontSize;
  const _LoginHeader({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppTypography.textTitle(
          context,
          "PDAM",
          fontSize: fontSize * 5,
          superTitle: true,
        ),
        const SizedBox(height: 8),
       
      ],
    );
  }
}

class _LoginForm extends StatelessWidget {
  final double fontSize;
  const _LoginForm({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        return Column(
          children: [
            Image.asset(
              isDarkMode
                  ? 'assets/imgs/perro_3.png'
                  : 'assets/imgs/gato_1.png',
              width: 200,
              height: MediaQuery.of(context).size.height * 0.3,
              fit: BoxFit.contain,
            ),
            Builder(
              builder: (context) {
                 if (state is AuthLoading) {
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }
                return CustomCardWidget(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: AppTypography.textTitle(
                            context,
                            'Ingrese sus credenciales',
                            fontSize: fontSize,
                          ),
                        ),
                        CustomTextField(
                          label: "Usuario",
                          icon: Icons.email_outlined,
                          onChanged: (value) =>
                              context.read<AuthBloc>().add(EmailChanged(value)),
                        ),
                        const SizedBox(height: 16),
                        CustomTextField(
                          label: "Contraseña",
                          icon: Icons.password_outlined,
                          isPassword: true,
                          onChanged: (value) =>
                              context.read<AuthBloc>().add(PasswordChanged(value)),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: CustomOutlinedButton(
                                text: 'Iniciar Sesión',
                                onPressed: () => context.read<AuthBloc>().add(
                                      const LoginSubmitted(),
                                    ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: CustomOutlinedButton(
                                text: 'Registrarse',
                                onPressed: () {},
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {},
                          child: AppTypography.textBody(
                            context,
                            "¿Olvidaste tu Contraseña?",
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            ),
          ],
        );
      },
    );
  }
}
