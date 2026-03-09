import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/core/theme/app_typography.dart';
import 'package:app_movil_pdam/presentation/shared/widgets/custom_card_widget.dart';
import 'package:app_movil_pdam/presentation/shared/widgets/custom_outlined_button.dart';
import 'package:app_movil_pdam/presentation/shared/widgets/custom_text_field.dart';
import 'package:flutter/material.dart';

class LoginScreenMobile extends StatelessWidget {
  const LoginScreenMobile({super.key});

  @override
  Widget build(BuildContext context) {
    final double fontSize = MediaQuery.of(context).size.width * 0.025;
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: AppTypography.textTitle('Sign In', fontSize: fontSize),
        backgroundColor: AppColors.darkBackground,
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: CustomCardWidget(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: AppTypography.textTitle(
                      'Ingrese sus redenciales',
                      fontSize: fontSize,
                      textAlign: TextAlign.start,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CustomTextField(
                      label: "Usuario",
                      icon: Icons.email_outlined,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CustomTextField(
                      label: "Usuario",
                      icon: Icons.password_outlined,
                      isPassword: true,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: CustomOutlinedButton(
                            text: 'Iniciar Seccion',
                            onPressed: () {},
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: CustomOutlinedButton(
                            text: 'Registrarse',
                            onPressed: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
