import 'package:app_movil_pdam/core/theme/app_colors.dart';
import 'package:app_movil_pdam/core/theme/app_typography.dart';
import 'package:app_movil_pdam/presentation/shared/widgets/custom_card_widget.dart';
import 'package:flutter/material.dart';

class LoginScreenDesktop extends StatelessWidget {
  const LoginScreenDesktop({super.key});

  @override
  Widget build(BuildContext context) {
    final double fontSize = MediaQuery.of(context).size.width * 0.020;
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: CustomCardWidget(
          child: AppTypography.textTitle('Login Screen', fontSize: fontSize),
        ),
      ),
    );
  }
}
